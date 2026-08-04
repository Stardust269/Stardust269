from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from features import get_model_feature_columns, prune_features_by_missing_rate
from preprocess import build_model_matrix


def load_table(path: Path) -> pd.DataFrame:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"数据文件不存在: {path}")
    if path.suffix.lower() == ".parquet":
        return pd.read_parquet(path)
    if path.suffix.lower() == ".csv":
        return pd.read_csv(path)
    raise ValueError("仅支持 .parquet / .csv")


def apply_filters(df: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    out = df.copy()
    filt = cfg["data"].get("filter", {})

    if filt.get("require_zx_report") and filt.get("zx_report_col") in out.columns:
        col = filt["zx_report_col"]
        out = out[out[col].fillna(0).astype(int) == 1]

    ms13_min = float(filt.get("unlabeled_ms13_min") or 0)
    ms13_col = filt.get("ms13_col")
    label_col = cfg["data"]["label_col"]
    if ms13_min > 0 and ms13_col and ms13_col in out.columns:
        is_pos = out[label_col] == 1
        ms13 = pd.to_numeric(out[ms13_col], errors="coerce")
        out = out[is_pos | (ms13 >= ms13_min)]

    if label_col in out.columns:
        out = out[out[label_col].isin([0, 1])]

    split_col = cfg["data"]["split_col"]
    if split_col in out.columns:
        allowed = {cfg["data"]["train_split_value"], cfg["data"]["val_split_value"]}
        out = out[out[split_col].isin(allowed)]

    return out.reset_index(drop=True)


def subsample_unlabeled(df: pd.DataFrame, label_col: str, ratio: float, seed: int) -> pd.DataFrame:
    """对 label/pu_label=0 负采样；正类行全部保留。"""
    if ratio >= 1.0:
        return df
    pos = df[df[label_col] == 1]
    unl = df[df[label_col] == 0]
    n = max(int(len(unl) * ratio), len(pos) * 5)
    unl_sample = unl.sample(n=min(n, len(unl)), random_state=seed)
    return pd.concat([pos, unl_sample], ignore_index=True)


def prepare_splits(
    df: pd.DataFrame, cfg: dict
) -> tuple[pd.DataFrame, pd.DataFrame, list[str]]:
    feature_columns = get_model_feature_columns(df.columns.tolist())
    split_col = cfg["data"]["split_col"]
    train_df = df[df[split_col] == cfg["data"]["train_split_value"]].copy()
    val_df = df[df[split_col] == cfg["data"]["val_split_value"]].copy()
    if train_df.empty or val_df.empty:
        raise ValueError("train 或 val 为空，请检查 dataset_split")
    return train_df, val_df, feature_columns


def apply_feature_missing_filter(
    train_df: pd.DataFrame, feature_columns: list[str], cfg: dict
) -> tuple[list[str], list[dict]]:
    feat_cfg = cfg.get("features") or {}
    max_rate = float(feat_cfg.get("max_missing_rate", 1.0))
    return prune_features_by_missing_rate(train_df, feature_columns, max_rate)


def to_xy(df: pd.DataFrame, feature_columns: list[str], label_col: str):
    x = build_model_matrix(df, feature_columns)
    y = df[label_col].astype(int)
    return x, y


def feature_group_summary(feature_columns: list[str]) -> dict[str, list[str]]:
    from features import summarize_feature_groups

    return summarize_feature_groups(feature_columns)
