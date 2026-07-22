-- =============================================================================
-- 十月三步漏斗核验（对齐同事：5022793 → 386311 → 5401）
-- cohort 五条件与 verify_cohort_5401.sql / jcr_cohort_5401_20260623 完全一致
-- =============================================================================

-- ① 10月 5103 有余额且 crdt>=2w，月内 rk=1
select count(1) as step1_oct_cnt,
       count(distinct uuid) as step1_oct_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1 and m = '202510';

-- ② pf：5103无余额60天 + 未提现
select count(1) as step2_oct_cnt,
       count(distinct uuid) as step2_oct_uuid
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
where m = '202510';

-- ③ cohort：5401 五条件（与 verify_cohort_5401 一致）
select count(1) as step3_cohort_oct,
       count(distinct uuid) as step3_cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m = '202510';

-- ③ 同条件在 info 表复算（应与 cohort 一致）
select count(1) as step3_info_5cond_oct
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where m = '202510'
  and crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 与权威 5401 重叠
select
    count(1) as jcr_oct,
    sum(if(a.uuid is not null, 1, 0)) as overlap_5401,
    sum(if(a.uuid is null, 1, 0)) as jcr_only,
    sum(if(a.uuid is not null and j.uuid is null, 1, 0)) as auth5401_only
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
full outer join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 a
  on j.uuid = a.uuid
where j.m = '202510' or j.m is null;
