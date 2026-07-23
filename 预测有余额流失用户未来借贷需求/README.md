# 预测有余额流失用户未来借贷需求

## 主脚本

| 文件 | 说明 |
|------|------|
| `sql/run_all_20260715.sql` | **一键全量**（样本 + 征信特征 + 标签 + 马消，insert overwrite） |
| `sql/yye_pril_bal_sample_reference_20260715.sql` | 同事 reference（产出 `yye_pril_bal_info_20260715_1`） |
| `sql/drop_all_jcr_tables_20260715.sql` | 清表重建时用 |
| `sql/list_project_tables.sql` | 查看 `jcr_*` 表 |
| `sql/preview_output_20260715.sql` | **预览产出**：行数、样例行、缺失率（只读） |

## 执行顺序

1. 同事跑 `yye_pril_bal_sample_reference_20260715.sql` → `yye_pril_bal_info_20260715_1`
2. 整文件提交 `run_all_20260715.sql`（Part 1~9）

仅刷新 train/val 划分：重跑 Part 7~8 即可，无需重算征信特征。

首跑无表：将 `insert overwrite` 改为 `create table ... as` 执行一次。  
清表：`drop_all_jcr_tables_20260715.sql` 后再跑全量。

## 样本口径（20260715）

| 项目 | 说明 |
|------|------|
| 左表 | `yye_pril_bal_info_20260715_1` |
| 我方加工 | had/with → `jcr_pril_bal_info_20260715` → cohort 五条件 |
| 锚点 | 全部 `days_dt`（无 `days_dt_1`） |
| 训练样本 | **仅** `m ∈ {202508, 202509, 202510}`，约 15836 人 |
| 划分 | `dataset_split`：train / val（仅 8/9/10 月，hash 8:2），**无 11 月、无 test** |

## cohort 五条件

```sql
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
```

## 产出表

终表：`jcr_credit_feature_label_full_20260715`

**查看实际数据**：跑完 `run_all_20260715.sql` 后，在数据平台执行 `sql/preview_output_20260715.sql`（分段执行即可），可看到各表行数、终表样例、train/val 划分与标签分布。

## 文档

- `项目说明_三月样本20260715.md` — 样本口径
- `项目说明_标签构建.md` — 标签与 train/val 划分
- `notion_schema/需要加工的数据.md` — 特征清单（Notion 原始）
- `项目说明_特征覆盖与运行.md` — 特征对照与运行记录
