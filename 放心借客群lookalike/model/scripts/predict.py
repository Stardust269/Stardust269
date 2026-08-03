#!/usr/bin/env python3
"""对未标注人群打分排序（lookalike 扩量名单）。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from dataset import load_table  # noqa: E402
from preprocess import build_model_matrix  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", type=Path, required=True, help="train 产出的 .joblib 或 .txt")
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=MODEL_ROOT / "data" / "scores.parquet")
    parser.add_argument("--top-k", type=int, default=0, help=">0 时仅输出 TopK")
    args = parser.parse_args()

    df = load_table(args.data)
    if args.model.suffix == ".joblib":
        bundle = joblib.load(args.model)
        clf = bundle["model"]
        features = bundle["features"]
        x = build_model_matrix(df, features)
        score = clf.predict_proba(x)[:, 1]
    else:
        import lightgbm as lgb

        booster = lgb.Booster(model_file=str(args.model))
        features = booster.feature_name()
        x = build_model_matrix(df, features)
        score = booster.predict(x)

    out = df[[c for c in ["unique_id"] if c in df.columns]].copy()
    out["lookalike_score"] = score
    out = out.sort_values("lookalike_score", ascending=False)
    if args.top_k > 0:
        out = out.head(args.top_k)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    out.to_parquet(args.out, index=False)
    print(f"已写入 {args.out}，行数={len(out)}")


if __name__ == "__main__":
    main()
