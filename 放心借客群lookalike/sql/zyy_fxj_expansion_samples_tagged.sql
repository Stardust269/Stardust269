-- =============================================================================
-- 同事样本表：打 pu_label + train/val 划分（9:1）
-- =============================================================================
-- 源表：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
--       同事已抽样：约 正 20 万 + 负 50 万（非全量背景未标注池）
-- 产出：
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_tagged
--
-- 划分规则（与同事一致）：hash(unique_id, dt_zx) 分 10 桶，9 桶 train、1 桶 val
-- 注意：勿用 build_pu_training_table*.sql（那是全量宽表未标注池，非本表）
-- =============================================================================

-- ########## 0. 探查（可选） ##########
-- select label, count(1) from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples group by label;
-- desc lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples;

-- ########## 1. 打 pu_label ##########
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

-- ########## 2. train/val 划分键（9:1；仅在同事 20万+50万 样本表上划分） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_split_dim;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_split_dim as
select
    k.unique_id,
    k.dt_zx_key,
    k.days_dt_zx_key,
    k.pu_label,
    case
        when pmod(abs(hash(concat(k.unique_id, k.dt_zx_key))), 10) < 9
        then 'train'
        else 'val'
    end as dataset_split
from (
    select
        unique_id,
        coalesce(cast(dt_zx as string), '') as dt_zx_key,
        coalesce(cast(days_dt_zx as string), '') as days_dt_zx_key,
        pu_label
    from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_samples_label_stg
    where pu_label in (0, 1)
) k
;

-- ########## 3. 带标签 + 划分的训练表（全量同事样本，约 70 万行） ##########
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

-- ########## 4. 核验 ##########
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
