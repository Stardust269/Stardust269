#!/usr/bin/env python3
"""从已保存的决策树探查 joblib 重新导出带种子占比标注的树图。"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from tree_viz import format_recall_summary_text, save_decision_tree_plot  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="绘制带种子占比的决策树图")
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()

    bundle = joblib.load(args.artifact)
    clf = bundle["clf"]
    features = bundle["feature_names"]
    node_stats = bundle.get("node_stats")
    recall_summary = bundle.get("seed_leaf_recall")
    if node_stats is None or recall_summary is None:
        raise ValueError(
            "joblib 中缺少 node_stats/seed_leaf_recall，请用新版 decision_tree_probe.py 重新跑一遍探查"
        )
    node_stats = {int(k): v for k, v in node_stats.items()}

    out = args.out or args.artifact.with_name(args.artifact.stem.replace(".joblib", "") + "_tree.png")
    if out.suffix == ".joblib":
        out = out.with_name(out.stem + "_tree.png")

    path, recall_summary, _ = save_decision_tree_plot(
        clf,
        features,
        out,
        node_stats=node_stats,
        recall_summary=recall_summary,
        dpi=args.dpi,
    )
    if recall_summary:
        print(format_recall_summary_text(recall_summary))
    print(f"已写入 {path}")


if __name__ == "__main__":
    main()
