-- =============================================================================
-- 一键全量 v20260715：样本 + 征信特征 + 标签 + 马消特征
-- =============================================================================
-- 前置：yye_pril_bal_info_20260715_1（同事 reference 产出）
--
-- 写法：全程 insert overwrite（表需已存在；全量清表见 drop_all_jcr_tables_20260715.sql）
--
-- 流水线：
--   Part 1~2 yye _1 → info → cohort（锚点 days_dt；cohort=info 五条件）
--   Part 3~6 征信账户→聚合→扩展→挂样本→特征宽表
--   Part 7   标签 zx_balance_label + train/val 划分（仅 202508/202509/202510，hash 8:2）
--   Part 7b  马消特征
--   Part 8   终表 jcr_credit_feature_label_full_20260715
--   Part 9   核验
-- =============================================================================

-- ########## Part 1~2：样本 + cohort ##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
select
    t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m,
    t1.no_balance_flg_30, t1.no_balance_flg_60, t1.no_balance_flg_90,
    max(case when t2.days_dt_zx between t1.days_dt and date_add(t1.days_dt, 30) then 1 else 0 end) as had_0_30_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt, 31) and date_add(t1.days_dt, 60) then 1 else 0 end) as had_31_60_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt, 61) and date_add(t1.days_dt, 90) then 1 else 0 end) as had_61_90_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt, 91) and date_add(t1.days_dt, 120) then 1 else 0 end) as had_91_120_zx,
    max(if(t3.wday between t1.days_dt and date_add(t1.days_dt, 30), 1, 0)) as with_0_30,
    max(if(t3.wday between date_add(t1.days_dt, 31) and date_add(t1.days_dt, 60), 1, 0)) as with_31_60,
    max(if(t3.wday between date_add(t1.days_dt, 61) and date_add(t1.days_dt, 90), 1, 0)) as with_61_90,
    max(if(t3.wday between date_add(t1.days_dt, 91) and date_add(t1.days_dt, 120), 1, 0)) as with_91_120
from (
    select *
    from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260715_1
    where m in ('202508', '202509', '202510')
) t1
left join (
    select id_unqp, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
) t2 on t1.uuid = t2.id_unqp
left join (
    select unique_id, user_id, bhv_time, event, aprv_status, day_time,
           instal_terms, wdraw_apply_amt, final_loan_amt, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, user_id, bhv_time, event, aprv_status, day_time,
             instal_terms, wdraw_apply_amt, final_loan_amt, prod_cd
) t3 on t1.uuid = t3.unique_id
group by
    t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m,
    t1.no_balance_flg_30, t1.no_balance_flg_60, t1.no_balance_flg_90
;

insert overwrite table lj_iceberg.ai_decision_dev.jcr_cohort_20260715
select uuid, user_id, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where crdt_lim_yx >= 20000
  and m in ('202508', '202509', '202510')
  and had_0_30_zx = 1
  and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
;

-- ########## Part 3：循环贷账户明细（仅 cohort uuid）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715
select
    t1.id_unqf, t1.id_unqp, t1.account_no, t2.account_id,
    coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) as balance,
    t2.org_manage_type, t2.org_manage_code,
    coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) as credit_grant_amount,
    t2.account_type, t1.dt,
    concat(substr(t1.dt, 1, 4), '-', substr(t1.dt, 5, 2), '-', substr(t1.dt, 7, 2)) as days_dt_zx,
    case when t3.settle_date is null or cast(t3.settle_date as string) = '' then null
         else cast(day(cast(t3.settle_date as date)) as int) end as bill_day,
    case when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
              and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
         then coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
              / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
         else null end as util_rate,
    case when coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0 then 1 else 0 end as is_pos_bal_acct
from (
    select id_unqf, id_unqp, account_no, close_date, balance, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
    where dt >= '20240801' and dt < '20260301'
      and (close_date is null or cast(close_date as string) = '')
) t1
inner join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 co on t1.id_unqp = co.uuid
inner join (
    select id_unqf, id_unqp, account_no, account_id, account_type,
           org_manage_type, org_manage_code, credit_grant_amount, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260301'
      and account_type in ('R1', 'R2', 'R3')
) t2 on t1.id_unqf = t2.id_unqf and t1.id_unqp = t2.id_unqp
    and t1.account_no = t2.account_no and t1.dt = t2.dt
left join (
    select id_unqf, id_unqp, account_no, settle_date, info_dt, month, dt,
           row_number() over (
               partition by id_unqf, id_unqp, account_no, dt
               order by coalesce(info_dt, settle_date) desc, month desc
           ) as rn
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform
    where dt >= '20240801' and dt < '20260301'
) t3 on t1.id_unqf = t3.id_unqf and t1.id_unqp = t3.id_unqp
    and t1.account_no = t3.account_no and t1.dt = t3.dt and t3.rn = 1
;

-- ########## Part 4：报告级聚合（剔马消 T10156530H0001）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715
select
    id_unqp, id_unqf, dt, days_dt_zx,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', 1, 0)) as pos_bal_acct_cnt,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, null)) as bal_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, null)) as bal_min,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0)) as crdt_sum,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, null)) as crdt_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, null)) as crdt_min,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', util_rate, null)) as util_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', util_rate, null)) as util_min,
    case when sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0)) > 0
         then sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0))
              / sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0))
         else null end as util_sum,
    count(distinct if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001' and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715
group by id_unqp, id_unqf, dt, days_dt_zx
;

insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715
select id_unqp, id_unqf, dt, days_dt_zx,
       max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
       max(bal_sum_same_billday) as same_billday_bal_sum_max
from (
    select id_unqp, id_unqf, dt, days_dt_zx, bill_day,
           sum(if(org_manage_code <> 'T10156530H0001', is_pos_bal_acct, 0)) as acct_cnt_same_billday,
           sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715
    where is_pos_bal_acct = 1 and bill_day is not null and org_manage_code <> 'T10156530H0001'
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715
select
    spine.id_unqp, spine.id_unqf, spine.dt, spine.days_dt_zx,
    cast(nullif(q.credit_audit_query_org_num_1m, '') as int) as credit_audit_query_org_num_1m,
    cast(nullif(q.loan_audit_query_num_1m, '') as int) as loan_audit_query_num_1m,
    cast(nullif(q.credit_audit_query_num_1m, '') as int) as credit_audit_query_num_1m,
    cast(nullif(q.person_query_num_1m, '') as int) as person_query_num_1m,
    cast(nullif(q.plm_query_num_2y, '') as int) as plm_query_num_2y,
    cast(nullif(q.assure_query_num_2y, '') as int) as assure_query_num_2y,
    cast(nullif(q.sam_query_num_2y, '') as int) as sam_query_num_2y,
    coalesce(cast(nullif(q.loan_audit_query_num_1m, '') as int), 0)
      + coalesce(cast(nullif(q.credit_audit_query_num_1m, '') as int), 0) as hard_query_num_1m,
    pd.pd_num_month_max, pd.pd_num_month_sum, pd.pd_max_overdue_months, pd.pd_max_overdue_amt,
    cast(nullif(cls.credit_account_num, '') as int) as credit_account_num,
    cast(nullif(cls.credit_amount, '') as decimal(18, 2)) as credit_amount,
    cast(nullif(cls.credit_used_amount, '') as decimal(18, 2)) as credit_used_amount,
    case when coalesce(cast(nullif(cls.credit_amount, '') as decimal(18, 2)), 0) > 0
         then cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))
              / cast(nullif(cls.credit_amount, '') as decimal(18, 2))
         else null end as credit_util_rate,
    case when coalesce(tip.has_house_loan_flg, 0) > 0 or coalesce(bi.has_house_loan_flg, 0) > 0 then 1 else 0 end as has_house_loan_flg,
    case when coalesce(tip.has_gjj_loan_flg, 0) > 0 or coalesce(phf.has_gjj_record_flg, 0) > 0
              or coalesce(bi.has_gjj_loan_flg, 0) > 0 then 1 else 0 end as has_gjj_loan_flg,
    job.org_type
from (
    select id_unqp, id_unqf, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20240801' and dt < '20260301'
      and id_unqp in (select uuid from lj_iceberg.ai_decision_dev.jcr_cohort_20260715)
) spine
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary q
  on spine.id_unqf = q.id_unqf and spine.id_unqp = q.id_unqp and spine.dt = q.dt
left join (
    select id_unqp, id_unqf, dt,
           max(cast(nullif(num_month, '') as int)) as pd_num_month_max,
           sum(cast(nullif(num_month, '') as int)) as pd_num_month_sum,
           max(cast(nullif(max_amt_pd, '') as int)) as pd_max_overdue_months,
           max(cast(nullif(amt_pdtotal, '') as decimal(18, 2))) as pd_max_overdue_amt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) pd on spine.id_unqf = pd.id_unqf and spine.id_unqp = pd.id_unqp and spine.dt = pd.dt
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary cls
  on spine.id_unqf = cls.id_unqf and spine.id_unqp = cls.id_unqp and spine.dt = cls.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when cre_tran_pro_type in ('11', '12') then 1 else 0 end) as has_house_loan_flg,
           max(case when cre_tran_pro_type = '13' then 1 else 0 end) as has_gjj_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) tip on spine.id_unqf = tip.id_unqf and spine.id_unqp = tip.id_unqp and spine.dt = tip.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when busi_type = '13' or busi_type like '%公积金%' then 1 else 0 end) as has_gjj_loan_flg,
           max(case when busi_type in ('11', '12') or busi_type like '%住房%' then 1 else 0 end) as has_house_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) bi on spine.id_unqf = bi.id_unqf and spine.id_unqp = bi.id_unqp and spine.dt = bi.dt
left join (
    select id_unqp, id_unqf, dt, 1 as has_gjj_record_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) phf on spine.id_unqf = phf.id_unqf and spine.id_unqp = phf.id_unqp and spine.dt = phf.dt
left join (
    select id_unqp, id_unqf, dt, org_type
    from (
        select id_unqp, id_unqf, dt, org_type,
               row_number() over (partition by id_unqf, id_unqp, dt order by update_date desc, time_inst desc) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801' and dt < '20260301'
    ) x where rn = 1
) job on spine.id_unqf = job.id_unqf and spine.id_unqp = job.id_unqp and spine.dt = job.dt
;

-- ########## Part 5：cohort 挂征信报告（锚点 days_dt，前推1年~后推60天）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715
select
    s.uuid, s.user_id, s.pril_bal, s.crdt_lim_yx, s.pril_bal_rate, s.dt, s.days_dt, s.m,
    s.no_balance_flg_30, s.no_balance_flg_60, s.no_balance_flg_90,
    s.had_0_30_zx, s.had_31_60_zx, s.had_61_90_zx, s.had_91_120_zx,
    s.with_0_30, s.with_31_60, s.with_61_90, s.with_91_120,
    rep.id_unqf, rep.dt as dt_zx, rep.days_dt_zx,
    r.pos_bal_acct_cnt, r.bal_sum, r.bal_max, r.bal_min,
    r.crdt_sum, r.crdt_max, r.crdt_min, r.util_sum, r.util_max, r.util_min, r.bill_day_cnt,
    b.same_billday_acct_cnt_max, b.same_billday_bal_sum_max,
    e.credit_audit_query_org_num_1m, e.loan_audit_query_num_1m, e.credit_audit_query_num_1m,
    e.person_query_num_1m, e.plm_query_num_2y, e.assure_query_num_2y, e.sam_query_num_2y, e.hard_query_num_1m,
    e.pd_num_month_max, e.pd_num_month_sum, e.pd_max_overdue_months, e.pd_max_overdue_amt,
    e.credit_account_num, e.credit_amount, e.credit_used_amount, e.credit_util_rate,
    e.has_house_loan_flg, e.has_gjj_loan_flg, e.org_type,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 30)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_1m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 180)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_6m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 365)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_1y,
    case when cast(rep.days_dt_zx as date) between cast(s.days_dt as date)
                                              and date_add(cast(s.days_dt as date), 60) then 1 else 0 end as flg_fwd_60d,
    row_number() over (
        partition by s.uuid, s.dt
        order by case when rep.days_dt_zx <= s.days_dt then 0 else 1 end, rep.days_dt_zx desc
    ) as latest_report_rn
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 s
inner join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
  on s.uuid = c.uuid and s.m = c.m and s.dt = c.dt
left join (
    select id_unqp, id_unqf, dt, days_dt_zx from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715
    union
    select id_unqp, id_unqf, dt, days_dt_zx from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715
) rep on s.uuid = rep.id_unqp
 and cast(rep.days_dt_zx as date) > date_sub(cast(s.days_dt as date), 365)
 and cast(rep.days_dt_zx as date) <= date_add(cast(s.days_dt as date), 60)
left join lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 r
  on rep.id_unqp = r.id_unqp and rep.id_unqf = r.id_unqf and rep.dt = r.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 e
  on rep.id_unqp = e.id_unqp and rep.id_unqf = e.id_unqf and rep.dt = e.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 b
  on rep.id_unqp = b.id_unqp and rep.id_unqf = b.id_unqf and rep.dt = b.dt
;

-- ########## Part 6：征信特征宽表（对齐 需要加工的数据.md）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715
select
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
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
    max(if(latest_report_rn = 1, pd_num_month_max, null)) as latest_pd_num_month,
    max(if(latest_report_rn = 1, pd_num_month_sum, null)) as latest_pd_total_overdue_cnt,
    max(if(latest_report_rn = 1, pd_max_overdue_months, null)) as latest_pd_max_overdue_months,
    max(if(latest_report_rn = 1, pd_max_overdue_amt, null)) as latest_pd_max_overdue_amt,
    max(if(latest_report_rn = 1, has_house_loan_flg, null)) as latest_has_house_loan_flg,
    max(if(latest_report_rn = 1, has_gjj_loan_flg, null)) as latest_has_gjj_loan_flg,
    max(if(latest_report_rn = 1, credit_account_num, null)) as latest_credit_account_num,
    max(if(latest_report_rn = 1, credit_amount, null)) as latest_credit_amount,
    max(if(latest_report_rn = 1, credit_used_amount, null)) as latest_credit_used_amount,
    max(if(latest_report_rn = 1, credit_util_rate, null)) as latest_credit_util_rate,
    max(if(latest_report_rn = 1, org_type, null)) as latest_org_type,
    max(if(latest_report_rn = 1, dt_zx, null)) as latest_dt_zx,
    sum(flg_win_1m) as zx_report_cnt_1m,
    sum(flg_win_6m) as zx_report_cnt_6m,
    sum(flg_win_1y) as zx_report_cnt_1y,
    sum(flg_fwd_60d) as zx_report_cnt_fwd_60d
from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715
group by
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120
;

-- ########## Part 7：标签 + train/val 划分（8/9/10 月 hash 8:2）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715
select
    f.*,
    l.fwd_first_balance,
    l.fwd_max_balance,
    case when l.fwd_max_balance > l.fwd_first_balance then 1
         when l.fwd_max_balance is not null then 0
         else null end as zx_balance_label,
    case when l.fwd_max_balance is not null then 1 else 0 end as label_eligible,
    case when abs(hash(concat(f.uuid, f.dt))) % 10 < 8 then 'train' else 'val' end as dataset_split
from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 f
left join (
    select uuid, dt,
           max(if(zx_rank = 1, balance, null)) as fwd_first_balance,
           max(balance) as fwd_max_balance
    from (
        select c.uuid, c.dt, b.days_dt_zx,
               sum(if(b.balance > 0 and b.org_manage_code <> 'T10156530H0001', b.balance, 0)) as balance,
               row_number() over (partition by c.uuid, c.dt order by b.days_dt_zx asc) as zx_rank
        from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
        left join lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 b
          on c.uuid = b.id_unqp
         and cast(b.days_dt_zx as date) between cast(c.days_dt as date) and date_add(cast(c.days_dt as date), 60)
        group by c.uuid, c.dt, b.dt, b.days_dt_zx
    ) t
    group by uuid, dt
) l on f.uuid = l.uuid and f.dt = l.dt
where f.m in ('202508', '202509', '202510')
;

-- ########## Part 7b：马消特征（cohort 子集，全渠道 base_df + 提现）##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715
select
    uuid, user_id, dt, days_dt,
    pril_bal_1w, crdt_lim_yx_1w, if(crdt_lim_yx_1w > 0, pril_bal_1w / crdt_lim_yx_1w, null) as pril_bal_rate_1w,
    pril_bal_1m, crdt_lim_yx_1m, if(crdt_lim_yx_1m > 0, pril_bal_1m / crdt_lim_yx_1m, null) as pril_bal_rate_1m,
    pril_bal_3m, crdt_lim_yx_3m, if(crdt_lim_yx_3m > 0, pril_bal_3m / crdt_lim_yx_3m, null) as pril_bal_rate_3m,
    pril_bal_6m, crdt_lim_yx_6m, if(crdt_lim_yx_6m > 0, pril_bal_6m / crdt_lim_yx_6m, null) as pril_bal_rate_6m,
    pril_bal_1y, crdt_lim_yx_1y, if(crdt_lim_yx_1y > 0, pril_bal_1y / crdt_lim_yx_1y, null) as pril_bal_rate_1y
from (
    select f.uuid, f.user_id, f.dt, f.days_dt,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 6), t2.pril_bal, null)) as pril_bal_1w,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 6), t2.crdt_lim_yx, null)) as crdt_lim_yx_1w,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 29), t2.pril_bal, null)) as pril_bal_1m,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 29), t2.crdt_lim_yx, null)) as crdt_lim_yx_1m,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 89), t2.pril_bal, null)) as pril_bal_3m,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 89), t2.crdt_lim_yx, null)) as crdt_lim_yx_3m,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 179), t2.pril_bal, null)) as pril_bal_6m,
           avg(if(t2.days_dt >= date_sub(f.days_dt, 179), t2.crdt_lim_yx, null)) as crdt_lim_yx_6m,
           avg(t2.pril_bal) as pril_bal_1y, avg(t2.crdt_lim_yx) as crdt_lim_yx_1y
    from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 f
    left join (
        select uuid, user_id, dt,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
               sum(pril_bal) as pril_bal, max(crdt_lim_yx) as crdt_lim_yx
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20240801' and dt <= '20251031' and sx_rowid = 1 and crdt_lim_yx > 0
        group by uuid, user_id, dt
    ) t2 on f.uuid = t2.uuid and f.user_id = t2.user_id
        and t2.days_dt between date_sub(f.days_dt, 359) and f.days_dt
    group by f.uuid, f.user_id, f.dt, f.days_dt
) agg
;

insert overwrite table lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715
select
    uuid, user_id, dt, days_dt,
    fq_cnt_1w, suc_cnt_1w, if(suc_cnt_1w > 0, fq_cnt_1w / suc_cnt_1w, null) as pass_rate_1w,
    fq_cnt_1m, suc_cnt_1m, if(suc_cnt_1m > 0, fq_cnt_1m / suc_cnt_1m, null) as pass_rate_1m,
    fq_cnt_3m, suc_cnt_3m, if(suc_cnt_3m > 0, fq_cnt_3m / suc_cnt_3m, null) as pass_rate_3m,
    fq_cnt_6m, suc_cnt_6m, if(suc_cnt_6m > 0, fq_cnt_6m / suc_cnt_6m, null) as pass_rate_6m,
    fq_cnt_1y, suc_cnt_1y, if(suc_cnt_1y > 0, fq_cnt_1y / suc_cnt_1y, null) as pass_rate_1y
from (
    select c.uuid, c.user_id, c.dt, c.days_dt,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 6), 1, 0)) as fq_cnt_1w,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 6) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1w,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 29), 1, 0)) as fq_cnt_1m,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 29) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1m,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 89), 1, 0)) as fq_cnt_3m,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 89) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_3m,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 179), 1, 0)) as fq_cnt_6m,
           sum(if(t2.draw_apply_date >= date_sub(c.days_dt, 179) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_6m,
           count(t2.draw_apply_date) as fq_cnt_1y,
           sum(if(t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1y
    from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
    left join (
        select unique_id, user_id, wdraw_apply_no, draw_apply_date, final_loan_amt
        from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
        where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
          and day_time >= '20240801' and day_time <= '20251031' and unique_id is not null
        group by unique_id, user_id, wdraw_apply_no, draw_apply_date, final_loan_amt
    ) t2 on c.uuid = t2.unique_id and c.user_id = t2.user_id
        and t2.draw_apply_date between date_sub(c.days_dt, 359) and c.days_dt
    group by c.uuid, c.user_id, c.dt, c.days_dt
) w
;

-- ########## Part 8：终表 ##########
insert overwrite table lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
select
    l.*,
    mx.pril_bal_1w, mx.crdt_lim_yx_1w, mx.pril_bal_rate_1w,
    mx.pril_bal_1m, mx.crdt_lim_yx_1m, mx.pril_bal_rate_1m,
    mx.pril_bal_3m, mx.crdt_lim_yx_3m, mx.pril_bal_rate_3m,
    mx.pril_bal_6m, mx.crdt_lim_yx_6m, mx.pril_bal_rate_6m,
    mx.pril_bal_1y, mx.crdt_lim_yx_1y, mx.pril_bal_rate_1y,
    wd.fq_cnt_1w, wd.suc_cnt_1w, wd.pass_rate_1w,
    wd.fq_cnt_1m, wd.suc_cnt_1m, wd.pass_rate_1m,
    wd.fq_cnt_3m, wd.suc_cnt_3m, wd.pass_rate_3m,
    wd.fq_cnt_6m, wd.suc_cnt_6m, wd.pass_rate_6m,
    wd.fq_cnt_1y, wd.suc_cnt_1y, wd.pass_rate_1y
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 l
left join lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715 mx
  on l.uuid = mx.uuid and l.dt = mx.dt
left join lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715 wd
  on l.uuid = wd.uuid and l.dt = wd.dt
;

-- ########## Part 9：核验 ##########
select m, count(1) as cohort_cnt, count(distinct uuid) as cohort_uuid
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m in ('202508', '202509', '202510')
group by m order by m;

-- 应为 0：11 月不应进入 cohort
select m, count(1) as should_be_zero
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
where m not in ('202508', '202509', '202510')
group by m order by m;

select
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715) as cohort_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715) as feature_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715) as full_cnt;

select zx_balance_label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where label_eligible = 1
group by zx_balance_label order by zx_balance_label;

select m, dataset_split, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where m in ('202508', '202509', '202510')
group by m, dataset_split order by m, dataset_split;
