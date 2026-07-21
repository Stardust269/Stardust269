-- =============================================================================
-- 仅跑 Part 0~2：三步漏斗样本 + cohort（10 月预期 ~5401）
-- =============================================================================
-- 与 run_all_20260715.sql Part1~2 一致
-- 口径：5103入口 → 全渠道无余额+未提现(with_*) → 征信had（无 *_5103 字段）
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;

-- Step 0a：漏斗① 5103 有余额且 crdt>=2w
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
  and if_lend = '复贷' and cust_types_01 = '有余额'
  and crdt_lim_yx >= 20000
;

-- Step 0b：漏斗② 全渠道无余额
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
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
           case
               when max(if(if_lend = '复贷' and cust_types_01 = '有余额', 1, 0)) = 0
                and max(if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0)) = 1
               then 1 else 0
           end as no_balance_flg
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20250831' and dt <= '20260201' and sx_rowid = 1
    group by uuid, user_id, dt
) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
group by t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m
;

-- Step 0pf
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 as
select
    uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
    no_balance_flg_30, no_balance_flg_60, no_balance_flg_90,
    date_sub(days_dt, 1) as days_dt_1
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
where no_balance_flg_60 = 1
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

-- Step 0c-with（全渠道提现 with_*）
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 as
select t1.uuid, t1.dt,
    max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30), 1, 0)) as with_0_30,
    max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60), 1, 0)) as with_31_60,
    max(if(t3.wday between date_add(t1.days_dt_1, 61) and date_add(t1.days_dt_1, 90), 1, 0)) as with_61_90,
    max(if(t3.wday between date_add(t1.days_dt_1, 91) and date_add(t1.days_dt_1, 120), 1, 0)) as with_91_120
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 t1
left join (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310' and unique_id is not null
    group by unique_id,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
) t3 on t1.uuid = t3.unique_id
group by t1.uuid, t1.dt
;

create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 as
select
    pf.uuid, pf.user_id, pf.pril_bal, pf.crdt_lim_yx, pf.pril_bal_rate, pf.dt, pf.days_dt, pf.m,
    pf.no_balance_flg_30, pf.no_balance_flg_60, pf.no_balance_flg_90, pf.days_dt_1,
    h.had_0_30_zx, h.had_31_60_zx, h.had_61_90_zx, h.had_91_120_zx,
    w.with_0_30, w.with_31_60, w.with_61_90, w.with_91_120
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 h on pf.uuid = h.uuid and pf.dt = h.dt
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w on pf.uuid = w.uuid and pf.dt = w.dt
;

create table lj_iceberg.ai_decision_dev.jcr_cohort_20260715 as
select uuid, user_id, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
;

select count(1) as step1_cnt from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 where rk = 1;
select count(1) as step2_cnt from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715;
select m, count(1) as step3_cnt from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 group by m order by m;
