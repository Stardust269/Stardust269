# 预测有余额流失用户未来借贷需求

## 目录结构

| 目录/文件 | 说明 |
|-----------|------|
| `sql/` | 特征加工与标签构建 SQL |
| `sql/run_all_20260623.sql` | **一键全量**（drop + 样本 + cohort + 特征 + 标签） |
| `notion_schema/` | Notion 征信字段字典、项目说明、标签构建文档 |

## 主要文档

- 特征需求清单：`notion_schema/需要加工的数据.md`
- 标签构建说明：`notion_schema/项目说明_标签构建.md`
- **同事样本 SQL 对照**：`notion_schema/项目说明_同事样本SQL对照.md`
- 字段总表：`notion_schema/FIELD_CATALOG.md`
- **一键全量 SQL**：`sql/run_all_20260623.sql`（推荐，drop 后整文件执行）
- 分步特征 SQL：`sql/yye_credit_feature_process.sql`
- **同事样本参考 SQL**：`sql/yye_pril_bal_sample_reference.sql`

## 分析 cohort（5401）

- **精确 5401**：`step0d` 从同事 `yye_pril_bal_info_20260623_4` 取 uuid 名单
- **勿用** `jcr_pril_bal_info` 同条件 WHERE 复算（约 5186，差 215）
- **核验**：`select count(1) from jcr_cohort_5401_20260623` 必须 = 5401
- 测试打分日：2025-11-01
