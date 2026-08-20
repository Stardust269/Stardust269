from __future__ import annotations

import gc
import json
from datetime import datetime
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from lightgbm import LGBMClassifier
from pulearn import ElkanotoPuClassifier

from memory_utils import memory_cfg, release
from metrics import precision_at_k, pu_ranking_metrics


def _lgbm_estimator(params: dict, seed: int) -> LGBMClassifier:
    p = {k: v for k, v in params.items() if k not in ("objective", "metric", "num_threads", "max_bin")}
    n_jobs = int(params.get("num_threads", 1))
    return LGBMClassifier(
        objective="binary",
        n_estimators=500,
        random_state=seed,
        n_jobs=n_jobs,
        verbose=-1,
        **p,
    )


def _lgb_train_params(params: dict, mem: dict) -> dict:
    train_params = {k: v for k, v in params.items() if k != "num_threads"}
    if "num_threads" in params:
        train_params["num_threads"] = int(params["num_threads"])
    if mem.get("max_bin"):
        train_params["max_bin"] = int(mem["max_bin"])
    return train_params


def train_elkanoto_pu(
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_val: np.ndarray,
    y_val: np.ndarray,
    feature_columns: list[str],
    categorical_indices: list[int],
    params: dict,
    hold_out_ratio: float,
    seed: int,
    mem: dict | None = None,
) -> tuple[ElkanotoPuClassifier, dict]:
    mem = mem or {}
    clf = ElkanotoPuClassifier(
        estimator=_lgbm_estimator(params, seed),
        hold_out_ratio=hold_out_ratio,
        random_state=seed,
    )
    clf.fit(x_train, y_train)
    if mem.get("release_train_matrix", True):
        release(x_train)
        if mem.get("skip_train_metrics", True):
            release(y_train)

    metrics: dict = {"method": "elkanoto"}
    if not mem.get("skip_train_metrics", True):
        train_prob = clf.predict_proba(x_train)[:, 1]
        metrics["train"] = pu_ranking_metrics(y_train, train_prob)
    val_prob = clf.predict_proba(x_val)[:, 1]
    metrics["val"] = pu_ranking_metrics(y_val, val_prob)
    metrics["val"]["precision_at_1pct"] = precision_at_k(y_val, val_prob, 0.01)
    metrics["val"]["precision_at_5pct"] = precision_at_k(y_val, val_prob, 0.05)
    return clf, metrics


def build_weighted_naive_datasets(
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_val: np.ndarray,
    y_val: np.ndarray,
    feature_columns: list[str],
    categorical_indices: list[int],
    params: dict,
    unlabeled_weight: float,
    mem: dict | None = None,
) -> tuple[lgb.Dataset, lgb.Dataset, dict]:
    mem = mem or {}
    free_raw = bool(mem.get("lgb_free_raw_data", True))
    w = np.where(y_train == 1, 1.0, float(unlabeled_weight)).astype(np.float32)

    cat_arg = categorical_indices if categorical_indices else "auto"
    train_set = lgb.Dataset(
        x_train,
        label=y_train,
        weight=w,
        feature_name=feature_columns,
        categorical_feature=cat_arg,
        free_raw_data=free_raw,
    )
    if free_raw and mem.get("skip_train_metrics", True):
        release(w)

    val_set = lgb.Dataset(
        x_val,
        label=y_val,
        feature_name=feature_columns,
        categorical_feature=cat_arg,
        reference=train_set,
        free_raw_data=free_raw,
    )
    train_params = _lgb_train_params(params, mem)
    return train_set, val_set, {
        "y_train": y_train,
        "y_val": y_val,
        "x_train": x_train,
        "x_val": x_val,
        "train_params": train_params,
        "feature_columns": feature_columns,
    }


def run_weighted_naive_training(
    train_set: lgb.Dataset,
    val_set: lgb.Dataset,
    ctx: dict,
    num_boost_round: int,
    early_stopping_rounds: int,
    mem: dict | None = None,
) -> tuple[lgb.Booster, dict]:
    mem = mem or {}
    free_raw = bool(mem.get("lgb_free_raw_data", True))
    valid_sets = [val_set] if mem.get("valid_on_val_only", True) else [train_set, val_set]
    valid_names = ["val"] if mem.get("valid_on_val_only", True) else ["train", "val"]

    booster = lgb.train(
        params=ctx["train_params"],
        train_set=train_set,
        num_boost_round=num_boost_round,
        valid_sets=valid_sets,
        valid_names=valid_names,
        callbacks=[
            lgb.early_stopping(stopping_rounds=early_stopping_rounds, verbose=True),
            lgb.log_evaluation(period=50),
        ],
    )
    gc.collect()

    y_train = ctx["y_train"]
    y_val = ctx["y_val"]
    x_train = ctx["x_train"]
    x_val = ctx["x_val"]
    metrics: dict = {
        "method": "weighted_naive",
        "best_iteration": int(booster.best_iteration),
    }
    if not mem.get("skip_train_metrics", True):
        train_prob = booster.predict(x_train, num_iteration=booster.best_iteration)
        metrics["train"] = pu_ranking_metrics(y_train, train_prob)
    val_prob = booster.predict(x_val, num_iteration=booster.best_iteration)
    metrics["val"] = pu_ranking_metrics(y_val, val_prob)
    metrics["val"]["precision_at_1pct"] = precision_at_k(y_val, val_prob, 0.01)
    if free_raw:
        release(x_val)
    return booster, metrics


def train_weighted_naive_pu(
    x_train: np.ndarray,
    y_train: np.ndarray,
    x_val: np.ndarray,
    y_val: np.ndarray,
    feature_columns: list[str],
    categorical_indices: list[int],
    params: dict,
    unlabeled_weight: float,
    num_boost_round: int,
    early_stopping_rounds: int,
    mem: dict | None = None,
) -> tuple[lgb.Booster, dict]:
    mem = mem or {}
    train_set, val_set, ctx = build_weighted_naive_datasets(
        x_train,
        y_train,
        x_val,
        y_val,
        feature_columns=feature_columns,
        categorical_indices=categorical_indices,
        params=params,
        unlabeled_weight=unlabeled_weight,
        mem=mem,
    )
    if mem.get("release_train_matrix", True):
        release(x_train, y_train)
    return run_weighted_naive_training(
        train_set,
        val_set,
        ctx,
        num_boost_round=num_boost_round,
        early_stopping_rounds=early_stopping_rounds,
        mem=mem,
    )


def save_sklearn_pu_artifacts(clf, metrics, feature_columns, output_dir: Path, model_name: str) -> dict:
    import joblib

    output_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_path = output_dir / f"{model_name}_{ts}.joblib"
    joblib.dump({"model": clf, "features": feature_columns}, model_path)
    metrics_path = output_dir / f"{model_name}_{ts}_metrics.json"
    with metrics_path.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)
    manifest = {
        "model_path": str(model_path),
        "metrics_path": str(metrics_path),
        "feature_count": len(feature_columns),
        "timestamp": ts,
    }
    manifest_path = output_dir / f"{model_name}_{ts}_manifest.json"
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    return manifest


from model_io import save_feature_list


def save_lgbm_artifacts(booster, metrics, feature_columns, output_dir: Path, model_name: str) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_path = output_dir / f"{model_name}_{ts}.txt"
    booster.save_model(str(model_path))
    features_path = save_feature_list(model_path, feature_columns)
    importance = pd.DataFrame(
        {
            "feature": feature_columns,
            "gain": booster.feature_importance(importance_type="gain"),
        }
    ).sort_values("gain", ascending=False)
    imp_path = output_dir / f"{model_name}_{ts}_feature_importance.csv"
    importance.to_csv(imp_path, index=False)
    metrics_path = output_dir / f"{model_name}_{ts}_metrics.json"
    with metrics_path.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)
    return {
        "model_path": str(model_path),
        "features_path": str(features_path),
        "metrics_path": str(metrics_path),
        "importance_path": str(imp_path),
        "timestamp": ts,
        "feature_count": len(feature_columns),
    }
