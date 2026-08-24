from __future__ import annotations

import numpy as np
import pandas as pd

from features import CATEGORICAL_COLUMNS


def build_training_arrays(
    df: pd.DataFrame,
    feature_columns: list[str],
    use_float32: bool = True,
) -> tuple[np.ndarray, list[int]]:
    """
    构建 LightGBM 训练矩阵（numpy），避免 pandas 宽表副本。
    数值列 float32；类别列编码为 float32 整数码（配合 categorical_feature 索引）。
    """
    n_rows = len(df)
    n_cols = len(feature_columns)
    dtype = np.float32 if use_float32 else np.float64
    matrix = np.full((n_rows, n_cols), np.nan, dtype=dtype)
    categorical_indices: list[int] = []

    for j, col in enumerate(feature_columns):
        if col not in df.columns:
            continue
        if col in CATEGORICAL_COLUMNS:
            series = df[col]
            if pd.api.types.is_string_dtype(series) or series.dtype == object:
                filled = series.fillna("__MISSING__")
            else:
                filled = series.astype("object").where(series.notna(), "__MISSING__")
            codes = pd.Categorical(filled).codes
            matrix[:, j] = codes.astype(dtype, copy=False)
            categorical_indices.append(j)
        else:
            col_values = df[col]
            if pd.api.types.is_numeric_dtype(col_values):
                matrix[:, j] = col_values.to_numpy(dtype=dtype, copy=False)
            else:
                matrix[:, j] = pd.to_numeric(col_values, errors="coerce").to_numpy(
                    dtype=dtype, na_value=np.nan, copy=False
                )

    return matrix, categorical_indices


def build_model_matrix(
    df: pd.DataFrame,
    feature_columns: list[str],
    use_float32: bool = True,
) -> pd.DataFrame:
    """预测/兼容接口：由 numpy 矩阵构造 float32 DataFrame（无整表 copy）。"""
    matrix, cat_indices = build_training_arrays(df, feature_columns, use_float32=use_float32)
    out = pd.DataFrame(matrix, columns=feature_columns)
    for idx in cat_indices:
        col = feature_columns[idx]
        out[col] = out[col].astype("int32").astype("category")
    return out
