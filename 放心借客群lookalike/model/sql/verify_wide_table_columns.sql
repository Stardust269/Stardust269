-- =============================================================================
-- 宽表字段确认（在 Hive / Spark SQL 客户端执行）
-- 表名按环境替换；以下为当前项目默认全名。
-- =============================================================================

-- 1) 全量列名与类型（最权威）
desc lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit;

-- 2) 列名清单（便于 grep / 复制）
show columns in lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit;

-- 3) 建模关键列是否存在（返回 1 表示存在）
select
    sum(if(col = 'unique_id', 1, 0)) as has_unique_id,
    sum(if(col = 'days_dt_zx', 1, 0)) as has_days_dt_zx,
    sum(if(col = 'dt_zx', 1, 0)) as has_dt_zx,
    sum(if(col = 'zx_has_report_flg', 1, 0)) as has_zx_has_report_flg,
    sum(if(col = 'label', 1, 0)) as has_label,
    sum(if(col = 'y_loan_base_rate', 1, 0)) as has_y_loan_base_rate,
    sum(if(col = 'lend_date_sj', 1, 0)) as has_lend_date_sj,
    sum(if(col = 'ms13_score', 1, 0)) as has_ms13_score,
    sum(if(col = 'latest_bal_sum', 1, 0)) as has_latest_bal_sum,
    sum(if(col = 'fpd_20_score', 1, 0)) as has_fpd_20_score,
    sum(if(col = 'risk_score', 1, 0)) as has_risk_score_bare
from (
    select lower(column_name) as col
    from information_schema.columns
    where table_schema = 'ai_decision_dev'
      and table_name = 'fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit'
) x
;

-- 若 information_schema 不可用，用 desc 结果人工核对即可。

-- 4) 样例行 + 征信列抽样（列太多时不要 select *）
select
    unique_id,
    user_id,
    label,
    days_dt_zx,
    dt_zx,
    zx_has_report_flg,
    latest_bal_sum,
    zx_D1_bal_sum,
    fpd_20_score,
    cpd_10term_4_score
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
limit 5
;

-- 5) 扩量表里的 label 与 PU 正类无关时，看分布（勿直接当 pu_label）
select label, count(1) as cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
group by label
order by label
;

-- 6) 放心借明细（打 pu_label 用）
desc lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630;

select
    count(1) as cnt,
    sum(if(y_loan_base_rate < 0.18, 1, 0)) as rate_lt_18
from lj_iceberg.mkt_ayh_ana.zxt_5789_cust_detail_0630
;
