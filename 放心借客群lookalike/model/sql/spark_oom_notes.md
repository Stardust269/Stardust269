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
- 导出时不要 `select *`：只选建模列 + `pu_label` + `dataset_split`（及可选 `ms13_score`），减小单次作业宽度。
