#!/usr/bin/env python3
"""从 feature_importance.csv 提取 TopK 特征，并将 Column_N 译为真实字段名。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from top_features import (  # noqa: E402
    infer_model_path,
    load_feature_list_for_model,
    load_importance_table,
    load_top_feature_names,
    save_feature_name_list,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="提取 TopK 特征重要度并翻译 Column_N")
    parser.add_argument("--importance", type=Path, required=True)
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--features", type=Path, default=None)
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--out", type=Path, default=None, help="TopK 重要度 CSV")
    parser.add_argument(
        "--out-features",
        type=Path,
        default=None,
        help="TopK 特征名 txt（每行一列，供 config feature_list_path 训练）",
    )
    args = parser.parse_args()

    model_path = args.model or infer_model_path(args.importance)
    feature_list = load_feature_list_for_model(model_path, args.features)
    names = load_top_feature_names(
        args.importance, top=args.top, model_path=model_path, features_path=args.features
    )

    imp = load_importance_table(args.importance).head(args.top).copy()
    imp["feature"] = names
    imp["rank"] = range(1, len(imp) + 1)
    top = imp[["rank", "feature", "gain"]]

    if feature_list is None and top["feature"].str.match(r"^Column_\d+$").any():
        print(
            "警告: 未找到特征名映射。可先运行 repair_lgb_features.py 生成 *_features.json"
        )

    print(f"\n=== Top {args.top} 特征重要度（gain）===\n")
    print(top.to_string(index=False))

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        top.to_csv(args.out, index=False, encoding="utf-8-sig")
        print(f"\n已写入 {args.out}")

    if args.out_features:
        save_feature_name_list(names, args.out_features)
        print(f"特征白名单已写入 {args.out_features}（{len(names)} 列）")


if __name__ == "__main__":
    main()
