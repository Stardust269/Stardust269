-- =============================================================================
-- 仅跑 Part 0~2：三步漏斗样本 + cohort（10 月预期 ~5401）
-- =============================================================================
-- 与 run_all_20260715.sql Part1~2 一致
-- 口径：
--   ① rk=1：月内最低额度利用率日 pril_bal/crdt_lim_yx
--   ② 全渠道 60 天无余额（锚点 days_dt；全渠道无余额即含 5103 无余额）
--      + 60 天内未提现 with_0_30+with_31_60=0（锚点 days_dt_1）
--   ③ cohort：had_0_30 + had_31_60（锚点 days_dt_1）
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.jcr_cohort_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 purge;
drop table if exists lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 purge;

-- Step 0a：漏斗① 5103 有余额且 crdt>=2w → 月内最低额度利用率日 rk
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
  and crdt_lim_yx >= 20000
;

-- Step 0b：全渠道无余额标识（锚点 days_dt；全渠道无余额即含5103无余额）
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
    select
        uuid, user_id,
        concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
        case
            when max(if(if_lend = '复贷' and cust_types_01 = '有余额', 1, 0)) = 0
             and max(if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0)) = 1
            then 1 else 0
        end as no_balance_flg
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20250831' and dt <= '20260201'
      and sx_rowid = 1
    group by uuid, user_id, dt
) t2
  on t1.uuid = t2.uuid and t1.user_id = t2.user_id
where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
group by t1.uuid, t1.user_id, t1.pril_bal, t1.crdt_lim_yx, t1.pril_bal_rate, t1.dt, t1.days_dt, t1.m
;

-- Step 0c-with：提现标识（锚点 days_dt_1；先于 0pf，仅对无余额候选聚合）
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 as
select
    t1.uuid, t1.dt,
    max(if(t3.wday between date_sub(t1.days_dt, 1) and date_add(date_sub(t1.days_dt, 1), 30), 1, 0)) as with_0_30,
    max(if(t3.wday between date_add(date_sub(t1.days_dt, 1), 31) and date_add(date_sub(t1.days_dt, 1), 60), 1, 0)) as with_31_60,
    max(if(t3.wday between date_add(date_sub(t1.days_dt, 1), 61) and date_add(date_sub(t1.days_dt, 1), 90), 1, 0)) as with_61_90,
    max(if(t3.wday between date_add(date_sub(t1.days_dt, 1), 91) and date_add(date_sub(t1.days_dt, 1), 120), 1, 0)) as with_91_120
from (
    select uuid, user_id, dt, days_dt
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
    where no_balance_flg_60 = 1
) t1
left join (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
) t3
  on t1.uuid = t3.unique_id
group by t1.uuid, t1.dt
;

-- Step 0pf：漏斗② — 全渠道60天无余额 + 60天内未提现
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 as
select
    nb.uuid, nb.user_id, nb.pril_bal, nb.crdt_lim_yx, nb.pril_bal_rate, nb.dt, nb.days_dt, nb.m,
    nb.no_balance_flg_30, nb.no_balance_flg_60, nb.no_balance_flg_90,
    date_sub(nb.days_dt, 1) as days_dt_1,
    w.with_0_30, w.with_31_60, w.with_61_90, w.with_91_120
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 nb
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_with_20260715 w
  on nb.uuid = w.uuid and nb.dt = w.dt
where nb.no_balance_flg_60 = 1
  and w.with_0_30 + w.with_31_60 = 0
;

-- Step 0c-had：仅预筛样本 × 征信报告
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

-- Step 0c：合并 pf（已含 with）+ had
create table lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 as
select
    pf.uuid, pf.user_id, pf.pril_bal, pf.crdt_lim_yx, pf.pril_bal_rate, pf.dt, pf.days_dt, pf.m,
    pf.no_balance_flg_30, pf.no_balance_flg_60, pf.no_balance_flg_90,
    pf.days_dt_1,
    h.had_0_30_zx, h.had_31_60_zx, h.had_61_90_zx, h.had_91_120_zx,
    pf.with_0_30, pf.with_31_60, pf.with_61_90, pf.with_91_120
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
inner join lj_iceberg.ai_decision_dev.jcr_pril_bal_had_20260715 h
  on pf.uuid = h.uuid and pf.dt = h.dt
;

-- cohort 漏斗③：仅 had（no_balance / 未提现已在 pf 预筛）
create table lj_iceberg.ai_decision_dev.jcr_cohort_20260715 as
select uuid, user_id, dt, days_dt, m
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where had_0_30_zx = 1
  and had_31_60_zx = 1
;

-- 漏斗核验（十月为例，三步人数应对齐 5022793 / 386311 / 5401）
-- 详见 sql/verify_funnel_oct_20260715.sql
select count(1) as step1_oct from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715 where rk = 1 and m = '202510';
select count(1) as step2_oct from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 where m = '202510';
select count(1) as step3_oct from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 where m = '202510';
