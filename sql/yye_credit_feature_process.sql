-- =============================================================================
-- 二代征信循环贷特征加工 SQL
-- 依据 Notion《需要加工的数据》清单 + 既有样本关联逻辑
--
-- 口径说明：
-- 1) 账户范围：account_type in ('R1','R2','R3')，且未结清(close_date 为空)
-- 2) 剔除马消：org_manage_code <> 'T10156530H0001'
-- 3) 有余额账户：balance > 0
-- 4) 额度利用率：balance / credit_grant_amount（授信额度>0 时计算）
-- 5) 账单日：借贷账户最近一月表现.settle_date 的“日”(1-31)
-- 6) 观察日锚点：样本表 days_dt_1
--    - 最近一份征信：观察日前最近一份报告；若无则取观察日后60天内最早一份
--    - 近一月/近6月/近1年：以观察日为锚点，分别回看 30/180/365 天内的征信报告做均值
-- =============================================================================

-- Step 1: 账户级征信明细（余额 + 基本信息 + 账单日）
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623 as
select
    t1.id_unqf,
    t1.id_unqp,
    t1.account_no,
    coalesce(cast(nullif(t1.balance, '') as double), 0) as balance,
    t2.org_manage_type,
    t2.org_manage_code,
    coalesce(cast(nullif(t2.credit_grant_amount, '') as double), 0) as credit_grant_amount,
    t2.account_type,
    t1.dt,
    concat(substr(t1.dt, 1, 4), '-', substr(t1.dt, 5, 2), '-', substr(t1.dt, 7, 2)) as days_dt_zx,
    case
        when t3.settle_date is null or t3.settle_date = '' then null
        else cast(day(cast(t3.settle_date as date)) as int)
    end as bill_day,
    case
        when coalesce(cast(nullif(t2.credit_grant_amount, '') as double), 0) > 0
             and coalesce(cast(nullif(t1.balance, '') as double), 0) > 0
        then coalesce(cast(nullif(t1.balance, '') as double), 0)
             / coalesce(cast(nullif(t2.credit_grant_amount, '') as double), 0)
        else null
    end as util_rate,
    case
        when coalesce(cast(nullif(t1.balance, '') as double), 0) > 0
             and t2.org_manage_code <> 'T10156530H0001'
        then 1 else 0
    end as is_pos_bal_non_mx
from (
    select
        id_unqf, id_unqp, account_no, account_state, close_date, turn_out_date,
        balance, latest_repayment_date, latest_repayment_amount, level5_type,
        repayment_state, info_date, time_inst, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
    where dt >= '20241001'
      and dt < '20260201'
      and (close_date is null or close_date = '')
) t1
join (
    select
        id_unqf, account_no, id_unqp, credit_serial_no, account_type,
        org_manage_type, org_manage_code, account_id, open_date, end_date,
        loan_amount, currency_type, busi_type, assure_type, payment_payment,
        payment_frequency, payment_type, loan_together_state, credit_grant_amount,
        share_credit_amount, loan_give_type, payment_state_transfer, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20241001'
      and dt < '20260201'
      and account_type in ('R1', 'R2', 'R3')
      and org_manage_code <> 'T10156530H0001'
) t2
  on t1.id_unqf = t2.id_unqf
 and t1.account_no = t2.account_no
 and t1.id_unqp = t2.id_unqp
 and t1.dt = t2.dt
left join (
    select
        id_unqf, id_unqp, account_no, settle_date, dt,
        row_number() over (
            partition by id_unqf, id_unqp, account_no, dt
            order by coalesce(info_dt, settle_date) desc, month desc
        ) as rn
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform
    where dt >= '20241001'
      and dt < '20260201'
) t3
  on t1.id_unqf = t3.id_unqf
 and t1.id_unqp = t3.id_unqp
 and t1.account_no = t3.account_no
 and t1.dt = t3.dt
 and t3.rn = 1
;

-- Step 2: 报告级聚合（每个用户+每份征信报告）
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_report_agg_20260623 as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    sum(is_pos_bal_non_mx) as pos_bal_acct_cnt,
    sum(if(is_pos_bal_non_mx = 1, balance, 0)) as bal_sum,
    max(if(is_pos_bal_non_mx = 1, balance, null)) as bal_max,
    min(if(is_pos_bal_non_mx = 1, balance, null)) as bal_min,
    sum(if(is_pos_bal_non_mx = 1, credit_grant_amount, 0)) as crdt_sum,
    max(if(is_pos_bal_non_mx = 1, credit_grant_amount, null)) as crdt_max,
    min(if(is_pos_bal_non_mx = 1, credit_grant_amount, null)) as crdt_min,
    max(if(is_pos_bal_non_mx = 1, util_rate, null)) as util_max,
    min(if(is_pos_bal_non_mx = 1, util_rate, null)) as util_min,
    case
        when sum(if(is_pos_bal_non_mx = 1, credit_grant_amount, 0)) > 0
        then sum(if(is_pos_bal_non_mx = 1, balance, 0))
             / sum(if(is_pos_bal_non_mx = 1, credit_grant_amount, 0))
        else null
    end as util_sum,
    count(distinct if(is_pos_bal_non_mx = 1 and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 3: 账单日压力指标（同账单日账户数/余额）
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_billday_agg_20260623 as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
    max(bal_sum_same_billday) as same_billday_bal_sum_max
from (
    select
        id_unqp,
        id_unqf,
        dt,
        days_dt_zx,
        bill_day,
        sum(is_pos_bal_non_mx) as acct_cnt_same_billday,
        sum(if(is_pos_bal_non_mx = 1, balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623
    where is_pos_bal_non_mx = 1
      and bill_day is not null
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 4: 样本用户关联征信报告，并打时间窗标签
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_report_with_sample_20260623 as
select
    s.uuid,
    s.user_id,
    s.pril_bal,
    s.crdt_lim_yx,
    s.pril_bal_rate,
    s.dt,
    s.days_dt,
    s.no_balance_flg_30,
    s.no_balance_flg_60,
    s.no_balance_flg_90,
    s.days_dt_1,
    s.had_0_30_zx,
    s.had_31_60_zx,
    s.had_61_90_zx,
    s.had_91_120_zx,
    s.with_0_30,
    s.with_31_60,
    s.with_61_90,
    s.with_91_120,
    s.with_0_30_5103,
    s.with_31_60_5103,
    s.with_61_90_5103,
    s.with_91_120_5103,
    r.id_unqf,
    r.dt as dt_zx,
    r.days_dt_zx,
    r.pos_bal_acct_cnt,
    r.bal_sum,
    r.bal_max,
    r.bal_min,
    r.crdt_sum,
    r.crdt_max,
    r.crdt_min,
    r.util_sum,
    r.util_max,
    r.util_min,
    r.bill_day_cnt,
    b.same_billday_acct_cnt_max,
    b.same_billday_bal_sum_max,
    case when r.days_dt_zx <= s.days_dt_1 then 1 else 0 end as flg_before_obs,
    case
        when r.days_dt_zx > s.days_dt_1
         and r.days_dt_zx <= date_add(s.days_dt_1, 60) then 1 else 0
    end as flg_after_obs_60d,
    case
        when r.days_dt_zx > date_sub(s.days_dt_1, 30)
         and r.days_dt_zx <= s.days_dt_1 then 1 else 0
    end as flg_win_1m,
    case
        when r.days_dt_zx > date_sub(s.days_dt_1, 180)
         and r.days_dt_zx <= s.days_dt_1 then 1 else 0
    end as flg_win_6m,
    case
        when r.days_dt_zx > date_sub(s.days_dt_1, 365)
         and r.days_dt_zx <= s.days_dt_1 then 1 else 0
    end as flg_win_1y,
    row_number() over (
        partition by s.uuid
        order by case when r.days_dt_zx <= s.days_dt_1 then 0 else 1 end,
                 case when r.days_dt_zx <= s.days_dt_1 then r.days_dt_zx end desc,
                 case when r.days_dt_zx > s.days_dt_1 then r.days_dt_zx end asc
    ) as latest_report_rn
from (
    select
        uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
        no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
        had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
        with_0_30, with_31_60, with_61_90, with_91_120,
        with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
    from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
) s
left join lj_iceberg.ai_decision_dev.yye_credit_report_agg_20260623 r
  on s.uuid = r.id_unqp
left join lj_iceberg.ai_decision_dev.yye_credit_billday_agg_20260623 b
  on r.id_unqp = b.id_unqp
 and r.id_unqf = b.id_unqf
 and r.dt = b.dt
where r.days_dt_zx is null
   or (
        (r.days_dt_zx <= s.days_dt_1 and r.days_dt_zx > date_sub(s.days_dt_1, 365))
        or (r.days_dt_zx > s.days_dt_1 and r.days_dt_zx <= date_add(s.days_dt_1, 60))
      )
;

-- Step 5: 最终特征宽表（对应 Notion《需要加工的数据》清单）
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_feature_20260623 as
select
    uuid,
    user_id,
    pril_bal,
    crdt_lim_yx,
    pril_bal_rate,
    dt,
    days_dt,
    no_balance_flg_30,
    no_balance_flg_60,
    no_balance_flg_90,
    days_dt_1,
    had_0_30_zx,
    had_31_60_zx,
    had_61_90_zx,
    had_91_120_zx,
    with_0_30,
    with_31_60,
    with_61_90,
    with_91_120,
    with_0_30_5103,
    with_31_60_5103,
    with_61_90_5103,
    with_91_120_5103,
    max(if(latest_report_rn = 1, pos_bal_acct_cnt, null)) as latest_pos_bal_acct_cnt,
    avg(if(flg_win_1m = 1, pos_bal_acct_cnt, null)) as avg_1m_pos_bal_acct_cnt,
    avg(if(flg_win_6m = 1, pos_bal_acct_cnt, null)) as avg_6m_pos_bal_acct_cnt,
    avg(if(flg_win_1y = 1, pos_bal_acct_cnt, null)) as avg_1y_pos_bal_acct_cnt,
    max(if(latest_report_rn = 1, bal_sum, null)) as latest_bal_sum,
    max(if(latest_report_rn = 1, bal_max, null)) as latest_bal_max,
    max(if(latest_report_rn = 1, bal_min, null)) as latest_bal_min,
    avg(if(flg_win_1m = 1, bal_sum, null)) as avg_1m_bal_sum,
    avg(if(flg_win_1m = 1, bal_max, null)) as avg_1m_bal_max,
    avg(if(flg_win_1m = 1, bal_min, null)) as avg_1m_bal_min,
    avg(if(flg_win_6m = 1, bal_sum, null)) as avg_6m_bal_sum,
    avg(if(flg_win_6m = 1, bal_max, null)) as avg_6m_bal_max,
    avg(if(flg_win_6m = 1, bal_min, null)) as avg_6m_bal_min,
    avg(if(flg_win_1y = 1, bal_sum, null)) as avg_1y_bal_sum,
    avg(if(flg_win_1y = 1, bal_max, null)) as avg_1y_bal_max,
    avg(if(flg_win_1y = 1, bal_min, null)) as avg_1y_bal_min,
    max(if(latest_report_rn = 1, crdt_sum, null)) as latest_crdt_sum,
    max(if(latest_report_rn = 1, crdt_max, null)) as latest_crdt_max,
    max(if(latest_report_rn = 1, crdt_min, null)) as latest_crdt_min,
    avg(if(flg_win_1m = 1, crdt_sum, null)) as avg_1m_crdt_sum,
    avg(if(flg_win_1m = 1, crdt_max, null)) as avg_1m_crdt_max,
    avg(if(flg_win_1m = 1, crdt_min, null)) as avg_1m_crdt_min,
    avg(if(flg_win_6m = 1, crdt_sum, null)) as avg_6m_crdt_sum,
    avg(if(flg_win_6m = 1, crdt_max, null)) as avg_6m_crdt_max,
    avg(if(flg_win_6m = 1, crdt_min, null)) as avg_6m_crdt_min,
    avg(if(flg_win_1y = 1, crdt_sum, null)) as avg_1y_crdt_sum,
    avg(if(flg_win_1y = 1, crdt_max, null)) as avg_1y_crdt_max,
    avg(if(flg_win_1y = 1, crdt_min, null)) as avg_1y_crdt_min,
    max(if(latest_report_rn = 1, util_sum, null)) as latest_util_sum,
    max(if(latest_report_rn = 1, util_max, null)) as latest_util_max,
    max(if(latest_report_rn = 1, util_min, null)) as latest_util_min,
    avg(if(flg_win_1m = 1, util_sum, null)) as avg_1m_util_sum,
    avg(if(flg_win_1m = 1, util_max, null)) as avg_1m_util_max,
    avg(if(flg_win_1m = 1, util_min, null)) as avg_1m_util_min,
    avg(if(flg_win_6m = 1, util_sum, null)) as avg_6m_util_sum,
    avg(if(flg_win_6m = 1, util_max, null)) as avg_6m_util_max,
    avg(if(flg_win_6m = 1, util_min, null)) as avg_6m_util_min,
    avg(if(flg_win_1y = 1, util_sum, null)) as avg_1y_util_sum,
    avg(if(flg_win_1y = 1, util_max, null)) as avg_1y_util_max,
    avg(if(flg_win_1y = 1, util_min, null)) as avg_1y_util_min,
    max(if(latest_report_rn = 1, bill_day_cnt, null)) as latest_bill_day_cnt,
    max(if(latest_report_rn = 1, same_billday_acct_cnt_max, null)) as latest_same_billday_acct_cnt_max,
    max(if(latest_report_rn = 1, same_billday_bal_sum_max, null)) as latest_same_billday_bal_sum_max,
    max(if(flg_win_1m = 1, same_billday_bal_sum_max, null)) as max_1m_same_billday_bal_sum,
    max(if(flg_win_6m = 1, same_billday_bal_sum_max, null)) as max_6m_same_billday_bal_sum,
    max(if(flg_win_1y = 1, same_billday_bal_sum_max, null)) as max_1y_same_billday_bal_sum,
    max(if(latest_report_rn = 1, dt_zx, null)) as latest_dt_zx,
    sum(flg_win_1m) as zx_report_cnt_1m,
    sum(flg_win_6m) as zx_report_cnt_6m,
    sum(flg_win_1y) as zx_report_cnt_1y
from lj_iceberg.ai_decision_dev.yye_credit_report_with_sample_20260623
group by
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
    with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
;
