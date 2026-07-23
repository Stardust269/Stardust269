from __future__ import annotations

# 终表 jcr_credit_feature_label_full_20260715 中不作为模型输入的列

ID_COLUMNS = frozenset({"uuid", "user_id", "dt", "days_dt"})

LABEL_COLUMN = "zx_balance_label"

META_COLUMNS = frozenset(
    {
        "label_eligible",
        "dataset_split",
    }
)

# 标签构造直接相关，严禁入模
LEAKAGE_COLUMNS = frozenset(
    {
        "fwd_first_balance",
        "fwd_max_balance",
    }
)

# 原始日期字符串；预处理会派生 days_since_last_zx
RAW_DATE_COLUMNS = frozenset({"latest_dt_zx"})

CATEGORICAL_COLUMNS = frozenset({"m", "latest_org_type"})

DERIVED_NUMERIC_COLUMNS = frozenset({"days_since_last_zx"})

EXCLUDE_FROM_FEATURES = (
    ID_COLUMNS | META_COLUMNS | LEAKAGE_COLUMNS | RAW_DATE_COLUMNS | {LABEL_COLUMN}
)


def get_model_feature_columns(all_columns: list[str]) -> list[str]:
    """从宽表列名中筛出模型特征（含后续派生列名预留）。"""
    features = [c for c in all_columns if c not in EXCLUDE_FROM_FEATURES]
    if "days_since_last_zx" not in features:
        features.append("days_since_last_zx")
    return features
