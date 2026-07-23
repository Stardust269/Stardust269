from __future__ import annotations

from pathlib import Path

import pandas as pd

from features import get_model_feature_columns
from preprocess import build_model_matrix


def load_table(path: Path) -> pd.DataFrame:
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"数据文件不存在: {path}")

    suffix = path.suffix.lower()
    if suffix == ".parquet":
        return pd.read_parquet(path)
    if suffix == ".csv":
        return pd.read_csv(path)
    raise ValueError(f"不支持的格式: {suffix}，请使用 .parquet 或 .csv")


def apply_filters(df: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    filt = cfg["data"].get("filter", {})
    out = df.copy()

    if "label_eligible" in filt and "label_eligible" in out.columns:
        out = out[out["label_eligible"] == filt["label_eligible"]]

    if "months" in filt and "m" in out.columns:
        months = {str(m) for m in filt["months"]}
        out = out[out["m"].astype(str).isin(months)]

    label_col = cfg["data"]["label_col"]
    if label_col in out.columns:
        out = out[out[label_col].notna()]

    split_col = cfg["data"]["split_col"]
    if split_col in out.columns:
        allowed = {
            cfg["data"]["train_split_value"],
            cfg["data"]["val_split_value"],
        }
        out = out[out[split_col].isin(allowed)]

    return out.reset_index(drop=True)


def prepare_splits(df: pd.DataFrame, cfg: dict) -> tuple[pd.DataFrame, pd.DataFrame, list[str]]:
    feature_columns = get_model_feature_columns(df.columns.tolist())
    split_col = cfg["data"]["split_col"]

    train_df = df[df[split_col] == cfg["data"]["train_split_value"]].copy()
    val_df = df[df[split_col] == cfg["data"]["val_split_value"]].copy()

    if train_df.empty or val_df.empty:
        raise ValueError("train 或 val 为空，请检查导出数据与 dataset_split 划分")

    return train_df, val_df, feature_columns


def to_xy(
    df: pd.DataFrame,
    feature_columns: list[str],
    label_col: str,
) -> tuple[pd.DataFrame, pd.Series]:
    x = build_model_matrix(df, feature_columns)
    y = df[label_col].astype(int)
    return x, y


def feature_group_summary(feature_columns: list[str]) -> dict[str, list[str]]:
    from features import summarize_feature_groups

    return summarize_feature_groups(feature_columns)
