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

-- ② 最低余额日(days_dt)起 0~60 天内全渠道变无余额
select count(1) as step2_oct_cnt,
       count(distinct uuid) as step2_oct_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
where m = '202510';
-- 预期 step2_oct_cnt ≈ 386,311

-- ③a 仅加征信 had（当前实现：锚点 days_dt_1，非 days_dt）
select count(1) as step3_had_only_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and no_balance_flg_60 = 1
  and had_0_30_zx = 1 and had_31_60_zx = 1;
-- 若此处已远大于 5401，说明 had 窗口或入口需再对

-- ③b 完整 cohort（含 未提现，对齐 0623/同事 _4 的 5401 口径）
select count(1) as step3_cohort_oct,
       count(distinct uuid) as step3_cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m = '202510';
-- 预期 ≈ 5,401

-- 对比：若去掉 with 条件会多出多少人
select count(1) as step3_no_with_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and no_balance_flg_60 = 1
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and with_0_30 + with_31_60 = 0;

select count(1) as step3_had_without_with_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and no_balance_flg_60 = 1
  and had_0_30_zx = 1 and had_31_60_zx = 1;

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
