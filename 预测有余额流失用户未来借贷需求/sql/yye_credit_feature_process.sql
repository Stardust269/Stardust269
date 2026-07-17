-- =============================================================================
-- 【执行说明】平台不支持 create or replace；已改为 drop + create。
-- 请每次只提交一个 Step（从 drop 到分号），不要整文件一次运行。
-- =============================================================================
-- 同事参考：sql/yye_pril_bal_sample_reference.sql
-- 对照说明：notion_schema/项目说明_同事样本SQL对照.md
--
-- 【权限与读写说明】
--   只读 征信：lj_iceberg.pboccr2d.*  共 9 张
--   只读 样本（Step 0 源表）：
--     lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
--     dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
--   只写 个人表：lj_iceberg.ai_decision_dev.jcr_* 
--
-- 样本口径（与同事一致）：
--   prod_cd=5103, 复贷有余额, rk=1 月内最低额度利用率日
--   days_dt_1 = date_sub(days_dt, 1)
--   no_balance 锚点 days_dt；had/with 锚点 days_dt_1
--
-- 建模 cohort（同事最后一查，已确认 5401）：
--   crdt_lim>=20000; had_0_30=1 AND had_31_60=1（仅 2 段，不含 61~90/91~120）
--   no_balance_flg_60=1; with_0_30+with_31_60=0（60 天窗，非 90 天）
-- label：yye _4 表 zx_rank=1 balance vs max(balance)，days_dt_1~+60，剔马消
-- =============================================================================

-- ===================== 日期与标签参数 =====================
-- mkt_dt_start/end     = 20251002 ~ 20251101  （分区延后一天，见同事注释）
-- zx_dt_start/end      = 20251001 ~ 20260310   （同事征信/提现窗）
-- feature_zx_start/end = 20240801 ~ 20260101   （特征回看 1 年）
-- test_predict_date    = 2025-11-01
-- =============================================================================

-- ===================== 个人表名 =====================
-- Step0 中间表：jcr_pril_bal_info_raw_20260623 / jcr_pril_bal_info_nb_20260623
-- 样本终表：    jcr_pril_bal_info_20260623
-- 特征/标签：  jcr_credit_*_20260623

-- =============================================================================
-- Step 0 替代：若自建 0a~0c 后 label cohort 仅 ~488，请改用
--   sql/step0c_copy_from_yye.sql（从同事 yye_pril_bal_info_20260623_2 复制）
-- =============================================================================
-- Step 0a：月内每日快照 + 额度利用率 rk（同事 yye_pril_bal_info_20260623）
-- =============================================================================
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623 as
select
    uuid, user_id, pril_bal, crdt_lim_yx,
    pril_bal / crdt_lim_yx as pril_bal_rate,
    curt_crdt_line_yx,
    pril_bal / curt_crdt_line_yx as pril_bal_rate_1,
    crdt_lim_op,
    pril_bal / crdt_lim_op as pril_bal_rate_2,
    dt,
    row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk,
    row_number() over (partition by uuid, user_id order by pril_bal / curt_crdt_line_yx) as rk_1,
    row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_op) as rk_2
from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
where dt >= '20251002' and dt <= '20251101'
  and sx_rowid = 1
  and prod_cd = '5103'
  and if_lend = '复贷'
  and cust_types_01 = '有余额'
  and crdt_lim_yx > 0
;

-- =============================================================================
-- Step 0b：rk=1 + 后续是否无余额（同事 yye_pril_bal_info_20260623_1）
-- no_balance 锚点：days_dt（最低利用率日），不是 days_dt_1
-- =============================================================================
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623 as
select
    t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt,
    max(t2.no_balance_flg) as no_balance_flg_90,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 30), t2.no_balance_flg, 0)) as no_balance_flg_30,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
from (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260623
    where rk = 1
) t1
left join (
    select uuid, user_id,
           if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
           dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt >= '20251101' and dt <= '20260201'
      and sx_rowid = 1
      and prod_cd = '5103'
) t2
  on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
group by t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt
;

-- =============================================================================
-- Step 0c：had_*_zx / with_* + days_dt_1（同事 yye_pril_bal_info_20260623_2）
-- days_dt_1 = date_sub(days_dt, 1)；had/with 锚点 days_dt_1
-- =============================================================================
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 as
select
    t1.*,
    max(case when days_dt_zx between days_dt_1 and date_add(days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
    max(case when days_dt_zx between date_add(days_dt_1, 31) and date_add(days_dt_1, 60) then 1 else 0 end) as had_31_60_zx,
    max(case when days_dt_zx between date_add(days_dt_1, 61) and date_add(days_dt_1, 90) then 1 else 0 end) as had_61_90_zx,
    max(case when days_dt_zx between date_add(days_dt_1, 91) and date_add(days_dt_1, 120) then 1 else 0 end) as had_91_120_zx,
    max(if(wday between days_dt_1 and date_add(days_dt_1, 30), 1, 0)) as with_0_30,
    max(if(wday between date_add(days_dt_1, 31) and date_add(days_dt_1, 60), 1, 0)) as with_31_60,
    max(if(wday between date_add(days_dt_1, 61) and date_add(days_dt_1, 90), 1, 0)) as with_61_90,
    max(if(wday between date_add(days_dt_1, 91) and date_add(days_dt_1, 120), 1, 0)) as with_91_120,
    max(if(wday between days_dt_1 and date_add(days_dt_1, 30) and prod_cd = '5103', 1, 0)) as with_0_30_5103,
    max(if(wday between date_add(days_dt_1, 31) and date_add(days_dt_1, 60) and prod_cd = '5103', 1, 0)) as with_31_60_5103,
    max(if(wday between date_add(days_dt_1, 61) and date_add(days_dt_1, 90) and prod_cd = '5103', 1, 0)) as with_61_90_5103,
    max(if(wday between date_add(days_dt_1, 91) and date_add(days_dt_1, 120) and prod_cd = '5103', 1, 0)) as with_91_120_5103
from (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
           no_balance_flg_30, no_balance_flg_60, no_balance_flg_90,
           date_sub(days_dt, 1) as days_dt_1
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260623
) t1
left join (
    select id_unqp, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20251001' and dt < '20260310'
    group by id_unqp, dt
) t2
  on t1.uuid = t2.id_unqp
left join (
    select unique_id, user_id, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20251001' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, user_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
) t3
  on t1.uuid = t3.unique_id
group by uuid, t1.user_id, pril_bal, crdt_lim_yx, pril_bal_rate, t1.dt, days_dt,
         no_balance_flg_30, no_balance_flg_60, no_balance_flg_90, days_dt_1
;

-- 核验：应对齐同事最后一查 5401
-- select count(1) as cohort_cnt
-- from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
-- where crdt_lim_yx >= 20000
--   and had_0_30_zx = 1 and had_31_60_zx = 1
--   and no_balance_flg_60 = 1
--   and with_0_30 + with_31_60 = 0;

-- Step 1: 循环贷账户级明细（R1/R2/R3；标签窗用 20251001~20260201 与同事 analyse 表一致）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623 as
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

-- Step 2: 循环贷报告级聚合（剔马消：与同事 balance 汇总口径一致）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623 as
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
from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 3: 账单日压力（剔马消有余额账户）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623 as
select id_unqp, id_unqf, dt, days_dt_zx,
       max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
       max(bal_sum_same_billday) as same_billday_bal_sum_max
from (
    select id_unqp, id_unqf, dt, days_dt_zx, bill_day,
           sum(if(org_manage_code <> 'T10156530H0001', is_pos_bal_acct, 0)) as acct_cnt_same_billday,
           sum(if(is_pos_bal_acct = 1 and org_manage_code <> 'T10156530H0001', balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623
    where is_pos_bal_acct = 1 and bill_day is not null
      and org_manage_code <> 'T10156530H0001'
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- Step 4: 报告级扩展特征（查询/逾期/信用卡/资质/职业）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623 as
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
           max(cast(nullif(max_amt_pd, '') as int)) as pd_max_overdue_months,
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
                   order by update_date desc, time_inst desc
               ) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801' and dt < '20260101'
    ) x
    where rn = 1
) job
  on spine.id_unqf = job.id_unqf and spine.id_unqp = job.id_unqp and spine.dt = job.dt
;

-- Step 5: 样本关联（报告主键统一后再挂循环贷/扩展/账单日特征）
-- 分析 cohort：同事最后一查（5401）
--   had_0_30+had_31_60; no_balance_flg_60; with_0_30+with_31_60=0
-- 征信关联窗：days_dt_1 前推365天 ~ 后推60天（标签观察窗）
--
-- 【跑前必查】以下 4 张上游表必须已存在且有数据，否则本步 CREATE 会失败且表不存在：
--   jcr_pril_bal_info_20260623 / jcr_credit_report_agg_20260623
--   jcr_credit_report_ext_20260623 / jcr_credit_billday_agg_20260623
-- 【执行方式】请单独提交本段（不要与 drop/select 混在一个失败即停的任务里）
-- 使用 drop + create（平台不支持 create or replace）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623 as
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

    case when rep.days_dt_zx > date_sub(cast(s.days_dt_1 as date), 30)
          and rep.days_dt_zx <= cast(s.days_dt_1 as date) then 1 else 0 end as flg_win_1m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt_1 as date), 180)
          and rep.days_dt_zx <= cast(s.days_dt_1 as date) then 1 else 0 end as flg_win_6m,
    case when rep.days_dt_zx > date_sub(cast(s.days_dt_1 as date), 365)
          and rep.days_dt_zx <= cast(s.days_dt_1 as date) then 1 else 0 end as flg_win_1y,
    case when cast(rep.days_dt_zx as date) between cast(s.days_dt_1 as date)
                                              and date_add(cast(s.days_dt_1 as date), 60)
         then 1 else 0 end as flg_fwd_60d,

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
    where crdt_lim_yx >= 20000
      and had_0_30_zx = 1 and had_31_60_zx = 1
      and no_balance_flg_60 = 1
      and with_0_30 + with_31_60 = 0
) s
left join (
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623
    union
    select id_unqp, id_unqf, dt, days_dt_zx
    from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623
) rep
  on s.uuid = rep.id_unqp
 and s.days_dt_1 is not null
 and cast(rep.days_dt_zx as date) > date_sub(cast(s.days_dt_1 as date), 365)
 and cast(rep.days_dt_zx as date) <= date_add(cast(s.days_dt_1 as date), 60)
left join lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623 r
  on rep.id_unqp = r.id_unqp and rep.id_unqf = r.id_unqf and rep.dt = r.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623 e
  on rep.id_unqp = e.id_unqp and rep.id_unqf = e.id_unqf and rep.dt = e.dt
left join lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623 b
  on rep.id_unqp = b.id_unqp and rep.id_unqf = b.id_unqf and rep.dt = b.dt
;

-- Step 6: 最终特征宽表（单独提交）
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623 as
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

-- Step 7: 标签 + 数据集划分（与同事 _3/_4 + 最后一查一致）
-- label：days_dt_1~+60 账户级余额（剔马消）最早 vs 最大
-- cohort_eligible：同事最后一查（5401）
--   had_0_30+had_31_60; no_balance_flg_60; with_0_30+with_31_60=0
drop table if exists lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;
create table lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623 as
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
        when f.crdt_lim_yx >= 20000
         and f.had_0_30_zx = 1
         and f.had_31_60_zx = 1
         and f.no_balance_flg_60 = 1
         and f.with_0_30 + f.with_31_60 = 0
        then 1 else 0
    end as cohort_eligible,
    case
        when f.crdt_lim_yx >= 20000
         and f.had_0_30_zx = 1
         and f.had_31_60_zx = 1
         and f.no_balance_flg_60 = 1
         and f.with_0_30 + f.with_31_60 = 0
         and l.fwd_max_balance is not null
        then 1 else 0
    end as label_eligible,
    case
        when f.days_dt = '2025-11-01' then 'test'
        when substr(f.dt, 1, 6) = '202510'
             and abs(hash(f.uuid)) % 10 < 8 then 'train'
        when substr(f.dt, 1, 6) = '202510' then 'val'
        else 'other'
    end as dataset_split
from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623 f
left join (
    select
        uuid,
        max(if(zx_rank = 1, balance, null)) as fwd_first_balance,
        max(balance) as fwd_max_balance
    from (
        select
            s.uuid,
            b.dt as dt_zx,
            b.days_dt_zx,
            sum(if(b.balance > 0 and b.org_manage_code <> 'T10156530H0001', b.balance, 0)) as balance,
            row_number() over (partition by s.uuid order by b.days_dt_zx asc) as zx_rank
        from (
            select uuid, days_dt_1
            from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
            where crdt_lim_yx >= 20000
              and had_0_30_zx = 1 and had_31_60_zx = 1
              and no_balance_flg_60 = 1
              and with_0_30 + with_31_60 = 0
        ) s
        left join lj_iceberg.ai_decision_dev.jcr_credit_account_base_20260623 b
          on s.uuid = b.id_unqp
         and cast(b.days_dt_zx as date) between cast(s.days_dt_1 as date)
                                              and date_add(cast(s.days_dt_1 as date), 60)
        group by s.uuid, b.dt, b.days_dt_zx
    ) t
    group by uuid
) l
  on f.uuid = l.uuid
;

-- =============================================================================
-- Step 8: 数据量排查（按顺序执行；某张表 not found 说明该 Step 的 CREATE 未成功）
-- =============================================================================
-- ⑧-0 跑 Step5 前：确认 4 张上游表都存在（缺任一都会导致 Step5 建表失败）
-- select 'jcr_pril_bal_info' as tbl, count(1) as cnt from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
-- union all select 'jcr_credit_report_agg', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623
-- union all select 'jcr_credit_report_ext', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623
-- union all select 'jcr_credit_billday_agg', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_billday_agg_20260623;
--
-- ⑧-1 样本表是否有数据
-- select count(1) as sample_cnt,
--        count(distinct uuid) as sample_uuid_cnt,
--        sum(case when days_dt_1 is null then 1 else 0 end) as null_days_dt_1_cnt
-- from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623;
--
-- ⑧-2 uuid 能否关联上征信 id_unqp（匹配率）
-- select count(distinct s.uuid) as sample_uuid_cnt,
--        count(distinct case when r.id_unqp is not null then s.uuid end) as matched_uuid_cnt
-- from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623 s
-- left join (
--     select distinct id_unqp from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623
--     union
--     select distinct id_unqp from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623
-- ) r on s.uuid = r.id_unqp;
--
-- ⑧-3 各 Step 行数（哪一步开始变 0；若 step5 not found 说明 Step5 CREATE 失败）
-- select 'jcr_pril_bal_info' as tbl, count(1) as cnt from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
-- union all select 'jcr_credit_report_agg', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_report_agg_20260623
-- union all select 'jcr_credit_report_ext', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_report_ext_20260623
-- union all select 'jcr_credit_report_with_sample', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623
-- union all select 'jcr_credit_feature', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_20260623
-- union all select 'jcr_credit_feature_label', count(1) from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623;
--
-- ⑧-4 Step5 每个样本是否至少有一行（仅 Step5 建表成功后执行）
-- select count(distinct uuid) as uuid_in_step5 from lj_iceberg.ai_decision_dev.jcr_credit_report_with_sample_20260623;
--
-- ⑧-5 若 step5 not found：看任务日志里 Step5 的报错（常见：缺 Step4 表、样本表为空、日期字段类型错误）
-- 若 ⑧-1=0：检查 Step0 样本表
-- 若 ⑧-0 中 ext 报错：先跑 Step4
-- 若 ⑧-4>0 但 feature=0：重跑 Step6

-- Step 9: 核验（应对齐同事最后一查 5401）
-- select count(1) as cohort_cnt, count(distinct uuid) as uuid_cnt
-- from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where cohort_eligible = 1;
--
-- 标签分布：
-- select label, count(1) as num
-- from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where cohort_eligible = 1 and label is not null
-- group by label order by label;
--
-- 或按 dataset_split：
-- select sample_month, label, dataset_split, count(1) as num
-- from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
-- where cohort_eligible = 1 and label_eligible = 1 and label is not null
-- group by sample_month, label, dataset_split
-- order by label, dataset_split;
