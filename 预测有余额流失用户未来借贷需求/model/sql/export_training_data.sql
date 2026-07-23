-- =============================================================================
-- 导出建模数据（在 Hive / Spark 平台执行后下载为 parquet 或 csv）
-- 本地路径建议：model/data/training_full.parquet
-- =============================================================================

select *
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where label_eligible = 1
  and zx_balance_label is not null
  and dataset_split in ('train', 'val')
  and m in ('202508', '202509', '202510');

-- Spark 落盘示例（路径按环境修改）：
-- write format parquet mode overwrite
--   path 'hdfs:///user/<you>/jcr_training_full_20260715'
--   as select * from ...
