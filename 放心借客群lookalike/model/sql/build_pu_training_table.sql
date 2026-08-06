-- =============================================================================
-- Step 1 / 2：构建 PU 训练表（轻量，不 join MS13）
-- =============================================================================
-- 当前默认源表：同事预采样（约 50 万负样本 + 正类），仅有 label，无 pu_label / dataset_split。
--   lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples
-- 产出：lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training（供 dtools 导出 + train.py）
--
-- 全量宽表（易 OOM）见文件末尾注释块，改回 feature_with_credit 源即可。
-- MS13：需要时再单独跑 build_pu_training_table_attach_ms13.sql。
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training as
select
    t.*,
    cast(t.label as int) as pu_label,
    case
        when abs(hash(concat(t.unique_id, coalesce(cast(t.dt_zx as string), '')))) % 10 < 8
        then 'train'
        else 'val'
    end as dataset_split
from lj_iceberg.ai_decision_dev.zyy_fxj_ayh_seed_users_expansion_samples t
-- 采样表若已只保留有征信报告人群，可注释掉下行
where coalesce(cast(t.zx_has_report_flg as int), 1) = 1
;

-- 核验
select pu_label, dataset_split, count(1) as cnt
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
group by pu_label, dataset_split
order by pu_label, dataset_split
;

-- -----------------------------------------------------------------------------
-- 全量征信宽表源（千万行，Spark 易 OOM；与 dtools 全表导出同理慎用）
-- -----------------------------------------------------------------------------
-- drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
-- create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training as
-- select
--     t.*,
--     cast(t.label as int) as pu_label,
--     case
--         when abs(hash(concat(t.unique_id, coalesce(cast(t.dt_zx as string), '')))) % 10 < 8
--         then 'train'
--         else 'val'
--     end as dataset_split
-- from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
-- where t.zx_has_report_flg = 1
-- ;
