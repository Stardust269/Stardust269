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
| **20260715**（三月版） | `sql/run_all_20260715.sql` | **八月~十月** cohort **~1.6w**（0623 同口径×3） |

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

### 三月样本（~1.5w）

| 文件 | 说明 |
|------|------|
| `sql/run_all_20260715.sql` | **一键全量**（征信特征 + 标签 + 马消关联） |
| `sql/yye_pril_bal_sample_reference_20260715.sql` | 同事参考 SQL（样本 + 马消特征） |
| `sql/drop_all_jcr_tables_20260715.sql` | 删除 jcr_*_20260715 表 |

## 三月版执行顺序（20260715）

1. **同事侧**（或对照参考 SQL）：跑 `yye_pril_bal_sample_reference_20260715.sql`  
   → 产出 `ayh_feature_pril_bal_crdt_lim_yx`、`ayh_feature_wdraw_fq_suc`
2. **我方征信侧**：跑 `run_all_20260715.sql`  
   → 终表 `jcr_credit_feature_label_full_20260715`

## 十月版 cohort（5401）

- **精确 5401**：`step0d` 从同事 `yye_pril_bal_info_20260623_4` 取 uuid 名单
- **勿用** `jcr_pril_bal_info` 同条件 WHERE 复算（约 5186，差 215）
- **核验**：`select count(1) from jcr_cohort_5401_20260623` 必须 = 5401
