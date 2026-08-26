from __future__ import annotations

import json
import re
from pathlib import Path

import joblib
import lightgbm as lgb
import numpy as np
import pandas as pd

from memory_utils import release
from preprocess import build_model_matrix, build_training_arrays


_COLUMN_RE = re.compile(r"^Column_(\d+)$")


def features_sidecar_path(model_path: Path) -> Path:
    return model_path.with_name(f"{model_path.stem}_features.json")


def save_feature_list(model_path: Path, features: list[str]) -> Path:
    path = features_sidecar_path(model_path)
    with path.open("w", encoding="utf-8") as f:
        json.dump(features, f, ensure_ascii=False, indent=2)
    return path


def load_feature_list(model_path: Path) -> list[str] | None:
    path = features_sidecar_path(model_path)
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"特征列表格式错误: {path}")
    return [str(c) for c in data]


def booster_uses_generic_names(feature_names: list[str]) -> bool:
    return bool(feature_names) and all(_COLUMN_RE.match(n) for n in feature_names)


def repair_feature_sidecar(
    model_path: Path,
    feature_columns: list[str],
    booster: lgb.Booster | None = None,
) -> Path:
    model_path = Path(model_path)
    if booster is None:
        booster = lgb.Booster(model_file=str(model_path))
    names = booster.feature_name()
    if not booster_uses_generic_names(names):
        raise ValueError(f"模型已是真实特征名，无需修复: {model_path}")
    if len(names) != len(feature_columns):
        raise ValueError(
            f"特征数不一致: 模型 {len(names)} vs 配置 {len(feature_columns)}"
        )
    return save_feature_list(model_path, feature_columns)


def resolve_model_features(
    model_path: Path,
    booster: lgb.Booster | None = None,
    *,
    config_path: Path | None = None,
    data_path: Path | None = None,
    auto_repair: bool = False,
) -> list[str]:
    """解析入模特征名；兼容旧版 Column_0 命名（需同目录 *_features.json）。"""
    model_path = Path(model_path)
    sidecar = load_feature_list(model_path)
    if sidecar is not None:
        return sidecar

    if booster is None:
        booster = lgb.Booster(model_file=str(model_path))
    names = booster.feature_name()
    if not booster_uses_generic_names(names):
        return names

    if auto_repair and config_path is not None:
        from config_loader import load_config, resolve_path
        from dataset import resolve_training_schema

        cfg = load_config(config_path)
        train_data = data_path or resolve_path(cfg["data"]["input_path"], config_path)
        feature_columns, _ = resolve_training_schema(train_data, cfg, config_path)
        sidecar_path = repair_feature_sidecar(model_path, feature_columns, booster)
        print(f"已自动补写特征 sidecar: {sidecar_path}（{len(feature_columns)} 列）")
        return feature_columns

    raise ValueError(
        f"模型 {model_path} 使用 Column_0 等占位特征名，且缺少 {features_sidecar_path(model_path)}。"
        "请运行 repair_lgb_features.py 补写 sidecar，或传入 config_path 自动修复。"
    )


def resolve_feature_display_name(name: str, feature_list: list[str] | None) -> str:
    """将 Column_N 映射为真实字段名；已是真实名则原样返回。"""
    m = _COLUMN_RE.match(str(name))
    if m and feature_list is not None:
        idx = int(m.group(1))
        if 0 <= idx < len(feature_list):
            return feature_list[idx]
    return str(name)


def resolve_feature_names(names: list[str], feature_list: list[str] | None) -> list[str]:
    return [resolve_feature_display_name(n, feature_list) for n in names]


def load_joblib_model(model_path: Path):
    bundle = joblib.load(model_path)
    features = bundle.get("features")
    if not features:
        raise ValueError(f"joblib 模型缺少 features 字段: {model_path}")
    return bundle["model"], features


class ScoringModel:
    """加载一次模型，支持分块打分（降低峰值内存）。"""

    def __init__(
        self,
        model_path: Path,
        *,
        config_path: Path | None = None,
        data_path: Path | None = None,
        auto_repair_features: bool = True,
    ):
        self.model_path = Path(model_path)
        self.is_joblib = self.model_path.suffix == ".joblib"
        if self.is_joblib:
            self.clf, self.features = load_joblib_model(self.model_path)
            self.booster = None
        else:
            self.booster = lgb.Booster(model_file=str(self.model_path))
            self.features = resolve_model_features(
                self.model_path,
                self.booster,
                config_path=config_path,
                data_path=data_path,
                auto_repair=auto_repair_features,
            )
            self.clf = None

    def predict_chunked(self, df: pd.DataFrame, chunk_size: int = 40_000) -> np.ndarray:
        n = len(df)
        scores = np.empty(n, dtype=np.float32)
        for start in range(0, n, chunk_size):
            end = min(start + chunk_size, n)
            chunk = df.iloc[start:end]
            if self.booster is not None:
                x, _ = build_training_arrays(chunk, self.features, use_float32=True)
                scores[start:end] = self.booster.predict(x)
                release(chunk, x)
            else:
                x = build_model_matrix(chunk, self.features)
                release(chunk)
                if hasattr(self.clf, "predict_proba"):
                    scores[start:end] = self.clf.predict_proba(x)[:, 1]
                else:
                    scores[start:end] = self.clf.predict(x)
                release(x)
        return scores


def slim_for_scoring(
    df: pd.DataFrame,
    features: list[str],
    label_col: str | None = None,
    extra_cols: list[str] | None = None,
) -> pd.DataFrame:
    base: list[str] = list(extra_cols or [])
    if label_col and label_col in df.columns:
        base.append(label_col)
    keep = list(dict.fromkeys([*base, *features]))
    keep = [c for c in keep if c in df.columns]
    return df[keep]
