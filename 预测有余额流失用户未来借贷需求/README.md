# 预测有余额流失用户未来借贷需求

## 目录结构

| 目录/文件 | 说明 |
|-----------|------|
| `sql/` | 特征加工与标签构建 SQL |
| `notion_schema/` | Notion 征信字段字典、项目说明、标签构建文档 |

## 两条流水线（勿混用）

| 版本 | 主脚本 | 场景 |
|------|--------|------|
| **20260623**（已验证） | `sql/run_all_20260623.sql` | 十月单 cohort **5401**；复制同事 `yye _2/_4` |
| **20260715**（三月版） | `sql/run_all_20260715.sql` | **八月~十月** cohort（5103 入口 + **全渠道无余额**；10 月 ~5401） |

## 主要文档

- 特征需求清单：`notion_schema/需要加工的数据.md`
- 标签构建说明：`notion_schema/项目说明_标签构建.md`（十月 5401 版）
- **三月样本说明**：`notion_schema/项目说明_三月样本20260715.md`
- **同事样本 SQL 对照**：`notion_schema/项目说明_同事样本SQL对照.md`
- 字段总表：`notion_schema/FIELD_CATALOG.md`

## SQL 文件索引

### 十月单 cohort（5401）

| 文件 | 说明 |
|------|------|
| `sql/run_all_20260623.sql` | **一键全量**（推荐） |
| `sql/yye_credit_feature_process.sql` | 分步特征 SQL |
| `sql/yye_pril_bal_sample_reference.sql` | 同事参考 SQL |
| `sql/drop_all_jcr_tables.sql` | 删除 jcr_*_20260623 表 |
| `sql/verify_cohort_5401.sql` | 核验 5401 |

### 三月样本（全渠道无余额 cohort，10 月 ~5401）

| 文件 | 说明 |
|------|------|
| `sql/run_all_20260715.sql` | **一键全量**（样本 + 征信特征 + 标签；Part8 需先跑马消特征） |
| `sql/run_mx_feature_20260715.sql` | **自建马消特征**（全渠道余额/提现，仅 cohort 子集） |
| `sql/yye_pril_bal_sample_reference_20260715.sql` | 同事参考示例（含 `*_5103` 字段，我方不用） |
| `sql/drop_all_jcr_tables_20260715.sql` | 删除本人 `jcr_*_20260715` 表（15 张） |
| `sql/drop_all_jcr_tables.sql` | 删除本人 `jcr_*_20260623` 表（11 张） |
| `sql/list_project_tables.sql` | 核验本人 `jcr%` 表残留 |
| `sql/run_part01_sample_cohort_20260715.sql` | 仅 Part0~2（样本+cohort） |
| `sql/drop_sample_intermediate_20260715.sql` | cohort 通过后删中间表腾空间 |

## 三月版执行顺序（20260715）

1. `drop_all_jcr_tables_20260715.sql`
2. `run_part01_sample_cohort_20260715.sql`（验漏斗：10 月 ~5401）
3. `run_all_20260715.sql` Part3~7（征信特征+标签）
4. `run_mx_feature_20260715.sql`（马消特征，全渠道 cohort 子集）
5. `run_all_20260715.sql` Part8（拼终表 `jcr_credit_feature_label_full_20260715`）

**口径**：入口 5103 有余额；**Step② pf** = 全渠道无余额（已含5103）+ 60天未提现；**Step③ cohort** = 征信 had。**不用** `*_5103` 后缀字段。

## 十月版 cohort（5401）

- **精确 5401**：`step0d` 从同事 `yye_pril_bal_info_20260623_4` 取 uuid 名单
- **勿用** `jcr_pril_bal_info` 同条件 WHERE 复算（约 5186，差 215）
- **核验**：`select count(1) from jcr_cohort_5401_20260623` 必须 = 5401
