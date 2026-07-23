-- =============================================================================
-- 删除 jcr_*_20260715 产出表（清表后重跑 run_all_20260715.sql）
-- 注意：yye_* / ayh_* 为同事表，请勿删除
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;
