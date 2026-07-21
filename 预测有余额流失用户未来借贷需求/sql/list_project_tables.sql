-- =============================================================================
-- 核验本人 jcr_* 表是否已清理干净（仅查 jcr 前缀，不涉及同事表）
-- =============================================================================

show tables in lj_iceberg.ai_decision_dev like 'jcr%';

-- 预期：重跑前应为空；Part0~2 跑完后应有 *_20260715 样本/cohort 表
-- select table_name
-- from lj_iceberg.ai_decision_dev.information_schema.tables
-- where table_schema = 'ai_decision_dev' and table_name like 'jcr_%'
-- order by table_name;
