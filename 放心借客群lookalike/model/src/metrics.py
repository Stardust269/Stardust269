from __future__ import annotations

import numpy as np
from sklearn.metrics import average_precision_score, roc_auc_score


def pu_ranking_metrics(y_true: np.ndarray, y_score: np.ndarray) -> dict:
    """PU 场景下的监控指标（将未标注当负例计算 AUC 仅作参考）。"""
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    out: dict = {}
    if len(np.unique(y_true)) > 1:
        out["auc_p_vs_u"] = float(roc_auc_score(y_true, y_score))
        out["pr_auc_p_vs_u"] = float(average_precision_score(y_true, y_score))
    pos = y_score[y_true == 1]
    unl = y_score[y_true == 0]
    out["mean_score_positive"] = float(pos.mean()) if len(pos) else None
    out["mean_score_unlabeled"] = float(unl.mean()) if len(unl) else None
    if len(pos) and len(unl):
        out["score_gap_pos_minus_unl"] = float(pos.mean() - unl.mean())
    out["positive_rate"] = float(y_true.mean())
    return out


def precision_at_k(y_true: np.ndarray, y_score: np.ndarray, k_ratio: float = 0.01) -> float:
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    n = max(int(len(y_score) * k_ratio), 1)
    idx = np.argsort(-y_score)[:n]
    return float(y_true[idx].mean())
