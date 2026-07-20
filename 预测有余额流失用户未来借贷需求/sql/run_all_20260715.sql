-- =============================================================================
-- 一键全量 v20260715：三月样本 + 征信特征 + 征信余额标签 + 马消特征关联
-- =============================================================================
-- 【与 20260623 版区别】
--   样本：202508~202510 三月，月内 rk=1，源表 ayh_mkt_yx_cust_type_base_df（T-1）
--   cohort：与 0623 完全同口径 5 条件（含 had_0_30_zx & had_31_60_zx），三月约 5401×3≈1.6w
--   had/with 锚点：days_dt_1（与 0623 一致）；no_balance 锚点：days_dt
--   性能：先 crdt+no_balance 预筛 → 分别算 had/with（避免笛卡尔积）→ cohort ~1.6w → 再 join 征信
--   马消特征：left join 同事 ayh_feature_*（只读，由同事加工）
--
-- 【前置只读】
--   lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
--   dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
--   lj_iceberg.pboccr2d.*（9张征信表）
--   lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx（同事马消，跑本脚本前需已产出）
--   lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc（同事马消，跑本脚本前需已产出）
--
-- 【产出】jcr_credit_feature_label_full_20260715（征信+马消+双标签）
-- 十月单 cohort 5401 版见：run_all_20260623.sql（勿混用）
-- =============================================================================

-- ########## Part 0：删除旧表（20260715）##########
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715;

-- ########## Part 1：样本三步（同事 20260715，八月~十月）##########
-- Step 0a：月内最低额度利用率日 rk（按月 partition）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 as
select
    uuid, user_id, pril_bal, crdt_lim_yx,
    pril_bal / crdt_lim_yx as pril_bal_rate,
    dt,
    concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
    substr(dt, 1, 6) as m,
    row_number() over (
        partition by uuid, user_id, substr(dt, 1, 6)
        order by pril_bal / crdt_lim_yx
    ) as rk
from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
where dt >= '20250801' and dt <= '20251031'
  and sx_rowid = 1
  and prod_cd = '5103'
  and if_lend = '复贷'
  and cust_types_01 = '有余额'
  and crdt_lim_yx > 0
;

-- Step 0b：后续是否无余额（锚点 days_dt）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 as
select
    t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m,
    max(t2.no_balance_flg) as no_balance_flg_90,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 30), t2.no_balance_flg, 0)) as no_balance_flg_30,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
from (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
    where rk = 1
) t1
left join (
    select uuid, user_id,
           if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20250831' and dt <= '20260201'
      and sx_rowid = 1
      and prod_cd = '5103'
) t2
  on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
group by t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m
;

-- Step 0pf：廉价条件先筛（crdt>=2w & no_balance_60），再做大表 join，避免全量笛卡尔积
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 as
select
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90,
    date_sub(days_dt, 1) as days_dt_1
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where crdt_lim_yx >= 20000
  and no_balance_flg_60 = 1
;

-- Step 0c-had：仅预筛样本 × 征信报告（单独聚合，不与提现 join）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 as
select
    t1.uuid, t1.dt,
    max(case when t2.days_dt_zx between t1.days_dt_1 and date_add(t1.days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) then 1 else 0 end) as had_31_60_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 61) and date_add(t1.days_dt_1, 90) then 1 else 0 end) as had_61_90_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 91) and date_add(t1.days_dt_1, 120) then 1 else 0 end) as had_91_120_zx
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 t1
left join (
    select id_unqp,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
) t2
  on t1.uuid = t2.id_unqp
group by t1.uuid, t1.dt
;

-- Step 0c-with：仅预筛样本 × 提现（单独聚合）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 as
select
    t1.uuid, t1.dt,
    max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30), 1, 0)) as with_0_30,
    max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60), 1, 0)) as with_31_60,
    max(if(t3.wday between date_add(t1.days_dt_1, 61) and date_add(t1.days_dt_1, 90), 1, 0)) as with_61_90,
    max(if(t3.wday between date_add(t1.days_dt_1, 91) and date_add(t1.days_dt_1, 120), 1, 0)) as with_91_120,
    max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30) and t3.prod_cd = '5103', 1, 0)) as with_0_30_5103,
    max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) and t3.prod_cd = '5103', 1, 0)) as with_31_60_5103,
    max(if(t3.wday between date_add(t1.days_dt_1, 61) and date_add(t1.days_dt_1, 90) and t3.prod_cd = '5103', 1, 0)) as with_61_90_5103,
    max(if(t3.wday between date_add(t1.days_dt_1, 91) and date_add(t1.days_dt_1, 120) and t3.prod_cd = '5103', 1, 0)) as with_91_120_5103
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 t1
left join (
    select unique_id, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
) t3
  on t1.uuid = t3.unique_id
group by t1.uuid, t1.dt
;

-- Step 0c：合并 had + with（预筛样本量级，非全量）
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 as
select
    pf.uuid, pf.user_id, pf.pril_bal, pf.crdt_lim_yx, pf.pril_bal_rate, pf.dt, pf.days_dt, pf.m,
    pf.no_balance_flg_30, pf.no_balance_flg_60, pf.no_balance_flg_90, pf.days_dt_1,
    h.had_0_30_zx, h.had_31_60_zx, h.had_61_90_zx, h.had_91_120_zx,
    w.with_0_30, w.with_31_60, w.with_61_90, w.with_91_120,
    w.with_0_30_5103, w.with_31_60_5103, w.with_61_90_5103, w.with_91_120_5103
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 h
  on pf.uuid = h.uuid and pf.dt = h.dt
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w
  on pf.uuid = w.uuid and pf.dt = w.dt
;

-- ########## Part 2：cohort（0623 同口径 5 条件，约 1.6w，uuid+dt）##########
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715;
create table lj_iceberg.ai_decision_dev.jcr_cohort_20260715 as
select uuid, user_id, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where had_0_30_zx = 1
  and had_31_60_zx = 1
  and with_0_30 + with_31_60 = 0;

-- ########## Part 3~7：征信特征（仅 cohort ~1.6w 用户）##########
-- Step 1: 循环贷账户级明细（仅 cohort uuid，大幅减量）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 as
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
    where dt >= '20240801' and dt < '20260301'
      and (close_date is null or cast(close_date as string) = '')
) t1
inner join (
    select distinct uuid from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
) co
  on t1.id_unqp = co.uuid
inner join (
    select id_unqf, id_unqp, account_no, account_id, account_type,
           org_manage_type, org_manage_code, credit_grant_amount, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260301'
      and account_type in ('R1', 'R2', 'R3')
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
    where dt >= '20240801' and dt < '20260301'
) t3
  on t1.id_unqf = t3.id_unqf and t1.id_unqp = t3.id_unqp
 and t1.account_no = t3.account_no and t1.dt = t3.dt and t3.rn = 1
;

-- Step 2: 循环贷报告级聚合（剔马消：与同事 balance 汇总口径一致）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 as
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

-- Step 3: 账单日压力（剔马消有余额账户）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 as
select id_unqp, id_unqf, dt, days_dt_zx,
       max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
       max(bal_sum_same_billday) as same_billday_bal_sum_max
from (
    select id_unqp, id_unqf, dt, days_dt_zx, bill_day,
           sum(if(org_manage_code <> 'T10156530H0001', is_pos_bal_acct, 0)) as acct_cnt_same_billday,
           sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715
    where is_pos_bal_acct = 1 and bill_day is not null
      and org_manage_code <> 'T10156530H0001'
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 4: 报告级扩展特征（查询/逾期/信用卡/资质/职业）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 as
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
    where dt >= '20240801' and dt < '20260301'
      and id_unqp in (select distinct uuid from lj_iceberg.ai_decision_dev.jcr_cohort_20260715)
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
) pd
  on spine.id_unqf = pd.id_unqf and spine.id_unqp = pd.id_unqp and spine.dt = pd.dt
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary cls
  on spine.id_unqf = cls.id_unqf and spine.id_unqp = cls.id_unqp and spine.dt = cls.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when cre_tran_pro_type in ('11', '12') then 1 else 0 end) as has_house_loan_flg,
           max(case when cre_tran_pro_type = '13' then 1 else 0 end) as has_gjj_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) tip
  on spine.id_unqf = tip.id_unqf and spine.id_unqp = tip.id_unqp and spine.dt = tip.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when busi_type = '13' or busi_type like '%公积金%' then 1 else 0 end) as has_gjj_loan_flg,
           max(case when busi_type in ('11', '12') or busi_type like '%住房%' then 1 else 0 end) as has_house_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) bi
  on spine.id_unqf = bi.id_unqf and spine.id_unqp = bi.id_unqp and spine.dt = bi.dt
left join (
    select id_unqp, id_unqf, dt, 1 as has_gjj_record_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record
    where dt >= '20240801' and dt < '20260301'
    group by id_unqp, id_unqf, dt
) phf
  on spine.id_unqf = phf.id_unqf and spine.id_unqp = phf.id_unqp and spine.dt = phf.dt
left join (
    select id_unqp, id_unqf, dt, org_type
    from (
        select id_unqp, id_unqf, dt, org_type,
               row_number() over (
                   partition by id_unqf, id_unqp, dt
                   order by update_date desc, time_inst desc
               ) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801' and dt < '20260301'
    ) x
    where rn = 1
) job
  on spine.id_unqf = job.id_unqf and spine.id_unqp = job.id_unqp and spine.dt = job.dt
;

-- Step 5: 样本关联（报告主键统一后再挂循环贷/扩展/账单日特征）
-- 分析 cohort：inner join jcr_cohort_20260715（0623 同口径 5 条件，三月约 1.6w，uuid+dt 粒度）
-- 征信关联窗：days_dt 前推365天 ~ 后推60天（标签观察窗）
--
-- 【跑前必查】以下 5 张上游表必须已存在且有数据，否则本步 CREATE 会失败：
--   jcr_cohort_20260715 / jcr_pril_bal_info_20260715
--   jcr_credit_report_agg_20260715 / jcr_credit_report_ext_20260715 / jcr_credit_billday_agg_20260715
-- 【执行方式】请单独提交本段（不要与 drop/select 混在一个失败即停的任务里）
-- 使用 drop + create（平台不支持 create or replace）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715 as
select
    s.uuid, s.user_id, s.pril_bal, s.crdt_lim_yx, s.pril_bal_rate,
    s.dt, s.days_dt, s.m, s.no_balance_flg_30, s.no_balance_flg_60, s.no_balance_flg_90,
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

    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 30)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_1m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 180)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_6m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt as date), 365)
          and rep.days_dt_zx <= cast(s.days_dt as date) then 1 else 0 end as flg_win_1y,
    case when cast(rep.days_dt_zx as date) between cast(s.days_dt as date)
                                              and date_add(cast(s.days_dt as date), 60)
         then 1 else 0 end as flg_fwd_60d,

    row_number() over (
        partition by s.uuid, s.dt
        order by case when rep.days_dt_zx <= s.days_dt then 0 else 1 end,
                 rep.days_dt_zx desc
    ) as latest_report_rn
from (
    select s.uuid, s.user_id, s.pril_bal, s.crdt_lim_yx, s.pril_bal_rate, s.dt, s.days_dt, s.m,
           s.no_balance_flg_30, s.no_balance_flg_60, s.no_balance_flg_90, s.days_dt_1,
           s.had_0_30_zx, s.had_31_60_zx, s.had_61_90_zx, s.had_91_120_zx,
           s.with_0_30, s.with_31_60, s.with_61_90, s.with_91_120,
           s.with_0_30_5103, s.with_31_60_5103, s.with_61_90_5103, s.with_91_120_5103
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 s
    inner join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
      on s.uuid = c.uuid and s.dt = c.dt
) s
left join (
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715
    union
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715
) rep
  on s.uuid = rep.id_unqp
 and s.days_dt is not null
 and cast(rep.days_dt_zx as date) > date_sub(cast(s.days_dt as date), 365)
 and cast(rep.days_dt_zx as date) <= date_add(cast(s.days_dt as date), 60)
left join lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 r
  on rep.id_unqp = r.id_unqp and rep.id_unqf = r.id_unqf and rep.dt = r.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260715 e
  on rep.id_unqp = e.id_unqp and rep.id_unqf = e.id_unqf and rep.dt = e.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260715 b
  on rep.id_unqp = b.id_unqp and rep.id_unqf = b.id_unqf and rep.dt = b.dt
;

-- Step 6: 最终特征宽表（单独提交）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 as
select
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
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
from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260715
group by
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1,
    had_0_30_zx, had_31_60_zx, had_61_90_zx, had_91_120_zx,
    with_0_30, with_31_60, with_61_90, with_91_120,
    with_0_30_5103, with_31_60_5103, with_61_90_5103, with_91_120_5103
;

-- Step 7: 标签 + 数据集划分
-- zx_balance_label：days_dt_1~+60 账户级余额（剔马消）最早 vs 最大（与 0623 一致）
-- cohort_eligible：uuid+dt 在 jcr_cohort_20260715（0623 同口径 5 条件）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260715 as
select
    f.*,
        l.fwd_first_balance,
    l.fwd_max_balance,
    case
        when l.fwd_max_balance > l.fwd_first_balance then 1
        when l.fwd_max_balance is not null then 0
        else null
    end as zx_balance_label,
    case when c.uuid is not null then 1 else 0 end as cohort_eligible,
    coalesce(c.m, f.m) as sample_month,
    case
        when c.uuid is not null and l.fwd_max_balance is not null
        then 1 else 0
    end as label_eligible,
    case
        when coalesce(c.m, f.m) = '202510' then 'test'
        when coalesce(c.m, f.m) in ('202508', '202509')
             and abs(hash(concat(f.uuid, f.dt))) % 10 < 8 then 'train'
        when coalesce(c.m, f.m) in ('202508', '202509') then 'val'
        else 'other'
    end as dataset_split,
    if(f.no_balance_flg_60 = 1 and f.with_0_30 + f.with_31_60 = 0, 1, 0) as colleague_mx_label_flg
from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260715 f
left join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
  on f.uuid = c.uuid and f.dt = c.dt
left join (
    select
        uuid,
        dt,
        max(if(zx_rank = 1, balance, null)) as fwd_first_balance,
        max(balance) as fwd_max_balance
    from (
        select
            s.uuid,
            s.dt,
            b.dt as dt_zx,
            b.days_dt_zx,
            sum(if(b.balance > 0 and b.org_manage_code <> 'T10156530H0001', b.balance, 0)) as balance,
            row_number() over (partition by s.uuid, s.dt order by b.days_dt_zx asc) as zx_rank
        from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 s
        inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 p
          on s.uuid = p.uuid and s.dt = p.dt
        left join lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260715 b
          on s.uuid = b.id_unqp
         and cast(b.days_dt_zx as date) between cast(p.days_dt_1 as date)
                                              and date_add(cast(p.days_dt_1 as date), 60)
        group by s.uuid, s.dt, b.dt, b.days_dt_zx
    ) t
    group by uuid, dt
) l
  on f.uuid = l.uuid and f.dt = l.dt
;


-- ########## Part 8：关联同事马消特征（只读）##########
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715;
create table lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715 as
select
    l.*,
    mx.label as mx_cohort_label,
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
left join lj_iceberg.ai_decision_dev.ayh_feature_pril_bal_crdt_lim_yx mx
  on l.uuid = mx.uuid and l.user_id = mx.user_id and l.dt = mx.dt and l.days_dt = mx.days_dt
left join lj_iceberg.ai_decision_dev.ayh_feature_wdraw_fq_suc wd
  on l.uuid = wd.uuid and l.user_id = wd.user_id and l.dt = wd.dt and l.days_dt = wd.days_dt
;


-- ########## Part 9：跑完核验 ##########
select m, count(1) as cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
group by m order by m;

select count(1) as cohort_cnt from lj_iceberg.ai_decision_dev.jcr_cohort_20260715;

select zx_balance_label, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where cohort_eligible = 1 and zx_balance_label is not null
group by zx_balance_label order by zx_balance_label;

select sample_month, dataset_split, count(1) as num
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_full_20260715
where cohort_eligible = 1
group by sample_month, dataset_split order by sample_month, dataset_split;
