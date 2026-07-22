-- =============================================================================
-- 十月漏斗拆因诊断
-- =============================================================================

select
    count(1) as step1_rows,
    count(distinct uuid) as step1_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1 and m = '202510';

-- Step2 逐层
select count(1) as s2a_nb60_only
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where m = '202510' and no_balance_flg_60 = 1;

select
    count(1) as s2b_pf_nb_and_no_with,
    sum(if(w.with_0_30 + w.with_31_60 = 0, 1, 0)) as s2c_pf_final
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 nb
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w
  on nb.uuid = w.uuid and nb.dt = w.dt
where nb.m = '202510' and nb.no_balance_flg_60 = 1;

-- Step3 五条件拆解
select
    count(1) as pf_cnt,
    sum(if(had_0_30_zx = 1 and had_31_60_zx = 1, 1, 0)) as pass_had,
    sum(if(crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1
            and no_balance_flg_60 = 1 and with_0_30 + with_31_60 = 0, 1, 0)) as pass_5cond
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
