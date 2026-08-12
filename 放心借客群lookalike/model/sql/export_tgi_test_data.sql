-- 导出测试集（tgi_result 最后 7 天，不采样）→ model/data/tgi_test.parquet
-- 前置：sql/zyy_fxj_expansion_samples_train_val_test.sql

select *
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tgi_test
;
