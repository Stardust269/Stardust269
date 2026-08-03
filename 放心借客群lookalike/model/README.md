# 放心借 lookalike 建模（LightGBM + PU）

在**马消存量背景人群**（未标注, U）中，学习**低定价放心借种子用户**（正类, P）的共性，输出 lookalike 评分用于扩量营销。

业务定义见 [`../notion/放心借lookalike.md`](../notion/放心借lookalike.md)：

| 角色 | 定义 |
| --- | --- |
| **P（pu_label=1）** | 利率 &lt; 18%，且**借款当日**有征信报告（`days_dt_zx = lend_date_sj`） |
| **U（pu_label=0）** | 宽表中其余用户（背景约千万级；含隐藏正例） |

特征来源：Hive 宽表 `fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit`（放心借 D 变量 + 腾讯/百行/朴道 + 征信 `latest_*` / `zx_*`）。**不入模**种子规则字段（如 `y_loan_base_rate`、`lend_date_sj`），避免标签泄漏。

## 目录

```
model/
├── config.yaml
├── requirements.txt
├── sql/
│   ├── build_pu_training_table.sql   # Hive 打 pu_label + split
│   └── export_training_data.sql
├── scripts/
│   ├── train.py
│   ├── predict.py
│   └── generate_demo_data.py
├── data/          # 本地数据（gitignore）
└── artifacts/     # 模型输出（gitignore）
```

## 1. Hive 准备

```bash
# 1) 征信特征宽表（若未跑）
# 放心借客群lookalike/sql/fxj_seed_users_attach_credit_feature.sql

# 2) PU 训练表
# model/sql/build_pu_training_table.sql

# 3) 导出
# model/sql/export_training_data.sql → 下载为 data/training_pu.parquet
```

扩量宽表**不含** `y_loan_base_rate` / `lend_date_sj`：`build_pu_training_table.sql` 已 join `zxt_5789_cust_detail_0630` 打 `pu_label`，并 join MS13（`standard_score` → `ms13_score`）。宽表里的 `label` 列**不是** PU 正类标签，请用 `pu_label`。字段核验见 `sql/verify_wide_table_columns.sql`。

## 2. 本地训练

```bash
cd model
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scripts/train.py
```

无集群数据时：

```bash
python scripts/generate_demo_data.py --rows 20000
python scripts/train.py
```

## 3. PU 方法（`config.yaml` → `pu.method`）

| 方法 | 说明 |
| --- | --- |
| **elkanoto**（默认） | `pulearn.ElkanotoPuClassifier` + `LGBMClassifier`，从未标注集中 hold-out 估计类先验 |
| **weighted_naive** | 原生 LightGBM，`sample_weight`：P=1，U=`unlabeled_weight`（弱负例近似） |

未标注量极大时，训练集对 U 做 `unlabeled_subsample_ratio` 下采样（验证集仍全量）。

## 4. 指标解读

验证集打印 `auc_p_vs_u`、`precision_at_1pct` 等：将 U 临时当作负例，**仅作训练监控**，不代表真实泛化 AUC。更关注 `score_gap_pos_minus_unl` 与 Top 分位中正类占比。

## 5. 打分扩量

```bash
python scripts/predict.py \
  --model artifacts/lgbm_fxj_lookalike_pu_YYYYMMDD_HHMMSS.joblib \
  --data data/background_scoring.parquet \
  --out data/lookalike_top.parquet \
  --top-k 500000
```

## 6. 与 Notion 策略对齐（可选过滤）

`config.yaml` → `filter.unlabeled_ms13_min: 630` 可对**未标注**人群施加 ms13 下限（种子不筛）。多头等特征已在宽表中，建模阶段不做硬过滤。
