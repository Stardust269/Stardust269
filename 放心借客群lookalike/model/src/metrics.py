from __future__ import annotations

import numpy as np
from sklearn.metrics import (
    average_precision_score,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)


def pu_ranking_metrics(y_true: np.ndarray, y_score: np.ndarray) -> dict:
    """PU 场景下的监控指标（将未标注当负例计算 AUC 仅作参考）。"""
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    out: dict = {}
    if len(np.unique(y_true)) > 1:
        out["auc"] = float(roc_auc_score(y_true, y_score))
        out["pr_auc"] = float(average_precision_score(y_true, y_score))
        # 与历史字段兼容
        out["auc_p_vs_u"] = out["auc"]
        out["pr_auc_p_vs_u"] = out["pr_auc"]
    pos = y_score[y_true == 1]
    unl = y_score[y_true == 0]
    out["mean_score_positive"] = float(pos.mean()) if len(pos) else None
    out["mean_score_unlabeled"] = float(unl.mean()) if len(unl) else None
    if len(pos) and len(unl):
        out["score_gap_pos_minus_unl"] = float(pos.mean() - unl.mean())
    out["positive_rate"] = float(y_true.mean())
    out["n_samples"] = int(len(y_true))
    out["n_positive"] = int((y_true == 1).sum())
    out["n_negative"] = int((y_true == 0).sum())
    return out


def precision_at_k(y_true: np.ndarray, y_score: np.ndarray, k_ratio: float = 0.01) -> float:
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    n = max(int(len(y_score) * k_ratio), 1)
    idx = np.argsort(-y_score)[:n]
    return float(y_true[idx].mean())


def recall_at_k(y_true: np.ndarray, y_score: np.ndarray, k_ratio: float = 0.01) -> float:
    """Top k% 按分数截断时，召回了多少比例的正样本。"""
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    n_pos = int((y_true == 1).sum())
    if n_pos == 0:
        return float("nan")
    n = max(int(len(y_score) * k_ratio), 1)
    idx = np.argsort(-y_score)[:n]
    return float(y_true[idx].sum() / n_pos)


def f1_at_k(y_true: np.ndarray, y_score: np.ndarray, k_ratio: float = 0.01) -> float:
    p = precision_at_k(y_true, y_score, k_ratio)
    r = recall_at_k(y_true, y_score, k_ratio)
    if p + r == 0:
        return 0.0
    return float(2 * p * r / (p + r))


def classification_metrics(
    y_true: np.ndarray,
    y_score: np.ndarray,
    threshold: float = 0.5,
) -> dict:
    """固定阈值下的二分类指标。"""
    y_true = np.asarray(y_true).astype(int)
    y_pred = (np.asarray(y_score).astype(float) >= threshold).astype(int)
    if len(np.unique(y_true)) < 2:
        return {
            "threshold": threshold,
            "precision": None,
            "recall": None,
            "f1": None,
            "note": "标签仅一类，无法计算 precision/recall/f1",
        }
    return {
        "threshold": threshold,
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
    }


def top_k_metrics(y_true: np.ndarray, y_score: np.ndarray, k_ratios: list[float]) -> dict:
    out = {}
    for k in k_ratios:
        key = f"top_{int(k * 100)}pct"
        out[key] = {
            "precision": precision_at_k(y_true, y_score, k),
            "recall": recall_at_k(y_true, y_score, k),
            "f1": f1_at_k(y_true, y_score, k),
            "k_ratio": k,
        }
    return out


def evaluate_scores(
    y_true: np.ndarray,
    y_score: np.ndarray,
    threshold: float = 0.5,
    top_k_ratios: list[float] | None = None,
) -> dict:
    top_k_ratios = top_k_ratios or [0.01, 0.05, 0.10]
    return {
        "ranking": pu_ranking_metrics(y_true, y_score),
        "threshold": classification_metrics(y_true, y_score, threshold),
        "top_k": top_k_metrics(y_true, y_score, top_k_ratios),
    }
