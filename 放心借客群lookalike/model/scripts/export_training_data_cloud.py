#!/usr/bin/env python3
"""云分析机导出 fxj_lookalike_pu_training。

请在终端执行: python scripts/export_training_data_cloud.py
不要在 Jupyter 里 %run 本脚本（会带上 -f kernel.json 导致 argparse 报错）。
请改用 notebooks/fxj_lookalike_cloud_train.ipynb。
"""
from __future__ import annotations

import argparse
import os

import dtools

DEFAULT_TABLE = "ai_decision_dev.fxj_lookalike_pu_training"
DEFAULT_OUT = "model/data/training_pu.parquet"


def build_query(
    table_name: str,
    splits: tuple[str, ...],
    unlabeled_frac: float,
    ms13_min: float,
    require_ms13: bool,
    limit: int | None,
) -> str:
    split_list = ", ".join(repr(s) for s in splits)
    extra = ""
    if require_ms13:
        extra += "\n  AND ms13_score IS NOT NULL"
    if ms13_min > 0:
        extra += f"\n  AND (pu_label = 1 OR ms13_score >= {ms13_min})"
    if unlabeled_frac < 1.0:
        extra += f"\n  AND (pu_label = 1 OR rand() < {unlabeled_frac})"
    limit_clause = f"\nLIMIT {limit}" if limit else ""
    return f"""
SELECT *
FROM {table_name}
WHERE dataset_split IN ({split_list})
{extra}
{limit_clause}
""".strip()


def main() -> None:
    p = argparse.ArgumentParser(description="Export PU training data via dtools")
    p.add_argument("--table", default=DEFAULT_TABLE)
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--unlabeled-frac", type=float, default=1.0)
    p.add_argument("--ms13-min", type=float, default=0.0)
    p.add_argument("--require-ms13", action="store_true")
    p.add_argument("--limit", type=int, default=None)
    args = p.parse_args()

    query = build_query(
        args.table,
        ("train", "val"),
        args.unlabeled_frac,
        args.ms13_min,
        args.require_ms13,
        args.limit,
    )
    print(query)
    df = dtools.get_as_frame(query)
    print(f"行数: {len(df)}, 列数: {len(df.columns)}")
    if "pu_label" in df.columns:
        print(df["pu_label"].value_counts().sort_index())

    out_dir = os.path.dirname(args.out) or "."
    os.makedirs(out_dir, exist_ok=True)
    if args.out.endswith(".csv"):
        df.to_csv(args.out, index=False)
    else:
        df.to_parquet(args.out, index=False)
    print("已保存", args.out)


if __name__ == "__main__":
    main()
