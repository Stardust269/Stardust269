-- =============================================================================
-- 构建 PU 学习用宽表（正类标签 + train/val 划分）
-- =============================================================================
-- 正类（pu_label=1）：扩量宽表字段 label=1（约 21.5 万，与 Notion 种子规模一致）
-- 未标注（pu_label=0）：label=0（背景扩量，约千万级；含隐藏正例）
-- 入模宽表：fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
--       （先跑 fxj_seed_users_attach_credit_feature.sql）
--
-- 宽表无 y_loan_base_rate / lend_date_sj；种子已由加工链路写入 label，勿用 label 入模。
-- ms13：m1_mgt_master_score_model_13_1.standard_score → ms13_score（可选过滤背景人群）
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training as
with ms13_daily as (
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
    cast(t.label as int) as pu_label,
    m.ms13_score,
    case
        when abs(hash(concat(t.unique_id, coalesce(cast(t.dt_zx as string), '')))) % 10 < 8
        then 'train'
        else 'val'
    end as dataset_split
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
left join ms13_daily m
    on t.unique_id = m.union_id
   and cast(t.days_dt_zx as date) = m.ms_anchor_dt
where t.zx_has_report_flg = 1
;

-- 核验（全表 label 分布约：1→215322，0→9847457；过滤 zx 后正类会略少）
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
