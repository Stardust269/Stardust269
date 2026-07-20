-- =============================================================================
-- 【全量清理】本项目在 ai_decision_dev 下产出的全部表
-- =============================================================================
-- 重要说明：
--   drop_all_jcr_tables_20260715.sql 只删 15 张 jcr_*_20260715，远远不够！
--   7TB 配额是整库 ai_decision_dev 共享，通常还被以下大表占满：
--     - yye_pril_bal_*（同事样本，尤其 _2 可达百万行）
--     - ayh_feature_*（马消特征，~109万行）
--     - jcr_*_20260623（十月版征信中间表）
--     - 多次失败跑留下的 jcr_*_20260715
--
-- 用法：
--   1. 单独提交本文件（不要与 create 混跑）
--   2. 跑完后执行 sql/list_project_tables.sql 核验
--   3. 确认腾出空间后再跑 run_all_20260715（建议分 Part）
--
-- Iceberg 表建议带 PURGE（立即删数据文件）；若平台不支持 PURGE，去掉该关键字
-- =============================================================================

-- ########## A. 三月 jcr（15 张）##########
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;

-- ########## B. 十月 jcr（11 张）##########
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623 purge;

-- ########## C. 同事 yye 样本（十月 + 三月）##########
-- ★ 通常最占空间；若马消特征已不需要可一并删除
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_2 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_1 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_3 purge;
drop table if exists lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4 purge;

-- ########## D. 同事马消特征（可选，Part 8 需要时再让同事重跑）##########
drop table if exists lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx purge;
drop table if exists lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc purge;

-- ########## E. 其他参考表 ##########
drop table if exists lj_iceberg.ai_decision_dev.analyse_user_260612_zyy_03 purge;

-- ########## F. 删后核验（应返回 0 行或仅剩无关表）##########
-- show tables in lj_iceberg.ai_decision_dev like 'jcr%';
-- show tables in lj_iceberg.ai_decision_dev like 'yye%';
-- show tables in lj_iceberg.ai_decision_dev like 'ayh%';
