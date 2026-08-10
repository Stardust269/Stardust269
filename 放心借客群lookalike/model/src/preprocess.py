from __future__ import annotations

import pandas as pd

from features import CATEGORICAL_COLUMNS


def build_model_matrix(df: pd.DataFrame, feature_columns: list[str]) -> pd.DataFrame:
    out = df.copy()

    if "days_dt_zx" in out.columns:
        anchor = pd.to_datetime(out["days_dt_zx"], errors="coerce")
        out["days_anchor_to_zx"] = 0.0
    else:
        out["days_anchor_to_zx"] = 0.0

    matrix = out.reindex(columns=feature_columns).copy()

    for col in matrix.columns:
        if col in CATEGORICAL_COLUMNS:
            matrix[col] = matrix[col].astype("string").fillna("__MISSING__").astype("category")
        else:
            matrix[col] = pd.to_numeric(matrix[col], errors="coerce")

    return matrix
