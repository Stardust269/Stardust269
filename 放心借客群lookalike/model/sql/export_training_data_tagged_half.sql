-- 导出半量同事训练集 → model/data/training_pu_half.parquet
-- 前置：sql/zyy_fxj_expansion_samples_tagged_half.sql

select *
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half
;
