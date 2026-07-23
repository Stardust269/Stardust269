-- =============================================================================
-- 预览 run_all_20260715.sql 产出内容（只读 SELECT，不写表）
-- 在 Hive / Spark / Trino 等平台整文件或分段执行即可
-- =============================================================================

-- ########## A. 产出表清单 ##########
show tables in lj_iceberg.ai_decision_dev like 'jcr%20260715';

-- ########## B. 各表行数（全链路）##########
select 'jcr_pril_bal_info_20260715' as tbl, count(1) as cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
union all
select 'jcr_cohort_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
union all
select 'jcr_credit_account_base_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715
union all
select 'jcr_credit_report_agg_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715
union all
select 'jcr_credit_billday_agg_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715
union all
select 'jcr_credit_report_ext_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715
union all
select 'jcr_credit_report_with_sample_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715
union all
select 'jcr_credit_feature_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715
union all
select 'jcr_credit_feature_label_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715
union all
select 'jcr_mx_feature_pril_bal_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715
union all
select 'jcr_mx_feature_wdraw_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715
union all
select 'jcr_credit_feature_label_full_20260715', count(1)
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
order by tbl;

-- ########## C. cohort / 标签 / 划分汇总（与 Part 9 一致）##########
select m, count(1) as cohort_cnt, count(distinct uuid) as cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
group by m
order by m;

select
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715) as cohort_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715) as feature_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715) as full_cnt;

select zx_balance_label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where label_eligible = 1
group by zx_balance_label
order by zx_balance_label;

select m, dataset_split, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where m in ('202508', '202509', '202510')
group by m, dataset_split
order by m, dataset_split;

-- ########## D. 终表字段结构 ##########
describe lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715;

-- ########## E. 终表样例行（核心字段，各 5 条）##########
select
    uuid, user_id, dt, days_dt, m,
    pril_bal, crdt_lim_yx, pril_bal_rate,
    dataset_split, label_eligible, zx_balance_label,
    fwd_first_balance, fwd_max_balance,
    latest_pos_bal_acct_cnt, latest_bal_sum, latest_crdt_sum, latest_util_sum,
    latest_hard_query_num_1m, latest_has_house_loan_flg, latest_has_gjj_loan_flg,
    pril_bal_rate_1m, pass_rate_1m, fq_cnt_1m
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
limit 5;

-- ########## F. train / val 各看 3 条（建模前快速肉眼检查）##########
select uuid, dt, days_dt, m, dataset_split, zx_balance_label,
       latest_bal_sum, latest_util_sum, fwd_first_balance, fwd_max_balance
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where dataset_split = 'train' and label_eligible = 1
limit 3;

select uuid, dt, days_dt, m, dataset_split, zx_balance_label,
       latest_bal_sum, latest_util_sum, fwd_first_balance, fwd_max_balance
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where dataset_split = 'val' and label_eligible = 1
limit 3;

-- ########## G. 特征缺失率（终表，仅 label_eligible=1）##########
select
    count(1) as n,
    round(avg(if(latest_bal_sum is null, 1, 0)), 4) as null_rate_latest_bal_sum,
    round(avg(if(latest_util_sum is null, 1, 0)), 4) as null_rate_latest_util_sum,
    round(avg(if(latest_hard_query_num_1m is null, 1, 0)), 4) as null_rate_latest_hard_query,
    round(avg(if(pril_bal_rate_1m is null, 1, 0)), 4) as null_rate_mx_pril_bal_rate_1m,
    round(avg(if(pass_rate_1m is null, 1, 0)), 4) as null_rate_mx_pass_rate_1m
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where label_eligible = 1;

-- ########## H. 导出到本地 CSV（按平台二选一）##########
-- Spark SQL 示例：
-- select * from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
-- where label_eligible = 1
--   and dataset_split in ('train', 'val');

-- Hive 落盘示例（路径按环境改）：
-- insert overwrite directory '/tmp/jcr_export_20260715'
-- row format delimited fields terminated by ','
-- select * from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
-- where label_eligible = 1;
