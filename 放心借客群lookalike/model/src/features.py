from __future__ import annotations

import json
from pathlib import Path

ID_COLUMNS = frozenset(
    {
        "unique_id",
        "user_id",
        "uuid",
        "contra_no",
        "zx_id_unqf",
    }
)

LABEL_AND_SPLIT = frozenset({"pu_label", "dataset_split", "is_seed", "label"})

# 用于定义 pu_label=1，不可入模（否则等价于记忆种子规则）
SEED_DEFINITION_LEAKAGE = frozenset(
    {
        "y_loan_base_rate",
        "lend_date_sj",
        "lend_amt",
        "org_credit_lim_yx",
        "if_ayh_types",
    }
)

RAW_DATE_COLUMNS = frozenset({"dt_zx", "days_dt_zx", "lend_date_sj"})

CATEGORICAL_COLUMNS = frozenset(
    {
        "latest_org_type",
        "d101",
        "d102",
        "d201",
        "d203",
        "d204",
        "d205",
        "d301",
        "d302",
        "d303",
        "d401",
        "d402",
        "D101",
        "D102",
        "D201",
        "D203",
        "D204",
        "D205",
        "D301",
        "D302",
        "D303",
        "D401",
        "D402",
    }
)

DERIVED_NUMERIC_COLUMNS = frozenset({"days_anchor_to_zx"})

EXCLUDE_FROM_FEATURES = (
    ID_COLUMNS
    | LABEL_AND_SPLIT
    | SEED_DEFINITION_LEAKAGE
    | RAW_DATE_COLUMNS
    | frozenset({"zx_has_report_flg"})
)


def load_feature_whitelist(path: Path) -> list[str]:
    """读取同事筛选特征白名单（txt 每行一列，或 json 数组）。"""
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(f"特征白名单不存在: {path}")
    if path.suffix.lower() == ".json":
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            raise ValueError(f"特征白名单 JSON 应为数组: {path}")
        return [str(c) for c in data]
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def get_required_load_columns(
    all_parquet_columns: list[str] | None,
    cfg: dict,
    whitelist: list[str],
) -> list[str]:
    """白名单 + 训练必需的 label/split/过滤列（用于 parquet 列裁剪加载）。"""
    data_cfg = cfg["data"]
    extra = {data_cfg["label_col"], data_cfg["split_col"], "label"}
    filt = data_cfg.get("filter", {})
    if filt.get("require_zx_report") and filt.get("zx_report_col"):
        extra.add(filt["zx_report_col"])
    cols = list(dict.fromkeys([*whitelist, *extra]))
    if all_parquet_columns is not None:
        available = set(all_parquet_columns)
        cols = [c for c in cols if c in available]
    return cols


def resolve_model_feature_columns(
    all_columns: list[str],
    cfg: dict,
    whitelist: list[str] | None = None,
) -> tuple[list[str], list[str], list[str]]:
    """
    返回 (入模特征, 白名单中缺失列, 白名单中排除列如 id/label)。
    未配置白名单时回退到全表自动筛特征。
    """
    if whitelist is not None:
        available = set(all_columns)
        model_features = [
            c for c in whitelist if c in available and c not in EXCLUDE_FROM_FEATURES
        ]
        missing = [
            c for c in whitelist if c not in available and c not in EXCLUDE_FROM_FEATURES
        ]
        excluded = [c for c in whitelist if c in EXCLUDE_FROM_FEATURES]
        return model_features, missing, excluded

    features = [c for c in all_columns if c not in EXCLUDE_FROM_FEATURES]
    if "days_anchor_to_zx" not in features:
        features.append("days_anchor_to_zx")
    return features, [], []


def get_model_feature_columns(all_columns: list[str]) -> list[str]:
    features, _, _ = resolve_model_feature_columns(all_columns, {}, None)
    return features


def summarize_feature_groups(columns: list[str]) -> dict[str, list[str]]:
    fxj = [c for c in columns if c.lower().startswith("d") and len(c) == 4]
    zx = [c for c in columns if c.startswith("latest_") or c.startswith("zx_")]
    ext = [c for c in columns if c not in fxj and c not in zx and c not in DERIVED_NUMERIC_COLUMNS]
    return {"fangxinjie_d": fxj, "credit_zx": zx, "external_other": ext, "derived": list(DERIVED_NUMERIC_COLUMNS)}
