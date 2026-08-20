-- 导出测试集（with_credit 全量宽表，days_dt_zx >= 6.22）→ model/data/test_window.parquet
-- 前置：sql/zyy_fxj_expansion_samples_train_val_test.sql

select *
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_with_credit_test
;
