from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from lightgbm import LGBMClassifier
from pulearn import ElkanotoPuClassifier

from metrics import precision_at_k, pu_ranking_metrics


def _lgbm_estimator(params: dict, seed: int) -> LGBMClassifier:
    p = {k: v for k, v in params.items() if k not in ("objective", "metric", "num_threads")}
    n_jobs = int(params.get("num_threads", 1))
    return LGBMClassifier(
        objective="binary",
        n_estimators=500,
        random_state=seed,
        n_jobs=n_jobs,
        verbose=-1,
        **p,
    )


def train_elkanoto_pu(
    x_train: pd.DataFrame,
    y_train: pd.Series,
    x_val: pd.DataFrame,
    y_val: pd.Series,
    params: dict,
    hold_out_ratio: float,
    seed: int,
) -> tuple[ElkanotoPuClassifier, dict]:
    clf = ElkanotoPuClassifier(
        estimator=_lgbm_estimator(params, seed),
        hold_out_ratio=hold_out_ratio,
        random_state=seed,
    )
    clf.fit(x_train, y_train)

    train_prob = clf.predict_proba(x_train)[:, 1]
    val_prob = clf.predict_proba(x_val)[:, 1]

    metrics = {
        "method": "elkanoto",
        "train": pu_ranking_metrics(y_train.to_numpy(), train_prob),
        "val": pu_ranking_metrics(y_val.to_numpy(), val_prob),
    }
    metrics["val"]["precision_at_1pct"] = precision_at_k(y_val.to_numpy(), val_prob, 0.01)
    metrics["val"]["precision_at_5pct"] = precision_at_k(y_val.to_numpy(), val_prob, 0.05)
    return clf, metrics


def train_weighted_naive_pu(
    x_train: pd.DataFrame,
    y_train: pd.Series,
    x_val: pd.DataFrame,
    y_val: pd.Series,
    params: dict,
    unlabeled_weight: float,
    num_boost_round: int,
    early_stopping_rounds: int,
    seed: int,
) -> tuple[lgb.Booster, dict]:
    w = np.where(y_train.to_numpy() == 1, 1.0, float(unlabeled_weight))
    cat_cols = [c for c in x_train.columns if str(x_train[c].dtype) == "category"]

    train_set = lgb.Dataset(
        x_train,
        label=y_train,
        weight=w,
        categorical_feature=cat_cols or "auto",
        free_raw_data=False,
    )
    val_set = lgb.Dataset(
        x_val,
        label=y_val,
        categorical_feature=cat_cols or "auto",
        reference=train_set,
        free_raw_data=False,
    )

    train_params = {k: v for k, v in params.items() if k != "num_threads"}
    if "num_threads" in params:
        train_params["num_threads"] = int(params["num_threads"])

    booster = lgb.train(
        params=train_params,
        train_set=train_set,
        num_boost_round=num_boost_round,
        valid_sets=[train_set, val_set],
        valid_names=["train", "val"],
        callbacks=[
            lgb.early_stopping(stopping_rounds=early_stopping_rounds, verbose=True),
            lgb.log_evaluation(period=50),
        ],
    )
    train_prob = booster.predict(x_train, num_iteration=booster.best_iteration)
    val_prob = booster.predict(x_val, num_iteration=booster.best_iteration)
    metrics = {
        "method": "weighted_naive",
        "best_iteration": int(booster.best_iteration),
        "train": pu_ranking_metrics(y_train.to_numpy(), train_prob),
        "val": pu_ranking_metrics(y_val.to_numpy(), val_prob),
    }
    metrics["val"]["precision_at_1pct"] = precision_at_k(y_val.to_numpy(), val_prob, 0.01)
    return booster, metrics


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


def save_lgbm_artifacts(booster, metrics, feature_columns, output_dir: Path, model_name: str) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_path = output_dir / f"{model_name}_{ts}.txt"
    booster.save_model(str(model_path))
    importance = pd.DataFrame(
        {
            "feature": booster.feature_name(),
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
        "metrics_path": str(metrics_path),
        "importance_path": str(imp_path),
        "timestamp": ts,
    }
