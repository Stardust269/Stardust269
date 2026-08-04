import os

import dtools

# 与 config.yaml export.unlabeled_sample_frac 一致；1.0 表示不抽背景
UNLABELED_SAMPLE_FRAC = 0.15

table_name = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training"
data_file = "data/training_pu.parquet"

sample_sql = ""
if UNLABELED_SAMPLE_FRAC < 1.0:
    sample_sql = f"\n  AND (pu_label = 1 OR rand() < {UNLABELED_SAMPLE_FRAC})"

query = f"""
SELECT *
FROM {table_name}
WHERE dataset_split IN ('train', 'val')
{sample_sql}
"""

df_data = dtools.get_as_frame(query)
print(f"行数: {len(df_data)}, 列数: {len(df_data.columns)}")
print(df_data["pu_label"].value_counts())

os.makedirs(os.path.dirname(data_file) or ".", exist_ok=True)
df_data.to_parquet(data_file, index=False)
print("已保存", data_file)
