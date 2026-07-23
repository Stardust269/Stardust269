from __future__ import annotations

import pandas as pd

from features import CATEGORICAL_COLUMNS, RAW_DATE_COLUMNS


def _parse_yyyymmdd(series: pd.Series) -> pd.Series:
    s = series.astype(str).str.replace("-", "", regex=False).str[:8]
    return pd.to_datetime(s, format="%Y%m%d", errors="coerce")


def _parse_days_dt(series: pd.Series) -> pd.Series:
    return pd.to_datetime(series, errors="coerce")


def build_model_matrix(df: pd.DataFrame, feature_columns: list[str]) -> pd.DataFrame:
    """特征工程：派生数值列 + 类别列转 category。"""
    out = df.copy()

    if "days_dt" in out.columns and "latest_dt_zx" in out.columns:
        anchor = _parse_days_dt(out["days_dt"])
        last_zx = _parse_yyyymmdd(out["latest_dt_zx"])
        out["days_since_last_zx"] = (anchor - last_zx).dt.days

    matrix = out.reindex(columns=feature_columns).copy()

    for col in CATEGORICAL_COLUMNS:
        if col in matrix.columns:
            matrix[col] = matrix[col].astype("string").fillna("__MISSING__").astype("category")

    for col in matrix.columns:
        if col in CATEGORICAL_COLUMNS:
            continue
        matrix[col] = pd.to_numeric(matrix[col], errors="coerce")

    return matrix
