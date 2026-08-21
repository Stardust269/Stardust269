-- =============================================================================
-- PU 训练表（抽样版）：基于 with_credit_1 终表，负样本随机抽取
-- =============================================================================
-- 前置：
--   fxj_seed_users_attach_credit_feature_with_credit_1.sql
--   → lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit_1
--
-- 逻辑：
--   is_positive / pu_label：直接沿用同事样本表 label（0/1），不再用种子规则 join 客群明细
--   正样本（label=1）：全量保留
--   负样本（label=0）：从未标注池中随机抽取，抽取量 = 正样本行数（约 21.5 万）
--   同事对照：负样本曾固定抽 50 万（本脚本默认与正样本对齐，见步骤 3 注释改 500000）
--
-- 输出：
--   lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1
-- =============================================================================

-- ########## 1. 有报告人群 + 同事 label → is_positive（未抽样） ##########
-- 宽表 with_credit_1 无 label 列，需 join 同事样本表 zyy_fxj_ayh_seed_users_expansion_samples
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg as
select
    t.*,
    smp.label as is_positive
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit_1 t
inner join lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples smp
    on t.unique_id = smp.unique_id
   and coalesce(cast(t.dt_zx as string), '') = coalesce(cast(smp.dt_zx as string), '')
where t.zx_has_report_flg = 1
  and cast(smp.label as int) in (0, 1)
;

-- ########## 2. 正样本（全量保留） ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_rows;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_rows as
select *
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg
where is_positive = 1
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_cnt;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_cnt as
select count(1) as pos_cnt
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_rows
;

-- ########## 3. 负样本随机抽取（行数 = 正样本行数） ##########
-- 随机序：hash + row_number；不用 SELECT * EXCEPT(rn)（部分引擎不支持）
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rank;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rank as
select
    s.unique_id,
    coalesce(cast(s.dt_zx as string), '') as dt_zx_key,
    coalesce(cast(s.days_dt_zx as string), '') as days_dt_zx_key,
    row_number() over (
        order by hash(concat(s.unique_id, coalesce(s.dt_zx, ''), 'fxj_pu_neg_sample_v1'))
    ) as rn
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg s
where s.is_positive = 0
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rows;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rows as
select
    stg.*
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg stg
inner join lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rank pick
    on stg.unique_id = pick.unique_id
    and coalesce(cast(stg.dt_zx as string), '') = pick.dt_zx_key
    and coalesce(cast(stg.days_dt_zx as string), '') = pick.days_dt_zx_key
inner join lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_cnt c
    on pick.rn <= c.pos_cnt
-- 与同事 50 万负样本对齐时，最后一行 join 改为：
-- inner join (select 500000 as pos_cnt) c on pick.rn <= c.pos_cnt
;

-- ########## 4. 合并 PU 标签 + train/val（拆步，避免控制台解析 select t.*, case/mod 失败） ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_union;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_union as
select
    p.*,
    1 as pu_label
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_rows p
union all
select
    n.*,
    0 as pu_label
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rows n
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_split;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_split as
select
    unique_id,
    coalesce(cast(dt_zx as string), '') as dt_zx_key,
    coalesce(cast(days_dt_zx as string), '') as days_dt_zx_key,
    pmod(abs(hash(concat(unique_id, coalesce(cast(dt_zx as string), '')))), 10) as split_bucket
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_union
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1 as
select
    sp.dataset_split,
    u.*
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_union u
inner join (
    select
        unique_id,
        dt_zx_key,
        days_dt_zx_key,
        if(split_bucket < 8, 'train', 'val') as dataset_split
    from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1_split
) sp
    on u.unique_id = sp.unique_id
    and coalesce(cast(u.dt_zx as string), '') = sp.dt_zx_key
    and coalesce(cast(u.days_dt_zx as string), '') = sp.days_dt_zx_key
;

-- ########## 5. 核验 ##########
select
    'label_stg' as step,
    sum(if(is_positive = 1, 1, 0)) as pos_cnt,
    sum(if(is_positive = 0, 1, 0)) as neg_pool_cnt,
    count(1) as row_cnt,
    count(distinct unique_id) as usr_cnt
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg
;

select
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    pos_cnt as stg_pos_cnt,
    (select count(1) from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rows) as neg_sample_cnt
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_cnt
;
