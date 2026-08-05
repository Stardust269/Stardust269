# Spark 任务 OOM（YARN 杀容器）说明

典型报错：

```text
Container killed by YARN for exceeding physical memory limits.
14.0 GB of 14 GB physical memory used.
Consider boosting spark.executor.memoryOverhead.
```

## 原因（本项目的常见场景）

1. **宽表极大**：`fxj_*_with_credit` 约千万行 × 数千列，`select t.*` 再 join 会在 shuffle/序列化阶段吃满 executor。
2. **单条 SQL 过重**：宽表 + MS13 + `create table as select` 写在同一作业里，容易在 stage 4 左右失败。
3. **executor 堆外不足**：列很多时，JVM 堆 + 堆外（shuffle、Iceberg）超过 YARN 容器上限。

## 建议操作顺序

1. **先只跑** `build_pu_training_table.sql`（已去掉 MS13 join）。
2. 训练若暂不需要 ms13 筛背景：`config.yaml` 保持 `unlabeled_ms13_min: 0`，可直接导出训练。
3. 需要 ms13 时再**单独会话**跑 `build_pu_training_table_attach_ms13.sql`（先物化 `fxj_ms13_daily_for_lookalike`，再 join）。
4. 征信宽表 `fxj_seed_users_attach_credit_feature.sql` 与 PU 表**不要**同一次提交里连续跑，避免资源未释放。

## Spark 参数（按你们平台「高级参数 / Spark conf」填写）

在默认值基础上优先调下面几项（数值可按队列上限微调）：

| 参数 | 建议起点 | 说明 |
|------|----------|------|
| `spark.executor.memory` | `8g` 或 `12g` | executor JVM 堆 |
| `spark.executor.memoryOverhead` | `4g`～`6g` | **报错里明确建议加大**；宽表/Shuffle 依赖堆外 |
| `spark.driver.memory` | `8g` | `collect`、计划过大时 driver 也会挂 |
| `spark.driver.memoryOverhead` | `2g` | |
| `spark.sql.shuffle.partitions` | `400`～`800` | 千万行 join 时避免单分区过大 |
| `spark.sql.adaptive.enabled` | `true` | AQE 合并小分区 |
| `spark.sql.adaptive.coalescePartitions.enabled` | `true` | |
| `spark.sql.autoBroadcastJoinThreshold` | `-1` 或保持默认 | MS13 日表很大时不要 broadcast，避免 driver OOM |

若平台用 **executor 总内存 14G** 且无法改：把 `spark.executor.memory` 设为 `9g`，`memoryOverhead` 设为 `5g`（合计约 14G 容器），不要堆内也设 14g。

## 仍失败时

- 向同事确认是否有**已物化的 PU 训练中间表**或导出到 OBS/HDFS 再本地训练。
- 导出时不要 `select *`：只选建模列 + `pu_label` + `dataset_split`（及可选 `ms13_score`），减小单次作业宽度（见下一节）。
- **征信 Part 2**（`fxj_seed_credit_account_base`）exit **137**：多为全量 PBOC `row_number` 或 perform 先全表扫再 join。请用最新脚本（`spine` 驱动 + `account_stg` 两步），并**单独提交**该段且加大 `spark.executor.memoryOverhead`（建议 5g～6g）。

## 减单次宽度：具体怎么做、能不能这么干

**可以。**「宽度」= 单次 SQL 读写的**列数 × 行数**。减宽度 = 让这次作业少带一些列（或先物化一张更窄的 Iceberg 表，再 dtools 拉数）。与「特征很多、只剔高缺失」不矛盾：业务特征仍保留，去掉的是**不入模**或**缺失过高**的列。

### 和 `train.py` 的关系

- 训练侧：`get_model_feature_columns` 对 parquet 里**存在的列**自动入模，并排除 `src/features.py` 里的 `EXCLUDE_FROM_FEATURES`（id、`label`、`rnk`、`time_inst`、原始日期等）。
- 导出 parquet **必须带**：`pu_label`、`dataset_split`、`unique_id`（配置里的 `id_col`）。
- 若 `config.yaml` 里 `require_zx_report: true`，需带 `zx_has_report_flg`，否则过滤会把表滤空。
- 若要用 `unlabeled_ms13_min > 0`，需带 `ms13_score`。
- 在 Spark 导出阶段就删掉的高缺失列，**不会**出现在 parquet 里；`train.py` 里 `max_missing_rate` 仍可在剩余列上再剔一遍（双重剔同一列无害）。

### 做法 A：dtools 里不用 `SELECT *`，写显式列清单

适合：列名已稳定，或已从 `DESC TABLE` 拷好清单。

```sql
SELECT
  unique_id,
  pu_label,
  dataset_split,
  zx_has_report_flg,
  ms13_score,          -- 不用 ms13 筛背景时可省略
  d101, d102, ...      -- 放心借 D 段
  , latest_xxx, zx_xxx -- 征信
  , bh_xxx, risk_score_xxx  -- 外部
FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training
WHERE dataset_split IN ('train', 'val')
  AND (pu_label = 1 OR rand() < 0.15)
```

**不要指望**只删 `rnk`/`time_inst` 就能从 OOM 里救出来（通常只少几十列）。明显减负的是：**在清单里不写** id 重复列、泄漏列（`label`、`lend_date_sj` 等），以及同事认定要剔的**高缺失列**。

### 做法 B（推荐）：Spark 先建「窄表」，dtools 只读窄表

适合：宽表几千列、dtools 一次拉不动。重活在 Spark 集群分区内完成，导出作业只扫窄表。

1. 在 Spark 上对 `fxj_lookalike_pu_training` 的 **train 划分**算各列缺失率（或抽样算），得到要删的列名列表（阈值与训练一致，如缺失率 > 0.9）。
2. `CREATE TABLE ... AS SELECT` 只选：必带字段 + 保留的特征列（用 `DESC TABLE` + `features.EXCLUDE_FROM_FEATURES` 规则在本地生成列清单，再贴进 SQL）。
3. dtools：`SELECT * FROM lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow WHERE ...` —— 此时的 `*` 列数已少很多。

窄表可与 PU 表同库不同名，训练逻辑不变，只改导出用的表名。详见 `sql/build_pu_training_narrow_table.sql` 与 `scripts/spark_build_narrow_pu_table.py`。

### 做法 C：Spark 侧按列模式裁剪（不维护全量列名）

若表结构前缀稳定，可在建窄表时用「反选」思路（平台支持时）：

- 保留：`pu_label`、`dataset_split`、`unique_id`、`zx_has_report_flg`、`ms13_score`
- 保留：列名 like `d%`（注意过滤掉 `days_dt_zx` 若不想带出）、`latest_%`、`zx_%`、`bh_%`、`risk_score_%` 等业务前缀
- 排除：`rnk%`、`time_inst`、`label`、种子定义泄漏字段等

具体语法因 Hive/Spark 版本而异；没有通用 `SELECT * EXCEPT` 时，仍建议用 **B：缺失率统计 + 生成列清单**。

### 和「分 100/200 桶」怎么配合

- **减宽度**和**分桶**可同时用：窄表 + `pu_label=0 AND pmod(hash(unique_id), N)=k`；种子单独导一次。
- 若仍是 `SELECT *` 且列数未减，分再多个桶也可能 OOM（列宽不变）。

### 小结

| 手段 | 减的是什么 | 能否操作 |
|------|------------|----------|
| 显式列清单 / 窄表 | 元数据、泄漏列、高缺失列 | 可以，与训练兼容 |
| 仅 train.py 剔高缺失 | 训练内存 | **不减** Spark/dtools 导出宽度 |
| 分桶 | 单次行数 | 可以；列仍宽时可能不够 |
