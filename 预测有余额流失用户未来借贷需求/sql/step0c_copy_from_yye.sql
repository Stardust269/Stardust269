-- =============================================================================
-- Step 0 替代方案：直接复制同事已产出的 _2 样本表
-- 使用场景：自建 Step 0a~0c 后 label cohort 仅 ~488，与同事 5401 无法对齐时
-- 前置：需有 lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2 读权限
-- 执行后：跳过 Step 0a/0b/0c，从 Step 1 或 Step 5 继续
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

-- 2) 复制后核验（cnt_label_cohort 应 ≈ 5401）
select count(1) as cnt_after_copy
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
  and no_balance_flg_90 = 1
  and with_0_30 + with_31_60 + with_61_90 = 0;

-- 3) 然后执行 drop B1（删 Step 5~7）并重跑 Step 5 → 6 → 7
