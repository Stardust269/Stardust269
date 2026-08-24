#!/usr/bin/env python3
"""
仅补算 TGI 顶部百分位（p99/p98/p97/p96 = top 1%~4%）。

推荐：--model + --data（直接打分，标签与分数天然对齐，无需重跑 report_eval）。
备选：--scores + --data（须含 unique_id + dt_zx + days_dt_zx 做 join）。
"""

from __future__ import annotations

import argparse
import gc
import sys
from pathlib import Path

import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config  # noqa: E402
from dataset import apply_filters, load_table  # noqa: E402
from memory_utils import release  # noqa: E402
from metrics import tgi_percentile_subset  # noqa: E402
from model_io import ScoringModel, slim_for_scoring  # noqa: E402

TOP_PERCENTILES = [99, 98, 97, 96]
JOIN_KEYS = ["unique_id", "dt_zx", "days_dt_zx"]


def _format_pct(x: float) -> str:
    if pd.isna(x):
        return ""
    return f"{x * 100:.2f}%"


def _print_table(df: pd.DataFrame) -> None:
    print("\n| tgi百分位 | 总数 | 种子用户数 | 累计总数 | 累计种子用户数 | recall | precision |")
    print("|-----------|------|------------|----------|----------------|--------|-----------|")
    for _, row in df.iterrows():
        print(
            f"| {row['tgi百分位']} "
            f"| {int(row['总数']):,} "
            f"| {int(row['种子用户数']):,} "
            f"| {int(row['累计总数']):,} "
            f"| {int(row['累计种子用户数']):,} "
            f"| {_format_pct(row['recall'])} "
            f"| {_format_pct(row['precision'])} |"
        )


def _sanity_check(y: np.ndarray, score: np.ndarray, df: pd.DataFrame) -> None:
    n_pos = int((y == 1).sum())
    order = np.argsort(-score, kind="mergesort")
    top1_n = max(int(round(len(y) * 0.01)), 1)
    top1_pos = int(y[order[:top1_n]].sum())
    top1_recall = top1_pos / n_pos if n_pos else 0.0
    print(f"\n[校验] 样本={len(y):,}，种子={n_pos:,}，top1% 命中种子={top1_pos}（recall≈{top1_recall:.2%}）")
    if top1_recall < 0.5:
        print(
            "警告: top1% recall 过低，分数与标签可能未对齐。"
            "请改用 --model + --data，或重新 predict 并保留 unique_id+dt_zx+days_dt_zx。"
        )
    # 与 p95 粗校：top5% recall 应明显高于 top4%
    top5_n = max(int(round(len(y) * 0.05)), 1)
    top5_pos = int(y[order[:top5_n]].sum())
    top5_recall = top5_pos / n_pos if n_pos else 0.0
    print(f"[校验] top5% recall≈{top5_recall:.2%}（应与 report 中 p95 的 ~69% 同量级）")


def _load_from_model(
    model_path: Path,
    data_path: Path,
    cfg: dict,
    config_path: Path,
    label_col: str,
    chunk_size: int,
) -> tuple[np.ndarray, np.ndarray]:
    print(f"加载 test 数据: {data_path}")
    df = load_table(data_path, cfg, config_path)
    if label_col not in df.columns:
        raise ValueError(f"标签列不存在: {label_col}")
    if cfg["data"].get("split_col") in df.columns and (df[cfg["data"]["split_col"]] == "test").any():
        df = apply_filters(df, cfg, restrict_splits=False)
    else:
        df = apply_filters(df, cfg)

    y = df[label_col].to_numpy(dtype=np.int8)
    mask = np.isin(y, [0, 1])
    y = y[mask]

    print("加载模型并分块打分（仅算 p99~p96，不重跑全表评估）...")
    scorer = ScoringModel(model_path)
    slim = slim_for_scoring(df.loc[mask], scorer.features, label_col)
    release(df)
    gc.collect()
    score = scorer.predict_chunked(slim, chunk_size=chunk_size)
    release(slim, scorer)
    gc.collect()
    return y, score.astype(np.float64)


def _join_labels_scores(
    labels_path: Path,
    scores_path: Path,
    label_col: str,
    score_col: str,
    cfg: dict | None,
    config_path: Path,
) -> tuple[np.ndarray, np.ndarray]:
    labels_df = load_table(labels_path, cfg, config_path)
    scores_df = pd.read_parquet(scores_path)
    if label_col not in labels_df.columns:
        raise ValueError(f"标签列不存在: {label_col}")
    if score_col not in scores_df.columns:
        raise ValueError(f"分数列不存在: {score_col}")

    keys = [c for c in JOIN_KEYS if c in labels_df.columns and c in scores_df.columns]
    if len(keys) < len([c for c in JOIN_KEYS if c in labels_df.columns]):
        missing = [c for c in JOIN_KEYS if c in labels_df.columns and c not in scores_df.columns]
        raise ValueError(
            f"scores 缺少 join 列 {missing}。请用最新 predict.py 重新导出（含 dt_zx/days_dt_zx），"
            "或改用 --model + --data。"
        )

    merged = labels_df[keys + [label_col]].merge(
        scores_df[keys + [score_col]], on=keys, how="inner", validate="one_to_one"
    )
    n_label = len(labels_df)
    n_merge = len(merged)
    print(f"[join] 标签行={n_label:,}，匹配行={n_merge:,}，join键={keys}")
    if n_merge < n_label * 0.99:
        raise ValueError(
            f"join 匹配率过低 ({n_merge}/{n_label})，分数与标签未对齐，请改用 --model + --data"
        )

    y = merged[label_col].to_numpy(dtype=np.int8)
    score = merged[score_col].to_numpy(dtype=np.float64)
    mask = np.isin(y, [0, 1])
    return y[mask], score[mask]


def _patch_existing_csv(existing: Path, new_rows: pd.DataFrame, out: Path) -> None:
    old = pd.read_csv(existing)
    if "tgi百分位" not in old.columns:
        raise ValueError(f"CSV 格式不符: {existing}")
    body = old[old["tgi百分位"] != "总计"].copy()
    total = old[old["tgi百分位"] == "总计"]

    def _pnum(s: str) -> int:
        if s == "总计":
            return -1
        return int(s[1:])

    labels = new_rows["tgi百分位"].tolist()
    body = body[~body["tgi百分位"].isin(labels)]
    combined = pd.concat([new_rows, body], ignore_index=True)
    combined = combined.sort_values(by="tgi百分位", key=lambda s: s.map(_pnum), ascending=False)
    pd.concat([combined, total], ignore_index=True).to_csv(out, index=False, encoding="utf-8-sig")


def main() -> None:
    parser = argparse.ArgumentParser(description="补算 p99~p96（top 1%~4%）TGI 指标")
    parser.add_argument("--data", type=Path, required=True, help="test_window.parquet（含 pu_label）")
    parser.add_argument("--model", type=Path, default=None, help="推荐：直接打分，避免 join 错位")
    parser.add_argument("--scores", type=Path, default=None, help="备选：已有分数 parquet")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--label-col", default="pu_label")
    parser.add_argument("--score-col", default="lookalike_score")
    parser.add_argument("--chunk-size", type=int, default=40_000)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--patch-csv", type=Path, default=None)
    parser.add_argument("--patch-out", type=Path, default=None)
    args = parser.parse_args()

    cfg = load_config(args.config) if args.config.exists() else None
    if args.model is not None:
        if cfg is None:
            raise ValueError("使用 --model 需要有效的 --config")
        y, score = _load_from_model(
            args.model, args.data, cfg, args.config, args.label_col, args.chunk_size
        )
    elif args.scores is not None:
        y, score = _join_labels_scores(
            args.data, args.scores, args.label_col, args.score_col, cfg, args.config
        )
    else:
        raise ValueError("请指定 --model（推荐）或 --scores")

    _sanity_check(y, score, pd.DataFrame())
    df = tgi_percentile_subset(y, score, TOP_PERCENTILES)
    _print_table(df)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(args.out, index=False, encoding="utf-8-sig")
        print(f"\n已写入 {args.out}")

    if args.patch_csv:
        patch_out = args.patch_out or args.patch_csv.with_name(args.patch_csv.stem + "_patched.csv")
        _patch_existing_csv(args.patch_csv, df, patch_out)
        print(f"已合并写入 {patch_out}")


if __name__ == "__main__":
    main()
