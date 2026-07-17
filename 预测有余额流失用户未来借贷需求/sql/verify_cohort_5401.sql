-- 核验：严格对齐同事统计查询 num=5401
-- 同事参考：sql/yye_pril_bal_sample_reference.sql 中 _2 表统计 SELECT

-- 1) Step 0c 后：样本表 cohort 计数（应 = 5401）
select count(1) as cohort_cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;

-- 2) Step 7 后：特征+标签表 cohort 计数（应 = 5401）
select count(1) as cohort_cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1;

-- 3) 标签子集分布（同事最后一查，约 3511+1890）
select label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1
  and label_eligible = 1
  and label is not null
group by label
order by label;

-- 4) 导出 5401 人全量特征（《需要加工的数据》字段均在 jcr_credit_feature_label 中）
-- select *
-- from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where cohort_eligible = 1;
