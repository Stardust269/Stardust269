-- =============================================================================
-- Step 0 推荐路径（精确 5401）：
--   1) 本文件：复制同事 yye_pril_bal_info_20260623_2 → jcr_pril_bal_info
--   2) step0d_cohort_5401_from_yye.sql：从 yye _4 取 5401 uuid
-- 勿仅自建 Step 0a~0c：同条件 WHERE 约 5186，与 5401 差 215
-- =============================================================================

-- 0) 先核验同事表各口径人数（确认 5401 来自哪一列）
select count(1) as cnt_all
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2;

select count(1) as cnt_4had
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;

select count(1) as cnt_label_cohort
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 1) 复制到个人样本表（替代 Step 0a~0c）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 as
select *
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2;

-- 2) 复制后核验（cnt_after_copy 应 ≈ 5401）
select count(1) as cnt_after_copy
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 3) 然后执行 drop B1（删 Step 5~7）并重跑 Step 5 → 6 → 7
