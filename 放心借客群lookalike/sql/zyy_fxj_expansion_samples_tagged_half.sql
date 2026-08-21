-- =============================================================================
-- 从 tagged（约 70 万行）正/负各随机抽 50%，用于训练（约 35 万行）
-- =============================================================================
-- 前置：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
--       （先跑 zyy_fxj_expansion_samples_tagged.sql）
-- 产出：
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half
--       约 正 10.7 万 + 负 25 万；dataset_split 继承 tagged（仍约 9:1）
-- =============================================================================

-- ########## 1. 随机序号（按 pu_label 分层，各取一半） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_keys;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_keys as
select
    t.unique_id,
    coalesce(cast(t.dt_zx as string), '') as dt_zx_key,
    coalesce(cast(t.days_dt_zx as string), '') as days_dt_zx_key,
    t.pu_label,
    row_number() over (
        partition by t.pu_label
        order by hash(concat(
            t.unique_id,
            coalesce(cast(t.dt_zx as string), ''),
            coalesce(cast(t.days_dt_zx as string), ''),
            'zyy_tagged_half_v1'
        ))
    ) as rn
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged t
where t.pu_label in (0, 1)
;

-- ########## 2. 各标签目标行数（floor(count/2)） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_cnt;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_cnt as
select
    pu_label,
    cast(floor(count(1) / 2) as bigint) as half_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
where pu_label in (0, 1)
group by pu_label
;

-- ########## 3. 半量训练表 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half as
select
    t.*
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged t
inner join lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_keys k
    on t.unique_id = k.unique_id
    and coalesce(cast(t.dt_zx as string), '') = k.dt_zx_key
    and coalesce(cast(t.days_dt_zx as string), '') = k.days_dt_zx_key
    and t.pu_label = k.pu_label
inner join lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_cnt c
    on k.pu_label = c.pu_label
    and k.rn <= c.half_cnt
;

-- 兼容旧表名（可选；与 tagged_half 内容相同）
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half as
select * from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half
;

-- ########## 4. 核验 ##########
select
    'tagged' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    'tagged_half' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    c.pu_label,
    c.half_cnt as target_half_cnt,
    (select count(1)
     from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged_half h
     where h.pu_label = c.pu_label) as actual_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_tagged_half_cnt c
order by c.pu_label
;
