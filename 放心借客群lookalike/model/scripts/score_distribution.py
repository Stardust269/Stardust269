#!/usr/bin/env python3
"""无标签人群打分并输出分数分布（不做 AUC/TGI 等需 ground truth 的评估）。"""

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
from dataset import apply_filters, load_table, resolve_training_schema  # noqa: E402
from memory_utils import release  # noqa: E402
from metrics import format_score_percentile_band_table, score_percentile_band_table  # noqa: E402
from model_io import ScoringModel, slim_for_scoring  # noqa: E402

DEFAULT_PERCENTILES = [1, 5, 10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 99, 99.5, 99.9]


def _model_stem(model_path: Path) -> str:
    name = model_path.stem
    if name.startswith("lgbm_"):
        return name
    return f"model_{name}"


def summarize_scores(scores: np.ndarray) -> dict:
    s = np.asarray(scores, dtype=np.float64)
    s = s[np.isfinite(s)]
    if s.size == 0:
        raise ValueError("无有效分数")
    pct = {f"p{int(p) if p == int(p) else p}": float(np.percentile(s, p)) for p in DEFAULT_PERCENTILES}
    return {
        "n": int(s.size),
        "mean": float(s.mean()),
        "std": float(s.std()),
        "min": float(s.min()),
        "max": float(s.max()),
        "percentiles": pct,
    }


def score_histogram(scores: np.ndarray, *, bins: int = 20) -> pd.DataFrame:
    s = np.asarray(scores, dtype=np.float64)
    s = s[np.isfinite(s)]
    counts, edges = np.histogram(s, bins=bins, range=(0.0, 1.0))
    rows = []
    for i, cnt in enumerate(counts):
        lo, hi = edges[i], edges[i + 1]
        rows.append(
            {
                "bin": i + 1,
                "score_lo": float(lo),
                "score_hi": float(hi),
                "count": int(cnt),
                "ratio": float(cnt / len(s)) if len(s) else 0.0,
            }
        )
    return pd.DataFrame(rows)


def _print_summary(model_path: Path, summary: dict, bands: pd.DataFrame) -> None:
    print(f"\n=== {model_path.name} 全局统计（n={summary['n']:,}）===")
    print(f"mean={summary['mean']:.6f}  std={summary['std']:.6f}")
    print(f"min={summary['min']:.6f}  max={summary['max']:.6f}")
    print("\n=== score 百分位分布（p99=top1%，按分数从高到低）===")
    print(format_score_percentile_band_table(bands))


def _load_scoring_frame(
    data_path: Path,
    cfg: dict,
    config_path: Path,
    *,
    require_zx: bool | None,
) -> tuple[pd.DataFrame, dict]:
    feature_columns, feat_meta = resolve_training_schema(data_path, cfg, config_path)
    print(
        f"入模特征 {len(feature_columns)} 列；白名单 {feat_meta.get('whitelist_size')}；"
        f"缺失 {len(feat_meta.get('missing_in_data') or [])} 列"
    )
    if feat_meta.get("missing_in_data"):
        miss = feat_meta["missing_in_data"]
        print(f"  缺失示例: {miss[:8]}{'...' if len(miss) > 8 else ''}")

    df = load_table(data_path, cfg, config_path)
    n_raw = len(df)
    if require_zx is not None:
        cfg = json.loads(json.dumps(cfg))
        cfg["data"]["filter"]["require_zx_report"] = require_zx
    df = apply_filters(df, cfg, restrict_splits=False, skip_label_filter=True)
    print(f"加载 {n_raw:,} 行 → 过滤后 {len(df):,} 行（已跳过 label 0/1 过滤，label=-1 保留）")
    meta = {"n_raw": n_raw, "n_filtered": len(df), **feat_meta}
    return df, meta


def _run_one_model(
    model_path: Path,
    df: pd.DataFrame,
    cfg: dict,
    config_path: Path,
    data_path: Path,
    *,
    chunk_size: int,
    out_dir: Path,
    save_scores: bool,
    id_cols: list[str],
) -> dict:
    print(f"\n加载模型: {model_path}")
    id_frame = df[[c for c in id_cols if c in df.columns]].copy() if id_cols else None

    scorer = ScoringModel(
        model_path,
        config_path=config_path,
        data_path=data_path,
    )
    missing_model_feats = [c for c in scorer.features if c not in df.columns]
    if missing_model_feats:
        print(f"警告: 模型特征在数据中缺失 {len(missing_model_feats)} 列，打分列将为 NaN")
        print(f"  示例: {missing_model_feats[:5]}")

    slim = slim_for_scoring(df, scorer.features)
    release(df)
    gc.collect()

    print(f"分块打分 chunk_size={chunk_size:,}，行数={len(slim):,}...")
    scores = scorer.predict_chunked(slim, chunk_size=chunk_size)
    release(slim, scorer)
    gc.collect()

    summary = summarize_scores(scores)
    hist = score_histogram(scores)
    bands = score_percentile_band_table(scores)

    stem = _model_stem(model_path)
    out_dir.mkdir(parents=True, exist_ok=True)

    summary_path = out_dir / f"{stem}_distribution_summary.json"
    with summary_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "model": str(model_path),
                "generated_at": datetime.now().isoformat(timespec="seconds"),
                **summary,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )

    pct_path = out_dir / f"{stem}_distribution_percentiles.csv"
    pd.DataFrame([summary["percentiles"]]).T.reset_index().rename(
        columns={"index": "percentile", 0: "score"}
    ).to_csv(pct_path, index=False)

    hist_path = out_dir / f"{stem}_distribution_histogram.csv"
    hist.to_csv(hist_path, index=False, encoding="utf-8-sig")

    bands_path = out_dir / f"{stem}_score_percentile_bands.csv"
    bands.to_csv(bands_path, index=False, encoding="utf-8-sig")

    scores_path = None
    if save_scores:
        out = id_frame.copy() if id_frame is not None else pd.DataFrame(index=range(len(scores)))
        out["lookalike_score"] = scores
        scores_path = out_dir / f"{stem}_scores.parquet"
        out.to_parquet(scores_path, index=False)

    _print_summary(model_path, summary, bands)
    print(f"已写入: {summary_path}")
    print(f"百分位分布表: {bands_path}")
    if scores_path:
        print(f"分数 parquet: {scores_path}")

    return {
        "model": str(model_path),
        "summary": summary,
        "paths": {
            "summary": str(summary_path),
            "histogram": str(hist_path),
            "top_bands": str(bands_path),
            "score_percentile_bands": str(bands_path),
            "scores": str(scores_path) if scores_path else None,
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="无标签数据打分并统计分数分布")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_predict_one_month.yaml")
    parser.add_argument("--data", type=Path, default=None, help="覆盖 config.data.input_path")
    parser.add_argument("--model", type=Path, nargs="+", required=True, help="一个或多个 .txt/.joblib 模型")
    parser.add_argument("--chunk-size", type=int, default=30_000)
    parser.add_argument("--out-dir", type=Path, default=MODEL_ROOT / "artifacts" / "score_distribution")
    parser.add_argument(
        "--require-zx-report",
        choices=["true", "false", "config"],
        default="config",
        help="是否仅保留 zx_has_report_flg=1（默认跟 config）",
    )
    parser.add_argument("--save-scores", action="store_true", help="额外输出带 lookalike_score 的 parquet")
    args = parser.parse_args()

    cfg = load_config(args.config)
    data_path = args.data or resolve_path(cfg["data"]["input_path"], args.config)
    if not data_path.exists():
        raise SystemExit(f"数据不存在: {data_path}")

    require_zx = None
    if args.require_zx_report == "true":
        require_zx = True
    elif args.require_zx_report == "false":
        require_zx = False

    df, load_meta = _load_scoring_frame(
        data_path, cfg, args.config, require_zx=require_zx
    )
    id_cols = [c for c in ["unique_id", "dt_zx", "days_dt_zx"] if c in df.columns]

    results = []
    for model_path in args.model:
        if not model_path.exists():
            raise SystemExit(f"模型不存在: {model_path}")
        if results:
            df, _ = _load_scoring_frame(
                data_path, cfg, args.config, require_zx=require_zx
            )
        results.append(
            _run_one_model(
                model_path,
                df,
                cfg,
                args.config,
                data_path,
                chunk_size=args.chunk_size,
                out_dir=args.out_dir,
                save_scores=args.save_scores,
                id_cols=id_cols,
            )
        )
        release(df)
        gc.collect()

    manifest_path = args.out_dir / "distribution_manifest.json"
    args.out_dir.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", encoding="utf-8") as f:
        json.dump(
            {
                "data": str(data_path),
                "load_meta": load_meta,
                "models": results,
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"\n汇总清单: {manifest_path}")


if __name__ == "__main__":
    main()
