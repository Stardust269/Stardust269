-- 5186 vs 5401 差异诊断（差 215 人）
-- 同事 5401 来自 _4 表 group by uuid；我方 5186 来自 jcr _2 同条件 WHERE

-- 1) 三处 cohort 计数对比
select 'jcr_2_where' as src, count(1) as cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
union all
select 'yye_2_where', count(1)
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
union all
select 'yye_4_distinct', count(distinct uuid)
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 2) 同事有、jcr 没有的 uuid（应在 yye_4 不在 jcr_2_where）
-- select y.uuid
-- from (
--   select distinct uuid
--   from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_4
--   where crdt_lim_yx >= 20000
--     and had_0_30_zx = 1 and had_31_60_zx = 1
--     and no_balance_flg_60 = 1
--     and with_0_30 + with_31_60 = 0
-- ) y
-- left join (
--   select uuid
--   from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
--   where crdt_lim_yx >= 20000
--     and had_0_30_zx = 1 and had_31_60_zx = 1
--     and no_balance_flg_60 = 1
--     and with_0_30 + with_31_60 = 0
-- ) j on y.uuid = j.uuid
-- where j.uuid is null;

-- 3) 复制 yye _2 后是否对齐
-- select count(1) as missing_in_jcr
-- from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 c
-- left join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 s on c.uuid = s.uuid
-- where s.uuid is null;
