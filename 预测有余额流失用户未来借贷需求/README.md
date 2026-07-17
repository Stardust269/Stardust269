# 预测有余额流失用户未来借贷需求

## 目录结构

| 目录/文件 | 说明 |
|-----------|------|
| `sql/` | 特征加工与标签构建 SQL |
| `notion_schema/` | Notion 征信字段字典、项目说明、标签构建文档 |

## 主要文档

- 特征需求清单：`notion_schema/需要加工的数据.md`
- 标签构建说明：`notion_schema/项目说明_标签构建.md`
- **同事样本 SQL 对照**：`notion_schema/项目说明_同事样本SQL对照.md`
- 字段总表：`notion_schema/FIELD_CATALOG.md`
- 特征 SQL：`sql/yye_credit_feature_process.sql`
- **删除全部 jcr 表**：`sql/drop_all_jcr_tables.sql`
- **同事样本参考 SQL**：`sql/yye_pril_bal_sample_reference.sql`

## 分析 cohort（5401）

- **口径**：2 段 had + `no_balance_flg_60` + 60 天内无提现（同事最后一查确认版）
- **产出表**：`jcr_credit_feature_label_20260623`（`cohort_eligible=1` 应为 5401 行）
- **核验**：`sql/verify_cohort_5401.sql`
- 测试打分日：2025-11-01
