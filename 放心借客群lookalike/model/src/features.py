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
        "label",
        "y_loan_base_rate",
        "lend_date_sj",
        "lend_amt",
        "org_credit_lim_yx",
        "if_ayh_types",
    }
)

RAW_DATE_COLUMNS = frozenset({"dt_zx", "days_dt_zx", "lend_date_sj", "time_inst"})

# 排序/入库字段，非业务特征
NON_FEATURE_META = frozenset({"rnk", "rnk_2"})

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
    | NON_FEATURE_META
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


def missing_rate_series(df, col: str) -> float:
    """训练集上单列缺失率（空值、空字符串视为缺失）。"""
    if col not in df.columns:
        return 1.0
    s = df[col]
    if s.dtype == object or str(s.dtype).startswith("string"):
        miss = s.isna() | (s.astype(str).str.strip() == "") | (s.astype(str) == "nan")
    else:
        miss = s.isna()
    return float(miss.mean()) if len(s) else 1.0


def prune_features_by_missing_rate(
    train_df,
    feature_columns: list[str],
    max_missing_rate: float,
) -> tuple[list[str], list[dict]]:
    """
    在 train 划分上计算缺失率，剔除高于阈值的特征。
    max_missing_rate: 保留 missing_rate <= 该值的列（如 0.90 表示缺失>90%则删）。
    """
    if max_missing_rate >= 1.0:
        return feature_columns, []

    kept: list[str] = []
    dropped: list[dict] = []
    for col in feature_columns:
        rate = missing_rate_series(train_df, col)
        if rate > max_missing_rate:
            dropped.append({"feature": col, "missing_rate": round(rate, 6)})
        else:
            kept.append(col)
    return kept, dropped
