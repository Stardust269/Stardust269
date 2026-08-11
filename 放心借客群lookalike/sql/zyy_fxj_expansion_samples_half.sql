-- =============================================================================
-- 同事样本表各随机剔除一半（正样本、负样本均保留 50%）
-- =============================================================================
-- 源表：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
--       （约 正 20 万 + 负 50 万）
-- 产出：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
--       （约 正 10 万 + 负 25 万，体积约减半 ~30G）
--
-- 标签列默认 pu_label（1=正，0=负）。若源表为 label / y 等，全局替换 pu_label。
-- 若 unique_id 非唯一，请把 join 键改为与源表一致的 (unique_id, dt_zx, …)。
-- =============================================================================

-- ########## 0. 探查（可选） ##########
-- select pu_label, count(1) as cnt, count(distinct unique_id) as usr
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
-- group by pu_label
-- order by pu_label
-- ;

-- ########## 1. 各标签随机排序序号 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_rank;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_rank as
select
    s.unique_id,
    coalesce(cast(s.dt_zx as string), '') as dt_zx_key,
    coalesce(cast(s.days_dt_zx as string), '') as days_dt_zx_key,
    s.pu_label,
    row_number() over (
        partition by s.pu_label
        order by hash(concat(s.unique_id, coalesce(cast(s.dt_zx as string), ''), 'zyy_samples_half_v1'))
    ) as rn
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples s
where s.pu_label in (0, 1)
;

-- ########## 2. 各标签一半行数 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt as
select
    pu_label,
    cast(floor(count(1) / 2) as bigint) as half_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
where pu_label in (0, 1)
group by pu_label
;

-- ########## 3. 挂回宽表 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half as
select
    t.*
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples t
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_rank r
    on t.unique_id = r.unique_id
    and coalesce(cast(t.dt_zx as string), '') = r.dt_zx_key
    and coalesce(cast(t.days_dt_zx as string), '') = r.days_dt_zx_key
    and t.pu_label = r.pu_label
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
    on r.pu_label = c.pu_label
    and r.rn <= c.half_cnt
;

-- ########## 4. 核验 ##########
select
    'source' as tbl,
    pu_label,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
where pu_label in (0, 1)
group by pu_label
order by pu_label
;

select
    'half' as tbl,
    pu_label,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
group by pu_label
order by pu_label
;

select
    c.pu_label,
    c.half_cnt as target_half_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half h where h.pu_label = c.pu_label) as actual_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
order by c.pu_label
;
