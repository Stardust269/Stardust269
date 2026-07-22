-- =============================================================================
-- 马消特征（全渠道口径，仅 cohort 子集）
-- =============================================================================
-- 左表：jcr_cohort_20260715 + jcr_pril_bal_info_20260715
-- 余额历史：base_df 全渠道用户-日聚合，不限 prod_cd
-- 提现：全渠道 dec_intel_eng_user_fact_wdraw_apply_df
-- 前置：run_part01_sample_cohort_20260715.sql 或 run_all Part1~2 已产出 cohort
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715;
create table lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715 as
select
    uuid, user_id, label,
    pril_bal, crdt_lim_yx, pril_bal_rate,
    pril_bal_1w, crdt_lim_yx_1w,
    if(crdt_lim_yx_1w > 0, pril_bal_1w / crdt_lim_yx_1w, null) as pril_bal_rate_1w,
    pril_bal_1m, crdt_lim_yx_1m,
    if(crdt_lim_yx_1m > 0, pril_bal_1m / crdt_lim_yx_1m, null) as pril_bal_rate_1m,
    pril_bal_3m, crdt_lim_yx_3m,
    if(crdt_lim_yx_3m > 0, pril_bal_3m / crdt_lim_yx_3m, null) as pril_bal_rate_3m,
    pril_bal_6m, crdt_lim_yx_6m,
    if(crdt_lim_yx_6m > 0, pril_bal_6m / crdt_lim_yx_6m, null) as pril_bal_rate_6m,
    pril_bal_1y, crdt_lim_yx_1y,
    if(crdt_lim_yx_1y > 0, pril_bal_1y / crdt_lim_yx_1y, null) as pril_bal_rate_1y,
    dt, days_dt
from (
    select
        t1.uuid, t1.user_id, t1.label,
        t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 6), t2.pril_bal, null)) as pril_bal_1w,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 6), t2.crdt_lim_yx, null)) as crdt_lim_yx_1w,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 29), t2.pril_bal, null)) as pril_bal_1m,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 29), t2.crdt_lim_yx, null)) as crdt_lim_yx_1m,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 89), t2.pril_bal, null)) as pril_bal_3m,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 89), t2.crdt_lim_yx, null)) as crdt_lim_yx_3m,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 179), t2.pril_bal, null)) as pril_bal_6m,
        avg(if(t2.days_dt >= date_sub(t1.days_dt, 179), t2.crdt_lim_yx, null)) as crdt_lim_yx_6m,
        avg(t2.pril_bal) as pril_bal_1y,
        avg(t2.crdt_lim_yx) as crdt_lim_yx_1y,
        t1.dt, t1.days_dt
    from (
        select
            p.uuid, p.user_id, p.pril_bal, p.crdt_lim_yx, p.pril_bal_rate, p.dt, p.days_dt,
            if(p.no_balance_flg_60 = 1 and p.no_balance_flg_60_5103 = 1
               and p.with_0_30 + p.with_31_60 = 0, 1, 0) as label
        from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
        inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 p
          on c.uuid = p.uuid and c.dt = p.dt
    ) t1
    left join (
        select
            uuid, user_id,
            concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
            sum(pril_bal) as pril_bal,
            max(crdt_lim_yx) as crdt_lim_yx
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20240801' and dt <= '20251031'
          and sx_rowid = 1 and crdt_lim_yx > 0
        group by uuid, user_id, dt
    ) t2
      on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where t2.days_dt between date_sub(t1.days_dt, 359) and t1.days_dt
    group by t1.uuid, t1.user_id, t1.label,
             t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt
) agg
;

drop table if exists lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715;
create table lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715 as
select
    uuid, user_id, label,
    fq_cnt_1w, suc_cnt_1w, if(suc_cnt_1w > 0, fq_cnt_1w / suc_cnt_1w, null) as pass_rate_1w,
    fq_cnt_1m, suc_cnt_1m, if(suc_cnt_1m > 0, fq_cnt_1m / suc_cnt_1m, null) as pass_rate_1m,
    fq_cnt_3m, suc_cnt_3m, if(suc_cnt_3m > 0, fq_cnt_3m / suc_cnt_3m, null) as pass_rate_3m,
    fq_cnt_6m, suc_cnt_6m, if(suc_cnt_6m > 0, fq_cnt_6m / suc_cnt_6m, null) as pass_rate_6m,
    fq_cnt_1y, suc_cnt_1y, if(suc_cnt_1y > 0, fq_cnt_1y / suc_cnt_1y, null) as pass_rate_1y,
    dt, days_dt
from (
    select
        t1.uuid, t1.user_id, t1.label,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 6), 1, 0)) as fq_cnt_1w,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 6) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1w,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 29), 1, 0)) as fq_cnt_1m,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 29) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1m,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 89), 1, 0)) as fq_cnt_3m,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 89) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_3m,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 179), 1, 0)) as fq_cnt_6m,
        sum(if(t2.draw_apply_date >= date_sub(t1.days_dt, 179) and t2.final_loan_amt > 0, 1, 0)) as suc_cnt_6m,
        count(1) as fq_cnt_1y,
        sum(if(t2.final_loan_amt > 0, 1, 0)) as suc_cnt_1y,
        t1.dt, t1.days_dt
    from (
        select p.uuid, p.user_id, p.dt, p.days_dt,
               if(p.no_balance_flg_60 = 1 and p.no_balance_flg_60_5103 = 1
               and p.with_0_30 + p.with_31_60 = 0, 1, 0) as label
        from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 c
        inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 p
          on c.uuid = p.uuid and c.dt = p.dt
    ) t1
    left join (
        select unique_id, user_id, wdraw_apply_no, draw_apply_date, final_loan_amt
        from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
        where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
          and day_time >= '20240801' and day_time <= '20251031'
          and unique_id is not null
        group by unique_id, user_id, wdraw_apply_no, draw_apply_date, final_loan_amt
    ) t2
      on t1.uuid = t2.unique_id and t1.user_id = t2.user_id
    where t2.draw_apply_date between date_sub(t1.days_dt, 359) and t1.days_dt
    group by t1.uuid, t1.user_id, t1.label, t1.dt, t1.days_dt
) w
;

select count(1) as mx_pril_cnt from lj_iceberg.ai_decision_dev.jcr_mx_feature_pril_bal_20260715;
select count(1) as mx_wdraw_cnt from lj_iceberg.ai_decision_dev.jcr_mx_feature_wdraw_20260715;
