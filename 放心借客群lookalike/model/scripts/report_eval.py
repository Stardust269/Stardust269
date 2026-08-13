#!/usr/bin/env python3
"""生成与同事对齐的完整评估报告（train/val/test AUC + Test TGI 百分位表）。

内存策略：串行处理 train → valid → test，每步加载→打分→写指标→释放，test 分块预测。
"""

from __future__ import annotations

import argparse
import gc
import json
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import load_split_table  # noqa: E402
from memory_utils import release  # noqa: E402
from metrics import pu_ranking_metrics, tgi_percentile_table  # noqa: E402
from model_io import ScoringModel, slim_for_scoring  # noqa: E402


def _format_pct(x: float) -> str:
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return ""
    return f"{x * 100:.2f}%"


def _ranking_markdown_table(rankings: list[dict]) -> str:
    lines = [
        "| 数据集 | 样本数 | 种子用户数 | 正类占比 | AUC | PR-AUC | 正类均分 | 负类均分 | 分差 |",
        "|--------|--------|------------|----------|-----|--------|----------|----------|------|",
    ]
    name_map = {"train": "train", "val": "valid", "test": "test"}
    for r in rankings:
        split = name_map.get(r["split"], r["split"])
        lines.append(
            f"| {split} "
            f"| {r['n_samples']:,} "
            f"| {r['n_positive']:,} "
            f"| {r['positive_rate']:.4%} "
            f"| {r.get('auc', float('nan')):.6f} "
            f"| {r.get('pr_auc', float('nan')):.6f} "
            f"| {r.get('mean_score_positive', float('nan')):.6f} "
            f"| {r.get('mean_score_unlabeled', float('nan')):.6f} "
            f"| {r.get('score_gap_pos_minus_unl', float('nan')):.6f} |"
        )
    return "\n".join(lines)


def _tgi_markdown_table(df: pd.DataFrame) -> str:
    lines = [
        "| tgi百分位 | 总数 | 种子用户数 | 累计总数 | 累计种子用户数 | recall | precision |",
        "|-----------|------|------------|----------|----------------|--------|-----------|",
    ]
    for _, row in df.iterrows():
        recall = _format_pct(row["recall"]) if row["tgi百分位"] != "总计" else ""
        precision = _format_pct(row["precision"]) if row["tgi百分位"] != "总计" else ""
        lines.append(
            f"| {row['tgi百分位']} "
            f"| {int(row['总数']):,} "
            f"| {int(row['种子用户数']):,} "
            f"| {int(row['累计总数']):,} "
            f"| {int(row['累计种子用户数']):,} "
            f"| {recall} "
            f"| {precision} |"
        )
    return "\n".join(lines)


def _build_report_md(model_path: Path, rankings: list[dict], tgi_df: pd.DataFrame) -> str:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return "\n".join(
        [
            "# 放心借 Lookalike 评估报告",
            "",
            f"- 生成时间: {ts}",
            f"- 模型: `{model_path}`",
            "",
            "## 一、排序指标（AUC / PR-AUC）",
            "",
            _ranking_markdown_table(rankings),
            "",
            "## 二、Test TGI 百分位表（与同事格式对齐）",
            "",
            "> p99 = 累计 top 1%，p98 = top 2%，p97 = top 3%，p96 = top 4%；"
        "p95 = 累计 top 5%，p90 = 累计 top 10%，以此类推；p00 = 全量。",
            "",
            _tgi_markdown_table(tgi_df),
            "",
        ]
    )


def _eval_one_split(
    scorer: ScoringModel,
    data_path: Path,
    cfg: dict,
    config_path: Path,
    label_col: str,
    split_name: str,
    split_value: str | None,
    chunk_size: int,
    restrict_splits: bool,
) -> dict:
    print(f"\n>>> [{split_name}] 1/3 加载数据（仅本分片）...")
    df = load_split_table(
        data_path,
        cfg,
        config_path,
        split_value=split_value,
        restrict_splits=restrict_splits,
    )
    if df.empty:
        raise ValueError(f"{split_name} 数据集为空")

    slim = slim_for_scoring(df, scorer.features, label_col)
    release(df)
    gc.collect()

    print(f">>> [{split_name}] 2/3 分块打分（chunk_size={chunk_size:,}，行数={len(slim):,}）...")
    y = slim[label_col].to_numpy(dtype=np.int8, copy=False)
    score = scorer.predict_chunked(slim, chunk_size=chunk_size)
    release(slim)
    gc.collect()

    print(f">>> [{split_name}] 3/3 计算指标...")
    ranking = pu_ranking_metrics(y, score)
    ranking["split"] = split_name
    release(y, score)
    gc.collect()
    return ranking


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 train/valid/test 评估报告（低内存串行）")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--train-data", type=Path, default=None)
    parser.add_argument("--test-data", type=Path, required=True)
    parser.add_argument("--label-col", default=None)
    parser.add_argument("--chunk-size", type=int, default=40_000, help="分块预测行数，OOM 可改为 20000")
    parser.add_argument("--out-dir", type=Path, default=MODEL_ROOT / "artifacts" / "eval_report")
    args = parser.parse_args()

    cfg = load_config(args.config)
    label_col = args.label_col or cfg["data"]["label_col"]
    train_data = args.train_data or resolve_path(cfg["data"]["input_path"], args.config)

    print(f"模型: {args.model}")
    print(f"train/val 数据: {train_data}")
    print(f"test 数据: {args.test_data}")
    print("加载模型（仅一次）...")
    scorer = ScoringModel(args.model)

    rankings: list[dict] = []

    rankings.append(
        _eval_one_split(
            scorer,
            train_data,
            cfg,
            args.config,
            label_col,
            "train",
            cfg["data"]["train_split_value"],
            args.chunk_size,
            restrict_splits=True,
        )
    )

    rankings.append(
        _eval_one_split(
            scorer,
            train_data,
            cfg,
            args.config,
            label_col,
            "val",
            cfg["data"]["val_split_value"],
            args.chunk_size,
            restrict_splits=True,
        )
    )

    # test：需保留 y/score 用于 TGI 表，但仍分块加载+打分
    print(f"\n>>> [test] 1/4 加载数据...")
    test_df = load_split_table(
        args.test_data,
        cfg,
        args.config,
        split_value=None,
        restrict_splits=False,
    )
    test_slim = slim_for_scoring(test_df, scorer.features, label_col)
    release(test_df)
    gc.collect()

    print(f">>> [test] 2/4 分块打分（行数={len(test_slim):,}）...")
    test_y = test_slim[label_col].to_numpy(dtype=np.int8, copy=False)
    test_score = scorer.predict_chunked(test_slim, chunk_size=args.chunk_size)
    release(test_slim)
    gc.collect()

    print(">>> [test] 3/4 计算 AUC + TGI 百分位表...")
    test_ranking = pu_ranking_metrics(test_y, test_score)
    test_ranking["split"] = "test"
    rankings.append(test_ranking)
    tgi_df = tgi_percentile_table(test_y, test_score, step=5)
    release(test_y, test_score)
    gc.collect()

    print(">>> [test] 4/4 写入报告...")
    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"eval_report_{ts}"

    md_path = out_dir / f"{stem}.md"
    csv_path = out_dir / f"{stem}_test_tgi_percentile.csv"
    json_path = out_dir / f"{stem}.json"

    md_text = _build_report_md(args.model, rankings, tgi_df)
    md_path.write_text(md_text, encoding="utf-8")
    tgi_df.to_csv(csv_path, index=False, encoding="utf-8-sig")

    payload = {
        "model": str(args.model),
        "generated_at": ts,
        "splits": {r["split"]: r for r in rankings},
        "test_tgi_percentile": tgi_df.to_dict(orient="records"),
    }
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    release(tgi_df, scorer)
    gc.collect()

    print(f"\n{md_text}")
    print("\n报告已写入:")
    print(f"  - {md_path}")
    print(f"  - {csv_path}")
    print(f"  - {json_path}")


if __name__ == "__main__":
    main()
