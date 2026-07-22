-- =============================================================================
-- 十月漏斗拆因诊断：解释 step1/2/3 与同事预期数字的差异
-- 在 verify_funnel_oct_20260715.sql 之后跑
-- =============================================================================

-- ---------- Step1：行数 vs 去重 uuid vs 多 user_id ----------
select
    count(1) as step1_rows,
    count(distinct uuid) as step1_uuid,
    count(distinct concat(uuid, '|', user_id)) as step1_uuid_user
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1 and m = '202510';
-- 若 step1_rows > step1_uuid，差额来自同一 uuid 多个 user_id

-- ---------- Step2：双无余额 + 未提现（对齐同事 386311）----------
select
    count(1) as s2_pf_all_conditions,
    count(distinct uuid) as s2_pf_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
where m = '202510';
-- 预期 ≈ 386,311

-- 拆因：两个无余额条件各自贡献
select
    count(1) as s2a_non5103_nb60_only,
    sum(if(no_balance_flg_60_5103 = 1, 1, 0)) as s2b_also_5103_nb60
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where m = '202510' and no_balance_flg_60 = 1;

select
    count(1) as s2c_5103_nb60_only,
    sum(if(no_balance_flg_60 = 1, 1, 0)) as s2d_also_non5103_nb60
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where m = '202510' and no_balance_flg_60_5103 = 1;

-- 拆因：双无余额后，未提现筛掉多少人
select
    count(1) as s2e_nb_both_no_withdraw,
    sum(if(w.with_0_30 + w.with_31_60 = 0, 1, 0)) as s2f_pf_final
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 nb
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w
  on nb.uuid = w.uuid and nb.dt = w.dt
where nb.m = '202510'
  and nb.no_balance_flg_60 = 1
  and nb.no_balance_flg_60_5103 = 1;

-- ---------- Step3：完整 cohort vs 权威 5401 ----------
select
    count(1) as step3_cohort_rows,
    count(distinct uuid) as step3_cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m = '202510';

select
    count(1) as step3_from_pf,
    sum(if(had_0_30_zx = 1 and had_31_60_zx = 1, 1, 0)) as step3_had_pass
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510';

select
    count(1) as overlap_5401_uuid,
    sum(if(j.uuid is not null and a.uuid is null, 1, 0)) as jcr_only,
    sum(if(j.uuid is null and a.uuid is not null, 1, 0)) as auth5401_only
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
full outer join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 a
  on j.uuid = a.uuid
where j.m = '202510' or j.m is null;
