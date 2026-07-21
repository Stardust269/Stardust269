-- =============================================================================
-- 删除本人产出的 jcr_*_20260715 表（三月样本版，共 15 张）
-- 十月版本人表见：sql/drop_all_jcr_tables.sql
-- 核验残留：sql/list_project_tables.sql
-- 注意：yye_* / ayh_* 为同事表，请勿删除
-- =============================================================================

-- 【可选】删前先查哪些表存在
-- select table_name
-- from lj_iceberg.ai_decision_dev.information_schema.tables
-- where table_schema = 'ai_decision_dev'
--   and table_name like 'jcr_%_20260715'
-- order by table_name;

-- =============================================================================
-- A. 全量删除（15 张，重跑完整链路前执行）
-- 顺序：先下游后上游（Part 8 → Part 0）
-- =============================================================================

-- Part 8  征信 + 马消终表
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 purge;

-- Part 7  征信特征 + 标签
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 purge;

-- Part 6  特征宽表
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 purge;

-- Part 5  样本关联征信
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715 purge;

-- Part 4  征信扩展（查询/逾期/信用卡/资质）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 purge;

-- Part 3  账单日聚合
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 purge;

-- Part 2  报告级循环贷聚合
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 purge;

-- Part 1  账户级明细
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 purge;

-- Part 1  cohort 子集名单
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;

-- Part 1  样本终表 + 中间表
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;

-- Part 1  无余额标识
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;

-- Part 1  月内快照 + rk
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;

-- =============================================================================
-- B. 分场景删除（按需选用，不要与 A 重复执行）
-- =============================================================================

-- B1. 仅重跑 Part 5~8（样本 Part 1 及征信 Step 1~4 保留）
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 purge;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 purge;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 purge;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715 purge;

-- B2. 仅重跑 Part 8（马消关联；需同事 ayh_feature_* 表已存在）
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 purge;

-- =============================================================================
-- C. 删后重跑指引
-- =============================================================================
-- 1. 同事先跑：sql/yye_pril_bal_sample_reference_20260715.sql（样本 + 马消特征）
-- 2. 我方再跑：sql/run_all_20260715.sql（征信特征 + 标签 + 关联马消）
-- 核验：run_all_20260715.sql 末尾 Part 9 统计 SQL
