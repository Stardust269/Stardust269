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

# 标签构造直接相关，或与前向 60 天观察窗重叠 — 严禁入模
LEAKAGE_COLUMNS = frozenset(
    {
        "fwd_first_balance",
        "fwd_max_balance",
        # 与标签同窗口（锚点后 60 天）内的征信报告份数，属于未来信息
        "zx_report_cnt_fwd_60d",
    }
)

# cohort 五条件保证全样本恒定，无信息量
COHORT_CONSTANT_COLUMNS = frozenset(
    {
        "had_0_30_zx",  # 恒 = 1（cohort 要求锚点后 0~30 天有征信）
        "had_31_60_zx",  # 恒 = 1（cohort 要求锚点后 31~60 天有征信）
        "with_0_30",  # 恒 = 0（cohort 要求近 60 天无提现）
        "with_31_60",  # 恒 = 0
        "no_balance_flg_60",  # 恒 = 1（cohort 五条件之一）
    }
)

# 原始日期字符串；预处理会派生 days_since_last_zx（仅使用锚点当日及以前的报告日期）
RAW_DATE_COLUMNS = frozenset({"latest_dt_zx"})

CATEGORICAL_COLUMNS = frozenset({"m", "latest_org_type"})

DERIVED_NUMERIC_COLUMNS = frozenset({"days_since_last_zx"})

# 马消特征前缀/列名（用于文档与可选分组，训练时仍与征信一并入模）
MX_FEATURE_PREFIXES = ("pril_bal_", "crdt_lim_yx_", "pril_bal_rate_", "fq_cnt_", "suc_cnt_", "pass_rate_")

EXCLUDE_FROM_FEATURES = (
    ID_COLUMNS
    | META_COLUMNS
    | LEAKAGE_COLUMNS
    | COHORT_CONSTANT_COLUMNS
    | RAW_DATE_COLUMNS
    | {LABEL_COLUMN}
)


def get_model_feature_columns(all_columns: list[str]) -> list[str]:
    """从宽表列名中筛出模型特征（含后续派生列名预留）。"""
    features = [c for c in all_columns if c not in EXCLUDE_FROM_FEATURES]
    if "days_since_last_zx" not in features:
        features.append("days_since_last_zx")
    return features


def summarize_feature_groups(columns: list[str]) -> dict[str, list[str]]:
    """按业务含义粗分特征组（便于检查与解释）。"""
    mx = [c for c in columns if c.startswith(MX_FEATURE_PREFIXES)]
    credit = [c for c in columns if c not in mx and c not in DERIVED_NUMERIC_COLUMNS]
    derived = [c for c in columns if c in DERIVED_NUMERIC_COLUMNS]
    return {"credit_bureau": credit, "maxiao_behavior": mx, "derived": derived}
