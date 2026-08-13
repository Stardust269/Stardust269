from __future__ import annotations

import json
import re
from pathlib import Path

import joblib
import lightgbm as lgb


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


def resolve_model_features(model_path: Path, booster: lgb.Booster | None = None) -> list[str]:
    """解析入模特征名；兼容旧版 Column_0 命名（需同目录 *_features.json）。"""
    sidecar = load_feature_list(model_path)
    if sidecar is not None:
        return sidecar

    if booster is None:
        booster = lgb.Booster(model_file=str(model_path))
    names = booster.feature_name()
    if not booster_uses_generic_names(names):
        return names

    raise ValueError(
        f"模型 {model_path} 使用 Column_0 等占位特征名，且缺少 {features_sidecar_path(model_path)}。"
        "请用修复后的 train.py 重新训练，或手动生成特征列表 sidecar。"
    )


def load_joblib_model(model_path: Path):
    bundle = joblib.load(model_path)
    features = bundle.get("features")
    if not features:
        raise ValueError(f"joblib 模型缺少 features 字段: {model_path}")
    return bundle["model"], features
