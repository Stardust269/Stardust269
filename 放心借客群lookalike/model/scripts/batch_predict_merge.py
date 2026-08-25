#!/usr/bin/env python3
"""多分片 parquet 逐批打分、合并为全量分数表，并输出全局分布与排名。"""

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
sys.path.insert(0, str(MODEL_ROOT / "scripts"))
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config  # noqa: E402
from memory_utils import release  # noqa: E402
from model_io import ScoringModel, slim_for_scoring  # noqa: E402
from score_distribution import (  # noqa: E402
    _load_scoring_frame,
    _model_stem,
    score_histogram,
    summarize_scores,
    top_band_table,
)

DEFAULT_ID_COLS = ["unique_id", "dt_zx", "days_dt_zx"]
DEFAULT_DATA_TEMPLATE = "data/predict_one_month_part{part}.parquet"


def _resolve_data_path(template: str, part: int) -> Path:
    path = Path(template.format(part=part))
    if not path.is_absolute():
        path = (MODEL_ROOT / path).resolve()
    return path


def resolve_part_paths(template: str, parts: list[int]) -> list[Path]:
    paths = [_resolve_data_path(template, p) for p in parts]
    missing = [str(p) for p in paths if not p.exists()]
    if missing:
        hint = (
            f"默认数据目录: {(MODEL_ROOT / 'data').resolve()}\n"
            f"若数据在 model/data/ 下，可用: --data-template data/predict_one_month_part{{part}}.parquet"
        )
        raise FileNotFoundError(f"以下分片数据不存在:\n  " + "\n  ".join(missing) + f"\n\n{hint}")
    return paths


def score_one_part(
    data_path: Path,
    model_path: Path,
    config_path: Path,
    cfg: dict,
    *,
    chunk_size: int,
    require_zx: bool | None,
) -> tuple[pd.DataFrame, dict]:
    df, meta = _load_scoring_frame(data_path, cfg, config_path, require_zx=require_zx)
    id_cols = [c for c in DEFAULT_ID_COLS if c in df.columns]

    scorer = ScoringModel(
        model_path,
        config_path=config_path,
        data_path=data_path,
    )
    id_frame = df[id_cols].copy() if id_cols else pd.DataFrame(index=df.index)

    slim = slim_for_scoring(df, scorer.features)
    release(df)
    gc.collect()

    print(f"  分块打分 chunk_size={chunk_size:,}，行数={len(slim):,}...")
    scores = scorer.predict_chunked(slim, chunk_size=chunk_size)
    release(slim, scorer)
    gc.collect()

    out = id_frame.copy()
    out["lookalike_score"] = scores
    meta["n_scored"] = len(out)
    return out, meta


def merge_key_columns(df: pd.DataFrame) -> list[str]:
    if "unique_id" in df.columns and "dt_zx" in df.columns:
        return ["unique_id", "dt_zx"]
    if "unique_id" in df.columns:
        return ["unique_id"]
    raise ValueError("分数表缺少 unique_id，无法做主键校验与排名")


def merge_and_rank(parts: list[pd.DataFrame]) -> pd.DataFrame:
    if not parts:
        raise ValueError("无分片分数可合并")
    merged = pd.concat(parts, ignore_index=True)
    key_cols = merge_key_columns(merged)
    dup_mask = merged.duplicated(subset=key_cols, keep=False)
    if dup_mask.any():
        n_dup = int(dup_mask.sum())
        sample = merged.loc[dup_mask, key_cols].head(5).to_dict(orient="records")
        raise ValueError(f"合并后发现重复主键 {n_dup} 行，示例: {sample}")
    merged = merged.sort_values("lookalike_score", ascending=False).reset_index(drop=True)
    merged["global_rank"] = np.arange(1, len(merged) + 1, dtype=np.int64)
    return merged


def write_global_outputs(
    merged: pd.DataFrame,
    out_dir: Path,
    *,
    model_path: Path,
    part_meta: list[dict],
    top_k: int,
) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = "scores_all"

    all_path = out_dir / f"{stem}.parquet"
    merged.to_parquet(all_path, index=False)

    scores = merged["lookalike_score"].to_numpy()
    summary = summarize_scores(scores)
    hist = score_histogram(scores)
    bands = top_band_table(scores)

    summary_path = out_dir / f"{stem}_distribution_summary.json"
    with summary_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "model": str(model_path),
                "generated_at": datetime.now().isoformat(timespec="seconds"),
                "parts": part_meta,
                **summary,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    hist_path = out_dir / f"{stem}_distribution_histogram.csv"
    hist.to_csv(hist_path, index=False, encoding="utf-8-sig")

    bands_path = out_dir / f"{stem}_distribution_top_bands.csv"
    bands.to_csv(bands_path, index=False, encoding="utf-8-sig")

    pct_path = out_dir / f"{stem}_distribution_percentiles.csv"
    pd.DataFrame([summary["percentiles"]]).T.reset_index().rename(
        columns={"index": "percentile", 0: "score"}
    ).to_csv(pct_path, index=False)

    topk_path = None
    if top_k > 0:
        topk_path = out_dir / f"{stem}_top{top_k}.parquet"
        merged.head(top_k).to_parquet(topk_path, index=False)

    print(f"\n=== 全局分数分布（n={summary['n']:,}）===")
    print(f"mean={summary['mean']:.6f}  std={summary['std']:.6f}")
    print(f"min={summary['min']:.6f}  max={summary['max']:.6f}")
    for k, v in summary["percentiles"].items():
        print(f"  {k}: {v:.6f}")

    return {
        "n_total": summary["n"],
        "paths": {
            "scores_all": str(all_path),
            "summary": str(summary_path),
            "histogram": str(hist_path),
            "top_bands": str(bands_path),
            "percentiles": str(pct_path),
            "top_k": str(topk_path) if topk_path else None,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="多分片无标签数据：逐批打分 → 合并 → 全局排名与分布"
    )
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_predict_one_month.yaml")
    parser.add_argument(
        "--data-template",
        type=str,
        default=DEFAULT_DATA_TEMPLATE,
        help="分片路径模板（相对路径以 model/ 为根），{part} 占位，默认 data/predict_one_month_part{part}.parquet",
    )
    parser.add_argument(
        "--parts",
        type=int,
        nargs="+",
        default=[1, 2, 3, 4, 5],
        help="分片编号列表，默认 1 2 3 4 5",
    )
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--chunk-size", type=int, default=30_000)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=MODEL_ROOT / "artifacts" / "predict_one_month_scores",
    )
    parser.add_argument(
        "--require-zx-report",
        choices=["true", "false", "config"],
        default="config",
        help="是否仅保留 zx_has_report_flg=1（默认跟 config）",
    )
    parser.add_argument(
        "--skip-predict",
        action="store_true",
        help="跳过打分，仅从 out-dir 中读取已有 scores_part*.parquet 做合并",
    )
    parser.add_argument("--top-k", type=int, default=0, help=">0 时额外输出全局 TopK parquet")
    args = parser.parse_args()

    if not args.model.exists():
        raise SystemExit(f"模型不存在: {args.model}")

    cfg = load_config(args.config)
    require_zx = None
    if args.require_zx_report == "true":
        require_zx = True
    elif args.require_zx_report == "false":
        require_zx = False

    args.out_dir.mkdir(parents=True, exist_ok=True)
    model_stem = _model_stem(args.model)
    part_frames: list[pd.DataFrame] = []
    part_meta: list[dict] = []

    if args.skip_predict:
        for part in args.parts:
            score_path = args.out_dir / f"scores_part{part}.parquet"
            if not score_path.exists():
                raise FileNotFoundError(f"缺少分片分数: {score_path}")
            print(f"读取已有分数: {score_path}")
            df = pd.read_parquet(score_path)
            part_frames.append(df)
            part_meta.append({"part": part, "score_path": str(score_path), "n_scored": len(df)})
    else:
        data_paths = resolve_part_paths(args.data_template, args.parts)
        for part, data_path in zip(args.parts, data_paths, strict=True):
            score_path = args.out_dir / f"scores_part{part}.parquet"
            print(f"\n========== part{part}: {data_path} ==========")
            scored, meta = score_one_part(
                data_path,
                args.model,
                args.config,
                cfg,
                chunk_size=args.chunk_size,
                require_zx=require_zx,
            )
            scored.to_parquet(score_path, index=False)
            print(f"  已写入 {score_path}，行数={len(scored):,}")
            part_frames.append(scored)
            part_meta.append(
                {
                    "part": part,
                    "data_path": str(data_path),
                    "score_path": str(score_path),
                    **meta,
                }
            )
            release(scored)
            gc.collect()

    print("\n========== 合并全量分数 ==========")
    merged = merge_and_rank(part_frames)
    release(*part_frames)
    gc.collect()

    global_result = write_global_outputs(
        merged,
        args.out_dir,
        model_path=args.model,
        part_meta=part_meta,
        top_k=args.top_k,
    )
    release(merged)
    gc.collect()

    manifest = {
        "model": str(args.model),
        "model_stem": model_stem,
        "config": str(args.config),
        "data_template": args.data_template,
        "parts": args.parts,
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "part_meta": part_meta,
        "global": global_result,
    }
    manifest_path = args.out_dir / "batch_predict_manifest.json"
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\n全量分数: {global_result['paths']['scores_all']}")
    print(f"汇总清单: {manifest_path}")


if __name__ == "__main__":
    main()
