-- 核验：严格对齐同事最后一查 5401（2026-07 确认版）
-- 同事参考：sql/yye_pril_bal_sample_reference.sql 末尾 SELECT

-- ★ 标准 cohort 口径（5401）
-- crdt_lim_yx >= 20000
-- AND had_0_30_zx=1 AND had_31_60_zx=1
-- AND no_balance_flg_60=1
-- AND with_0_30 + with_31_60 = 0

-- 1) Step 0c 后：样本表（应 ≈ 5401）
select count(1) as cnt_cohort, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 2) Step 7 后：特征+标签表（应 ≈ 5401）
select count(1) as cnt_cohort, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1;

-- 3) 标签分布（与同事最后一查 flg/num 对应）
select label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1 and label is not null
group by label order by label;

-- 4) 漏斗（定位每步过滤）
select 'crdt>=2w' as step, count(1) as cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
union all
select 'had_0_30+31_60', count(1)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1
union all
select '+ no_balance_60', count(1)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
union all
select '+ with_0_60=0 (5401)', count(1)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1 and with_0_30 + with_31_60 = 0;

-- 5) 导出 5401 人全量特征
-- select * from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where cohort_eligible = 1;
