-- 删除本项目产出的全部 jcr_ 个人表（重跑前执行）
-- 若平台一次只能跑一条 SQL，请逐条执行下面 10 行 drop

drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623;
