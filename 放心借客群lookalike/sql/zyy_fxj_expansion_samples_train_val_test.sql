-- =============================================================================
-- 同事样本：时间切分 train/val + 全量宽表 test（最后 7 天）
-- =============================================================================
-- 背景（同事 TGI 验收方案，不调参）：
--   训练窗：days_dt_zx < '2026-06-22'  → 再 hash 9:1 得 train / val（同事样本表）
--   测试窗：days_dt_zx >= '2026-06-22' → 融合征信全量宽表按日期筛选，不采样，仅评估
--
-- test 源表（原始特征宽表，非 TGI 打分结果）：
--   lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
-- 勿用：fxj_ayh_seed_users_expansion_tgi_result（TGI 全量打分结果表）
--
-- 前置（同事已建）：
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train
--       ← zyy_fxj_ayh_seed_users_expansion_samples where days_dt_zx < '2026-06-22'
--
-- 产出：
--   zyy_fxj_ayh_seed_users_expansion_samples_train_tagged      train+val（带 pu_label、dataset_split）
--   fxj_ayh_seed_users_expansion_with_credit_test              test（dataset_split='test'）
--   zyy_fxj_ayh_seed_users_expansion_samples_train_model       可选：训练用抽样表（负样本=正样本数）
--
-- 同事核验参考（samples 表按 days_dt_zx 切，仅供参考）：
--   < 2026-06-22 : 665723 行, sum(label)=213083 正
--   >=2026-06-22 :  49599 行, sum(label)=2239  正
-- =============================================================================

-- ########## 0. 样本量探查（跑脚本前先执行） ##########
select
    'samples_train_window' as src,
    count(1) as row_cnt,
    sum(cast(label as int)) as pos_cnt,
    count(1) - sum(cast(label as int)) as neg_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train
;

select
    'samples_test_window_in_expansion' as src,
    count(1) as row_cnt,
    sum(cast(label as int)) as pos_cnt,
    count(1) - sum(cast(label as int)) as neg_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
where cast(days_dt_zx as date) >= date '2026-06-22'
;

select
    'with_credit_test_window' as src,
    count(1) as row_cnt,
    sum(case
        when seed.y_loan_base_rate is not null
         and cast(seed.y_loan_base_rate as double) < 0.18
         and seed.lend_date_sj is not null
         and t.days_dt_zx is not null
         and cast(t.days_dt_zx as date) = cast(seed.lend_date_sj as date)
        then 1 else 0
    end) as pos_cnt,
    count(1) - sum(case
        when seed.y_loan_base_rate is not null
         and cast(seed.y_loan_base_rate as double) < 0.18
         and seed.lend_date_sj is not null
         and t.days_dt_zx is not null
         and cast(t.days_dt_zx as date) = cast(seed.lend_date_sj as date)
        then 1 else 0
    end) as neg_cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
left join (
    select
        unique_id,
        lend_date_sj,
        max(y_loan_base_rate) as y_loan_base_rate
    from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
    group by unique_id, lend_date_sj
) seed
    on t.unique_id = seed.unique_id
    and cast(t.days_dt_zx as date) = cast(seed.lend_date_sj as date)
where cast(t.days_dt_zx as date) >= date '2026-06-22'
;

-- 负样本是否需 SQL 层抽样（训练窗）：
--   当前约 45 万负 / 21 万正（约 2.1:1），未超过 50 万负、比例 < 3:1 → 默认不抽样
--   若分析机仍 OOM，启用文末「步骤 5」生成 _train_model 表

-- ########## 1. 训练窗打 pu_label ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_label_stg as
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
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train s
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
;

-- ########## 2. 训练窗 train/val 划分（9:1，hash） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_split_dim;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_split_dim as
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
    from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_label_stg
    where pu_label in (0, 1)
) k
;

-- ########## 3. 训练+验证表（建模用，全量 train 窗，不负采样） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged as
select
    sp.dataset_split,
    stg.*
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_label_stg stg
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_split_dim sp
    on stg.unique_id = sp.unique_id
    and coalesce(cast(stg.dt_zx as string), '') = sp.dt_zx_key
    and coalesce(cast(stg.days_dt_zx as string), '') = sp.days_dt_zx_key
    and stg.pu_label = sp.pu_label
where stg.pu_label in (0, 1)
;

-- ########## 4. 测试集（with_credit 全量宽表，days_dt_zx >= 6.22，不采样） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_test_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_test_label_stg as
select
    t.*,
    case
        when seed.y_loan_base_rate is not null
         and cast(seed.y_loan_base_rate as double) < 0.18
         and seed.lend_date_sj is not null
         and t.days_dt_zx is not null
         and cast(t.days_dt_zx as date) = cast(seed.lend_date_sj as date)
        then 1
        else 0
    end as pu_label
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
left join (
    select
        unique_id,
        lend_date_sj,
        max(y_loan_base_rate) as y_loan_base_rate
    from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
    group by unique_id, lend_date_sj
) seed
    on t.unique_id = seed.unique_id
    and cast(t.days_dt_zx as date) = cast(seed.lend_date_sj as date)
where cast(t.days_dt_zx as date) >= date '2026-06-22'
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_with_credit_test;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_with_credit_test as
select
    'test' as dataset_split,
    stg.*
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_test_label_stg stg
where stg.pu_label in (0, 1)
;

-- ########## 5. 【可选】训练窗负样本抽样（仅分析机 OOM 时启用） ##########
-- 规则：正样本全留；负样本随机抽取，行数 = 正样本行数（与同事早期 1:1 对齐）
-- 取消下面注释块即可执行

-- drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_neg_rank;
-- create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_neg_rank as
-- select
--     unique_id,
--     coalesce(cast(dt_zx as string), '') as dt_zx_key,
--     coalesce(cast(days_dt_zx as string), '') as days_dt_zx_key,
--     dataset_split,
--     row_number() over (
--         order by hash(concat(unique_id, coalesce(cast(dt_zx as string), ''), 'zyy_train_neg_v1'))
--     ) as rn
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged
-- where pu_label = 0
-- ;
--
-- drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_pos_cnt;
-- create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_pos_cnt as
-- select count(1) as pos_cnt
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged
-- where pu_label = 1
-- ;
--
-- drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_model;
-- create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_model as
-- select t.*
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged t
-- where t.pu_label = 1
-- union all
-- select t.*
-- from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged t
-- inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_neg_rank pick
--     on t.unique_id = pick.unique_id
--     and coalesce(cast(t.dt_zx as string), '') = pick.dt_zx_key
--     and coalesce(cast(t.days_dt_zx as string), '') = pick.days_dt_zx_key
--     and t.dataset_split = pick.dataset_split
-- inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_train_pos_cnt c
--     on pick.rn <= c.pos_cnt
-- where t.pu_label = 0
-- ;

-- ########## 6. 核验 ##########
select
    'train_tagged' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    'with_credit_test' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_with_credit_test
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    'train_window_date_range' as step,
    min(cast(days_dt_zx as date)) as min_days_dt_zx,
    max(cast(days_dt_zx as date)) as max_days_dt_zx,
    count(1) as cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples_train_tagged
;

select
    'test_window_date_range' as step,
    min(cast(days_dt_zx as date)) as min_days_dt_zx,
    max(cast(days_dt_zx as date)) as max_days_dt_zx,
    count(1) as cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_with_credit_test
;
