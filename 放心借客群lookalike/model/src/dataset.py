from __future__ import annotations

from pathlib import Path

import pandas as pd

from features import (
    get_required_load_columns,
    load_feature_whitelist,
    resolve_model_feature_columns,
    summarize_feature_groups,
)
from preprocess import build_model_matrix


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
        return pd.read_parquet(path, columns=columns)
    if path.suffix.lower() == ".csv":
        df = pd.read_csv(path)
        if columns is not None:
            keep = [c for c in columns if c in df.columns]
            df = df[keep]
        return df
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
    if ratio >= 1.0:
        return df
    pos = df[df[label_col] == 1]
    unl = df[df[label_col] == 0]
    n = max(int(len(unl) * ratio), 1)
    unl_sample = unl.sample(n=min(n, len(unl)), random_state=seed)
    return pd.concat([pos, unl_sample], ignore_index=True)


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

    split_col = cfg["data"]["split_col"]
    train_df = df[df[split_col] == cfg["data"]["train_split_value"]].copy()
    val_df = df[df[split_col] == cfg["data"]["val_split_value"]].copy()
    if train_df.empty or val_df.empty:
        raise ValueError("train 或 val 为空，请检查 dataset_split")

    meta = {
        "whitelist_size": len(whitelist) if whitelist else None,
        "missing_in_data": missing,
        "excluded_id_label": excluded,
    }
    return train_df, val_df, feature_columns, meta


def to_xy(df: pd.DataFrame, feature_columns: list[str], label_col: str):
    x = build_model_matrix(df, feature_columns)
    y = df[label_col].astype(int)
    return x, y


def feature_group_summary(feature_columns: list[str]) -> dict[str, list[str]]:
    return summarize_feature_groups(feature_columns)
