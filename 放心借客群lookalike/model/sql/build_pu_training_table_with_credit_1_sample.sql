-- =============================================================================
-- PU 训练表（抽样版）：基于 with_credit_1 终表，负样本随机抽取
-- =============================================================================
-- 前置：
--   fxj_seed_users_attach_credit_feature_with_credit_1.sql
--   → lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit_1
--
-- 逻辑（与 build_pu_training_table.sql 一致）：
--   pu_label=1：放心借利率 <18%，且借款当日有征信报告
--   利率/首借日期来自客群明细表（宽表 multiloans_feature 本身无 y_loan_base_rate）
--   客群明细：lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630（见 客群及其他相关表.md）
--   pu_label=0：从未标注池中随机抽取，抽取量 = 正样本行数（约 20 万）
--   同事对照：负样本曾固定抽 50 万（本脚本默认与正样本对齐，见步骤 3 注释改 500000）
--
-- 输出：
--   lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1
-- =============================================================================

-- ########## 1. 有报告人群 + 是否正类（未抽样） ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_label_stg as
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
    end as is_positive
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit_1 t
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
where t.zx_has_report_flg = 1
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

-- ########## 4. 合并打 PU 标签 + train/val 划分 ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1 as
select
    u.*,
    case
        when abs(hash(concat(u.unique_id, coalesce(u.dt_zx, ''))) % 10 < 8
        then 'train'
        else 'val'
    end as dataset_split
from (
    select
        p.*,
        1 as pu_label
    from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_pos_rows p
    union all
    select
        n.*,
        0 as pu_label
    from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_neg_sample_rows n
) u
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
