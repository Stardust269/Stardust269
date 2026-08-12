-- =============================================================================
-- 同事样本表：在 tagged（9:1 已划分）基础上，正/负各再随机保留 50%
-- =============================================================================
-- 前置：先跑 zyy_fxj_expansion_samples_tagged.sql
--       → lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
-- 产出：
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
--       （约 正 10 万 + 负 25 万，dataset_split 继承 tagged，不再重划）
-- =============================================================================

-- ########## 1. 各 pu_label 随机序号（用于抽一半） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys as
select
    t.unique_id,
    coalesce(cast(t.dt_zx as string), '') as dt_zx_key,
    coalesce(cast(t.days_dt_zx as string), '') as days_dt_zx_key,
    t.pu_label,
    row_number() over (
        partition by t.pu_label
        order by hash(concat(t.unique_id, coalesce(cast(t.dt_zx as string), ''), 'zyy_samples_half_v2'))
    ) as rn
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged t
where t.pu_label in (0, 1)
;

-- ########## 2. 各标签一半行数 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt as
select
    pu_label,
    cast(floor(count(1) / 2) as bigint) as half_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
where pu_label in (0, 1)
group by pu_label
;

-- ########## 3. 半量训练表（继承 tagged 的 pu_label + dataset_split） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half as
select
    t.*
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged t
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys k
    on t.unique_id = k.unique_id
    and coalesce(cast(t.dt_zx as string), '') = k.dt_zx_key
    and coalesce(cast(t.days_dt_zx as string), '') = k.days_dt_zx_key
    and t.pu_label = k.pu_label
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
    on k.pu_label = c.pu_label
    and k.rn <= c.half_cnt
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
    'half' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    c.pu_label,
    c.half_cnt as target_half_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half h where h.pu_label = c.pu_label) as actual_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
order by c.pu_label
;
