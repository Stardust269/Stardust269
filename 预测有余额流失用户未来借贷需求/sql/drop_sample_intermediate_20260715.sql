-- =============================================================================
-- cohort 核验通过后，删除样本中间表以释放空间（保留 cohort + pril_bal_info）
-- 后续 Part 3~8 只需 jcr_cohort_20260715 和 jcr_pril_bal_info_20260715
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
