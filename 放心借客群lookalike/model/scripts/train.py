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
    load_table,
    prepare_splits,
    subsample_unlabeled,
    to_xy,
)
from train_pu import (  # noqa: E402
    save_lgbm_artifacts,
    save_sklearn_pu_artifacts,
    train_elkanoto_pu,
    train_weighted_naive_pu,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train LightGBM + PU lookalike model")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config.yaml")
    parser.add_argument("--data", type=Path, default=None)
    args = parser.parse_args()

    cfg = load_config(args.config)
    data_path = Path(args.data) if args.data else resolve_path(cfg["data"]["input_path"], args.config)

    print(f"加载数据: {data_path}")
    df = load_table(data_path, cfg, args.config)
    print(f"原始行数: {len(df)}，列数: {len(df.columns)}")

    df = apply_filters(df, cfg)
    label_col = cfg["data"]["label_col"]
    print(f"过滤后: {len(df)}，正类={int((df[label_col]==1).sum())}，未标注={int((df[label_col]==0).sum())}")

    train_df, val_df, feature_columns, feat_meta = prepare_splits(df, cfg, args.config)
    if feat_meta.get("whitelist_size"):
        print(
            f"同事特征白名单: {feat_meta['whitelist_size']} 列，"
            f"入模 {len(feature_columns)} 列，"
            f"数据中缺失 {len(feat_meta['missing_in_data'])} 列，"
            f"排除 id/label {len(feat_meta['excluded_id_label'])} 列"
        )
        if feat_meta["missing_in_data"][:5]:
            print(f"  缺失示例: {feat_meta['missing_in_data'][:5]}")
    ratio = float(cfg["training"].get("unlabeled_subsample_ratio", 1.0))
    seed = int(cfg["training"]["random_seed"])
    train_df = subsample_unlabeled(train_df, label_col, ratio, seed)
    print(f"train={len(train_df)} (下采样后), val={len(val_df)}, features={len(feature_columns)}")

    groups = feature_group_summary(feature_columns)
    print(
        f"特征: 放心借D={len(groups['fangxinjie_d'])}, 征信={len(groups['credit_zx'])}, "
        f"外部/其他={len(groups['external_other'])}"
    )

    x_train, y_train = to_xy(train_df, feature_columns, label_col)
    x_val, y_val = to_xy(val_df, feature_columns, label_col)

    pu_cfg = cfg["pu"]
    train_cfg = cfg["training"]
    method = pu_cfg.get("method", "elkanoto")

    if method == "elkanoto":
        clf, metrics = train_elkanoto_pu(
            x_train,
            y_train,
            x_val,
            y_val,
            params=train_cfg["params"],
            hold_out_ratio=float(pu_cfg.get("hold_out_ratio", 0.1)),
            seed=seed,
        )
        out_dir = resolve_path(cfg["output"]["artifacts_dir"], args.config)
        manifest = save_sklearn_pu_artifacts(
            clf, metrics, feature_columns, out_dir, cfg["output"]["model_name"]
        )
    elif method == "weighted_naive":
        params = dict(train_cfg["params"])
        booster, metrics = train_weighted_naive_pu(
            x_train,
            y_train,
            x_val,
            y_val,
            params=params,
            unlabeled_weight=float(pu_cfg.get("unlabeled_weight", 0.05)),
            num_boost_round=int(train_cfg["num_boost_round"]),
            early_stopping_rounds=int(train_cfg["early_stopping_rounds"]),
            seed=seed,
        )
        out_dir = resolve_path(cfg["output"]["artifacts_dir"], args.config)
        manifest = save_lgbm_artifacts(
            booster, metrics, feature_columns, out_dir, cfg["output"]["model_name"]
        )
    else:
        raise ValueError(f"未知 pu.method: {method}")

    print("\n=== 验证集 PU 监控指标 ===")
    print(json.dumps(metrics["val"], ensure_ascii=False, indent=2))
    print(f"\n模型已保存: {manifest['model_path']}")


if __name__ == "__main__":
    main()
