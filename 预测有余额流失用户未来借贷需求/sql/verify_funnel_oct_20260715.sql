-- =============================================================================
-- 十月三步漏斗核验（对齐同事：5022793 → 386311 → 5401）
-- 前置：已跑 run_part01_sample_cohort_20260715.sql
-- =============================================================================

-- ① 10月 5103 有余额且 crdt>=2w，月内 rk=1（最低额度利用率日）
select count(1) as step1_oct_cnt,
       count(distinct uuid) as step1_oct_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1 and m = '202510';
-- 预期 step1_oct_cnt ≈ 5,022,793

-- ② 最低余额日(days_dt)起 0~60 天全渠道无余额 + 60天内未提现
--    pf 表已含 no_balance_flg_60=1 且 with_0_30+with_31_60=0（全渠道无余额即含5103）
select count(1) as step2_oct_cnt,
       count(distinct uuid) as step2_oct_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
where m = '202510';
-- 预期 step2_oct_cnt ≈ 386,311

-- ③a 仅加征信 had（锚点 days_dt_1）
select count(1) as step3_had_only_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and had_0_30_zx = 1 and had_31_60_zx = 1;

-- ③b cohort（= ③a，因 no_balance/未提现已在 pf 预筛）
select count(1) as step3_cohort_oct,
       count(distinct uuid) as step3_cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m = '202510';
-- 预期 ≈ 5,401

-- 对比：若 pf 不含未提现会多出多少人（诊断）
select count(1) as step3_had_if_pf_had_withdraw_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 nb
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 h
  on nb.uuid = h.uuid and nb.dt = h.dt
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w
  on nb.uuid = w.uuid and nb.dt = w.dt
where nb.m = '202510'
  and nb.no_balance_flg_60 = 1
  and h.had_0_30_zx = 1 and h.had_31_60_zx = 1
  and w.with_0_30 + w.with_31_60 > 0;

-- 对比：had 若改锚点为 days_dt（相对最低余额日，而非 days_dt_1）— 仅诊断，不改表
select count(1) as had_if_anchor_days_dt_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
where pf.m = '202510'
  and exists (
      select 1
      from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary z
      where z.id_unqp = pf.uuid
        and concat(substr(z.dt,1,4),'-',substr(z.dt,5,2),'-',substr(z.dt,7,2))
            between pf.days_dt and date_add(pf.days_dt, 30)
  )
  and exists (
      select 1
      from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary z
      where z.id_unqp = pf.uuid
        and concat(substr(z.dt,1,4),'-',substr(z.dt,5,2),'-',substr(z.dt,7,2))
            between date_add(pf.days_dt, 31) and date_add(pf.days_dt, 60)
  );

-- 与权威 5401 重叠
select
    count(1) as jcr_oct,
    sum(if(a.uuid is not null, 1, 0)) as overlap_5401,
    sum(if(a.uuid is null, 1, 0)) as jcr_only
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
left join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 a on j.uuid = a.uuid
where j.m = '202510';
