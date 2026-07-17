-- 核验：5401 口径排查（请逐条执行，把每步 cnt 发回）
-- 同事参考：sql/yye_pril_bal_sample_reference.sql

-- 0) 样本底池规模
select count(1) as cnt_all,
       count(distinct uuid) as uuid_all
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;

-- 1) 统计查询口径（4 段 had，不含 no_balance/with）→ 你当前约 339211
select count(1) as cnt_stat_4had
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;

-- 2) label 圈选口径（同事 _4 最后一查，3511+1890=5401）→ 目标应 ≈ 5401
select count(1) as cnt_label_cohort
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
  and no_balance_flg_90 = 1
  and with_0_30 + with_31_60 + with_61_90 = 0;

-- 3) 同事统计 SELECT 全量输出（看 num 与各 sum 列哪个是 5401）
select count(1) as num,
       count(distinct uuid) as usr_num,
       sum(if(no_balance_flg_90 = 1 and with_0_30 + with_31_60 + with_61_90 = 0, 1, 0)) as nb90_no_with
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;

-- 4) 漏斗（定位卡在哪一步）
select count(1) as step_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
union all
select count(1) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
union all
select count(1) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
  and no_balance_flg_90 = 1
union all
select count(1) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000 and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
  and no_balance_flg_90 = 1 and with_0_30 + with_31_60 + with_61_90 = 0;

-- 5) Step 7 后（重跑 Step 5~7 后执行）
select count(1) as cohort_cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1;

-- 6) 标签分布（应约 3511 负 + 1890 正）
select label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1 and label is not null
group by label order by label;

-- 7) 若同事 yye 表存在，直接对比
-- select count(1) from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
-- where crdt_lim_yx >= 20000 and had_0_30_zx=1 and had_31_60_zx=1
--   and had_61_90_zx=1 and had_91_120_zx=1;
