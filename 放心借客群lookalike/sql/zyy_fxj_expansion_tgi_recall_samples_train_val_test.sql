-- =============================================================================
-- TGI 回归后样本：train/val + test（与同事表对齐）
-- =============================================================================
-- 源表（同事已建，TGI 过滤后）：
--   train/val 候选：lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples
--   test：         lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test
--
-- 划分规则与 TGI 过滤前完全一致：
--   时间窗：train/val 用 days_dt_zx < 2026-06-22；test 用 days_dt_zx >= 2026-06-22
--   pu_label：直接沿用源表 label（0/1）
--   train/val：hash(unique_id, dt_zx) 9:1
--
-- 产出（供 parquet 导出）：
--   zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_train_tagged
--   zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged
-- =============================================================================

-- ########## 0. 样本量探查 ##########
select
    'tgi_recall_train_src' as src,
    count(1) as row_cnt,
    sum(cast(label as int)) as pos_cnt,
    count(1) - sum(cast(label as int)) as neg_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples
where cast(days_dt_zx as date) < date '2026-06-22'
;

select
    'tgi_recall_test_src' as src,
    count(1) as row_cnt,
    sum(cast(label as int)) as pos_cnt,
    count(1) - sum(cast(label as int)) as neg_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test
where cast(days_dt_zx as date) >= date '2026-06-22'
;

select
    'tgi_recall_test_src_all_dates' as src,
    count(1) as row_cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test
;

-- ########## 1. 训练窗打 pu_label（直接沿用源表 label） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_label_stg as
select
    s.*,
    s.label as pu_label
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples s
where cast(s.days_dt_zx as date) < date '2026-06-22'
;

-- ########## 2. train/val 划分（9:1，hash，与过滤前一致） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_split_dim;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_split_dim as
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
    from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_label_stg
    where pu_label in (0, 1)
) k
;

-- ########## 3. 训练+验证表 ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_train_tagged;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_train_tagged as
select
    sp.dataset_split,
    stg.*
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_label_stg stg
inner join lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_train_split_dim sp
    on stg.unique_id = sp.unique_id
    and coalesce(cast(stg.dt_zx as string), '') = sp.dt_zx_key
    and coalesce(cast(stg.days_dt_zx as string), '') = sp.days_dt_zx_key
    and stg.pu_label = sp.pu_label
where stg.pu_label in (0, 1)
;

-- ########## 4. 测试集（TGI 过滤后 test 表，test 窗 >= 2026-06-22） ##########
drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_test_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_test_label_stg as
select
    t.*,
    t.label as pu_label
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test t
where cast(t.days_dt_zx as date) >= date '2026-06-22'
;

drop table if exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged;
create table if not exists lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged as
select
    'test' as dataset_split,
    stg.*
from lj_iceberg.ai_decision_dev.zyy_fxj_expansion_tgi_recall_test_label_stg stg
where stg.pu_label in (0, 1)
;

-- ########## 5. 核验 ##########
select
    'tgi_recall_train_tagged' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_train_tagged
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    'tgi_recall_test_tagged' as step,
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    'tgi_recall_test_tagged_date_range' as step,
    min(cast(days_dt_zx as date)) as min_days_dt_zx,
    max(cast(days_dt_zx as date)) as max_days_dt_zx,
    count(1) as cnt
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_tgi_recall_samples_test_tagged
;
