import os

import dtools

# 同事预采样表（约 50 万负样本 + 正类），dtools 可整表加载
TABLE_NAME = "lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples"

# 全量 PU 表过大时用下面表名，并设 UNLABELED_SAMPLE_FRAC = 0.15
# TABLE_NAME = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training"

UNLABELED_SAMPLE_FRAC = 1.0
data_file = "data/training_pu.parquet"

# 若无 dataset_split 列，设 False，并在 config 中调整划分逻辑
FILTER_TRAIN_VAL_SPLIT = True

where_parts = []
if FILTER_TRAIN_VAL_SPLIT:
    where_parts.append("dataset_split IN ('train', 'val')")
if UNLABELED_SAMPLE_FRAC < 1.0:
    where_parts.append(f"(pu_label = 1 OR rand() < {UNLABELED_SAMPLE_FRAC})")

where_sql = ""
if where_parts:
    where_sql = "\nWHERE " + "\n  AND ".join(where_parts)

query = f"""
SELECT *
FROM {TABLE_NAME}
{where_sql}
"""

df_data = dtools.get_as_frame(query)
print(f"行数: {len(df_data)}, 列数: {len(df_data.columns)}")

if "pu_label" not in df_data.columns and "label" in df_data.columns:
    df_data["pu_label"] = df_data["label"].astype(int)
    print("已从 label 生成 pu_label")

label_col = "pu_label" if "pu_label" in df_data.columns else "label"
print(df_data[label_col].value_counts())

os.makedirs(os.path.dirname(data_file) or ".", exist_ok=True)
df_data.to_parquet(data_file, index=False)
print("已保存", data_file)
print("提示: 预采样表训练时建议 config.yaml 设 training.unlabeled_subsample_ratio: 1.0")
