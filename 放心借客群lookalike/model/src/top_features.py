from __future__ import annotations

import re
from pathlib import Path

import pandas as pd

from model_io import (
    load_feature_list,
    resolve_feature_display_name,
    resolve_model_features,
)

_IMPORTANCE_SUFFIX = re.compile(r"_feature_importance\.csv$", re.I)


def infer_model_path(importance_path: Path) -> Path | None:
    stem = _IMPORTANCE_SUFFIX.sub("", importance_path.name)
    for ext in (".txt", ".joblib"):
        candidate = importance_path.with_name(stem + ext)
        if candidate.exists():
            return candidate
    return None


def load_feature_list_for_model(model_path: Path | None, features_path: Path | None) -> list[str] | None:
    if features_path is not None:
        import json

        with features_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        return [str(x) for x in data]

    if model_path is None:
        return None

    sidecar = load_feature_list(model_path)
    if sidecar is not None:
        return sidecar

    if model_path.suffix == ".txt":
        return resolve_model_features(model_path)
    return None


def load_importance_table(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    cols = {c.lower(): c for c in df.columns}
    feat_col = cols.get("feature") or cols.get("column") or df.columns[0]
    gain_col = cols.get("gain") or cols.get("importance") or df.columns[1]
    out = df[[feat_col, gain_col]].copy()
    out.columns = ["feature", "gain"]
    out["gain"] = pd.to_numeric(out["gain"], errors="coerce").fillna(0)
    return out.sort_values("gain", ascending=False).reset_index(drop=True)


def load_top_feature_names(
    importance_path: Path,
    *,
    top: int = 10,
    model_path: Path | None = None,
    features_path: Path | None = None,
) -> list[str]:
    model_path = model_path or infer_model_path(importance_path)
    feature_list = load_feature_list_for_model(model_path, features_path)
    imp = load_importance_table(importance_path).head(top)
    names = [
        resolve_feature_display_name(row["feature"], feature_list)
        for _, row in imp.iterrows()
    ]
    return names
