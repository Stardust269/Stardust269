#!/usr/bin/env python3
"""LightGBM + PU 训练入口（放心借 lookalike）。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import (  # noqa: E402
    apply_filters,
    feature_group_summary,
    load_split_table,
    load_table,
    prepare_splits,
    resolve_training_schema,
    subsample_unlabeled,
    to_xy,
)
from memory_utils import memory_cfg, release  # noqa: E402
from train_pu import (  # noqa: E402
    save_lgbm_artifacts,
    save_sklearn_pu_artifacts,
    train_elkanoto_pu,
    train_weighted_naive_pu,
)


def _matrix_gb(rows: int, cols: int) -> float:
    return rows * cols * 4 / (1024**3)


def _print_feature_meta(feat_meta: dict, feature_columns: list[str]) -> None:
    if feat_meta.get("whitelist_size"):
        print(
            f"同事特征白名单: {feat_meta['whitelist_size']} 列，"
            f"入模 {len(feature_columns)} 列，"
            f"数据中缺失 {len(feat_meta['missing_in_data'])} 列，"
            f"排除 id/label {len(feat_meta['excluded_id_label'])} 列"
        )
        if feat_meta["missing_in_data"][:5]:
            print(f"  缺失示例: {feat_meta['missing_in_data'][:5]}")


def _load_train_val_splits(
    data_path: Path,
    cfg: dict,
    config_path: Path,
    feature_columns: list[str],
    label_col: str,
    mem: dict,
    train_cfg: dict,
) -> tuple:
    use_float32 = bool(mem.get("use_float32", True))
    ratio = float(train_cfg.get("unlabeled_subsample_ratio", 1.0))
    seed = int(train_cfg["random_seed"])

    if mem.get("load_splits_separately", True):
        train_df = load_split_table(
            data_path,
            cfg,
            config_path,
            split_value=cfg["data"]["train_split_value"],
        )
        print(
            f"train 分片: {len(train_df)}，"
            f"正类={int((train_df[label_col] == 1).sum())}，"
            f"未标注={int((train_df[label_col] == 0).sum())}"
        )
        train_df = subsample_unlabeled(train_df, label_col, ratio, seed)

        x_train, y_train, cat_train = to_xy(
            train_df, feature_columns, label_col, use_float32=use_float32
        )
        print(f"x_train 矩阵约 {_matrix_gb(len(train_df), len(feature_columns)):.2f} GB (float32)")
        if mem.get("release_dataframes", True):
            release(train_df)

        val_df = load_split_table(
            data_path,
            cfg,
            config_path,
            split_value=cfg["data"]["val_split_value"],
        )
        print(
            f"val 分片: {len(val_df)}，"
            f"正类={int((val_df[label_col] == 1).sum())}，"
            f"未标注={int((val_df[label_col] == 0).sum())}"
        )
        x_val, y_val, cat_val = to_xy(val_df, feature_columns, label_col, use_float32=use_float32)
        print(f"x_val 矩阵约 {_matrix_gb(len(val_df), len(feature_columns)):.2f} GB (float32)")
        if mem.get("release_dataframes", True):
            release(val_df)
        return x_train, y_train, cat_train, x_val, y_val, cat_val, len(train_df), len(val_df)

    df = load_table(data_path, cfg, config_path)
    print(f"原始行数: {len(df)}，列数: {len(df.columns)}")
    df = apply_filters(df, cfg)
    print(
        f"过滤后: {len(df)}，"
        f"正类={int((df[label_col] == 1).sum())}，"
        f"未标注={int((df[label_col] == 0).sum())}"
    )
    train_df, val_df, _, _ = prepare_splits(df, cfg, config_path)
    if mem.get("release_dataframes", True):
        release(df)
    train_df = subsample_unlabeled(train_df, label_col, ratio, seed)

    x_train, y_train, cat_train = to_xy(
        train_df, feature_columns, label_col, use_float32=use_float32
    )
    print(f"x_train 矩阵约 {_matrix_gb(len(train_df), len(feature_columns)):.2f} GB (float32)")
    if mem.get("release_dataframes", True):
        release(train_df)

    x_val, y_val, cat_val = to_xy(val_df, feature_columns, label_col, use_float32=use_float32)
    print(f"x_val 矩阵约 {_matrix_gb(len(val_df), len(feature_columns)):.2f} GB (float32)")
    if mem.get("release_dataframes", True):
        release(val_df)
    return x_train, y_train, cat_train, x_val, y_val, cat_val, len(train_df), len(val_df)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train LightGBM + PU lookalike model")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config.yaml")
    parser.add_argument("--data", type=Path, default=None)
    args = parser.parse_args()

    cfg = load_config(args.config)
    train_cfg = cfg["training"]
    mem = memory_cfg(train_cfg)
    data_path = Path(args.data) if args.data else resolve_path(cfg["data"]["input_path"], args.config)
    label_col = cfg["data"]["label_col"]

    print(f"加载数据: {data_path}")
    feature_columns, feat_meta = resolve_training_schema(data_path, cfg, args.config)
    _print_feature_meta(feat_meta, feature_columns)

    x_train, y_train, cat_train, x_val, y_val, cat_val, n_train, n_val = _load_train_val_splits(
        data_path, cfg, args.config, feature_columns, label_col, mem, train_cfg
    )
    print(f"train={n_train} (下采样后), val={n_val}, features={len(feature_columns)}")
    print(
        f"内存优化: float32={mem.get('use_float32')}, split_load={mem.get('load_splits_separately')}, "
        f"release_train_matrix={mem.get('release_train_matrix')}, "
        f"free_raw_data={mem.get('lgb_free_raw_data')}, "
        f"skip_train_metrics={mem.get('skip_train_metrics')}, max_bin={mem.get('max_bin')}"
    )

    groups = feature_group_summary(feature_columns)
    print(
        f"特征: 放心借D={len(groups['fangxinjie_d'])}, 征信={len(groups['credit_zx'])}, "
        f"外部/其他={len(groups['external_other'])}"
    )

    categorical_indices = cat_train or cat_val
    pu_cfg = cfg["pu"]
    method = pu_cfg.get("method", "elkanoto")
    params = dict(train_cfg["params"])
    if mem.get("max_bin"):
        params.setdefault("max_bin", int(mem["max_bin"]))
    seed = int(train_cfg["random_seed"])

    if method == "elkanoto":
        clf, metrics = train_elkanoto_pu(
            x_train,
            y_train,
            x_val,
            y_val,
            feature_columns=feature_columns,
            categorical_indices=categorical_indices,
            params=params,
            hold_out_ratio=float(pu_cfg.get("hold_out_ratio", 0.1)),
            seed=seed,
            mem=mem,
        )
        out_dir = resolve_path(cfg["output"]["artifacts_dir"], args.config)
        manifest = save_sklearn_pu_artifacts(
            clf, metrics, feature_columns, out_dir, cfg["output"]["model_name"]
        )
    elif method == "weighted_naive":
        booster, metrics = train_weighted_naive_pu(
            x_train,
            y_train,
            x_val,
            y_val,
            feature_columns=feature_columns,
            categorical_indices=categorical_indices,
            params=params,
            unlabeled_weight=float(pu_cfg.get("unlabeled_weight", 0.05)),
            num_boost_round=int(train_cfg["num_boost_round"]),
            early_stopping_rounds=int(train_cfg["early_stopping_rounds"]),
            mem=mem,
        )
        out_dir = resolve_path(cfg["output"]["artifacts_dir"], args.config)
        manifest = save_lgbm_artifacts(
            booster, metrics, feature_columns, out_dir, cfg["output"]["model_name"]
        )
    else:
        raise ValueError(f"未知 pu.method: {method}")

    release(x_train, x_val, y_train, y_val)

    print("\n=== 验证集 PU 监控指标 ===")
    print(json.dumps(metrics["val"], ensure_ascii=False, indent=2))
    print(f"\n模型已保存: {manifest['model_path']}")
    if manifest.get("features_path"):
        print(f"特征列表: {manifest['features_path']}")


if __name__ == "__main__":
    main()
