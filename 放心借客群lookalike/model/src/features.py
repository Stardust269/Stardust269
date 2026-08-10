from __future__ import annotations

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


def get_model_feature_columns(all_columns: list[str]) -> list[str]:
    features = [c for c in all_columns if c not in EXCLUDE_FROM_FEATURES]
    if "days_anchor_to_zx" not in features:
        features.append("days_anchor_to_zx")
    return features


def summarize_feature_groups(columns: list[str]) -> dict[str, list[str]]:
    fxj = [c for c in columns if c.lower().startswith("d") and len(c) == 4]
    zx = [c for c in columns if c.startswith("latest_") or c.startswith("zx_")]
    ext = [c for c in columns if c not in fxj and c not in zx and c not in DERIVED_NUMERIC_COLUMNS]
    return {"fangxinjie_d": fxj, "credit_zx": zx, "external_other": ext, "derived": list(DERIVED_NUMERIC_COLUMNS)}
