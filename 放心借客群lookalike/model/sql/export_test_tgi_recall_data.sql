-- 导出 TGI 回归后 test → model/data/test_tgi_recall.parquet
-- 前置：sql/zyy_fxj_expansion_tgi_recall_samples_train_val_test.sql

select *
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged
;
