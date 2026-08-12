#!/usr/bin/env python3
"""生成 PU 演示数据（无 Hive 时本地跑通训练）。"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", type=int, default=20000)
    parser.add_argument("--pos-ratio", type=float, default=0.03)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    n = args.rows
    n_pos = int(n * args.pos_ratio)

    rows = []
    for i in range(n):
        is_pos = i < n_pos
        rows.append(
            {
                "unique_id": f"u{i:08d}",
                "pu_label": 1 if is_pos else 0,
                "zx_has_report_flg": 1,
                "dataset_split": "train" if rng.random() < 0.8 else "val",
                "latest_bal_sum": float(rng.exponential(5000 if is_pos else 2000)),
                "latest_hard_query_num_1m": int(rng.poisson(2 if is_pos else 4)),
                "latest_credit_util_rate": float(rng.uniform(0, 0.9)),
                "zx_R1_bal_sum": float(rng.exponential(3000 if is_pos else 1000)),
                "zx_D1_bal_sum": float(rng.exponential(2000 if is_pos else 800)),
                "d401": str(rng.integers(1, 6)),
                "ms13_score": float(rng.normal(680 if is_pos else 640, 30)),
                "tx_score": float(rng.normal(0.2 if is_pos else 0.0, 0.5)),
            }
        )

    df = pd.DataFrame(rows)
    out = MODEL_ROOT / "data" / "training_pu.parquet"
    out.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(out, index=False)
    print(f"写入 {out}，行数={len(df)}，正类={n_pos}")


if __name__ == "__main__":
    main()
