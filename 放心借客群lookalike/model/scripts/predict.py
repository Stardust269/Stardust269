#!/usr/bin/env python3
"""对未标注人群打分排序（lookalike 扩量名单）。"""

from __future__ import annotations

import argparse
import gc
import sys
from pathlib import Path

import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from dataset import load_table  # noqa: E402
from memory_utils import release  # noqa: E402
from model_io import ScoringModel, slim_for_scoring  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True, help="train 产出的 .joblib 或 .txt")
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=MODEL_ROOT / "data" / "scores.parquet")
    parser.add_argument("--top-k", type=int, default=0, help=">0 时仅输出 TopK")
    parser.add_argument("--chunk-size", type=int, default=40_000, help="分块预测行数，OOM 可改为 20000")
    args = parser.parse_args()

    print(f"加载数据: {args.data}")
    df = load_table(args.data)
    id_cols = [c for c in ["unique_id", "dt_zx", "days_dt_zx"] if c in df.columns]
    ids = df[id_cols].copy() if id_cols else pd.DataFrame(index=df.index)

    print("加载模型...")
    scorer = ScoringModel(args.model)
    slim = slim_for_scoring(df, scorer.features, label_col="__dummy__")
    if "__dummy__" in slim.columns:
        slim = slim.drop(columns=["__dummy__"])
    release(df)
    gc.collect()

    print(f"分块打分（chunk_size={args.chunk_size:,}，行数={len(slim):,}）...")
    score = scorer.predict_chunked(slim, chunk_size=args.chunk_size)
    release(slim)
    gc.collect()

    out = ids.copy()
    out["lookalike_score"] = score
    out = out.sort_values("lookalike_score", ascending=False)
    if args.top_k > 0:
        out = out.head(args.top_k)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.to_parquet(args.out, index=False)
    print(f"已写入 {args.out}，行数={len(out)}")


if __name__ == "__main__":
    main()
