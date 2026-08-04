-- =============================================================================
-- 窄表：train 划分上算缺失率 → 剔高缺失列 → 物化 Iceberg 表
-- =============================================================================
-- 源表：lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
-- 目标：lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow
--
-- 极宽表（数千列）无法在 SQL 里手写每一列的缺失率，请用 PySpark 脚本（推荐）：
--   scripts/spark_build_narrow_pu_table.py
-- 在 Spark 任务 / Notebook（已有 spark 会话）中 %run 或 spark-submit。
--
-- 下面给出「原理等价」的纯 SQL 片段，便于理解或与脚本对照。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Step 0：仅用 train 行做缺失统计（与 config.yaml / train.py 一致）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW fxj_pu_train_for_miss AS
SELECT *
FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
WHERE dataset_split = 'train'
;

-- -----------------------------------------------------------------------------
-- Step 1（示例）：手工对少量列算缺失率（全表请用 PySpark 脚本批量 agg）
-- 缺失定义：NULL 或 trim(cast as string) in ('', 'nan')
-- -----------------------------------------------------------------------------
SELECT
  COUNT(1) AS n,
  AVG(CASE
        WHEN d101 IS NULL OR TRIM(CAST(d101 AS STRING)) IN ('', 'nan') THEN 1.0
        ELSE 0.0
      END) AS d101_miss,
  AVG(CASE
        WHEN latest_org_type IS NULL OR TRIM(CAST(latest_org_type AS STRING)) IN ('', 'nan') THEN 1.0
        ELSE 0.0
      END) AS latest_org_type_miss
FROM fxj_pu_train_for_miss
;

-- -----------------------------------------------------------------------------
-- Step 2（示例）：建窄表 — 只选必带列 + 你确认要保留的特征列
-- 真实环境由 spark_build_narrow_pu_table.py 根据 Step1 结果自动生成列清单
-- -----------------------------------------------------------------------------
-- CREATE OR REPLACE TABLE lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow
-- USING iceberg
-- AS
-- SELECT
--   unique_id,
--   pu_label,
--   dataset_split,
--   zx_has_report_flg,
--   -- ms13_score,  -- 若已 attach MS13
--   d101,
--   d102
--   -- … 其余缺失率 <= 0.90 的特征列
-- FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
-- ;

-- -----------------------------------------------------------------------------
-- Step 3：核验窄表
-- -----------------------------------------------------------------------------
-- SELECT COUNT(1) AS rows, COUNT(DISTINCT unique_id) AS users
-- FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow
-- ;
--
-- SELECT pu_label, dataset_split, COUNT(1) AS cnt
-- FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow
-- GROUP BY pu_label, dataset_split
-- ORDER BY pu_label, dataset_split
-- ;

-- -----------------------------------------------------------------------------
-- Step 4：dtools 导出改读窄表（列少，SELECT * 不易 OOM）
-- -----------------------------------------------------------------------------
-- SELECT *
-- FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow
-- WHERE dataset_split IN ('train', 'val')
--   AND (pu_label = 1 OR rand() < 0.15)
-- ;
