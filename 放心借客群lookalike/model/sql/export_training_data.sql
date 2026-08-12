-- 导出到本地：model/data/training_pu.parquet（或 csv）
-- 前置（二选一）：
--   build_pu_training_table.sql → fxj_lookalike_pu_training
--   build_pu_training_table_with_credit_1_sample.sql → fxj_lookalike_pu_training_1（抽样，约 40 万行）

-- 全量训练表
-- select * from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;

select *
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1
;
