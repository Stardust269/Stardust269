-- =============================================================================
-- Step 1 / 2：构建 PU 训练表（轻量，不 join MS13）
-- =============================================================================
-- 约千万行 × 极宽列时，与 MS13 同 SQL 易触发 executor OOM（14G 打满被 YARN kill）。
-- 请先只跑本脚本；需要 ms13 过滤时再跑 build_pu_training_table_attach_ms13.sql。
--
-- 提交前可在 Spark 任务里加大 memoryOverhead（见 sql/spark_oom_notes.md）。
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
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit t
where t.zx_has_report_flg = 1
;

-- 核验
select pu_label, dataset_split, count(1) as cnt
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
group by pu_label, dataset_split
order by pu_label, dataset_split
;
