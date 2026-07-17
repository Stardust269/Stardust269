-- =============================================================================
-- 删除本项目产出的全部 jcr_ 个人表
-- 主流程：sql/yye_credit_feature_process.sql（Step 0a ~ Step 7）
-- 若平台一次只能跑一条 SQL，请逐条执行下面 drop
-- =============================================================================

-- 【可选】删前先查哪些表存在
-- select table_name
-- from lj_iceberg.ai_decision_dev.information_schema.tables
-- where table_schema = 'ai_decision_dev'
--   and table_name like 'jcr_%_20260623'
-- order by table_name;

-- =============================================================================
-- A. 全量删除（10 张，重跑完整链路前执行）
-- 顺序：先下游后上游（Step 7 → Step 0a）
-- =============================================================================

-- Step 7  特征 + 标签
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;

-- Step 6  特征宽表
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623;

-- Step 5  样本关联征信
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;

-- Step 4  征信扩展（查询/逾期/信用卡/资质）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623;

-- Step 3  账单日聚合
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623;

-- Step 2  报告级循环贷聚合
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623;

-- Step 1  账户级明细
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623;

-- Step 0c 样本终表（had/with/no_balance）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;

-- Step 0b 无余额标识
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623;

-- Step 0a 月内快照 + rk
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623;

-- =============================================================================
-- B. 分场景删除（按需选用，不要与 A 重复执行）
-- =============================================================================

-- B1. 仅重跑 Step 5~7（样本 Step 0c 及 Step 1~4 保留）
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;

-- B2. 仅重跑 Step 0a~0c（样本链路），并清下游
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623;
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623;

-- B3. 仅重跑 Step 7（Step 6 特征宽表保留）
-- drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;

-- =============================================================================
-- C. 删后重跑指引
-- =============================================================================
-- 全量：A 删完后按 Step 0a → 0b → 0c → 1 → 2 → 3 → 4 → 5 → 6 → 7 逐段执行
-- 样本已好、只改 cohort：B1 后重跑 Step 5~7
-- 核验 5401：sql/verify_cohort_5401.sql
