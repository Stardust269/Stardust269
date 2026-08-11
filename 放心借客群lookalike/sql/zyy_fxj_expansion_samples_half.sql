-- =============================================================================
-- 同事样本表：先打 pu_label + dataset_split，再正/负各随机保留 50%
-- =============================================================================
-- 源表：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
--       （约 正 20 万 + 负 50 万，尚无 pu_label / dataset_split）
-- 产出：
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged  （全量带标签）
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_half     （各抽 50%）
--
-- pu_label 规则（二选一，见步骤 1 case）：
--   A. 同事表已有 label（0/负 1/正）→ 直接作 pu_label（与 20万/50万 一致）
--   B. 无 label 时 join 客群明细，与 build_pu_training_table 种子规则一致
-- =============================================================================

-- ########## 0. 探查（可选） ##########
-- select label, count(1) from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples group by label;
-- desc lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples;

-- ########## 1. 打 pu_label（中间层） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg as
select
    s.*,
    case
        when cast(s.label as int) in (0, 1)
        then cast(s.label as int)
        when seed.y_loan_base_rate is not null
         and cast(seed.y_loan_base_rate as double) < 0.18
         and seed.lend_date_sj is not null
         and s.days_dt_zx is not null
         and cast(s.days_dt_zx as date) = cast(seed.lend_date_sj as date)
        then 1
        else 0
    end as pu_label
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples s
left join (
    select
        unique_id,
        lend_date_sj,
        max(y_loan_base_rate) as y_loan_base_rate
    from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
    group by unique_id, lend_date_sj
) seed
    on s.unique_id = seed.unique_id
    and cast(s.days_dt_zx as date) = cast(seed.lend_date_sj as date)
-- 若正负列是 is_seed 而非 label，把上面 case 第一行改为 cast(s.is_seed as int)
;

-- ########## 2. train/val 划分键（窄表，避免控制台解析失败） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_split_dim;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_split_dim as
select
    unique_id,
    coalesce(cast(dt_zx as string), '') as dt_zx_key,
    coalesce(cast(days_dt_zx as string), '') as days_dt_zx_key,
    pu_label,
    if(pmod(abs(hash(concat(unique_id, coalesce(cast(dt_zx as string), ''))), 10) < 8, 'train', 'val') as dataset_split
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg
where pu_label in (0, 1)
;

-- ########## 3. 全量带标签表 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged as
select
    sp.dataset_split,
    stg.*
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg stg
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_split_dim sp
    on stg.unique_id = sp.unique_id
    and coalesce(cast(stg.dt_zx as string), '') = sp.dt_zx_key
    and coalesce(cast(stg.days_dt_zx as string), '') = sp.days_dt_zx_key
    and stg.pu_label = sp.pu_label
where stg.pu_label in (0, 1)
;

-- ########## 4. 各 pu_label 随机序号（用于抽一半） ##########
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

-- ########## 5. 各标签一半行数 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_half_cnt as
select
    pu_label,
    cast(floor(count(1) / 2) as bigint) as half_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
where pu_label in (0, 1)
group by pu_label
;

-- ########## 6. 半量训练表（带 pu_label + dataset_split） ##########
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

-- ########## 7. 核验 ##########
select
    'label_stg' as step,
    pu_label,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg
where pu_label in (0, 1)
group by pu_label
order by pu_label
;

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
