-- 导出训练+验证（时间窗 train，9:1）→ model/data/training_pu_train_window.parquet
-- 前置：sql/zyy_fxj_expansion_samples_train_val_test.sql

select *
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged
;
