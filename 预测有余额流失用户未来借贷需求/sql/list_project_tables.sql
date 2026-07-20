-- =============================================================================
-- 核验 ai_decision_dev 下本项目相关表是否已清理干净
-- 删表后执行；若仍有残留，用 drop_all_project_tables.sql 补删
-- =============================================================================

-- 方式1：按前缀列出（推荐）
show tables in lj_iceberg.ai_decision_dev like 'jcr%';
show tables in lj_iceberg.ai_decision_dev like 'yye%';
show tables in lj_iceberg.ai_decision_dev like 'ayh%';
show tables in lj_iceberg.ai_decision_dev like 'analyse_user%';

-- 方式2：information_schema（部分平台可用）
-- select table_name
-- from lj_iceberg.ai_decision_dev.information_schema.tables
-- where table_schema = 'ai_decision_dev'
--   and (
--        table_name like 'jcr_%'
--     or table_name like 'yye_%'
--     or table_name like 'ayh_%'
--     or table_name like 'analyse_user%'
--   )
-- order by table_name;

-- 方式3：关键表行数抽查（判断是否有百万级残留）
-- select 'jcr_pril_bal_info_raw_20260715' as tbl, count(1) as cnt from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
-- union all select 'yye_pril_bal_info_20260715_2', count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2
-- union all select 'ayh_feature_pril_bal_crdt_lim_yx', count(1) from lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx;
