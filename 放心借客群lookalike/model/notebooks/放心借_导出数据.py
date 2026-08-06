import os

import dtools

# 先 Spark 跑 sql/build_pu_training_table.sql，再从本表导出（含 pu_label、dataset_split）
TABLE_NAME = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training"

# 勿跳过 build 直接读同事采样表（无 dataset_split 会报错）：
# TABLE_NAME = "lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples"

UNLABELED_SAMPLE_FRAC = 1.0
data_file = "data/training_pu.parquet"

where_parts = ["dataset_split IN ('train', 'val')"]
if UNLABELED_SAMPLE_FRAC < 1.0:
    where_parts.append(f"(pu_label = 1 OR rand() < {UNLABELED_SAMPLE_FRAC})")

query = f"""
SELECT *
FROM {TABLE_NAME}
WHERE {" AND ".join(where_parts)}
"""

df_data = dtools.get_as_frame(query)
print(f"行数: {len(df_data)}, 列数: {len(df_data.columns)}")
print(df_data["pu_label"].value_counts())

os.makedirs(os.path.dirname(data_file) or ".", exist_ok=True)
df_data.to_parquet(data_file, index=False)
print("已保存", data_file)
