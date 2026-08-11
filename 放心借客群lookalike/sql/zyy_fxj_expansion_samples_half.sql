-- =============================================================================
-- 同事样本表：正/负各随机保留 50%（无 pu_label / dataset_split 版本）
-- =============================================================================
-- 源表：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
--       （约 正 20 万 + 负 50 万，仅有特征宽表 + 正负标记列，非 pu_label）
-- 产出：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
--       （约 正 10 万 + 负 25 万，体积约减半）
--
-- 【必改】步骤 0 里 sample_side 表达式：改成同事表上区分正/负的列。
--   常见：label / y / sample_label / is_seed（1=正，0=负）
--   跑步骤 0 探查，看哪列分组后约为 20 万 / 50 万。
-- =============================================================================

-- ########## 0. 探查正负标记列（先跑，确认用哪列） ##########
-- select label, count(1) as cnt, count(distinct unique_id) as usr
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
-- group by label order by label;
--
-- select sample_label, count(1) from ... group by sample_label;
-- select is_seed, count(1) from ... group by is_seed;

-- ########## 1. 行键 + 抽样侧 sample_side（1=正，0=负） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys as
select
    s.unique_id,
    coalesce(cast(s.dt_zx as string), '') as dt_zx_key,
    coalesce(cast(s.days_dt_zx as string), '') as days_dt_zx_key,
  -- ↓↓↓ 默认用 label；若不是，只改这一行 case（不要用尚不存在的 pu_label）↓↓↓
    cast(s.label as int) as sample_side,
    row_number() over (
        partition by cast(s.label as int)
        order by hash(concat(s.unique_id, coalesce(cast(s.dt_zx as string), ''), 'zyy_samples_half_v1'))
    ) as rn
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples s
where cast(s.label as int) in (0, 1)
-- 若正负是 is_seed：改为 cast(s.is_seed as int) as sample_side，where cast(s.is_seed as int) in (0, 1)
;

-- ########## 2. 各侧一半行数 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt as
select
    sample_side,
    cast(floor(count(1) / 2) as bigint) as half_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys
group by sample_side
;

-- ########## 3. 产出半量宽表（结构同源表，仍无 pu_label / dataset_split） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half as
select
    t.*
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples t
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_keys k
    on t.unique_id = k.unique_id
    and coalesce(cast(t.dt_zx as string), '') = k.dt_zx_key
    and coalesce(cast(t.days_dt_zx as string), '') = k.days_dt_zx_key
  -- join 侧与步骤 1 的 sample_side 定义保持一致
    and cast(t.label as int) = k.sample_side
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
    on k.sample_side = c.sample_side
    and k.rn <= c.half_cnt
;

-- ########## 4. 核验 ##########
select
    'source' as tbl,
    cast(label as int) as sample_side,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
where cast(label as int) in (0, 1)
group by cast(label as int)
order by sample_side
;

select
    'half' as tbl,
    cast(label as int) as sample_side,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half
group by cast(label as int)
order by sample_side
;

select
    c.sample_side,
    c.half_cnt as target_half_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half h where cast(h.label as int) = c.sample_side) as actual_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt c
order by c.sample_side
;
