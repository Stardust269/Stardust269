-- =============================================================================
-- 二代征信循环贷特征加工 SQL（已按 Notion 全量子页面字段校对）
--
-- 源表（Notion 子页面括号内表名）：
--   t1: lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform  借贷账户--最近一次表现
--   t2: lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info       借贷账户--基本信息
--   t3: lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform 借贷账户--最近一月表现
--   样本: lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
--
-- 关键字段编码（Notion）：
--   id_unqf            报告ID
--   id_unqp            客户ID
--   account_id         账户标识（latest_perform / basic_info）
--   account_no         账户编号（basic_info）；1m表中 account_no 实际存的是“账户标识”
--   account_type       账户类型（R1/R2/R3）
--   org_manage_code    业务管理机构代码（马消=T10156530H0001，需剔除）
--   balance            余额
--   credit_grant_amount 账户授信额度
--   close_date         关闭日期
--   settle_date        结算/应还款日（账单日来源）
--   dt                 分区日期（生产表通用，Notion 字段页未列出）
--
-- 特征清单来源：Notion《需要加工的数据》
-- =============================================================================

-- ===================== 参数区（按需修改） =====================
-- set hivevar:zx_dt_start=20241001;   -- 需覆盖观察日前推1年
-- set hivevar:zx_dt_end=20260201;
-- set hivevar:mx_org_code=T10156530H0001;
-- set hivevar:sample_table=lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2;

-- =============================================================================
-- Step 1: 账户级征信明细
-- 关联键（按 Notion 字段定义校对）：
--   latest_perform.account_id = basic_info.account_id
--   latest_1m_perform.account_no = basic_info.account_id   -- 1m表 account_no 即账户标识
-- =============================================================================
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623 as
select
    t1.id_unqf,                                          -- 报告ID
    t1.id_unqp,                                          -- 客户ID
    t2.account_no,                                       -- 账户编号（来自 basic_info）
    t1.account_id,                                       -- 账户标识
    coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) as balance,
    t2.org_manage_type,                                  -- 业务管理机构类型
    t2.org_manage_code,                                  -- 业务管理机构代码
    coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) as credit_grant_amount,
    t2.account_type,                                     -- R1/R2/R3
    t1.dt,
    concat(substr(t1.dt, 1, 4), '-', substr(t1.dt, 5, 2), '-', substr(t1.dt, 7, 2)) as days_dt_zx,
    case
        when t3.settle_date is null or cast(t3.settle_date as string) = '' then null
        else cast(day(cast(t3.settle_date as date)) as int)
    end as bill_day,                                     -- settle_date 结算/应还款日
    case
        when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
             and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
        then coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
             / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
        else null
    end as util_rate,
    case
        when coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0 then 1
        else 0
    end as is_pos_bal_acct                                 -- 有余额账户（马消已在 t2 过滤）
from (
    select
        id_unqf, id_unqp, account_id, account_state, close_date, turn_out_date,
        balance, latest_repayment_date, latest_repayment_amount, level5_type,
        repayment_state, info_date, time_inst, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
    where dt >= '20241001'
      and dt < '20260201'
      and (close_date is null or cast(close_date as string) = '')   -- close_date 未结清
) t1
inner join (
    select
        id_unqf, id_unqp, account_no, account_id, credit_serial_no, account_type,
        org_manage_type, org_manage_code, open_date, end_date,
        loan_amount, currency_type, busi_type, assure_type, payment_payment,
        payment_frequency, payment_type, loan_together_state, credit_grant_amount,
        share_credit_amount, loan_give_type, payment_state_transfer, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20241001'
      and dt < '20260201'
      and account_type in ('R1', 'R2', 'R3')
      and org_manage_code <> 'T10156530H0001'              -- 剔除马消
) t2
  on t1.id_unqf = t2.id_unqf
 and t1.id_unqp = t2.id_unqp
 and t1.account_id = t2.account_id                         -- 校对：用 account_id 关联
 and t1.dt = t2.dt
left join (
    select
        id_unqf, id_unqp, account_no, settle_date, info_dt, month, dt,
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
 and t1.account_id = t3.account_no                          -- 校对：1m.account_no = 账户标识
 and t1.dt = t3.dt
 and t3.rn = 1
;

-- =============================================================================
-- Step 2: 报告级聚合（id_unqp + id_unqf + dt）
-- =============================================================================
create table if not exists lj_iceberg.ai_decision_dev.yye_credit_report_agg_20260623 as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    sum(is_pos_bal_acct) as pos_bal_acct_cnt,
    sum(if(is_pos_bal_acct = 1, balance, 0)) as bal_sum,
    max(if(is_pos_bal_acct = 1, balance, null)) as bal_max,
    min(if(is_pos_bal_acct = 1, balance, null)) as bal_min,
    sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0)) as crdt_sum,
    max(if(is_pos_bal_acct = 1, credit_grant_amount, null)) as crdt_max,
    min(if(is_pos_bal_acct = 1, credit_grant_amount, null)) as crdt_min,
    max(if(is_pos_bal_acct = 1, util_rate, null)) as util_max,
    min(if(is_pos_bal_acct = 1, util_rate, null)) as util_min,
    case
        when sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0)) > 0
        then sum(if(is_pos_bal_acct = 1, balance, 0))
             / sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0))
        else null
    end as util_sum,
    count(distinct if(is_pos_bal_acct = 1 and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- =============================================================================
-- Step 3: 账单日压力（同账单日最大账户数 / 最大余额合计）
-- =============================================================================
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
        sum(is_pos_bal_acct) as acct_cnt_same_billday,
        sum(if(is_pos_bal_acct = 1, balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.yye_credit_account_base_20260623
    where is_pos_bal_acct = 1
      and bill_day is not null
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- =============================================================================
-- Step 4: 样本关联 + 时间窗标签
-- 观察日锚点：days_dt_1
--   flg_win_1m/6m/1y : 观察日前回看 30/180/365 天（Notion 近一月/近6月/近1年）
--   flg_fwd_60d      : 观察日后 60 天（兼容你原 SQL 关联窗口）
--   latest_report_rn : 最近一份=观察日前最新报告；若无则取观察日后60天内最新报告
-- =============================================================================
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
    case
        when r.days_dt_zx >= s.days_dt_1
         and r.days_dt_zx <= date_add(s.days_dt_1, 60) then 1 else 0
    end as flg_fwd_60d,
    row_number() over (
        partition by s.uuid
        order by
            case when r.days_dt_zx <= s.days_dt_1 then 0 else 1 end,
            r.days_dt_zx desc
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
   or r.days_dt_zx > date_sub(s.days_dt_1, 365)
  and r.days_dt_zx <= date_add(s.days_dt_1, 60)
;

-- =============================================================================
-- Step 5: 最终特征宽表 ↔ Notion《需要加工的数据》
-- =============================================================================
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

    -- 账户数
    max(if(latest_report_rn = 1, pos_bal_acct_cnt, null)) as latest_pos_bal_acct_cnt,          -- 最近一份有余额账户数
    avg(if(flg_win_1m = 1, pos_bal_acct_cnt, null))       as avg_1m_pos_bal_acct_cnt,          -- 近一月平均有余额账户数
    avg(if(flg_win_6m = 1, pos_bal_acct_cnt, null))       as avg_6m_pos_bal_acct_cnt,          -- 近6月平均有余额账户数
    avg(if(flg_win_1y = 1, pos_bal_acct_cnt, null))       as avg_1y_pos_bal_acct_cnt,          -- 近一年平均有余额账户数

    -- 余额
    max(if(latest_report_rn = 1, bal_sum, null))            as latest_bal_sum,                 -- 最近一份总余额
    max(if(latest_report_rn = 1, bal_max, null))            as latest_bal_max,                 -- 最近一份账户最大余额
    max(if(latest_report_rn = 1, bal_min, null))            as latest_bal_min,                 -- 最近一份账户最小余额
    avg(if(flg_win_1m = 1, bal_sum, null))                  as avg_1m_bal_sum,
    avg(if(flg_win_1m = 1, bal_max, null))                  as avg_1m_bal_max,
    avg(if(flg_win_1m = 1, bal_min, null))                  as avg_1m_bal_min,
    avg(if(flg_win_6m = 1, bal_sum, null))                  as avg_6m_bal_sum,
    avg(if(flg_win_6m = 1, bal_max, null))                  as avg_6m_bal_max,
    avg(if(flg_win_6m = 1, bal_min, null))                  as avg_6m_bal_min,
    avg(if(flg_win_1y = 1, bal_sum, null))                  as avg_1y_bal_sum,
    avg(if(flg_win_1y = 1, bal_max, null))                  as avg_1y_bal_max,
    avg(if(flg_win_1y = 1, bal_min, null))                  as avg_1y_bal_min,

    -- 授信额度
    max(if(latest_report_rn = 1, crdt_sum, null))           as latest_crdt_sum,                -- 最近一份授信额度
    max(if(latest_report_rn = 1, crdt_max, null))           as latest_crdt_max,                -- 最近一份账户最大授信额度
    max(if(latest_report_rn = 1, crdt_min, null))           as latest_crdt_min,                -- 最近一份账户最小授信额度
    avg(if(flg_win_1m = 1, crdt_sum, null))                  as avg_1m_crdt_sum,                -- 近一月账户授信额度(均值)
    avg(if(flg_win_1m = 1, crdt_max, null))                  as avg_1m_crdt_max,
    avg(if(flg_win_1m = 1, crdt_min, null))                  as avg_1m_crdt_min,
    avg(if(flg_win_6m = 1, crdt_sum, null))                  as avg_6m_crdt_sum,
    avg(if(flg_win_6m = 1, crdt_max, null))                  as avg_6m_crdt_max,
    avg(if(flg_win_6m = 1, crdt_min, null))                  as avg_6m_crdt_min,
    avg(if(flg_win_1y = 1, crdt_sum, null))                  as avg_1y_crdt_sum,
    avg(if(flg_win_1y = 1, crdt_max, null))                  as avg_1y_crdt_max,
    avg(if(flg_win_1y = 1, crdt_min, null))                  as avg_1y_crdt_min,

    -- 额度利用率
    max(if(latest_report_rn = 1, util_sum, null))             as latest_util_sum,
    max(if(latest_report_rn = 1, util_max, null))             as latest_util_max,
    max(if(latest_report_rn = 1, util_min, null))             as latest_util_min,
    avg(if(flg_win_1m = 1, util_sum, null))                  as avg_1m_util_sum,
    avg(if(flg_win_1m = 1, util_max, null))                   as avg_1m_util_max,
    avg(if(flg_win_1m = 1, util_min, null))                   as avg_1m_util_min,
    avg(if(flg_win_6m = 1, util_sum, null))                  as avg_6m_util_sum,
    avg(if(flg_win_6m = 1, util_max, null))                   as avg_6m_util_max,
    avg(if(flg_win_6m = 1, util_min, null))                   as avg_6m_util_min,
    avg(if(flg_win_1y = 1, util_sum, null))                  as avg_1y_util_sum,
    avg(if(flg_win_1y = 1, util_max, null))                   as avg_1y_util_max,
    avg(if(flg_win_1y = 1, util_min, null))                   as avg_1y_util_min,

    -- 账单日（最近一份报告）
    max(if(latest_report_rn = 1, bill_day_cnt, null))         as latest_bill_day_cnt,            -- 账单日总数
    max(if(latest_report_rn = 1, same_billday_acct_cnt_max, null)) as latest_same_billday_acct_cnt_max, -- 相同账单日最大账户数
    max(if(latest_report_rn = 1, same_billday_bal_sum_max, null))   as latest_same_billday_bal_sum_max,  -- 相同账单日最大余额
    max(if(flg_win_1m = 1, same_billday_bal_sum_max, null)) as max_1m_same_billday_bal_sum,
    max(if(flg_win_6m = 1, same_billday_bal_sum_max, null))  as max_6m_same_billday_bal_sum,
    max(if(flg_win_1y = 1, same_billday_bal_sum_max, null)) as max_1y_same_billday_bal_sum,

    -- 辅助字段
    max(if(latest_report_rn = 1, dt_zx, null))              as latest_dt_zx,
    sum(flg_win_1m)                                         as zx_report_cnt_1m,
    sum(flg_win_6m)                                         as zx_report_cnt_6m,
    sum(flg_win_1y)                                         as zx_report_cnt_1y,
    sum(flg_fwd_60d)                                        as zx_report_cnt_fwd_60d
from lj_iceberg.ai_decision_dev.yye_credit_report_with_sample_20260623
group by
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
    with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
;

-- =============================================================================
-- Step 6: 复现你原来的“余额是否上升”统计（可选）
-- =============================================================================
-- select
--     if(coalesce(max_6m_same_billday_bal_sum, latest_bal_max, 0)
--        > coalesce(latest_bal_sum, 0), 1, 0) as flg_bal_increase,
--     count(1) as num
-- from lj_iceberg.ai_decision_dev.yye_credit_feature_20260623
-- where crdt_lim_yx >= 20000
--   and had_0_30_zx = 1
--   and had_31_60_zx = 1
--   and had_61_90_zx = 1
--   and no_balance_flg_90 = 1
--   and with_0_30 + with_31_60 + with_61_90 = 0
-- group by if(coalesce(max_6m_same_billday_bal_sum, latest_bal_max, 0)
--             > coalesce(latest_bal_sum, 0), 1, 0)
-- ;
