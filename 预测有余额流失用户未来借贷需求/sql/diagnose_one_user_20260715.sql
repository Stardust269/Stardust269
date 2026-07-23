-- =============================================================================
-- 单用户诊断：看清一条样本的征信报告挂载与特征为何为 null
-- 用法：把下面 uuid / dt 换成你要查的人
-- =============================================================================

-- ① 终表一行（带列名，不要 select *）
select
    uuid, dt, days_dt, m, dataset_split,
    label_eligible, zx_balance_label, fwd_first_balance, fwd_max_balance,
    latest_pos_bal_acct_cnt, latest_bal_sum, latest_crdt_sum, latest_util_sum,
    avg_1m_bal_sum, avg_6m_bal_sum, avg_1y_bal_sum,
    latest_credit_account_num, latest_credit_amount, latest_credit_used_amount,
    latest_has_house_loan_flg, latest_has_gjj_loan_flg, latest_org_type,
    latest_hard_query_num_1m, latest_dt_zx,
    zx_report_cnt_1m, zx_report_cnt_6m, zx_report_cnt_1y, zx_report_cnt_fwd_60d
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where uuid = '09330a2442714daaae4fb66cdd6beca4'
  and dt = '20251122';

-- ② 是否还在 cohort（修月份后 202511 应为 0 行）
select uuid, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where uuid = '09330a2442714daaae4fb66cdd6beca4';

-- ③ 该用户挂上了哪些征信报告（Part 5 明细）
select
    uuid, dt, days_dt, m,
    days_dt_zx, dt_zx,
    flg_win_1m, flg_win_6m, flg_win_1y, flg_fwd_60d,
    latest_report_rn,
    pos_bal_acct_cnt, bal_sum, crdt_sum, util_sum,
    credit_account_num, credit_amount, credit_used_amount, credit_util_rate,
    has_house_loan_flg, has_gjj_loan_flg, org_type,
    hard_query_num_1m, org_type
from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715
where uuid = '09330a2442714daaae4fb66cdd6beca4'
  and dt = '20251122'
order by days_dt_zx;

-- ④ 标签窗内账户余额（Part 7 标签来源）
select
    c.uuid, c.dt, c.days_dt,
    b.days_dt_zx,
    sum(if(b.balance > 0 and b.org_manage_code <> 'T10156530H0001', b.balance, 0)) as balance
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
left join lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 b
  on c.uuid = b.id_unqp
 and cast(b.days_dt_zx as date) between cast(c.days_dt as date) and date_add(cast(c.days_dt as date), 60)
where c.uuid = '09330a2442714daaae4fb66cdd6beca4'
  and c.dt = '20251122'
group by c.uuid, c.dt, c.days_dt, b.days_dt_zx
order by b.days_dt_zx;

-- ⑥ 资质类字段填充率（8/9/10 月，可标注样本）
select
    count(1) as n,
    round(avg(if(latest_has_house_loan_flg is not null, 1, 0)), 4) as rate_house_flg,
    round(avg(if(latest_has_gjj_loan_flg is not null, 1, 0)), 4) as rate_gjj_flg,
    round(avg(if(latest_org_type is not null, 1, 0)), 4) as rate_org_type,
    round(avg(latest_has_house_loan_flg), 4) as pct_has_house,
    round(avg(latest_has_gjj_loan_flg), 4) as pct_has_gjj
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where m in ('202508', '202509', '202510')
  and label_eligible = 1;

-- ⑦ 全表征信特征填充率（label_eligible=1，仅 8/9/10 月）
select
    count(1) as n,
    round(avg(if(latest_bal_sum is not null, 1, 0)), 4) as rate_latest_bal,
    round(avg(if(avg_1m_bal_sum is not null, 1, 0)), 4) as rate_avg_1m_bal,
    round(avg(if(latest_credit_account_num is not null, 1, 0)), 4) as rate_latest_cc,
    round(avg(if(latest_dt_zx is not null, 1, 0)), 4) as rate_latest_dt_zx,
    round(avg(if(zx_balance_label is not null, 1, 0)), 4) as rate_has_label
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where m in ('202508', '202509', '202510')
  and label_eligible = 1;
