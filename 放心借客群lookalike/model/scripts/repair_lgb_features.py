#!/usr/bin/env python3
"""为 Column_0 命名的旧版 .txt 模型补写 *_features.json（无需重训）。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import load_table, prepare_splits  # noqa: E402
from model_io import booster_uses_generic_names, save_feature_list  # noqa: E402

import lightgbm as lgb  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="补写 LightGBM 模型的特征名 sidecar")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument(
        "--data",
        type=Path,
        default=None,
        help="训练 parquet，用于还原入模特征顺序（默认 config.data.input_path）",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    data_path = args.data or resolve_path(cfg["data"]["input_path"], args.config)
    df = load_table(data_path, cfg, args.config)
    _, _, feature_columns, _ = prepare_splits(df, cfg, args.config)

    booster = lgb.Booster(model_file=str(args.model))
    names = booster.feature_name()
    if not booster_uses_generic_names(names):
        print(f"模型已是真实特征名（示例: {names[:3]}），无需修复")
        return
    if len(names) != len(feature_columns):
        raise ValueError(
            f"特征数不一致: 模型 {len(names)} vs 训练数据 {len(feature_columns)}，请确认 --data 与训练一致"
        )

    out = save_feature_list(args.model, feature_columns)
    print(f"已写入 {out}，共 {len(feature_columns)} 列")
    print("请重新运行 evaluate.py / predict.py")


if __name__ == "__main__":
    main()
