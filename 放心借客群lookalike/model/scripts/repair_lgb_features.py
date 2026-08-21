#!/usr/bin/env python3
"""为 Column_0 命名的旧版 .txt 模型补写 *_features.json（无需重训）。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import resolve_training_schema  # noqa: E402
from model_io import booster_uses_generic_names, repair_feature_sidecar  # noqa: E402

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
    feature_columns, _ = resolve_training_schema(data_path, cfg, args.config)

    booster = lgb.Booster(model_file=str(args.model))
    names = booster.feature_name()
    if not booster_uses_generic_names(names):
        print(f"模型已是真实特征名（示例: {names[:3]}），无需修复")
        return

    out = repair_feature_sidecar(args.model, feature_columns, booster)
    print(f"已写入 {out}，共 {len(feature_columns)} 列")
    print("请重新运行 evaluate.py / predict.py / report_eval.py")


if __name__ == "__main__":
    main()
