#!/usr/bin/env python3
"""从 feature_importance.csv 提取 TopK 特征，并将 Column_N 译为真实字段名。"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from model_io import (  # noqa: E402
    load_feature_list,
    resolve_feature_display_name,
    resolve_model_features,
)

_IMPORTANCE_SUFFIX = re.compile(r"_feature_importance\.csv$", re.I)


def _infer_model_path(importance_path: Path) -> Path | None:
    stem = _IMPORTANCE_SUFFIX.sub("", importance_path.name)
    for ext in (".txt", ".joblib"):
        candidate = importance_path.with_name(stem + ext)
        if candidate.exists():
            return candidate
    return None


def _load_feature_list_for_model(model_path: Path | None, features_path: Path | None) -> list[str] | None:
    if features_path is not None:
        import json

        with features_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return [str(x) for x in data]

    if model_path is None:
        return None

    sidecar = load_feature_list(model_path)
    if sidecar is not None:
        return sidecar

    if model_path.suffix == ".txt":
        return resolve_model_features(model_path)
    return None


def load_importance_table(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    # 兼容列名 feature / Feature / column 等
    cols = {c.lower(): c for c in df.columns}
    feat_col = cols.get("feature") or cols.get("column") or df.columns[0]
    gain_col = cols.get("gain") or cols.get("importance") or df.columns[1]
    out = df[[feat_col, gain_col]].copy()
    out.columns = ["feature", "gain"]
    out["gain"] = pd.to_numeric(out["gain"], errors="coerce").fillna(0)
    return out.sort_values("gain", ascending=False).reset_index(drop=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="提取 TopK 特征重要度并翻译 Column_N")
    parser.add_argument(
        "--importance",
        type=Path,
        required=True,
        help="*_feature_importance.csv 路径",
    )
    parser.add_argument(
        "--model",
        type=Path,
        default=None,
        help="对应 .txt / .joblib（默认从 importance 文件名推断）",
    )
    parser.add_argument(
        "--features",
        type=Path,
        default=None,
        help="*_features.json（可选，优先于 --model）",
    )
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--out", type=Path, default=None, help="输出 CSV 路径")
    args = parser.parse_args()

    model_path = args.model or _infer_model_path(args.importance)
    feature_list = _load_feature_list_for_model(model_path, args.features)

    imp = load_importance_table(args.importance)
    top = imp.head(args.top).copy()
    top["feature_raw"] = top["feature"]
    top["feature"] = top["feature_raw"].map(lambda x: resolve_feature_display_name(x, feature_list))
    top["rank"] = range(1, len(top) + 1)
    top = top[["rank", "feature", "gain", "feature_raw"]]

    if feature_list is None and top["feature"].str.match(r"^Column_\d+$").any():
        print(
            "警告: 未找到特征名映射（请提供同目录 *_features.json 或 --model）。"
            "可先运行: python scripts/repair_lgb_features.py --model <model.txt> --data <train.parquet>"
        )

    print(f"\n=== Top {args.top} 特征重要度（gain）===\n")
    print(top[["rank", "feature", "gain"]].to_string(index=False))

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        top.to_csv(args.out, index=False, encoding="utf-8-sig")
        print(f"\n已写入 {args.out}")


if __name__ == "__main__":
    main()
