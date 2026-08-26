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


def _score_stats(arr: np.ndarray) -> dict[str, float]:
    if arr.size == 0:
        return {"min": float("nan"), "max": float("nan"), "mean": float("nan")}
    return {"min": float(arr.min()), "max": float(arr.max()), "mean": float(arr.mean())}


def _score_percentile_band_rows(
    scores_sorted: np.ndarray,
    n: int,
    percentiles: list[int],
) -> list[dict]:
    """按分数从高到低互斥切片；每行含本层与累计的 min/max/mean。"""
    rows: list[dict] = []
    prev_cum_n = 0

    for p in sorted(percentiles, reverse=True):
        top_ratio = (100 - p) / 100.0
        cum_n = n if p == 0 else max(int(round(n * top_ratio)), 1)
        cum_n = min(cum_n, n)
        slice_n = cum_n - prev_cum_n
        cum_scores = scores_sorted[:cum_n]
        slice_scores = scores_sorted[prev_cum_n:cum_n]
        cum_st = _score_stats(cum_scores)
        slice_st = _score_stats(slice_scores)
        rows.append(
            {
                "score百分位": f"p{p:02d}",
                "总数": slice_n,
                "分数_min": slice_st["min"],
                "分数_max": slice_st["max"],
                "分数_mean": slice_st["mean"],
                "累计总数": cum_n,
                "累计分数_min": cum_st["min"],
                "累计分数_max": cum_st["max"],
                "累计分数_mean": cum_st["mean"],
            }
        )
        prev_cum_n = cum_n
    return rows


def score_percentile_band_table(
    y_score: np.ndarray,
    step: int = 5,
    percentiles: list[int] | None = None,
) -> pd.DataFrame:
    """
    无标签预测分布：按分数从高到低分层。
    p99=最高 1% 互斥层，p98=次高 1%，…，p95 后每 5% 一档至 p00。
    每层输出本层与累计的样本数及分数 min/max/mean。
    """
    y_score = np.asarray(y_score).astype(float)
    y_score = y_score[np.isfinite(y_score)]
    order = np.argsort(-y_score, kind="mergesort")
    scores_sorted = y_score[order]
    n = len(scores_sorted)
    pct_list = _resolve_tgi_percentiles(step, percentiles)
    rows = _score_percentile_band_rows(scores_sorted, n, pct_list)
    df = pd.DataFrame(rows)
    all_st = _score_stats(scores_sorted)
    total_row = {
        "score百分位": "总计",
        "总数": n,
        "分数_min": all_st["min"],
        "分数_max": all_st["max"],
        "分数_mean": all_st["mean"],
        "累计总数": n,
        "累计分数_min": all_st["min"],
        "累计分数_max": all_st["max"],
        "累计分数_mean": all_st["mean"],
    }
    return pd.concat([df, pd.DataFrame([total_row])], ignore_index=True)


def format_score_percentile_band_table(df: pd.DataFrame) -> str:
    cols = [
        "score百分位",
        "总数",
        "分数_min",
        "分数_max",
        "分数_mean",
        "累计总数",
        "累计分数_min",
        "累计分数_max",
        "累计分数_mean",
    ]
    lines = ["\t".join(cols)]
    for _, row in df.iterrows():
        vals = []
        for c in cols:
            v = row[c]
            if c == "score百分位":
                vals.append(str(v))
            elif c in ("总数", "累计总数"):
                vals.append(f"{int(v):,}")
            else:
                vals.append(f"{float(v):.6f}")
        lines.append("\t".join(vals))
    return "\n".join(lines)


# 与同事表一致：顶部细粒度 top1%~4% + 每 5% 一档至全量
DEFAULT_TGI_PERCENTILES = [99, 98, 97, 96, *range(95, -1, -5)]

# TGI 过滤前 test 集各百分位档位的绝对人数（与同事验收表一致，非按当前 n 的百分比）
PRE_TGI_TEST_BAND_SIZES: dict[int, int] = {
    99: 46731,
    98: 46732,
    97: 46731,
    96: 46732,
    95: 46732,
    90: 46731,
    85: 46732,
    80: 46731,
    75: 46732,
    70: 46732,
    65: 46731,
    60: 46732,
    55: 46731,
    50: 46732,
    45: 46732,
    40: 46731,
    35: 46732,
    30: 46731,
    25: 46732,
    20: 46731,
    15: 46732,
    10: 46731,
    5: 46732,
}


def _resolve_tgi_percentiles(step: int = 5, percentiles: list[int] | None = None) -> list[int]:
    if percentiles is not None:
        return percentiles
    pct_list = [99, 98, 97, 96, *range(95, -1, -step)]
    seen: set[int] = set()
    out: list[int] = []
    for p in pct_list:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def _tgi_rows_for_fixed_bands(
    y_sorted: np.ndarray,
    n: int,
    n_pos_total: int,
    percentiles: list[int],
    band_sizes: dict[int, int],
) -> list[dict]:
    """按固定绝对人数分档（TGI 回归后 test 与 pre-TGI test 人数对齐）。"""
    rows: list[dict] = []
    prev_cum_n = 0
    prev_cum_pos = 0

    for p in sorted(percentiles, reverse=True):
        if p == 0:
            cum_n = n
        else:
            slice_n = int(band_sizes[p])
            cum_n = min(prev_cum_n + slice_n, n)
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


def tgi_percentile_table_fixed_bands(
    y_true: np.ndarray,
    y_score: np.ndarray,
    band_sizes: dict[int, int] | None = None,
    step: int = 5,
    percentiles: list[int] | None = None,
) -> pd.DataFrame:
    """
    TGI 回归后 test 评估：各档「总数」使用 pre-TGI test 的绝对人数，而非 round(n * pct)。
    p00 档为排序后剩余全量（n - 前面各档累计人数）。
    """
    y_true = np.asarray(y_true).astype(int)
    y_score = np.asarray(y_score).astype(float)
    order = np.argsort(-y_score, kind="mergesort")
    y_sorted = y_true[order]
    n = len(y_true)
    n_pos_total = int(y_sorted.sum())
    pct_list = _resolve_tgi_percentiles(step, percentiles)
    sizes = band_sizes or PRE_TGI_TEST_BAND_SIZES

    missing = [p for p in pct_list if p not in (0,) and p not in sizes]
    if missing:
        raise ValueError(f"固定分档缺少百分位人数配置: {missing}")

    rows = _tgi_rows_for_fixed_bands(y_sorted, n, n_pos_total, pct_list, sizes)
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


def tgi_percentile_table_from_config(
    y_true: np.ndarray,
    y_score: np.ndarray,
    eval_cfg: dict | None,
    step: int = 5,
    percentiles: list[int] | None = None,
) -> pd.DataFrame:
    """按配置选择 ratio 或 fixed 分档。"""
    eval_cfg = eval_cfg or {}
    mode = str(eval_cfg.get("tgi_band_mode", "ratio")).lower()
    if mode == "fixed":
        raw = eval_cfg.get("tgi_band_sizes") or PRE_TGI_TEST_BAND_SIZES
        band_sizes = {int(k): int(v) for k, v in raw.items()}
        return tgi_percentile_table_fixed_bands(
            y_true, y_score, band_sizes=band_sizes, step=step, percentiles=percentiles
        )
    return tgi_percentile_table(y_true, y_score, step=step, percentiles=percentiles)


def tgi_percentile_table(
    y_true: np.ndarray,
    y_score: np.ndarray,
    step: int = 5,
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
        percentiles = _resolve_tgi_percentiles(step)

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
