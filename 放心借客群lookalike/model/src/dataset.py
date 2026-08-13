from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

from features import (
    get_required_load_columns,
    load_feature_whitelist,
    resolve_model_feature_columns,
    summarize_feature_groups,
)
from memory_utils import memory_cfg
from preprocess import build_training_arrays


def _parquet_column_names(path: Path) -> list[str]:
    import pyarrow.parquet as pq

    return pq.read_schema(path).names


def _load_feature_whitelist_from_cfg(cfg: dict, config_path: Path | None) -> list[str] | None:
    rel = cfg.get("data", {}).get("feature_list_path")
    if not rel:
        return None
    if config_path is None:
        raise ValueError("使用 feature_list_path 时必须提供 config_path")
    from config_loader import resolve_path

    return load_feature_whitelist(resolve_path(rel, config_path))


def _downcast_numeric(df: pd.DataFrame) -> pd.DataFrame:
    float_cols = df.select_dtypes(include=["float64"]).columns
    if len(float_cols):
        df[float_cols] = df[float_cols].astype(np.float32)
    int_cols = df.select_dtypes(include=["int64"]).columns
    for col in int_cols:
        if col in {"pu_label", "label", "dataset_split"}:
            continue
        df[col] = pd.to_numeric(df[col], downcast="integer")
    return df


def load_table(path: Path, cfg: dict | None = None, config_path: Path | None = None) -> pd.DataFrame:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"数据文件不存在: {path}")

    columns = None
    whitelist = None
    if cfg is not None:
        whitelist = _load_feature_whitelist_from_cfg(cfg, config_path)
        if whitelist is not None and path.suffix.lower() == ".parquet":
            parquet_cols = _parquet_column_names(path)
            columns = get_required_load_columns(parquet_cols, cfg, whitelist)

    if path.suffix.lower() == ".parquet":
        df = pd.read_parquet(path, columns=columns)
    elif path.suffix.lower() == ".csv":
        df = pd.read_csv(path)
        if columns is not None:
            keep = [c for c in columns if c in df.columns]
            df = df[keep]
    else:
        raise ValueError("仅支持 .parquet / .csv")

    if cfg is not None and memory_cfg(cfg.get("training", {})).get("use_float32", True):
        df = _downcast_numeric(df)
    return df


def apply_filters(df: pd.DataFrame, cfg: dict, *, restrict_splits: bool = True) -> pd.DataFrame:
    filt = cfg["data"].get("filter", {})
    label_col = cfg["data"]["label_col"]
    split_col = cfg["data"]["split_col"]
    mask = pd.Series(True, index=df.index)

    if filt.get("require_zx_report") and filt.get("zx_report_col") in df.columns:
        col = filt["zx_report_col"]
        mask &= df[col].fillna(0).astype(int) == 1

    ms13_min = float(filt.get("unlabeled_ms13_min") or 0)
    ms13_col = filt.get("ms13_col")
    if ms13_min > 0 and ms13_col and ms13_col in df.columns:
        is_pos = df[label_col] == 1
        ms13 = pd.to_numeric(df[ms13_col], errors="coerce")
        mask &= is_pos | (ms13 >= ms13_min)

    if label_col in df.columns:
        mask &= df[label_col].isin([0, 1])

    if restrict_splits and split_col in df.columns:
        allowed = {cfg["data"]["train_split_value"], cfg["data"]["val_split_value"]}
        mask &= df[split_col].isin(allowed)

    return df.loc[mask].reset_index(drop=True)


def subsample_unlabeled(df: pd.DataFrame, label_col: str, ratio: float, seed: int) -> pd.DataFrame:
    if ratio >= 1.0:
        return df
    pos = df[df[label_col] == 1]
    unl = df[df[label_col] == 0]
    n = max(int(len(unl) * ratio), 1)
    unl_sample = unl.sample(n=min(n, len(unl)), random_state=seed)
    return pd.concat([pos, unl_sample], ignore_index=True)


def _slim_columns(
    df: pd.DataFrame,
    feature_columns: list[str],
    label_col: str,
    split_col: str,
) -> pd.DataFrame:
    keep = list(dict.fromkeys([*feature_columns, label_col, split_col]))
    keep = [c for c in keep if c in df.columns]
    return df[keep]


def prepare_splits(
    df: pd.DataFrame,
    cfg: dict,
    config_path: Path | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame, list[str], dict]:
    whitelist = _load_feature_whitelist_from_cfg(cfg, config_path)
    feature_columns, missing, excluded = resolve_model_feature_columns(
        df.columns.tolist(), cfg, whitelist
    )
    if not feature_columns:
        raise ValueError("入模特征为空，请检查 feature_list_path 或数据列名")

    label_col = cfg["data"]["label_col"]
    split_col = cfg["data"]["split_col"]
    slim = _slim_columns(df, feature_columns, label_col, split_col)

    train_mask = slim[split_col] == cfg["data"]["train_split_value"]
    val_mask = slim[split_col] == cfg["data"]["val_split_value"]
    train_df = slim.loc[train_mask].reset_index(drop=True)
    val_df = slim.loc[val_mask].reset_index(drop=True)
    if train_df.empty or val_df.empty:
        raise ValueError("train 或 val 为空，请检查 dataset_split")

    meta = {
        "whitelist_size": len(whitelist) if whitelist else None,
        "missing_in_data": missing,
        "excluded_id_label": excluded,
    }
    return train_df, val_df, feature_columns, meta


def to_xy(
    df: pd.DataFrame,
    feature_columns: list[str],
    label_col: str,
    use_float32: bool = True,
):
    x, categorical_indices = build_training_arrays(
        df, feature_columns, use_float32=use_float32
    )
    y = df[label_col].to_numpy(dtype=np.int8, copy=False)
    return x, y, categorical_indices


def feature_group_summary(feature_columns: list[str]) -> dict[str, list[str]]:
    return summarize_feature_groups(feature_columns)
