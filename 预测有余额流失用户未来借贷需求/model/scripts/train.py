#!/usr/bin/env python3
"""LightGBM 二分类训练入口。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import apply_filters, load_table, prepare_splits, to_xy  # noqa: E402
from train_lgbm import save_artifacts, train_lightgbm  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Train LightGBM for zx_balance_label")
    parser.add_argument(
        "--config",
        type=Path,
        default=MODEL_ROOT / "config.yaml",
        help="配置文件路径",
    )
    parser.add_argument(
        "--data",
        type=Path,
        default=None,
        help="覆盖 config 中的 data.input_path",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    data_path = Path(args.data) if args.data else resolve_path(cfg["data"]["input_path"], args.config)

    print(f"加载数据: {data_path}")
    df = load_table(data_path)
    print(f"原始行数: {len(df)}")

    df = apply_filters(df, cfg)
    print(f"过滤后行数: {len(df)}")
    print(f"标签分布:\n{df[cfg['data']['label_col']].value_counts()}")

    train_df, val_df, feature_columns = prepare_splits(df, cfg)
    print(f"train={len(train_df)}, val={len(val_df)}, features={len(feature_columns)}")

    x_train, y_train = to_xy(train_df, feature_columns, cfg["data"]["label_col"])
    x_val, y_val = to_xy(val_df, feature_columns, cfg["data"]["label_col"])

    train_cfg = cfg["training"]
    booster, metrics = train_lightgbm(
        x_train=x_train,
        y_train=y_train,
        x_val=x_val,
        y_val=y_val,
        params=train_cfg["params"],
        num_boost_round=int(train_cfg["num_boost_round"]),
        early_stopping_rounds=int(train_cfg["early_stopping_rounds"]),
    )

    out_dir = resolve_path(cfg["output"]["artifacts_dir"], args.config)
    manifest = save_artifacts(
        booster=booster,
        metrics=metrics,
        feature_columns=feature_columns,
        output_dir=out_dir,
        model_name=cfg["output"]["model_name"],
    )

    print("\n=== 验证集指标 ===")
    print(json.dumps(metrics["val"], ensure_ascii=False, indent=2))
    print(f"\n模型已保存: {manifest['model_path']}")


if __name__ == "__main__":
    main()
