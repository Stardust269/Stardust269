-- =============================================================================
-- 可选：0623 样本表五条件对照（需 jcr_pril_bal_info_20260623 已存在）
-- =============================================================================
-- 若报错 Object not found → 表未建，跳过即可；用 Part1 的 A 行与 E(5401) 对比
-- =============================================================================

select 'G_jcr_pril_bal_info_0623_5cond' as path,
       count(1) as cohort_5cond,
       count(distinct uuid) as cohort_uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
;

-- 若有同事 yye _2 表，也可对照：
-- select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
-- where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1
--   and no_balance_flg_60 = 1 and with_0_30 + with_31_60 = 0;
