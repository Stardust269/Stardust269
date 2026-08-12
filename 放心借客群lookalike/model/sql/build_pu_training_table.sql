-- =============================================================================
-- 构建 PU 学习用宽表（正类标签 + train/val 划分，9:1）
-- =============================================================================
-- 正类（pu_label=1）：Notion 种子定义 — 放心借利率 <18%，且借款当日有征信报告
-- 未标注（pu_label=0）：宽表中其余用户（背景扩量人群，含隐藏正例）
-- 入模数据：..._feature_with_credit（需先跑 fxj_seed_users_attach_credit_feature.sql）
-- 标签字段 y_loan_base_rate / lend_date_sj 在客群明细表，宽表无此列时需 join：
--   lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training as
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
    end as pu_label,
    case
        when pmod(abs(hash(concat(t.unique_id, coalesce(t.dt_zx, '')))), 10) < 9
        then 'train'
        else 'val'
    end as dataset_split
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
