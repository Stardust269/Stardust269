#!/usr/bin/env python3
"""从已保存的决策树探查 joblib 导出带种子数/召回率标注的树图。

默认使用 joblib 内缓存的 train 节点统计；加 --split test 可从 test 数据重算并出图。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import load_split_minimal  # noqa: E402
from memory_utils import release  # noqa: E402
from tree_viz import (  # noqa: E402
    compute_node_statistics,
    format_recall_summary_text,
    save_decision_tree_plot,
    summarize_pred_seed_leaf_recall,
)


def _prepare_xy(df: pd.DataFrame, features: list[str], label_col: str):
    use = [c for c in features if c in df.columns]
    x = df[use].copy()
    for col in use:
        x[col] = pd.to_numeric(x[col], errors="coerce")
    y = df[label_col].astype(int).to_numpy()
    mask = np.isin(y, [0, 1]) & x.notna().all(axis=1).to_numpy()
    return x.loc[mask].to_numpy(dtype=np.float32), y[mask]


def _load_split_xy(
    split: str,
    features: list[str],
    label_col: str,
    cfg: dict,
    config_path: Path,
    train_data: Path | None,
    test_data: Path | None,
):
    if split == "test":
        if not test_data:
            raise ValueError("绘制 test 图需要 --test-data")
        print(f">>> 加载 test: {test_data}")
        df = load_split_minimal(
            test_data,
            cfg,
            config_path,
            features,
            split_value=None,
            restrict_splits=False,
        )
    else:
        if not train_data:
            train_data = resolve_path(cfg["data"]["input_path"], config_path)
        split_value = (
            cfg["data"]["train_split_value"]
            if split == "train"
            else cfg["data"]["val_split_value"]
        )
        print(f">>> 加载 {split}: {train_data} (split={split_value})")
        df = load_split_minimal(
            train_data,
            cfg,
            config_path,
            features,
            split_value=split_value,
            restrict_splits=True,
        )
    x, y = _prepare_xy(df, features, label_col)
    release(df)
    return x, y


def main() -> None:
    parser = argparse.ArgumentParser(description="绘制带种子数/召回率的决策树图")
    parser.add_argument("--artifact", type=Path, required=True, help="dt_probe .joblib")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument(
        "--split",
        choices=["cached", "train", "val", "test"],
        default="cached",
        help="cached=用 joblib 内 train 统计；train/val/test=从数据重算节点统计",
    )
    parser.add_argument("--data", type=Path, default=None, help="train+val parquet（split=train/val）")
    parser.add_argument("--test-data", type=Path, default=None, help="test parquet（split=test）")
    parser.add_argument("--out", type=Path, default=None, help="输出 .png/.pdf/.svg")
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()

    bundle = joblib.load(args.artifact)
    clf = bundle["clf"]
    features = bundle["feature_names"]
    cfg = load_config(args.config)
    label_col = cfg["data"]["label_col"]

    suffix_map = {
        "cached": "_tree",
        "train": "_tree_train",
        "val": "_tree_val",
        "test": "_tree_test",
    }
    default_out = args.artifact.with_name(
        args.artifact.stem.replace(".joblib", "") + suffix_map[args.split] + ".png"
    )
    out = args.out or default_out
    if out.suffix == ".joblib":
        out = out.with_name(out.stem + suffix_map[args.split] + ".png")

    if args.split == "cached":
        node_stats = bundle.get("node_stats")
        recall_summary = bundle.get("seed_leaf_recall")
        if node_stats is None or recall_summary is None:
            raise ValueError(
                "joblib 中缺少 node_stats/seed_leaf_recall；"
                "请用 --split train 从数据重算，或重跑 decision_tree_probe.py"
            )
        node_stats = {int(k): v for k, v in node_stats.items()}
        x = y = None
    else:
        x, y = _load_split_xy(
            args.split,
            features,
            label_col,
            cfg,
            args.config,
            args.data,
            args.test_data,
        )
        node_stats = compute_node_statistics(clf, x, y)
        recall_summary = summarize_pred_seed_leaf_recall(clf, node_stats, y)
        print(f">>> {args.split} 样本: n={len(y):,}, seeds={int(y.sum()):,}")

    path, recall_summary, _ = save_decision_tree_plot(
        clf,
        features,
        out,
        x=x,
        y=y,
        node_stats=node_stats,
        recall_summary=recall_summary,
        dpi=args.dpi,
    )
    if recall_summary:
        print(format_recall_summary_text(recall_summary))
    print(f"已写入 {path}")
    print(f"节点明细: {path.with_suffix('.csv')}")
    print(f"DOT 源文件: {path.with_suffix('.dot')}")


if __name__ == "__main__":
    main()
