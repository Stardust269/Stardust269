#!/usr/bin/env python3
"""在带标签的 test/val 集上计算整体 recall、precision、F1、AUC 等指标。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import load_table  # noqa: E402
from metrics import evaluate_scores  # noqa: E402
from preprocess import build_model_matrix  # noqa: E402


def _predict_scores(df: pd.DataFrame, model_path: Path) -> tuple[np.ndarray, list[str]]:
    if model_path.suffix == ".joblib":
        bundle = joblib.load(model_path)
        clf = bundle["model"]
        features = bundle["features"]
        x = build_model_matrix(df, features)
        if hasattr(clf, "predict_proba"):
            score = clf.predict_proba(x)[:, 1]
        else:
            score = clf.predict(x)
        return score, features

    import lightgbm as lgb

    booster = lgb.Booster(model_file=str(model_path))
    features = booster.feature_name()
    x = build_model_matrix(df, features)
    return booster.predict(x), features


def _load_labels_and_scores(args: argparse.Namespace, cfg: dict | None) -> tuple[pd.Series, np.ndarray]:
    label_col = args.label_col

    if args.scores is not None:
        scores_df = pd.read_parquet(args.scores)
        score_col = args.score_col
        if score_col not in scores_df.columns:
            raise ValueError(f"分数列不存在: {score_col}，可选: {list(scores_df.columns)}")

        labels_df = load_table(args.data, cfg, args.config)
        if label_col not in labels_df.columns:
            raise ValueError(f"标签列不存在: {label_col}")

        join_keys = [c for c in [args.id_col] if c in scores_df.columns and c in labels_df.columns]
        if join_keys:
            merged = labels_df[join_keys + [label_col]].merge(
                scores_df[join_keys + [score_col]], on=join_keys, how="inner"
            )
        else:
            if len(scores_df) != len(labels_df):
                raise ValueError(
                    "scores 与 data 行数不一致且无可 join 的 id 列，请保证顺序一致或提供 unique_id"
                )
            merged = labels_df[[label_col]].copy()
            merged[score_col] = scores_df[score_col].to_numpy()

        y = merged[label_col]
        score = merged[score_col].to_numpy(dtype=float)
        return y, score

    if args.model is None:
        raise ValueError("请指定 --model，或先用 predict.py 打分后传 --scores")

    df = load_table(args.data, cfg, args.config)
    if label_col not in df.columns:
        raise ValueError(f"标签列不存在: {label_col}，请确认 test parquet 含 pu_label")

    score, _ = _predict_scores(df, args.model)
    return df[label_col], score


def _print_report(metrics: dict) -> None:
    ranking = metrics["ranking"]
    threshold = metrics["threshold"]
    print("\n=== 样本概况 ===")
    print(f"样本数: {ranking.get('n_samples')}")
    print(f"正类: {ranking.get('n_positive')}，负类/未标注: {ranking.get('n_negative')}")
    print(f"正类占比: {ranking.get('positive_rate', 0):.4%}")

    print("\n=== 排序指标（不依赖阈值，推荐优先看） ===")
    if ranking.get("auc") is not None:
        print(f"AUC:     {ranking['auc']:.6f}")
        print(f"PR-AUC:  {ranking['pr_auc']:.6f}")
    print(f"正类均分: {ranking.get('mean_score_positive')}")
    print(f"负类均分: {ranking.get('mean_score_unlabeled')}")
    if ranking.get("score_gap_pos_minus_unl") is not None:
        print(f"分差:    {ranking['score_gap_pos_minus_unl']:.6f}")

    print(f"\n=== 固定阈值 threshold={threshold.get('threshold')} ===")
    if threshold.get("precision") is None:
        print(threshold.get("note", "无法计算"))
    else:
        print(f"Precision: {threshold['precision']:.6f}")
        print(f"Recall:    {threshold['recall']:.6f}")
        print(f"F1:        {threshold['f1']:.6f}")

    print("\n=== Top-K 截断（lookalike 常用：按分数取前 K%） ===")
    for name, block in metrics["top_k"].items():
        print(
            f"{name}: precision={block['precision']:.6f}, "
            f"recall={block['recall']:.6f}, f1={block['f1']:.6f}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="计算 test 集整体分类/排序指标")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--data", type=Path, required=True, help="带 pu_label 的 test parquet")
    parser.add_argument("--model", type=Path, default=None, help="train 产出的 .txt 或 .joblib")
    parser.add_argument(
        "--scores",
        type=Path,
        default=None,
        help="已打分的 parquet（含 lookalike_score），与 --data join 后算指标",
    )
    parser.add_argument("--score-col", default="lookalike_score")
    parser.add_argument("--label-col", default="pu_label")
    parser.add_argument("--id-col", default="unique_id")
    parser.add_argument("--threshold", type=float, default=0.5, help="二分类阈值")
    parser.add_argument("--out", type=Path, default=None, help="指标 JSON 输出路径")
    args = parser.parse_args()

    cfg = None
    if args.config.exists():
        cfg = load_config(args.config)

    y, score = _load_labels_and_scores(args, cfg)
    mask = y.isin([0, 1])
    if not mask.all():
        dropped = int((~mask).sum())
        print(f"警告: 丢弃 {dropped} 行无效标签")
        y = y.loc[mask]
        score = score[mask.to_numpy()]

    metrics = evaluate_scores(y.to_numpy(), score, threshold=args.threshold)
    _print_report(metrics)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with args.out.open("w", encoding="utf-8") as f:
            json.dump(metrics, f, ensure_ascii=False, indent=2)
        print(f"\n指标已写入 {args.out}")


if __name__ == "__main__":
    main()
