#!/usr/bin/env python3
"""生成与终表结构一致的演示数据，用于本地跑通训练流程。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))


def generate(n: int, seed: int) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    months = ["202508", "202509", "202510"]

    rows = []
    for i in range(n):
        m = rng.choice(months)
        month_day = rng.integers(1, 28)
        days_dt = f"2025-{m[4:6]}-{month_day:02d}"
        dt = days_dt.replace("-", "")

        latest_bal = float(rng.uniform(0, 50000))
        util = float(rng.uniform(0, 0.9))
        hard_q = int(rng.integers(0, 30))
        house = int(rng.random() < 0.2)
        gjj = int(rng.random() < 0.15)
        org = str(rng.integers(1, 10))

        score = (
            -1.2
            + 0.8 * util
            + 0.03 * hard_q
            + 0.4 * house
            + 0.3 * gjj
            + rng.normal(0, 0.5)
        )
        prob = 1 / (1 + np.exp(-score))
        label = int(rng.random() < prob)

        fwd_first = latest_bal * rng.uniform(0.8, 1.0)
        fwd_max = fwd_first * (1 + label * rng.uniform(0.05, 0.3))

        split = "train" if rng.random() < 0.8 else "val"

        rows.append(
            {
                "uuid": f"demo_{i:06d}",
                "user_id": 100000 + i,
                "pril_bal": latest_bal * 0.1,
                "crdt_lim_yx": latest_bal / max(util, 0.01),
                "pril_bal_rate": util * 0.1,
                "dt": dt,
                "days_dt": days_dt,
                "m": m,
                "no_balance_flg_30": 1,
                "no_balance_flg_60": 1,
                "no_balance_flg_90": 1,
                "had_0_30_zx": 1,
                "had_31_60_zx": 1,
                "had_61_90_zx": 0,
                "had_91_120_zx": 0,
                "with_0_30": 0,
                "with_31_60": 0,
                "with_61_90": 0,
                "with_91_120": 0,
                "latest_pos_bal_acct_cnt": rng.integers(1, 5),
                "avg_1m_pos_bal_acct_cnt": rng.uniform(1, 4),
                "avg_6m_pos_bal_acct_cnt": rng.uniform(1, 4),
                "avg_1y_pos_bal_acct_cnt": rng.uniform(1, 4),
                "latest_bal_sum": latest_bal,
                "latest_bal_max": latest_bal * 1.1,
                "latest_bal_min": latest_bal * 0.5,
                "avg_1m_bal_sum": latest_bal * rng.uniform(0.8, 1.1),
                "avg_6m_bal_sum": latest_bal * rng.uniform(0.7, 1.1),
                "avg_1y_bal_sum": latest_bal * rng.uniform(0.6, 1.1),
                "latest_crdt_sum": latest_bal / max(util, 0.01),
                "latest_util_sum": util,
                "latest_hard_query_num_1m": hard_q,
                "latest_has_house_loan_flg": house,
                "latest_has_gjj_loan_flg": gjj,
                "latest_credit_account_num": rng.integers(0, 5),
                "latest_credit_amount": rng.uniform(0, 80000),
                "latest_credit_used_amount": rng.uniform(0, 40000),
                "latest_credit_util_rate": rng.uniform(0, 0.9),
                "latest_org_type": org,
                "latest_dt_zx": (pd.Timestamp(days_dt) - pd.Timedelta(days=int(rng.integers(5, 120)))).strftime(
                    "%Y%m%d"
                ),
                "zx_report_cnt_1m": rng.integers(0, 3),
                "zx_report_cnt_6m": rng.integers(1, 6),
                "zx_report_cnt_1y": rng.integers(2, 12),
                "zx_report_cnt_fwd_60d": rng.integers(0, 4),
                "fwd_first_balance": fwd_first,
                "fwd_max_balance": fwd_max,
                "zx_balance_label": label,
                "label_eligible": 1,
                "dataset_split": split,
                "pril_bal_rate_1m": util * rng.uniform(0.8, 1.2),
                "pass_rate_1m": rng.uniform(0, 1),
                "fq_cnt_1m": int(rng.integers(0, 5)),
            }
        )

    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=MODEL_ROOT / "data/training_full.parquet")
    parser.add_argument("--rows", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    df = generate(args.rows, args.seed)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_parquet(args.output, index=False)
    print(f"写入 {len(df)} 行 -> {args.output.resolve()}")
    print(f"标签正样本率: {df['zx_balance_label'].mean():.3f}")
    print(f"train/val: {df['dataset_split'].value_counts().to_dict()}")


if __name__ == "__main__":
    main()
