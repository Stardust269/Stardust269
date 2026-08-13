#!/usr/bin/env python3
"""
仅补算 TGI 顶部百分位（p99/p98/p97/p96 = top 1%~4%），无需重跑模型预测。

依赖已有 test 分数文件 + 带 pu_label 的 test parquet（或仅标签 + 分数 join）。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config  # noqa: E402
from dataset import load_table  # noqa: E402
from metrics import tgi_percentile_subset  # noqa: E402

TOP_PERCENTILES = [99, 98, 97, 96]


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


def _join_labels_scores(
    labels_path: Path,
    scores_path: Path,
    label_col: str,
    score_col: str,
    id_cols: list[str],
    cfg: dict | None,
    config_path: Path,
) -> tuple[pd.Series, pd.Series]:
    labels_df = load_table(labels_path, cfg, config_path)
    scores_df = pd.read_parquet(scores_path)
    if label_col not in labels_df.columns:
        raise ValueError(f"标签列不存在: {label_col}")
    if score_col not in scores_df.columns:
        raise ValueError(f"分数列不存在: {score_col}")

    keys = [c for c in id_cols if c in labels_df.columns and c in scores_df.columns]
    if keys:
        merged = labels_df[keys + [label_col]].merge(
            scores_df[keys + [score_col]], on=keys, how="inner"
        )
    else:
        if len(labels_df) != len(scores_df):
            raise ValueError("无法 join：请保证 scores 含 unique_id/dt_zx/days_dt_zx，或行数一致")
        merged = labels_df[[label_col]].copy()
        merged[score_col] = scores_df[score_col].to_numpy()

    y = merged[label_col]
    score = merged[score_col]
    mask = y.isin([0, 1])
    return y.loc[mask], score.loc[mask]


def _patch_existing_csv(existing: Path, new_rows: pd.DataFrame, out: Path) -> None:
    old = pd.read_csv(existing)
    if "tgi百分位" not in old.columns:
        raise ValueError(f"CSV 格式不符: {existing}")
    body = old[old["tgi百分位"] != "总计"].copy()
    total = old[old["tgi百分位"] == "总计"]
    labels = new_rows["tgi百分位"].tolist()
    body = body[~body["tgi百分位"].isin(labels)]
    # 新行插在 p95 之前（按百分位数字降序）
    def _pnum(s: str) -> int:
        if s == "总计":
            return -1
        return int(s[1:])

    combined = pd.concat([new_rows, body], ignore_index=True)
    combined = combined.sort_values(by="tgi百分位", key=lambda s: s.map(_pnum), ascending=False)
    out_df = pd.concat([combined, total], ignore_index=True)
    out_df.to_csv(out, index=False, encoding="utf-8-sig")


def main() -> None:
    parser = argparse.ArgumentParser(description="补算 p99~p96（top 1%~4%）TGI 指标")
    parser.add_argument("--scores", type=Path, required=True, help="test_window_scores.parquet")
    parser.add_argument("--data", type=Path, required=True, help="test_window.parquet（含 pu_label）")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--label-col", default="pu_label")
    parser.add_argument("--score-col", default="lookalike_score")
    parser.add_argument("--id-col", action="append", default=["unique_id", "dt_zx", "days_dt_zx"])
    parser.add_argument("--out", type=Path, default=None, help="输出 CSV（仅 p99~p96 四行）")
    parser.add_argument(
        "--patch-csv",
        type=Path,
        default=None,
        help="将四行插入已有 eval_report *_test_tgi_percentile.csv 并输出",
    )
    parser.add_argument("--patch-out", type=Path, default=None, help="--patch-csv 的输出路径（默认同目录 _patched）")
    args = parser.parse_args()

    cfg = load_config(args.config) if args.config.exists() else None
    y, score = _join_labels_scores(
        args.data,
        args.scores,
        args.label_col,
        args.score_col,
        args.id_col,
        cfg,
        args.config,
    )
    df = tgi_percentile_subset(y.to_numpy(), score.to_numpy(), TOP_PERCENTILES)
    _print_table(df)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(args.out, index=False, encoding="utf-8-sig")
        print(f"\n已写入 {args.out}")

    if args.patch_csv:
        patch_out = args.patch_out
        if patch_out is None:
            patch_out = args.patch_csv.with_name(args.patch_csv.stem + "_patched.csv")
        _patch_existing_csv(args.patch_csv, df, patch_out)
        print(f"已合并写入 {patch_out}")


if __name__ == "__main__":
    main()
