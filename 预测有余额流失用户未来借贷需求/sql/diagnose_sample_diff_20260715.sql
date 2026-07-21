-- =============================================================================
-- 三月样本差异定位（仅 jcr_* 表，不依赖同事 yye_* 表）
-- =============================================================================
-- 用法：Part0~2 跑完后，分段提交（0 → A → B → C → E → F）
-- 引擎：Trino/Kyuubi — date_add('day', N, cast(... as date))
-- 与同事 yye 表对比：见 diagnose_sample_diff_yye_optional_20260715.sql（需先跑同事脚本）
-- =============================================================================

-- ########## Part 0：重复键检查（排除一人多条导致虚高）##########
select 'cohort_dup' as chk, m,
       count(1) as row_cnt,
       count(distinct uuid) as uuid_cnt,
       count(distinct concat(uuid, '|', dt)) as uuid_dt_cnt
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
group by m
order by m
;

-- ########## Part A：逐步漏斗（jcr 表）##########
select 'A1_raw_rk1' as step, m, count(1) as cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_raw_20260715
where rk = 1
group by m
union all
select 'A2_nb_after_0b', m, count(1), count(distinct uuid)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715
group by m
union all
select 'A3_pf_crdt2w_nb60', m, count(1), count(distinct uuid)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715
group by m
union all
select 'A4_jcr_3cond_days_dt1_with', m, count(1), count(distinct uuid)
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
where with_0_30 + with_31_60 = 0
group by m
union all
select 'A5_jcr_5cond_cohort', m, count(1), count(distinct uuid)
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715
group by m
order by step, m
;

-- ########## Part B：同事口径 3 条件 pnum（在 jcr_nb 上按 days_dt 重算 with）##########
with wdraw_dedup as (
    select unique_id, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
nb_with_yye as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m,
        t1.crdt_lim_yx, t1.no_balance_flg_60,
        max(if(cast(t3.wday as date) between cast(t1.days_dt as date)
                and date_add('day', 30, cast(t1.days_dt as date)), 1, 0)) as with_0_30,
        max(if(cast(t3.wday as date) between date_add('day', 31, cast(t1.days_dt as date))
                and date_add('day', 60, cast(t1.days_dt as date)), 1, 0)) as with_31_60
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 t1
    left join wdraw_dedup t3 on t1.uuid = t3.unique_id
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m,
             t1.crdt_lim_yx, t1.no_balance_flg_60
),
nb_with_jcr as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m,
        t1.crdt_lim_yx, t1.no_balance_flg_60,
        max(if(cast(t3.wday as date) between date_add('day', -1, cast(t1.days_dt as date))
                and date_add('day', 29, cast(t1.days_dt as date)), 1, 0)) as with_0_30,
        max(if(cast(t3.wday as date) between date_add('day', 30, cast(t1.days_dt as date))
                and date_add('day', 59, cast(t1.days_dt as date)), 1, 0)) as with_31_60
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_nb_20260715 t1
    left join wdraw_dedup t3 on t1.uuid = t3.unique_id
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m,
             t1.crdt_lim_yx, t1.no_balance_flg_60
)
select
    coalesce(y.m, j.m) as m,
    sum(if(y.crdt_lim_yx >= 20000 and y.no_balance_flg_60 = 1
           and y.with_0_30 + y.with_31_60 = 0, 1, 0)) as pnum_3cond_yye_with_days_dt,
    sum(if(j.crdt_lim_yx >= 20000 and j.no_balance_flg_60 = 1
           and j.with_0_30 + j.with_31_60 = 0, 1, 0)) as pnum_3cond_jcr_with_days_dt1,
    sum(if(y.crdt_lim_yx >= 20000 and y.no_balance_flg_60 = 1
           and y.with_0_30 + y.with_31_60 = 0, 1, 0))
  - sum(if(j.crdt_lim_yx >= 20000 and j.no_balance_flg_60 = 1
           and j.with_0_30 + j.with_31_60 = 0, 1, 0)) as diff_yye_minus_jcr_with_anchor
from nb_with_yye y
full outer join nb_with_jcr j
  on y.uuid = j.uuid and y.dt = j.dt
group by coalesce(y.m, j.m)
order by m
;

-- ########## Part C：5 条件拆解（had 贡献 vs with 锚点贡献）##########
with wdraw_dedup as (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
pf_yye_with as (
    select
        pf.uuid, pf.dt, pf.m,
        max(if(cast(w.wday as date) between cast(pf.days_dt as date)
                and date_add('day', 30, cast(pf.days_dt as date)), 1, 0)) as with_0_30,
        max(if(cast(w.wday as date) between date_add('day', 31, cast(pf.days_dt as date))
                and date_add('day', 60, cast(pf.days_dt as date)), 1, 0)) as with_31_60
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
    left join wdraw_dedup w on pf.uuid = w.unique_id
    group by pf.uuid, pf.dt, pf.m
)
select
    pf.m,
    count(1) as pf_cnt,
    sum(if(info.had_0_30_zx = 1 and info.had_31_60_zx = 1, 1, 0)) as pass_had_only,
    sum(if(info.with_0_30 + info.with_31_60 = 0, 1, 0)) as pass_jcr_with_days_dt1,
    sum(if(yw.with_0_30 + yw.with_31_60 = 0, 1, 0)) as pass_yye_with_days_dt,
    sum(if(info.had_0_30_zx = 1 and info.had_31_60_zx = 1
           and info.with_0_30 + info.with_31_60 = 0, 1, 0)) as cohort_5cond_jcr,
    sum(if(info.had_0_30_zx = 1 and info.had_31_60_zx = 1
           and yw.with_0_30 + yw.with_31_60 = 0, 1, 0)) as cohort_5cond_if_yye_with,
    sum(if(yw.with_0_30 + yw.with_31_60 = 0, 1, 0)) as pnum_3cond_on_pf_yye_with
from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
left join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 info
  on pf.uuid = info.uuid and pf.dt = info.dt
left join pf_yye_with yw
  on pf.uuid = yw.uuid and pf.dt = yw.dt
group by pf.m
order by pf.m
;

-- Part D（需同事 yye_* 表）已移至：
--   sql/diagnose_sample_diff_yye_optional_20260715.sql

-- ########## Part E：与 10 月 5401 对照（旧口径）##########
select
    count(1) as oct_cohort_jcr_5cond,
    sum(if(c.uuid is not null, 1, 0)) as oct_in_5401_auth,
    sum(if(c.uuid is null, 1, 0)) as oct_extra_vs_5401
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
left join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 c on j.uuid = c.uuid
where j.m = '202510'
;

-- ########## Part F：with 锚点翻转样本（10 月，看 D2 影响量级）##########
with wdraw_dedup as (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
flip as (
    select
        pf.uuid, pf.dt, pf.days_dt,
        max(if(cast(w.wday as date) between cast(pf.days_dt as date)
                and date_add('day', 30, cast(pf.days_dt as date)), 1, 0)) as with_yye,
        max(if(cast(w.wday as date) between date_add('day', -1, cast(pf.days_dt as date))
                and date_add('day', 29, cast(pf.days_dt as date)), 1, 0)) as with_jcr,
        info.with_0_30 as stored_with_0_30,
        info.with_31_60 as stored_with_31_60
    from lj_iceberg.ai_decision_dev.jcr_pril_bal_pf_20260715 pf
    left join wdraw_dedup w on pf.uuid = w.unique_id
    left join lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715 info
      on pf.uuid = info.uuid and pf.dt = info.dt
    where pf.m = '202510'
    group by pf.uuid, pf.dt, pf.days_dt, info.with_0_30, info.with_31_60
)
select
    sum(if(with_yye = 1 and with_jcr = 0, 1, 0)) as only_yye_sees_with,
    sum(if(with_jcr = 1 and with_yye = 0, 1, 0)) as only_jcr_sees_with,
    sum(if((with_yye + coalesce(stored_with_31_60, 0)) = 0
            and (stored_with_0_30 + stored_with_31_60) > 0, 1, 0)) as pass_jcr_with_but_yye_would_fail_0_30
from flip
;
