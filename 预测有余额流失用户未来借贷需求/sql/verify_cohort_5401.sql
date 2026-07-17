-- 核验：精确 5401（须先跑 Step 0d 建 jcr_cohort_5401_20260623）

-- 1) 权威 cohort 表（必须 = 5401）
select count(1) as cohort_uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623;

-- 2) jcr _2 同条件 WHERE（约 5186，仅作对比，非权威）
select count(1) as jcr_2_where_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- 3) Step 7 后（必须 = 5401）
select count(1) as feature_label_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1;

-- 4) cohort 是否在样本表都能关联
select count(1) as missing_sample
from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 c
left join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 s on c.uuid = s.uuid
where s.uuid is null;

-- 5) 标签分布
select label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1 and label is not null
group by label order by label;
