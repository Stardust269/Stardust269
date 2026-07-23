from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    average_precision_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)

from features import CATEGORICAL_COLUMNS


def _ks_score(y_true: np.ndarray, y_prob: np.ndarray) -> float:
    order = np.argsort(-y_prob)
    y = y_true[order]
    cum_pos = np.cumsum(y) / max(y.sum(), 1)
    cum_neg = np.cumsum(1 - y) / max((1 - y).sum(), 1)
    return float(np.max(np.abs(cum_pos - cum_neg)))


def evaluate_binary(y_true: np.ndarray, y_prob: np.ndarray, threshold: float = 0.5) -> dict:
    y_pred = (y_prob >= threshold).astype(int)
    return {
        "auc": float(roc_auc_score(y_true, y_prob)),
        "pr_auc": float(average_precision_score(y_true, y_prob)),
        "ks": _ks_score(y_true, y_prob),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "threshold": threshold,
        "positive_rate": float(y_true.mean()),
        "pred_positive_rate": float(y_pred.mean()),
        "confusion_matrix": confusion_matrix(y_true, y_pred).tolist(),
    }


def train_lightgbm(
    x_train: pd.DataFrame,
    y_train: pd.Series,
    x_val: pd.DataFrame,
    y_val: pd.Series,
    params: dict,
    num_boost_round: int,
    early_stopping_rounds: int,
) -> tuple[lgb.Booster, dict]:
    cat_cols = [c for c in x_train.columns if c in CATEGORICAL_COLUMNS]

    train_set = lgb.Dataset(
        x_train,
        label=y_train,
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

    booster = lgb.train(
        params=params,
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
        "best_iteration": int(booster.best_iteration),
        "train": evaluate_binary(y_train.to_numpy(), train_prob),
        "val": evaluate_binary(y_val.to_numpy(), val_prob),
    }
    return booster, metrics


def save_artifacts(
    booster: lgb.Booster,
    metrics: dict,
    feature_columns: list[str],
    output_dir: Path,
    model_name: str,
) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")

    model_path = output_dir / f"{model_name}_{ts}.txt"
    booster.save_model(str(model_path))

    importance = pd.DataFrame(
        {
            "feature": booster.feature_name(),
            "gain": booster.feature_importance(importance_type="gain"),
            "split": booster.feature_importance(importance_type="split"),
        }
    ).sort_values("gain", ascending=False)
    importance_path = output_dir / f"{model_name}_{ts}_feature_importance.csv"
    importance.to_csv(importance_path, index=False)

    metrics_path = output_dir / f"{model_name}_{ts}_metrics.json"
    with metrics_path.open("w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)

    manifest = {
        "model_path": str(model_path),
        "metrics_path": str(metrics_path),
        "importance_path": str(importance_path),
        "feature_columns": feature_columns,
        "metrics": metrics,
    }
    manifest_path = output_dir / f"{model_name}_{ts}_manifest.json"
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    return manifest
