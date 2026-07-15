-- =============================================================================
-- 二代征信特征加工 SQL（按 Notion《需要加工的数据》最新版）
--
-- 【权限与读写说明】
--   只读（征信公共源表，不会改写任何人数据）：
--     lj_iceberg.pboccr2d.*  共 9 张
--   只读（你自己的样本表）：
--     lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
--   只写（下面 Step1~6 全部为你个人新建表，前缀 jcr_，与同事 yye_ 表无关）：
--     lj_iceberg.ai_decision_dev.jcr_credit_*  共 7 张（含标签表）
--
-- 特征大类：
--   A. 循环贷额度及额度利用率（剔除马消 T10156530H0001）
--   B. 征信查询次数（查询记录概要 + 近一年多份报告均值）
--   C. 逾期次数/金额（逾期透支信息汇总，最近一份）
--   D. 资质：房贷/公积金贷款（最近一份）
--   E. 信用卡额度/账户数/余额/利用率（信贷交易信息概要，最近一份）
--   F. 工作单位类型（个人职业信息 org_type，最近一份）
--
-- 【标签构建 / 日期口径】详见 notion_schema/项目说明_标签构建.md
--   训练 cohort ：2025-08 / 09 / 10，样本日=月内额度利用率最低日
--   标签观察窗  ：样本日后 0~60 日，征信余额是否增加
--   测试打分日  ：2025-11-01
-- =============================================================================

-- ===================== 日期与标签参数（2025） =====================
-- zx_dt_start         = '20240801'   征信分区起点（样本日前推1年特征）
-- zx_dt_end           = '20260101'   征信分区终点（10月样本+60天 & 11.1测试）
-- train_sample_months = 202508, 202509, 202510
-- test_predict_date   = '2025-11-01'
-- label_fwd_days      = 60
-- min_crdt_lim_yx     = 20000
-- =============================================================================

-- ===================== 个人表名参数（按需修改后缀日期） =====================
-- 样本表（须由你自己维护，本脚本只读、不写）
--   lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
-- 产出表（本脚本创建，全是新表）：
--   jcr_credit_account_base_20260623
--   jcr_credit_report_agg_20260623
--   jcr_credit_billday_agg_20260623
--   jcr_credit_report_ext_20260623
--   jcr_credit_report_with_sample_20260623
--   jcr_credit_feature_20260623          <-- 最终特征宽表
--   jcr_credit_feature_label_20260623    <-- 特征+标签+数据集划分

-- Step 0（可选，一次性）：若你还没有自己的样本表，可从同事表复制到你名下。
-- 执行一次后请注释掉，避免反复依赖同事表。
-- create table if not exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 as
-- select * from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2;

-- Step 1: 循环贷账户级明细（R1/R2/R3，剔除马消）
-- 关联键说明：生产表 latest_perform 实际字段为 account_no（与你原 SQL 一致），
-- 非 Notion 文档中的 account_id。
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623 as
select
    t1.id_unqf,
    t1.id_unqp,
    t1.account_no,
    t2.account_id,
    coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) as balance,
    t2.org_manage_type,
    t2.org_manage_code,
    coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) as credit_grant_amount,
    t2.account_type,
    t1.dt,
    concat(substr(t1.dt, 1, 4), '-', substr(t1.dt, 5, 2), '-', substr(t1.dt, 7, 2)) as days_dt_zx,
    case
        when t3.settle_date is null or cast(t3.settle_date as string) = '' then null
        else cast(day(cast(t3.settle_date as date)) as int)
    end as bill_day,
    case
        when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
             and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
        then coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
             / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
        else null
    end as util_rate,
    case when coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0 then 1 else 0 end as is_pos_bal_acct
from (
    select id_unqf, id_unqp, account_no, close_date, balance, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
    where dt >= '20240801' and dt < '20260101'
      and (close_date is null or cast(close_date as string) = '')
) t1
inner join (
    select id_unqf, id_unqp, account_no, account_id, account_type,
           org_manage_type, org_manage_code, credit_grant_amount, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260101'
      and account_type in ('R1', 'R2', 'R3')
      and org_manage_code <> 'T10156530H0001'
) t2
  on t1.id_unqf = t2.id_unqf and t1.id_unqp = t2.id_unqp
 and t1.account_no = t2.account_no and t1.dt = t2.dt
left join (
    select id_unqf, id_unqp, account_no, settle_date, info_dt, month, dt,
           row_number() over (
               partition by id_unqf, id_unqp, account_no, dt
               order by coalesce(info_dt, settle_date) desc, month desc
           ) as rn
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform
    where dt >= '20240801' and dt < '20260101'
) t3
  on t1.id_unqf = t3.id_unqf and t1.id_unqp = t3.id_unqp
 and t1.account_no = t3.account_no and t1.dt = t3.dt and t3.rn = 1
;

-- Step 2: 循环贷报告级聚合
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623 as
select
    id_unqp, id_unqf, dt, days_dt_zx,
    sum(is_pos_bal_acct) as pos_bal_acct_cnt,
    sum(if(is_pos_bal_acct = 1, balance, 0)) as bal_sum,
    max(if(is_pos_bal_acct = 1, balance, null)) as bal_max,
    min(if(is_pos_bal_acct = 1, balance, null)) as bal_min,
    sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0)) as crdt_sum,
    max(if(is_pos_bal_acct = 1, credit_grant_amount, null)) as crdt_max,
    min(if(is_pos_bal_acct = 1, credit_grant_amount, null)) as crdt_min,
    max(if(is_pos_bal_acct = 1, util_rate, null)) as util_max,
    min(if(is_pos_bal_acct = 1, util_rate, null)) as util_min,
    case when sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0)) > 0
         then sum(if(is_pos_bal_acct = 1, balance, 0))
              / sum(if(is_pos_bal_acct = 1, credit_grant_amount, 0))
         else null end as util_sum,
    count(distinct if(is_pos_bal_acct = 1 and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 3: 账单日压力
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623 as
select id_unqp, id_unqf, dt, days_dt_zx,
       max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
       max(bal_sum_same_billday) as same_billday_bal_sum_max
from (
    select id_unqp, id_unqf, dt, days_dt_zx, bill_day,
           sum(is_pos_bal_acct) as acct_cnt_same_billday,
           sum(if(is_pos_bal_acct = 1, balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623
    where is_pos_bal_acct = 1 and bill_day is not null
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 4: 报告级扩展特征（查询/逾期/信用卡/资质/职业）
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623 as
select
    spine.id_unqp,
    spine.id_unqf,
    spine.dt,
    spine.days_dt_zx,

    -- B. 征信查询次数 dsst_eds_gaa02_query_summary
    cast(nullif(q.credit_audit_query_org_num_1m, '') as int) as credit_audit_query_org_num_1m,
    cast(nullif(q.loan_audit_query_num_1m, '') as int) as loan_audit_query_num_1m,
    cast(nullif(q.credit_audit_query_num_1m, '') as int) as credit_audit_query_num_1m,
    cast(nullif(q.person_query_num_1m, '') as int) as person_query_num_1m,
    cast(nullif(q.plm_query_num_2y, '') as int) as plm_query_num_2y,
    cast(nullif(q.assure_query_num_2y, '') as int) as assure_query_num_2y,
    cast(nullif(q.sam_query_num_2y, '') as int) as sam_query_num_2y,
    coalesce(cast(nullif(q.loan_audit_query_num_1m, '') as int), 0)
      + coalesce(cast(nullif(q.credit_audit_query_num_1m, '') as int), 0) as hard_query_num_1m,

    -- C. 逾期 dsst_eds_gaa02_credit_loan_summary_pd_summary（按报告汇总多业务类型）
    pd.pd_num_month_max,
    pd.pd_num_month_sum,
    pd.pd_max_overdue_months,
    pd.pd_max_overdue_amt,

    -- E. 信用卡 dsst_eds_gaa02_credit_loan_summary
    cast(nullif(cls.credit_account_num, '') as int) as credit_account_num,
    cast(nullif(cls.credit_amount, '') as decimal(18, 2)) as credit_amount,
    cast(nullif(cls.credit_used_amount, '') as decimal(18, 2)) as credit_used_amount,
    case when coalesce(cast(nullif(cls.credit_amount, '') as decimal(18, 2)), 0) > 0
         then cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))
              / cast(nullif(cls.credit_amount, '') as decimal(18, 2))
         else null end as credit_util_rate,

    -- D. 资质：房贷 / 公积金贷款
    case when coalesce(tip.has_house_loan_flg, 0) > 0
           or coalesce(bi.has_house_loan_flg, 0) > 0 then 1 else 0 end as has_house_loan_flg,
    case when coalesce(tip.has_gjj_loan_flg, 0) > 0
           or coalesce(phf.has_gjj_record_flg, 0) > 0
           or coalesce(bi.has_gjj_loan_flg, 0) > 0 then 1 else 0 end as has_gjj_loan_flg,

    -- F. 工作单位类型 dsst_eds_gaa02_person_job_info.org_type
    job.org_type

from (
    select id_unqp, id_unqf, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20240801' and dt < '20260101'
) spine
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary q
  on spine.id_unqf = q.id_unqf and spine.id_unqp = q.id_unqp and spine.dt = q.dt
left join (
    select id_unqp, id_unqf, dt,
           max(cast(nullif(num_month, '') as int)) as pd_num_month_max,
           sum(cast(nullif(num_month, '') as int)) as pd_num_month_sum,
           max(cast(nullif(first_business_month, '') as int)) as pd_max_overdue_months,
           max(cast(nullif(amt_pdtotal, '') as decimal(18, 2))) as pd_max_overdue_amt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary
    where dt >= '20240801' and dt < '20260101'
    group by id_unqp, id_unqf, dt
) pd
  on spine.id_unqf = pd.id_unqf and spine.id_unqp = pd.id_unqp and spine.dt = pd.dt
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary cls
  on spine.id_unqf = cls.id_unqf and spine.id_unqp = cls.id_unqp and spine.dt = cls.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when cre_tran_pro_type in ('11', '12') then 1 else 0 end) as has_house_loan_flg,
           max(case when cre_tran_pro_type = '13' then 1 else 0 end) as has_gjj_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail
    where dt >= '20240801' and dt < '20260101'
    group by id_unqp, id_unqf, dt
) tip
  on spine.id_unqf = tip.id_unqf and spine.id_unqp = tip.id_unqp and spine.dt = tip.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when busi_type = '13' or busi_type like '%公积金%' then 1 else 0 end) as has_gjj_loan_flg,
           max(case when busi_type in ('11', '12') or busi_type like '%住房%' then 1 else 0 end) as has_house_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260101'
    group by id_unqp, id_unqf, dt
) bi
  on spine.id_unqf = bi.id_unqf and spine.id_unqp = bi.id_unqp and spine.dt = bi.dt
left join (
    select id_unqp, id_unqf, dt, 1 as has_gjj_record_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record
    where dt >= '20240801' and dt < '20260101'
    group by id_unqp, id_unqf, dt
) phf
  on spine.id_unqf = phf.id_unqf and spine.id_unqp = phf.id_unqp and spine.dt = phf.dt
left join (
    select id_unqp, id_unqf, dt, org_type
    from (
        select id_unqp, id_unqf, dt, org_type,
               row_number() over (
                   partition by id_unqf, id_unqp, dt
                   order by update_date desc nulls last, time_inst desc
               ) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801' and dt < '20260101'
    ) x
    where rn = 1
) job
  on spine.id_unqf = job.id_unqf and spine.id_unqp = job.id_unqp and spine.dt = job.dt
;

-- Step 5: 样本关联（报告主键统一后再挂循环贷/扩展/账单日特征）
-- 训练 cohort：样本表 dt 落在 202508/202509/202510（2025年8~10月）
-- 征信关联窗：days_dt_1 前推365天 ~ 后推60天（标签观察窗）
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623 as
select
    s.uuid, s.user_id, s.pril_bal, s.crdt_lim_yx, s.pril_bal_rate,
    s.dt, s.days_dt, s.no_balance_flg_30, s.no_balance_flg_60, s.no_balance_flg_90,
    s.days_dt_1, s.had_0_30_zx, s.had_31_60_zx, s.had_61_90_zx, s.had_91_120_zx,
    s.with_0_30, s.with_31_60, s.with_61_90, s.with_91_120,
    s.with_0_30_5103, s.with_31_60_5103, s.with_61_90_5103, s.with_91_120_5103,

    rep.id_unqf,
    rep.dt as dt_zx,
    rep.days_dt_zx,

    r.pos_bal_acct_cnt, r.bal_sum, r.bal_max, r.bal_min,
    r.crdt_sum, r.crdt_max, r.crdt_min, r.util_sum, r.util_max, r.util_min, r.bill_day_cnt,
    b.same_billday_acct_cnt_max, b.same_billday_bal_sum_max,

    e.credit_audit_query_org_num_1m, e.loan_audit_query_num_1m, e.credit_audit_query_num_1m,
    e.person_query_num_1m, e.plm_query_num_2y, e.assure_query_num_2y, e.sam_query_num_2y,
    e.hard_query_num_1m,
    e.pd_num_month_max, e.pd_num_month_sum, e.pd_max_overdue_months, e.pd_max_overdue_amt,
    e.credit_account_num, e.credit_amount, e.credit_used_amount, e.credit_util_rate,
    e.has_house_loan_flg, e.has_gjj_loan_flg, e.org_type,

    case when rep.days_dt_zx > date_sub(s.days_dt_1, 30)
          and rep.days_dt_zx <= s.days_dt_1 then 1 else 0 end as flg_win_1m,
    case when rep.days_dt_zx > date_sub(s.days_dt_1, 180)
          and rep.days_dt_zx <= s.days_dt_1 then 1 else 0 end as flg_win_6m,
    case when rep.days_dt_zx > date_sub(s.days_dt_1, 365)
          and rep.days_dt_zx <= s.days_dt_1 then 1 else 0 end as flg_win_1y,
    case when rep.days_dt_zx >= s.days_dt_1
          and rep.days_dt_zx <= date_add(s.days_dt_1, 60) then 1 else 0 end as flg_fwd_60d,

    row_number() over (
        partition by s.uuid
        order by case when rep.days_dt_zx <= s.days_dt_1 then 0 else 1 end,
                 rep.days_dt_zx desc
    ) as latest_report_rn
from (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
           no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
           had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
           with_0_30, with_31_60, with_61_90, with_91_120,
           with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
) s
left join (
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623
    union
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623
) rep
  on s.uuid = rep.id_unqp
left join lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623 r
  on rep.id_unqp = r.id_unqp and rep.id_unqf = r.id_unqf and rep.dt = r.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623 e
  on rep.id_unqp = e.id_unqp and rep.id_unqf = e.id_unqf and rep.dt = e.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623 b
  on rep.id_unqp = b.id_unqp and rep.id_unqf = b.id_unqf and rep.dt = b.dt
where rep.days_dt_zx is null
   or (
        rep.days_dt_zx > date_sub(s.days_dt_1, 365)
    and rep.days_dt_zx <= date_add(s.days_dt_1, 60)
      )
;

-- Step 6: 最终特征宽表
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623 as
select
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
    with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103,

    -- A. 循环贷账户数
    max(if(latest_report_rn = 1, pos_bal_acct_cnt, null)) as latest_pos_bal_acct_cnt,
    avg(if(flg_win_1m = 1, pos_bal_acct_cnt, null)) as avg_1m_pos_bal_acct_cnt,
    avg(if(flg_win_6m = 1, pos_bal_acct_cnt, null)) as avg_6m_pos_bal_acct_cnt,
    avg(if(flg_win_1y = 1, pos_bal_acct_cnt, null)) as avg_1y_pos_bal_acct_cnt,

    -- A. 余额
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

    -- A. 授信额度
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

    -- A. 额度利用率
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

    -- A. 账单日
    max(if(latest_report_rn = 1, bill_day_cnt, null)) as latest_bill_day_cnt,
    max(if(latest_report_rn = 1, same_billday_acct_cnt_max, null)) as latest_same_billday_acct_cnt_max,
    max(if(latest_report_rn = 1, same_billday_bal_sum_max, null)) as latest_same_billday_bal_sum_max,
    max(if(flg_win_1m = 1, same_billday_bal_sum_max, null)) as max_1m_same_billday_bal_sum,
    max(if(flg_win_6m = 1, same_billday_bal_sum_max, null)) as max_6m_same_billday_bal_sum,
    max(if(flg_win_1y = 1, same_billday_bal_sum_max, null)) as max_1y_same_billday_bal_sum,

    -- B. 征信查询次数（最近一份 + 近一年均值）
    max(if(latest_report_rn = 1, credit_audit_query_org_num_1m, null)) as latest_credit_audit_query_org_num_1m,
    max(if(latest_report_rn = 1, loan_audit_query_num_1m, null)) as latest_loan_audit_query_num_1m,
    max(if(latest_report_rn = 1, credit_audit_query_num_1m, null)) as latest_credit_audit_query_num_1m,
    max(if(latest_report_rn = 1, person_query_num_1m, null)) as latest_person_query_num_1m,
    max(if(latest_report_rn = 1, plm_query_num_2y, null)) as latest_plm_query_num_2y,
    max(if(latest_report_rn = 1, assure_query_num_2y, null)) as latest_assure_query_num_2y,
    max(if(latest_report_rn = 1, sam_query_num_2y, null)) as latest_sam_query_num_2y,
    max(if(latest_report_rn = 1, hard_query_num_1m, null)) as latest_hard_query_num_1m,
    avg(if(flg_win_1y = 1, credit_audit_query_org_num_1m, null)) as avg_1y_credit_audit_query_org_num_1m,
    avg(if(flg_win_1y = 1, loan_audit_query_num_1m, null)) as avg_1y_loan_audit_query_num_1m,
    avg(if(flg_win_1y = 1, credit_audit_query_num_1m, null)) as avg_1y_credit_audit_query_num_1m,
    avg(if(flg_win_1y = 1, person_query_num_1m, null)) as avg_1y_person_query_num_1m,
    avg(if(flg_win_1y = 1, plm_query_num_2y, null)) as avg_1y_plm_query_num_2y,
    avg(if(flg_win_1y = 1, assure_query_num_2y, null)) as avg_1y_assure_query_num_2y,
    avg(if(flg_win_1y = 1, sam_query_num_2y, null)) as avg_1y_sam_query_num_2y,
    avg(if(flg_win_1y = 1, hard_query_num_1m, null)) as avg_1y_hard_query_num_1m,

    -- C. 逾期（最近一份）
    max(if(latest_report_rn = 1, pd_num_month_max, null)) as latest_pd_num_month,
    max(if(latest_report_rn = 1, pd_num_month_sum, null)) as latest_pd_total_overdue_cnt,
    max(if(latest_report_rn = 1, pd_max_overdue_months, null)) as latest_pd_max_overdue_months,
    max(if(latest_report_rn = 1, pd_max_overdue_amt, null)) as latest_pd_max_overdue_amt,

    -- D. 资质（最近一份）
    max(if(latest_report_rn = 1, has_house_loan_flg, null)) as latest_has_house_loan_flg,
    max(if(latest_report_rn = 1, has_gjj_loan_flg, null)) as latest_has_gjj_loan_flg,

    -- E. 信用卡（最近一份）
    max(if(latest_report_rn = 1, credit_account_num, null)) as latest_credit_account_num,
    max(if(latest_report_rn = 1, credit_amount, null)) as latest_credit_amount,
    max(if(latest_report_rn = 1, credit_used_amount, null)) as latest_credit_used_amount,
    max(if(latest_report_rn = 1, credit_util_rate, null)) as latest_credit_util_rate,

    -- F. 工作单位类型（最近一份）
    max(if(latest_report_rn = 1, org_type, null)) as latest_org_type,

    -- 辅助
    max(if(latest_report_rn = 1, dt_zx, null)) as latest_dt_zx,
    sum(flg_win_1m) as zx_report_cnt_1m,
    sum(flg_win_6m) as zx_report_cnt_6m,
    sum(flg_win_1y) as zx_report_cnt_1y,
    sum(flg_fwd_60d) as zx_report_cnt_fwd_60d
from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623
group by
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
    with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
;

-- Step 7: 标签 + 数据集划分（训练/验证/测试）
-- 正样本 label=1：样本日后60天内征信余额增加（fwd_max_balance > fwd_first_balance）
-- 负样本 label=0：未增加
-- 训练 cohort：2025-08/09/10；测试打分：2025-11-01（仅特征，label 可为空）
create table if not exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623 as
select
    f.*,
    substr(f.dt, 1, 6) as sample_month,
    l.fwd_first_balance,
    l.fwd_max_balance,
    case
        when l.fwd_max_balance > l.fwd_first_balance then 1
        when l.fwd_max_balance is not null then 0
        else null
    end as label,
    case
        when f.days_dt = '2025-11-01' then 'test'
        when substr(f.dt, 1, 6) in ('202508', '202509', '202510')
             and pmod(hash(f.uuid), 10) < 8 then 'train'
        when substr(f.dt, 1, 6) in ('202508', '202509', '202510') then 'val'
        else 'other'
    end as dataset_split
from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623 f
left join (
    select
        uuid,
        max(if(fwd_rn = 1, bal_sum, null)) as fwd_first_balance,
        max(if(flg_fwd_60d = 1, bal_sum, null)) as fwd_max_balance
    from (
        select
            uuid,
            bal_sum,
            flg_fwd_60d,
            row_number() over (partition by uuid order by dt_zx asc) as fwd_rn
        from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623
        where flg_fwd_60d = 1
          and bal_sum is not null
    ) t
    group by uuid
) l
  on f.uuid = l.uuid
where f.crdt_lim_yx >= 20000
  and (
        substr(f.dt, 1, 6) in ('202508', '202509', '202510')
        or f.days_dt = '2025-11-01'
      )
;

-- Step 8: 标签分布核验（2025年10月示例，可按 sample_month 调整）
-- select
--     sample_month,
--     label,
--     dataset_split,
--     count(1) as num,
--     round(count(1) * 100.0 / sum(count(1)) over (partition by sample_month), 2) as pct
-- from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where sample_month = '202510'
--   and no_balance_flg_90 = 1
--   and had_0_30_zx = 1
--   and had_31_60_zx = 1
--   and had_61_90_zx = 1
--   and with_0_30 + with_31_60 + with_61_90 = 0
--   and label is not null
-- group by sample_month, label, dataset_split
-- order by label, dataset_split
-- ;
