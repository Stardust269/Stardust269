from __future__ import annotations

import numpy as np
import pandas as pd
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
    include_threshold: bool = True,
) -> dict:
    top_k_ratios = top_k_ratios or [0.01, 0.05, 0.10]
    out: dict = {
        "ranking": pu_ranking_metrics(y_true, y_score),
        "top_k": top_k_metrics(y_true, y_score, top_k_ratios),
    }
    if include_threshold:
        out["threshold"] = classification_metrics(y_true, y_score, threshold)
    return out


def _tgi_rows_for_percentiles(
    y_sorted: np.ndarray,
    n: int,
    n_pos_total: int,
    percentiles: list[int],
) -> list[dict]:
    """按给定百分位（降序，如 99,98,...,0）生成 TGI 行；p99=累计 top 1%。"""
    rows: list[dict] = []
    prev_cum_n = 0
    prev_cum_pos = 0

    for p in sorted(percentiles, reverse=True):
        top_ratio = (100 - p) / 100.0
        cum_n = n if p == 0 else max(int(round(n * top_ratio)), 1)
        cum_n = min(cum_n, n)
        cum_pos = int(y_sorted[:cum_n].sum())
        slice_n = cum_n - prev_cum_n
        slice_pos = cum_pos - prev_cum_pos
        recall = cum_pos / n_pos_total if n_pos_total else float("nan")
        precision = cum_pos / cum_n if cum_n else float("nan")
        rows.append(
            {
                "tgi百分位": f"p{p:02d}",
                "总数": slice_n,
                "种子用户数": slice_pos,
                "累计总数": cum_n,
                "累计种子用户数": cum_pos,
                "recall": recall,
                "precision": precision,
            }
        )
        prev_cum_n = cum_n
        prev_cum_pos = cum_pos
    return rows


# 与同事表一致：顶部细粒度 top1%~4% + 每 5% 一档至全量
DEFAULT_TGI_PERCENTILES = [99, 98, 97, 96, *range(95, -1, -5)]


def tgi_percentile_table(
    y_true: np.ndarray,
    y_score: np.ndarray,
    step: int = 5,
    extra_top_percentiles: list[int] | None = None,
    percentiles: list[int] | None = None,
) -> pd.DataFrame:
    """
    与同事 TGI 验收表对齐的百分位表。
    p99=累计 top 1%，p98=top 2%，…，p95=top 5%，p90=top 10%，…，p00=全量。
    """
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    order = np.argsort(-y_score, kind="mergesort")
    y_sorted = y_true[order]
    n = len(y_true)
    n_pos_total = int(y_sorted.sum())

    if percentiles is None:
        pct_list = [99, 98, 97, 96, *range(95, -1, -step)]
        seen: set[int] = set()
        percentiles = []
        for p in pct_list:
            if p not in seen:
                seen.add(p)
                percentiles.append(p)

    rows = _tgi_rows_for_percentiles(y_sorted, n, n_pos_total, percentiles)
    df = pd.DataFrame(rows)
    total_row = {
        "tgi百分位": "总计",
        "总数": n,
        "种子用户数": n_pos_total,
        "累计总数": n,
        "累计种子用户数": n_pos_total,
        "recall": float("nan"),
        "precision": float("nan"),
    }
    return pd.concat([df, pd.DataFrame([total_row])], ignore_index=True)


def tgi_percentile_subset(
    y_true: np.ndarray,
    y_score: np.ndarray,
    percentiles: list[int],
) -> pd.DataFrame:
    """仅计算指定百分位（如 p99~p96），用于补算指标、无需重跑全量评估。"""
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    order = np.argsort(-y_score, kind="mergesort")
    y_sorted = y_true[order]
    n = len(y_true)
    n_pos_total = int(y_sorted.sum())
    return pd.DataFrame(_tgi_rows_for_percentiles(y_sorted, n, n_pos_total, percentiles))
