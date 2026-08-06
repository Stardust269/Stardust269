-- =============================================================================
-- Step 2 / 2（可选）：为训练表补 ms13_score
-- =============================================================================
-- 前置：build_pu_training_table.sql 已成功产出 fxj_lookalike_pu_training
-- 若 Step 1 仍 OOM，先调 Spark 资源（spark_oom_notes.md），不要与征信宽表加工混在同一会话里跑。
-- =============================================================================

drop table if exists lj_iceberg.ai_decision_dev.fxj_ms13_daily_for_lookalike;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ms13_daily_for_lookalike as
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
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_with_ms13;
create table if not exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_with_ms13 as
select
    t.*,
    m.ms13_score
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training t
left join lj_iceberg.ai_decision_dev.fxj_ms13_daily_for_lookalike m
    on t.unique_id = m.union_id
   and cast(t.days_dt_zx as date) = m.ms_anchor_dt
;

-- 用带 ms13 的表替换训练表（确认行数与 Step1 一致后再执行）
-- drop table if exists lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training;
-- alter table lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_with_ms13
--   rename to fxj_lookalike_pu_training;

select
    pu_label,
    count(1) as cnt,
    sum(if(ms13_score is not null, 1, 0)) as ms13_hit
from lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_with_ms13
group by pu_label
order by pu_label
;
