#!/usr/bin/env python3
"""生成与同事对齐的完整评估报告（train/val/test AUC + Test TGI 百分位表）。"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import apply_filters, load_table  # noqa: E402
from metrics import pu_ranking_metrics, tgi_percentile_table  # noqa: E402
from model_io import load_joblib_model, resolve_model_features  # noqa: E402
from preprocess import build_model_matrix  # noqa: E402


def _predict(df: pd.DataFrame, model_path: Path) -> np.ndarray:
    if model_path.suffix == ".joblib":
        clf, features = load_joblib_model(model_path)
        x = build_model_matrix(df, features)
        if hasattr(clf, "predict_proba"):
            return clf.predict_proba(x)[:, 1]
        return clf.predict(x)

    import lightgbm as lgb

    booster = lgb.Booster(model_file=str(model_path))
    features = resolve_model_features(model_path, booster)
    x = build_model_matrix(df, features)
    return booster.predict(x)


def _load_split_df(
    path: Path,
    cfg: dict,
    config_path: Path,
    split_value: str | None,
) -> pd.DataFrame:
    df = load_table(path, cfg, config_path)
    restrict_splits = split_value is not None
    df = apply_filters(df, cfg, restrict_splits=restrict_splits)
    label_col = cfg["data"]["label_col"]
    if split_value is None:
        return df
    split_col = cfg["data"]["split_col"]
    return df[df[split_col] == split_value].reset_index(drop=True)


def _eval_split(
    df: pd.DataFrame,
    model_path: Path,
    label_col: str,
    split_name: str,
) -> dict:
    if df.empty:
        raise ValueError(f"{split_name} 数据集为空")
    score = _predict(df, model_path)
    y = df[label_col].to_numpy(dtype=int)
    ranking = pu_ranking_metrics(y, score)
    ranking["split"] = split_name
    return {"ranking": ranking, "y": y, "score": score}


def _format_pct(x: float) -> str:
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return ""
    return f"{x * 100:.2f}%"


def _ranking_markdown_table(splits: list[dict]) -> str:
    lines = [
        "| 数据集 | 样本数 | 种子用户数 | 正类占比 | AUC | PR-AUC | 正类均分 | 负类均分 | 分差 |",
        "|--------|--------|------------|----------|-----|--------|----------|----------|------|",
    ]
    name_map = {"train": "train", "val": "valid", "test": "test"}
    for item in splits:
        r = item["ranking"]
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


def _build_report_md(
    model_path: Path,
    splits: list[dict],
    tgi_df: pd.DataFrame,
) -> str:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    parts = [
        "# 放心借 Lookalike 评估报告",
        "",
        f"- 生成时间: {ts}",
        f"- 模型: `{model_path}`",
        "",
        "## 一、排序指标（AUC / PR-AUC）",
        "",
        _ranking_markdown_table(splits),
        "",
        "## 二、Test TGI 百分位表（与同事格式对齐）",
        "",
        "> p95 = 累计 top 5%，p90 = 累计 top 10%，以此类推；p00 = 全量。",
        "",
        _tgi_markdown_table(tgi_df),
        "",
    ]
    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(description="生成 train/valid/test 评估报告")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument(
        "--train-data",
        type=Path,
        default=None,
        help="含 train/val 划分的 parquet（默认 config.data.input_path）",
    )
    parser.add_argument("--test-data", type=Path, required=True)
    parser.add_argument("--label-col", default=None)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=MODEL_ROOT / "artifacts" / "eval_report",
        help="报告输出目录",
    )
    args = parser.parse_args()

    cfg = load_config(args.config)
    label_col = args.label_col or cfg["data"]["label_col"]
    train_data = args.train_data or resolve_path(cfg["data"]["input_path"], args.config)

    print(f"模型: {args.model}")
    print(f"train/val 数据: {train_data}")
    print(f"test 数据: {args.test_data}")

    train_df = _load_split_df(train_data, cfg, args.config, cfg["data"]["train_split_value"])
    val_df = _load_split_df(train_data, cfg, args.config, cfg["data"]["val_split_value"])
    test_df = _load_split_df(args.test_data, cfg, args.config, split_value=None)

    results = [
        _eval_split(train_df, args.model, label_col, "train"),
        _eval_split(val_df, args.model, label_col, "val"),
        _eval_split(test_df, args.model, label_col, "test"),
    ]

    tgi_df = tgi_percentile_table(results[-1]["y"], results[-1]["score"], step=5)

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = f"eval_report_{ts}"

    md_path = out_dir / f"{stem}.md"
    csv_path = out_dir / f"{stem}_test_tgi_percentile.csv"
    json_path = out_dir / f"{stem}.json"

    md_text = _build_report_md(args.model, results, tgi_df)
    md_path.write_text(md_text, encoding="utf-8")
    tgi_df.to_csv(csv_path, index=False, encoding="utf-8-sig")

    payload = {
        "model": str(args.model),
        "generated_at": ts,
        "splits": {r["ranking"]["split"]: r["ranking"] for r in results},
        "test_tgi_percentile": tgi_df.to_dict(orient="records"),
    }
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"\n{md_text}")
    print(f"\n报告已写入:")
    print(f"  - {md_path}")
    print(f"  - {csv_path}")
    print(f"  - {json_path}")


if __name__ == "__main__":
    main()
