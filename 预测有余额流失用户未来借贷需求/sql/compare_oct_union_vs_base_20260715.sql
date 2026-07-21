-- =============================================================================
-- 10 月 cohort 对比：union_df（0623 底池）vs base_df（0715 底池）
-- =============================================================================
-- 【已迁移 Hive 版】请使用：compare_oct_union_vs_base_hive_20260715.sql
-- 本文件为旧版 Trino 语法，易与 run_all 结果不一致，勿再使用
-- =============================================================================
--
-- 五条件（与 0623 征信 cohort 一致）：
--   crdt_lim_yx >= 20000
--   AND had_0_30_zx = 1 AND had_31_60_zx = 1
--   AND no_balance_flg_60 = 1
--   AND with_0_30 + with_31_60 = 0
-- had/with 锚点：days_dt_1 = date_sub(days_dt, 1)（0623 口径）
-- =============================================================================

-- ##############################################################################
-- 【推荐先跑】汇总：两条链路 10 月五条件 cohort 人数 + 与权威表对照
-- ##############################################################################
with
wdraw_dedup as (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310'
      and unique_id is not null
    group by unique_id,
             concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
zx_dedup as (
    select id_unqp,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
),

-- ---------- Path A：0623 union_df 底池（十月单窗，rk=uuid+user_id）----------
a_raw as (
    select
        uuid, user_id, pril_bal, crdt_lim_yx,
        pril_bal / crdt_lim_yx as pril_bal_rate,
        dt,
        concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
        row_number() over (
            partition by uuid, user_id
            order by pril_bal / crdt_lim_yx
        ) as rk
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt >= '20251002' and dt <= '20251101'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
a_anchor as (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt,
           date_add('day', -1, cast(days_dt as date)) as days_dt_1
    from a_raw where rk = 1
),
a_nb as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.days_dt_1,
        t1.crdt_lim_yx, t1.pril_bal, t1.pril_bal_rate,
        max(if(cast(t2.days_dt as date) between cast(t1.days_dt as date)
                and date_add('day', 60, cast(t1.days_dt as date)), t2.no_balance_flg, 0)) as no_balance_flg_60
    from a_anchor t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
        where dt >= '20251101' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where cast(t2.days_dt as date) between cast(t1.days_dt as date)
                                      and date_add('day', 90, cast(t1.days_dt as date))
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.days_dt_1,
             t1.crdt_lim_yx, t1.pril_bal, t1.pril_bal_rate
),
a_pf as (
    select * from a_nb
    where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
a_feat as (
    select
        pf.uuid, pf.dt,
        max(if(cast(z.days_dt_zx as date) between pf.days_dt_1
                and date_add('day', 30, pf.days_dt_1), 1, 0)) as had_0_30_zx,
        max(if(cast(z.days_dt_zx as date) between date_add('day', 31, pf.days_dt_1)
                and date_add('day', 60, pf.days_dt_1), 1, 0)) as had_31_60_zx,
        max(if(cast(w.wday as date) between pf.days_dt_1
                and date_add('day', 30, pf.days_dt_1), 1, 0)) as with_0_30,
        max(if(cast(w.wday as date) between date_add('day', 31, pf.days_dt_1)
                and date_add('day', 60, pf.days_dt_1), 1, 0)) as with_31_60
    from a_pf pf
    left join zx_dedup z on pf.uuid = z.id_unqp
    left join wdraw_dedup w on pf.uuid = w.unique_id
    group by pf.uuid, pf.dt
),
a_cohort as (
    select pf.uuid, pf.dt, pf.days_dt
    from a_pf pf
    inner join a_feat f on pf.uuid = f.uuid and pf.dt = f.dt
    where f.had_0_30_zx = 1 and f.had_31_60_zx = 1
      and f.with_0_30 + f.with_31_60 = 0
),

-- ---------- Path B：0715 base_df 底池（仅 10 月，rk=uuid+user_id+月）----------
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
    where dt >= '20251001' and dt <= '20251031'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
b_anchor as (
    select uuid, user_id, pril_bal, crdt_lim_yx, pril_bal_rate, dt, days_dt, m,
           date_add('day', -1, cast(days_dt as date)) as days_dt_1
    from b_raw where rk = 1
),
b_nb as (
    select
        t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.days_dt_1, t1.m,
        t1.crdt_lim_yx,
        max(if(cast(t2.days_dt as date) between cast(t1.days_dt as date)
                and date_add('day', 60, cast(t1.days_dt as date)), t2.no_balance_flg, 0)) as no_balance_flg_60
    from b_anchor t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20250831' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where cast(t2.days_dt as date) between cast(t1.days_dt as date)
                                      and date_add('day', 90, cast(t1.days_dt as date))
    group by t1.uuid, t1.user_id, t1.dt, t1.days_dt, t1.days_dt_1, t1.m, t1.crdt_lim_yx
),
b_pf as (
    select * from b_nb
    where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
b_feat as (
    select
        pf.uuid, pf.dt,
        max(if(cast(z.days_dt_zx as date) between pf.days_dt_1
                and date_add('day', 30, pf.days_dt_1), 1, 0)) as had_0_30_zx,
        max(if(cast(z.days_dt_zx as date) between date_add('day', 31, pf.days_dt_1)
                and date_add('day', 60, pf.days_dt_1), 1, 0)) as had_31_60_zx,
        max(if(cast(w.wday as date) between pf.days_dt_1
                and date_add('day', 30, pf.days_dt_1), 1, 0)) as with_0_30,
        max(if(cast(w.wday as date) between date_add('day', 31, pf.days_dt_1)
                and date_add('day', 60, pf.days_dt_1), 1, 0)) as with_31_60
    from b_pf pf
    left join zx_dedup z on pf.uuid = z.id_unqp
    left join wdraw_dedup w on pf.uuid = w.unique_id
    group by pf.uuid, pf.dt
),
b_cohort as (
    select pf.uuid, pf.dt, pf.days_dt
    from b_pf pf
    inner join b_feat f on pf.uuid = f.uuid and pf.dt = f.dt
    where f.had_0_30_zx = 1 and f.had_31_60_zx = 1
      and f.with_0_30 + f.with_31_60 = 0
),

-- ---------- Path C：base_df + 0623 式 rk（仅隔离「表」差异，rk 与 A 相同）----------
c_raw as (
    select
        uuid, user_id, pril_bal, crdt_lim_yx,
        pril_bal / crdt_lim_yx as pril_bal_rate,
        dt,
        concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
        row_number() over (
            partition by uuid, user_id
            order by pril_bal / crdt_lim_yx
        ) as rk
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20251001' and dt <= '20251031'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
c_anchor as (
    select uuid, user_id, dt, days_dt,
           date_add('day', -1, cast(days_dt as date)) as days_dt_1, crdt_lim_yx
    from c_raw where rk = 1
),
c_nb as (
    select
        t1.uuid, t1.dt, t1.days_dt, t1.days_dt_1, t1.crdt_lim_yx,
        max(if(cast(t2.days_dt as date) between cast(t1.days_dt as date)
                and date_add('day', 60, cast(t1.days_dt as date)), t2.no_balance_flg, 0)) as no_balance_flg_60
    from c_anchor t1
    left join (
        select uuid, user_id,
               if(if_lend = '复贷' and cust_types_01 = '无余额', 1, 0) as no_balance_flg,
               concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt
        from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
        where dt >= '20250831' and dt <= '20260201'
          and sx_rowid = 1 and prod_cd = '5103'
    ) t2 on t1.uuid = t2.uuid and t1.user_id = t2.user_id
    where cast(t2.days_dt as date) between cast(t1.days_dt as date)
                                      and date_add('day', 90, cast(t1.days_dt as date))
    group by t1.uuid, t1.dt, t1.days_dt, t1.days_dt_1, t1.crdt_lim_yx
),
c_pf as (
    select * from c_nb where crdt_lim_yx >= 20000 and no_balance_flg_60 = 1
),
c_feat as (
    select pf.uuid, pf.dt,
        max(if(cast(z.days_dt_zx as date) between pf.days_dt_1 and date_add('day', 30, pf.days_dt_1), 1, 0)) as had_0_30_zx,
        max(if(cast(z.days_dt_zx as date) between date_add('day', 31, pf.days_dt_1) and date_add('day', 60, pf.days_dt_1), 1, 0)) as had_31_60_zx,
        max(if(cast(w.wday as date) between pf.days_dt_1 and date_add('day', 30, pf.days_dt_1), 1, 0)) as with_0_30,
        max(if(cast(w.wday as date) between date_add('day', 31, pf.days_dt_1) and date_add('day', 60, pf.days_dt_1), 1, 0)) as with_31_60
    from c_pf pf
    left join zx_dedup z on pf.uuid = z.id_unqp
    left join wdraw_dedup w on pf.uuid = w.unique_id
    group by pf.uuid, pf.dt
),
c_cohort as (
    select pf.uuid, pf.dt
    from c_pf pf
    inner join c_feat f on pf.uuid = f.uuid and pf.dt = f.dt
    where f.had_0_30_zx = 1 and f.had_31_60_zx = 1 and f.with_0_30 + f.with_31_60 = 0
)

select 'A_union_df_0623_rk' as path,
       (select count(1) from a_raw where rk = 1) as anchor_cnt,
       (select count(1) from a_pf) as pf_cnt,
       (select count(1) from a_cohort) as cohort_5cond,
       (select count(distinct uuid) from a_cohort) as cohort_uuid_cnt
union all
select 'B_base_df_0715_rk',
       (select count(1) from b_anchor),
       (select count(1) from b_pf),
       (select count(1) from b_cohort),
       (select count(distinct uuid) from b_cohort)
union all
select 'C_base_df_0623_rk',
       (select count(1) from c_anchor),
       (select count(1) from c_pf),
       (select count(1) from c_cohort),
       (select count(distinct uuid) from c_cohort)
union all
select 'D_jcr_cohort_20260715_oct',
       null,
       null,
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 where m = '202510'),
       (select count(distinct uuid) from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 where m = '202510')
union all
select 'E_auth_5401',
       null,
       null,
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623),
       (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623)
;


-- ##############################################################################
-- 漏斗拆解：A vs B 各步骤人数（定位从哪一步开始岔开）
-- ##############################################################################
-- 若上面汇总已够，可跳过本段
with
wdraw_dedup as (
    select unique_id,
           concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2)) as wday
    from dec_intelligence_eng.dec_intel_eng_user_fact_wdraw_apply_df
    where dt = 'get_max_pt[dec_intelligence_eng@dec_intel_eng_user_fact_wdraw_apply_df]'
      and day_time >= '20250801' and day_time < '20260310' and unique_id is not null
    group by unique_id, concat(substr(day_time, 1, 4), '-', substr(day_time, 5, 2), '-', substr(day_time, 7, 2))
),
zx_dedup as (
    select id_unqp, concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt_zx
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
    where dt >= '20250801' and dt < '20260310'
    group by id_unqp, dt
),
a_raw as (
    select uuid, user_id, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
           pril_bal / crdt_lim_yx as pril_bal_rate, crdt_lim_yx,
           row_number() over (partition by uuid, user_id order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
    where dt >= '20251002' and dt <= '20251101'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
),
b_raw as (
    select uuid, user_id, dt,
           concat(substr(dt, 1, 4), '-', substr(dt, 5, 2), '-', substr(dt, 7, 2)) as days_dt,
           pril_bal / crdt_lim_yx as pril_bal_rate, crdt_lim_yx,
           row_number() over (partition by uuid, user_id, substr(dt, 1, 6) order by pril_bal / crdt_lim_yx) as rk
    from lj_iceberg.ayh_mkt.ayh_mkt_yx_cust_type_base_df
    where dt >= '20251001' and dt <= '20251031'
      and sx_rowid = 1 and prod_cd = '5103'
      and if_lend = '复贷' and cust_types_01 = '有余额' and crdt_lim_yx > 0
)
select 'anchor_rk1' as step,
       (select count(1) from a_raw where rk = 1) as union_df_cnt,
       (select count(1) from b_raw where rk = 1) as base_df_cnt
;


-- ##############################################################################
-- Overlap：A vs B vs 5401 vs jcr 十月（与汇总同一次提交，接在汇总 CTE 后）
-- 把上面「汇总」最后 select ... union all ... 换成下面这段即可
-- ##############################################################################
/*
select
    count(distinct coalesce(a.uuid, b.uuid)) as ab_union_uuid,
    sum(if(a.uuid is not null and b.uuid is not null, 1, 0)) as ab_both,
    sum(if(a.uuid is not null and b.uuid is null, 1, 0)) as only_A_union_df,
    sum(if(a.uuid is null and b.uuid is not null, 1, 0)) as only_B_base_df,
    sum(if(a.uuid is not null and e.uuid is not null, 1, 0)) as A_and_5401,
    sum(if(b.uuid is not null and e.uuid is not null, 1, 0)) as B_and_5401,
    sum(if(b.uuid is not null and j.uuid is not null, 1, 0)) as B_and_jcr_oct_7220,
    sum(if(a.uuid is not null and j.uuid is not null, 1, 0)) as A_and_jcr_oct
from a_cohort a
full outer join b_cohort b on a.uuid = b.uuid
left join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 e on coalesce(a.uuid, b.uuid) = e.uuid
left join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j on coalesce(a.uuid, b.uuid) = j.uuid and j.m = '202510'
;
*/

-- ##############################################################################
-- 简化 overlap（仅依赖已建表，可单独跑）
-- ##############################################################################
select
    count(1) as jcr_oct_cnt,
    sum(if(e.uuid is not null, 1, 0)) as overlap_5401,
    sum(if(e.uuid is null, 1, 0)) as jcr_only,
    (select count(1) from lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 e2
     left join lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j2
       on e2.uuid = j2.uuid and j2.m = '202510'
     where j2.uuid is null) as auth_only_not_in_jcr
from lj_iceberg.ai_decision_dev.jcr_cohort_20260715 j
left join lj_iceberg.ai_decision_dev.jcr_cohort_5401_20260623 e on j.uuid = e.uuid
where j.m = '202510'
;
