#!/usr/bin/env python3
"""从已保存的决策树探查 joblib 重新导出树图（无需重训）。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from tree_viz import save_decision_tree_plot  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="绘制决策树探查图")
    parser.add_argument(
        "--artifact",
        type=Path,
        required=True,
        help="dt_probe 产出的 .joblib（或同目录 *_tree.png 对应的 .joblib）",
    )
    parser.add_argument("--out", type=Path, default=None, help="输出 .png 或 .pdf")
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()

    bundle = joblib.load(args.artifact)
    clf = bundle["clf"]
    features = bundle["feature_names"]
    out = args.out or args.artifact.with_name(args.artifact.stem + "_tree.png")
    path = save_decision_tree_plot(clf, features, out, dpi=args.dpi)
    print(f"已写入 {path}")


if __name__ == "__main__":
    main()
