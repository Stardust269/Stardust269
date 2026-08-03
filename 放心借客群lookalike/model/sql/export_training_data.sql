-- 导出到本地：model/data/training_pu.parquet（或 csv）
-- 前置：build_pu_training_table.sql

select *
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
;
