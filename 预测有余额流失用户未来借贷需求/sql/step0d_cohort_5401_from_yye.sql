-- =============================================================================
-- Step 0d：权威 cohort 名单（精确 5401）
-- 与同事最后一查完全一致：从 yye_pril_bal_info_20260623_4 取 distinct uuid
-- 前置：
--   1) 同事已产出 yye_pril_bal_info_20260623_4（见其参考 SQL _3/_4）
--   2) 建议先执行 step0c_copy_from_yye.sql 复制 _2 到 jcr_pril_bal_info
-- 核验：select count(1) from jcr_cohort_5401_20260623;  -- 必须 = 5401
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623;
create table lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 as
select distinct uuid
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1
  and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 应与同事最后一查 sum(num) 一致
select count(1) as cohort_uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623;
