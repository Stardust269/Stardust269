# 预测有余额流失用户未来借贷需求

## 目录结构

| 目录/文件 | 说明 |
|-----------|------|
| `sql/` | 特征加工与标签构建 SQL |
| `notion_schema/` | Notion 征信字段字典、项目说明、标签构建文档 |

## 主要文档

- 特征需求清单：`notion_schema/需要加工的数据.md`
- 标签构建说明：`notion_schema/项目说明_标签构建.md`
- 字段总表：`notion_schema/FIELD_CATALOG.md`
- 特征 SQL：`sql/yye_credit_feature_process.sql`

## 训练 cohort

- 2025 年 8 / 9 / 10 月
- 测试打分日：2025-11-01
