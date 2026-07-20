-- =============================================================================
-- 仅跑 Part 0~2：样本 + cohort（~1.6w）
-- =============================================================================
-- 用法：drop_all_project_tables.sql 清完并核验后，单独提交本文件
-- 不要与 run_all_20260715.sql 整文件混跑（避免重复占空间）
-- 跑完核验：
--   select count(1) from jcr_cohort_20260715;  -- 预期 ~1.6w
-- 核验通过后，可删中间表腾空间，再跑 Part 3~8：
--   drop jcr_pril_bal_info_raw/nb/pf/had/with（保留 cohort + pril_bal_info）
-- =============================================================================

-- Part 0：删本链路表（仅 20260715）
drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;

-- Step 0a
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
  and sx_rowid = 1 and prod_cd = '5103'
  and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
;

-- Step 0b
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 as
select
    t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m,
    max(t2.no_balance_flg) as no_balance_flg_90,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 30), t2.no_balance_flg, 0)) as no_balance_flg_30,
    max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
from (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 where rk = 1
) t1
left join (
    select uuid, user_id,
           if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20250831' and dt <= '20260201' and sx_rowid = 1 and prod_cd = '5103'
) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
group by t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m
;

-- Step 0pf
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 as
select *, date_sub(days_dt, 1) as days_dt_1
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
;

-- Step 0c-had
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 as
select t1.uuid, t1.dt,
    max(case when t2.days_dt_zx between t1.days_dt_1 and date_add(t1.days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) then 1 else 0 end) as had_31_60_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 61) and date_add(t1.days_dt_1, 90) then 1 else 0 end) as had_61_90_zx,
    max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 91) and date_add(t1.days_dt_1, 120) then 1 else 0 end) as had_91_120_zx
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 t1
left join (
    select id_unqp, concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
) t2 on t1.uuid = t2.id_unqp
group by t1.uuid, t1.dt
;

-- Step 0c-with
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 as
select t1.uuid, t1.dt,
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
      and day_time >= '20250801' and day_time < '20260310' and unique_id is not null
    group by unique_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
) t3 on t1.uuid = t3.unique_id
group by t1.uuid, t1.dt
;

-- merge + cohort
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 as
select pf.*, h.had_0_30_zx, h.had_31_60_zx, h.had_61_90_zx, h.had_91_120_zx,
       w.with_0_30, w.with_31_60, w.with_61_90, w.with_91_120,
       w.with_0_30_5103, w.with_31_60_5103, w.with_61_90_5103, w.with_91_120_5103
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 h on pf.uuid = h.uuid and pf.dt = h.dt
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w on pf.uuid = w.uuid and pf.dt = w.dt
;

create table lj_iceberg.ai_decision_dev.jcr_cohort_20260715 as
select uuid, user_id, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where had_0_30_zx = 1 and had_31_60_zx = 1 and with_0_30 + with_31_60 = 0
;

-- 核验
select m, count(1) as cohort_cnt from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 group by m order by m;
select count(1) as total_cohort from lj_iceberg.ai_decision_dev.jcr_cohort_20260715;
