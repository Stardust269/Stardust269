-- =============================================================================
-- 构建 PU 学习用宽表（正类标签 + train/val 划分）
-- =============================================================================
-- 正类（pu_label=1）：Notion 种子定义 — 放心借利率 <18%，且借款当日有征信报告
-- 未标注（pu_label=0）：宽表中其余用户（背景扩量人群，含隐藏正例）
-- 入模宽表：..._feature_with_credit（先跑 fxj_seed_users_attach_credit_feature.sql）
--
-- 说明：扩量宽表本身不含 y_loan_base_rate / lend_date_sj，需 join 放心借客群明细表打标签；
--       ms13 来自 model_13 表 standard_score，导出为 ms13_score 供 config 过滤（可选）。
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training as
with fxj_cust as (
    select
        unique_id,
        lend_date_sj,
        cast(y_loan_base_rate as double) as y_loan_base_rate
    from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
),
ms13_daily as (
    select
        union_id,
        cast(standard_score as double) as ms13_score,
        date_add(
            from_unixtime(unix_timestamp(dt, 'yyyymmdd'), 'yyyy-mm-dd'),
            1
        ) as ms_anchor_dt
    from lj_iceberg.model_deployment.m1_mgt_master_score_model_13_1
    where dt >= '20260209'
      and dt <= '20260628'
)
select
    t.*,
    case
        when c.y_loan_base_rate is not null
         and c.y_loan_base_rate < 0.18
         and c.lend_date_sj is not null
         and t.days_dt_zx is not null
         and cast(t.days_dt_zx as date) = cast(c.lend_date_sj as date)
        then 1
        else 0
    end as pu_label,
    m.ms13_score,
    case
        when abs(hash(concat(t.unique_id, coalesce(cast(t.dt_zx as string), '')))) % 10 < 8
        then 'train'
        else 'val'
    end as dataset_split
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
left join fxj_cust c
    on t.unique_id = c.unique_id
left join ms13_daily m
    on t.unique_id = m.union_id
   and cast(t.days_dt_zx as date) = m.ms_anchor_dt
where t.zx_has_report_flg = 1
;

-- 核验
select
    pu_label,
    dataset_split,
    count(1) as cnt,
    count(distinct unique_id) as usr
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
group by pu_label, dataset_split
order by pu_label, dataset_split
;

select
    pu_label,
    count(1) as cnt,
    sum(if(ms13_score is not null, 1, 0)) as ms13_hit,
    percentile_approx(ms13_score, 0.5) as ms13_p50
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
group by pu_label
order by pu_label
;
