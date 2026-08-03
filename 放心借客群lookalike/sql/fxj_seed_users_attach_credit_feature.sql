-- =============================================================================
-- 放心借 lookalike：样本表挂征信特征（仅最近一次征信报告，不含马消特征）
-- =============================================================================
-- 输入（已有腾讯/百行/朴道等）：
--   lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature
-- 约定：
--   - days_dt_zx、dt_zx 为样本侧已算好的「最近一次征信报告」日期（勿再 row_number 选报告）
--   - 征信特征逻辑对齐 jcr 项目 run_all_20260715 Part 3~4（剔马消机构码 T10156530H0001）
--   - 不挂马消（安逸花）余额/提现等特征
-- 输出：
--   lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
-- =============================================================================

-- ########## 0. 探查（上线前在集群执行）##########
-- desc lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature;
-- select count(1), count(distinct unique_id),
--        sum(if(dt_zx is not null, 1, 0)) as has_dt_zx
-- from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature;

-- ########## 1. 征信报告锚点（样本已定的最近一份）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_zx_spine;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_zx_spine as
select distinct
    unique_id,
    dt_zx,
    days_dt_zx
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature
where dt_zx is not null
  and trim(cast(dt_zx as string)) <> ''
;

-- ########## 2. 循环贷账户明细（仅 spine 上的 uuid + dt_zx）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base as
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
    where dt >= '20240801'
      and dt < '20260701'
      and (close_date is null or cast(close_date as string) = '')
) t1
inner join lj_iceberg.ai_decision_dev.fxj_seed_zx_spine sp
    on t1.id_unqp = sp.unique_id
   and t1.dt = sp.dt_zx
inner join (
    select id_unqf, id_unqp, account_no, account_id, account_type,
           org_manage_type, org_manage_code, credit_grant_amount, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801'
      and dt < '20260701'
      and account_type in ('R1', 'R2', 'R3')
) t2
    on t1.id_unqf = t2.id_unqf
   and t1.id_unqp = t2.id_unqp
   and t1.account_no = t2.account_no
   and t1.dt = t2.dt
left join (
    select id_unqf, id_unqp, account_no, settle_date, info_dt, month, dt,
           row_number() over (
               partition by id_unqf, id_unqp, account_no, dt
               order by coalesce(info_dt, settle_date) desc, month desc
           ) as rn
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform
    where dt >= '20240801'
      and dt < '20260701'
) t3
    on t1.id_unqf = t3.id_unqf
   and t1.id_unqp = t3.id_unqp
   and t1.account_no = t3.account_no
   and t1.dt = t3.dt
   and t3.rn = 1
;

-- ########## 3. 报告级聚合（剔马消）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', 1, 0)) as pos_bal_acct_cnt,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, null)) as bal_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, null)) as bal_min,
    sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0)) as crdt_sum,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, null)) as crdt_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, null)) as crdt_min,
    max(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', util_rate, null)) as util_max,
    min(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', util_rate, null)) as util_min,
    case
        when sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0)) > 0
        then sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0))
             / sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', credit_grant_amount, 0))
        else null
    end as util_sum,
    count(distinct if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001' and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base
group by id_unqp, id_unqf, dt, days_dt_zx
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg as
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
        sum(if(org_manage_code <> 'T10156530H0001', is_pos_bal_acct, 0)) as acct_cnt_same_billday,
        sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base
    where is_pos_bal_acct = 1
      and bill_day is not null
      and org_manage_code <> 'T10156530H0001'
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- ########## 4. 查询 / 逾期 / 信用卡 / 资质（报告扩展，剔马消无关表内逻辑同 jcr）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext as
select
    spine.unique_id as id_unqp,
    spine.id_unqf,
    spine.dt_zx as dt,
    spine.days_dt_zx,
    cast(nullif(q.credit_audit_query_org_num_1m, '') as int) as credit_audit_query_org_num_1m,
    cast(nullif(q.loan_audit_query_num_1m, '') as int) as loan_audit_query_num_1m,
    cast(nullif(q.credit_audit_query_num_1m, '') as int) as credit_audit_query_num_1m,
    cast(nullif(q.person_query_num_1m, '') as int) as person_query_num_1m,
    cast(nullif(q.plm_query_num_2y, '') as int) as plm_query_num_2y,
    cast(nullif(q.assure_query_num_2y, '') as int) as assure_query_num_2y,
    cast(nullif(q.sam_query_num_2y, '') as int) as sam_query_num_2y,
    coalesce(cast(nullif(q.loan_audit_query_num_1m, '') as int), 0)
        + coalesce(cast(nullif(q.credit_audit_query_num_1m, '') as int), 0) as hard_query_num_1m,
    pd.pd_num_month_max,
    pd.pd_num_month_sum,
    pd.pd_max_overdue_months,
    pd.pd_max_overdue_amt,
    cast(nullif(cls.credit_account_num, '') as int) as credit_account_num,
    cast(nullif(cls.credit_amount, '') as decimal(18, 2)) as credit_amount,
    cast(nullif(cls.credit_used_amount, '') as decimal(18, 2)) as credit_used_amount,
    case
        when coalesce(cast(nullif(cls.credit_amount, '') as decimal(18, 2)), 0) > 0
        then cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))
             / cast(nullif(cls.credit_amount, '') as decimal(18, 2))
        else null
    end as credit_util_rate,
    case when coalesce(tip.has_house_loan_flg, 0) > 0 or coalesce(bi.has_house_loan_flg, 0) > 0 then 1 else 0 end as has_house_loan_flg,
    case
        when coalesce(tip.has_gjj_loan_flg, 0) > 0 or coalesce(phf.has_gjj_record_flg, 0) > 0
          or coalesce(bi.has_gjj_loan_flg, 0) > 0
        then 1
        else 0
    end as has_gjj_loan_flg,
    job.org_type
from (
    select sp.unique_id, sp.dt_zx, sp.days_dt_zx, z.id_unqf
    from lj_iceberg.ai_decision_dev.fxj_seed_zx_spine sp
    left join (
        select id_unqp, id_unqf, dt
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
        where dt >= '20240801'
          and dt < '20260701'
        group by id_unqp, id_unqf, dt
    ) z
        on sp.unique_id = z.id_unqp
       and sp.dt_zx = z.dt
) spine
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary q
    on spine.id_unqf = q.id_unqf
   and spine.unique_id = q.id_unqp
   and spine.dt_zx = q.dt
left join (
    select id_unqp, id_unqf, dt,
           max(cast(nullif(num_month, '') as int)) as pd_num_month_max,
           sum(cast(nullif(num_month, '') as int)) as pd_num_month_sum,
           max(cast(nullif(max_amt_pd, '') as int)) as pd_max_overdue_months,
           max(cast(nullif(amt_pdtotal, '') as decimal(18, 2))) as pd_max_overdue_amt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) pd
    on spine.id_unqf = pd.id_unqf
   and spine.unique_id = pd.id_unqp
   and spine.dt_zx = pd.dt
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary cls
    on spine.id_unqf = cls.id_unqf
   and spine.unique_id = cls.id_unqp
   and spine.dt_zx = cls.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when cre_tran_pro_type in ('11', '12') then 1 else 0 end) as has_house_loan_flg,
           max(case when cre_tran_pro_type = '13' then 1 else 0 end) as has_gjj_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) tip
    on spine.id_unqf = tip.id_unqf
   and spine.unique_id = tip.id_unqp
   and spine.dt_zx = tip.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when busi_type = '13' or busi_type like '%公积金%' then 1 else 0 end) as has_gjj_loan_flg,
           max(case when busi_type in ('11', '12') or busi_type like '%住房%' then 1 else 0 end) as has_house_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) bi
    on spine.id_unqf = bi.id_unqf
   and spine.unique_id = bi.id_unqp
   and spine.dt_zx = bi.dt
left join (
    select id_unqp, id_unqf, dt, 1 as has_gjj_record_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) phf
    on spine.id_unqf = phf.id_unqf
   and spine.unique_id = phf.id_unqp
   and spine.dt_zx = phf.dt
left join (
    select id_unqp, id_unqf, dt, org_type
    from (
        select id_unqp, id_unqf, dt, org_type,
               row_number() over (partition by id_unqf, id_unqp, dt order by update_date desc, time_inst desc) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801'
          and dt < '20260701'
    ) x
    where rn = 1
) job
    on spine.id_unqf = job.id_unqf
   and spine.unique_id = job.id_unqp
   and spine.dt_zx = job.dt
;

-- ########## 5. 挂回样本宽表（字段名对齐 jcr_credit_feature 的 latest_* 单报告口径）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit as
select
    s.*,
    r.id_unqf as zx_id_unqf,
    r.pos_bal_acct_cnt as latest_pos_bal_acct_cnt,
    r.bal_sum as latest_bal_sum,
    r.bal_max as latest_bal_max,
    r.bal_min as latest_bal_min,
    r.crdt_sum as latest_crdt_sum,
    r.crdt_max as latest_crdt_max,
    r.crdt_min as latest_crdt_min,
    r.util_sum as latest_util_sum,
    r.util_max as latest_util_max,
    r.util_min as latest_util_min,
    r.bill_day_cnt as latest_bill_day_cnt,
    b.same_billday_acct_cnt_max as latest_same_billday_acct_cnt_max,
    b.same_billday_bal_sum_max as latest_same_billday_bal_sum_max,
    e.credit_audit_query_org_num_1m as latest_credit_audit_query_org_num_1m,
    e.loan_audit_query_num_1m as latest_loan_audit_query_num_1m,
    e.credit_audit_query_num_1m as latest_credit_audit_query_num_1m,
    e.person_query_num_1m as latest_person_query_num_1m,
    e.plm_query_num_2y as latest_plm_query_num_2y,
    e.assure_query_num_2y as latest_assure_query_num_2y,
    e.sam_query_num_2y as latest_sam_query_num_2y,
    e.hard_query_num_1m as latest_hard_query_num_1m,
    e.pd_num_month_max as latest_pd_num_month,
    e.pd_num_month_sum as latest_pd_total_overdue_cnt,
    e.pd_max_overdue_months as latest_pd_max_overdue_months,
    e.pd_max_overdue_amt as latest_pd_max_overdue_amt,
    e.has_house_loan_flg as latest_has_house_loan_flg,
    e.has_gjj_loan_flg as latest_has_gjj_loan_flg,
    e.credit_account_num as latest_credit_account_num,
    e.credit_amount as latest_credit_amount,
    e.credit_used_amount as latest_credit_used_amount,
    e.credit_util_rate as latest_credit_util_rate,
    e.org_type as latest_org_type
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature s
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg r
    on s.unique_id = r.id_unqp
   and s.dt_zx = r.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg b
    on r.id_unqp = b.id_unqp
   and r.id_unqf = b.id_unqf
   and r.dt = b.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext e
    on r.id_unqp = e.id_unqp
   and r.id_unqf = e.id_unqf
   and r.dt = e.dt
;

-- ########## 6. 核验 ##########
select
    count(1) as row_cnt,
    count(distinct unique_id) as usr_cnt,
    sum(if(dt_zx is not null, 1, 0)) as has_dt_zx_cnt,
    sum(if(latest_bal_sum is not null, 1, 0)) as has_zx_feature_cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
;

-- 可选：与 jcr 流水线结果交叉验证（仅重叠 uuid+dt 应一致）
-- select count(1)
-- from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit a
-- inner join lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260715 j
--   on a.unique_id = j.id_unqp and a.dt_zx = j.dt
-- where abs(coalesce(a.latest_bal_sum, 0) - coalesce(j.bal_sum, 0)) > 0.01;
