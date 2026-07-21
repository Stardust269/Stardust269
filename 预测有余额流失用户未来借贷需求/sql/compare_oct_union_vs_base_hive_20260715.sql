-- =============================================================================
-- 10 月 cohort 对比：union_df（0623 底池）vs base_df（0715 底池）— Hive 版
-- =============================================================================
-- 引擎：Hive / Spark SQL（date_add(days_dt, 30)、date_sub(days_dt, 1)）
-- 【Kyuubi/Trino 查询请用】compare_oct_union_vs_base_trino_20260715.sql
-- 用法：先只提交「Part 1 汇总」；通过后再跑 Part 2 / Part 3
--
-- 五条件（0623 征信 cohort）：
--   crdt>=2w + had_0_30 + had_31_60 + no_balance_60 + with_0_30+with_31_60=0
-- had/with 锚点：days_dt_1 = date_sub(days_dt, 1)
--
-- 路径说明：
--   A  union_df + 0623 rk + 0623 后续窗（zx/提现从 20251001）
--   B  base_df  + 0715 rk（三月 raw，取 m=202510）+ 0715 后续窗 — 对齐 run_all
--   C  base_df  + 0623 rk（仅隔离「表」差异）
--   D  已建表 jcr_cohort_20260715（十月真值）
--   E  权威 jcr_cohort_5401_20260623
--   F  已建表 jcr_pril_bal_info_20260715 五条件（不重建，核验 7220）
--   G  已移至 compare_oct_union_vs_base_hive_optional_20260715.sql（需 jcr_pril_bal_info_20260623）
-- =============================================================================

-- ##############################################################################
-- Part 1：汇总（先跑这一段）
-- ##############################################################################
with
wdraw_dedup as (
    select unique_id, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
wdraw_dedup_oct as (
    select unique_id, prod_cd,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20251001' and day_time < '20260310'
      and unique_id is not null
    group by unique_id, prod_cd,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
zx_dedup_all as (
    select id_unqp,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
),
zx_dedup_oct as (
    select id_unqp,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20251001' and dt < '20260310'
    group by id_unqp, dt
),

-- ===================== Path A：union_df（0623 十月底池）=====================
a_raw as (
    select
        uuid, user_id, pril_bal, crdt_lim_yx,
        pril_bal / crdt_lim_yx as pril_bal_rate,
        dt,
        concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
        row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt >= '20251002' and dt <= '20251101'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
a_nb as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt,
        date_sub(t1.days_dt, 1) as days_dt_1,
        t1.crdt_lim_yx,
        max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
    from (
        select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt
        from a_raw where rk = 1
    ) t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
        where dt >= '20251101' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.crdt_lim_yx
),
a_pf as (
    select * from a_nb
    where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
a_had as (
    select
        t1.uuid, t1.dt,
        max(case when t2.days_dt_zx between t1.days_dt_1 and date_add(t1.days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
        max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) then 1 else 0 end) as had_31_60_zx
    from a_pf t1
    left join zx_dedup_oct t2 on t1.uuid = t2.id_unqp
    group by t1.uuid, t1.dt
),
a_with as (
    select
        t1.uuid, t1.dt,
        max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30), 1, 0)) as with_0_30,
        max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60), 1, 0)) as with_31_60
    from a_pf t1
    left join wdraw_dedup_oct t3 on t1.uuid = t3.unique_id
    group by t1.uuid, t1.dt
),
a_cohort as (
    select pf.uuid, pf.dt, pf.days_dt
    from a_pf pf
    inner join a_had h on pf.uuid = h.uuid and pf.dt = h.dt
    inner join a_with w on pf.uuid = w.uuid and pf.dt = w.dt
    where h.had_0_30_zx = 1 and h.had_31_60_zx = 1
      and w.with_0_30 + w.with_31_60 = 0
),

-- ===================== Path B：base_df（0715，对齐 run_all，取十月）=====================
b_raw as (
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
),
b_nb as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m,
        date_sub(t1.days_dt, 1) as days_dt_1,
        t1.crdt_lim_yx,
        max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
    from (
        select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m
        from b_raw where rk = 1 and m = '202510'
    ) t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20250831' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.m, t1.crdt_lim_yx
),
b_pf as (
    select * from b_nb
    where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
b_had as (
    select
        t1.uuid, t1.dt,
        max(case when t2.days_dt_zx between t1.days_dt_1 and date_add(t1.days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
        max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) then 1 else 0 end) as had_31_60_zx
    from b_pf t1
    left join zx_dedup_all t2 on t1.uuid = t2.id_unqp
    group by t1.uuid, t1.dt
),
b_with as (
    select
        t1.uuid, t1.dt,
        max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30), 1, 0)) as with_0_30,
        max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60), 1, 0)) as with_31_60
    from b_pf t1
    left join wdraw_dedup t3 on t1.uuid = t3.unique_id
    group by t1.uuid, t1.dt
),
b_cohort as (
    select pf.uuid, pf.dt, pf.days_dt
    from b_pf pf
    inner join b_had h on pf.uuid = h.uuid and pf.dt = h.dt
    inner join b_with w on pf.uuid = w.uuid and pf.dt = w.dt
    where h.had_0_30_zx = 1 and h.had_31_60_zx = 1
      and w.with_0_30 + w.with_31_60 = 0
),

-- ===================== Path C：base_df + 0623 rk（十月窗）=====================
c_raw as (
    select
        uuid, user_id, pril_bal, crdt_lim_yx,
        pril_bal / crdt_lim_yx as pril_bal_rate,
        dt,
        concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
        row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20251001' and dt <= '20251031'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
c_nb as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt,
        date_sub(t1.days_dt, 1) as days_dt_1,
        t1.crdt_lim_yx,
        max(if(t2.days_dt between t1.days_dt and date_add(t1.days_dt, 60), t2.no_balance_flg, 0)) as no_balance_flg_60
    from (select uuid, user_id, dt, days_dt, crdt_lim_yx from c_raw where rk = 1) t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20250831' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where t2.days_dt between t1.days_dt and date_add(t1.days_dt, 90)
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.crdt_lim_yx
),
c_pf as (
    select * from c_nb where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
c_had as (
    select t1.uuid, t1.dt,
        max(case when t2.days_dt_zx between t1.days_dt_1 and date_add(t1.days_dt_1, 30) then 1 else 0 end) as had_0_30_zx,
        max(case when t2.days_dt_zx between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60) then 1 else 0 end) as had_31_60_zx
    from c_pf t1
    left join zx_dedup_oct t2 on t1.uuid = t2.id_unqp
    group by t1.uuid, t1.dt
),
c_with as (
    select t1.uuid, t1.dt,
        max(if(t3.wday between t1.days_dt_1 and date_add(t1.days_dt_1, 30), 1, 0)) as with_0_30,
        max(if(t3.wday between date_add(t1.days_dt_1, 31) and date_add(t1.days_dt_1, 60), 1, 0)) as with_31_60
    from c_pf t1
    left join wdraw_dedup_oct t3 on t1.uuid = t3.unique_id
    group by t1.uuid, t1.dt
),
c_cohort as (
    select pf.uuid, pf.dt
    from c_pf pf
    inner join c_had h on pf.uuid = h.uuid and pf.dt = h.dt
    inner join c_with w on pf.uuid = w.uuid and pf.dt = w.dt
    where h.had_0_30_zx = 1 and h.had_31_60_zx = 1 and w.with_0_30 + w.with_31_60 = 0
)

select 'A_union_df_0623_rk' as path,
       (select count(1) from a_raw where rk = 1) as anchor_cnt,
       (select count(1) from a_pf) as pf_cnt,
       (select count(1) from a_had where had_0_30_zx = 1 and had_31_60_zx = 1) as pass_had_cnt,
       (select count(1) from a_cohort) as cohort_5cond,
       (select count(distinct uuid) from a_cohort) as cohort_uuid_cnt
union all
select 'B_base_df_0715_rk_runall',
       (select count(1) from b_raw where rk = 1 and m = '202510'),
       (select count(1) from b_pf),
       (select count(1) from b_had where had_0_30_zx = 1 and had_31_60_zx = 1),
       (select count(1) from b_cohort),
       (select count(distinct uuid) from b_cohort)
union all
select 'C_base_df_0623_rk',
       (select count(1) from c_raw where rk = 1),
       (select count(1) from c_pf),
       (select count(1) from c_had where had_0_30_zx = 1 and had_31_60_zx = 1),
       (select count(1) from c_cohort),
       (select count(distinct uuid) from c_cohort)
union all
select 'D_jcr_cohort_20260715_oct',
       null, null, null,
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 where m = '202510'),
       (select count(distinct uuid) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 where m = '202510')
union all
select 'E_auth_5401',
       null, null, null,
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623),
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623)
union all
select 'F_jcr_pril_bal_info_oct_no_rebuild',
       null, null,
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
        where m = '202510' and had_0_30_zx = 1 and had_31_60_zx = 1),
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
        where m = '202510' and had_0_30_zx = 1 and had_31_60_zx = 1
          and with_0_30 + with_31_60 = 0),
       (select count(distinct uuid) from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260715
        where m = '202510' and had_0_30_zx = 1 and had_31_60_zx = 1
          and with_0_30 + with_31_60 = 0)
;


-- G 行（需 jcr_pril_bal_info_20260623）见：compare_oct_union_vs_base_hive_optional_20260715.sql

-- ##############################################################################
-- Part 2：逐步漏斗（十月，A vs B）
-- ##############################################################################
with
a_raw as (
    select uuid, user_id, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
           crdt_lim_yx,
           row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt >= '20251002' and dt <= '20251101'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
b_raw as (
    select uuid, user_id, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
           substr(dt, 1, 6) as m, crdt_lim_yx,
           row_number() over (partition by uuid, user_id, substr(dt, 1, 6) order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20250801' and dt <= '20251031'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
)
select 'anchor_rk1_oct' as step,
       (select count(1) from a_raw where rk = 1) as union_df_cnt,
       (select count(1) from b_raw where rk = 1 and m = '202510') as base_df_cnt
;


-- ##############################################################################
-- Part 3：uuid 交集（单独提交；若 Part1 已通过，用下面简化版）
-- ##############################################################################
select
    count(1) as jcr_oct_cnt,
    sum(if(e.uuid is not null, 1, 0)) as overlap_5401,
    sum(if(e.uuid is null, 1, 0)) as jcr_only,
    (select count(1)
     from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 e2
     left join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j2
       on e2.uuid = j2.uuid and j2.m = '202510'
     where j2.uuid is null) as auth_only_not_in_jcr
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
left join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 e on j.uuid = e.uuid
where j.m = '202510'
;
