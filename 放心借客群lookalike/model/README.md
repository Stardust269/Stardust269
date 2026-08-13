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
│   ├── build_pu_training_table.sql   # 全量 U 打 pu_label + split
│   ├── build_pu_training_table_with_credit_1_sample.sql  # with_credit_1 + 负样本抽（量=正样本）
│   ├── export_training_data.sql
│   └── export_training_data_tagged_half.sql   # 同事 tagged 半量 → training_pu_half.parquet
├── config_half.yaml     # 半量训练配置（约 35 万行，省内存）
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

# 2) PU 训练表（二选一）
# 全量：model/sql/build_pu_training_table.sql
# 抽样（推荐先训）：with_credit_1 脚本 + build_pu_training_table_with_credit_1_sample.sql

# 3) 导出 → data/training_pu.parquet（默认 fxj_lookalike_pu_training_1）
# model/sql/export_training_data.sql
```

若宽表无 `y_loan_base_rate` / `lend_date_sj`（纯背景表），请在 `build_pu_training_table.sql` 中改为 join 种子清单表打 `pu_label`。

**同事 50 万负样本表**（`zyy_fxj_ayh_seed_users_expansion_samples`）请用 `sql/zyy_fxj_expansion_samples_tagged.sql` 打 `pu_label` + **9:1** `dataset_split`。分析机内存不足时，再跑 **`sql/zyy_fxj_expansion_samples_tagged_half.sql`**（从 tagged 约 70 万行各抽 50% → 约 35 万行）。

训练默认仅使用同事筛选的 **4443 列**特征白名单（`features/colleague_selected_features.txt`），parquet 加载时列裁剪。

**内存优化**（`training.memory` 配置，见 `config_half.yaml`）：
- `float32` 矩阵替代 pandas float64 宽表
- 分步构建 `x_train` / `x_val` 后释放 DataFrame
- LightGBM `free_raw_data`、仅 val early stopping、跳过 train 全量 predict
- `max_bin: 127`、`num_threads: 2`

半量导出与训练：

```bash
# Hive：model/sql/export_training_data_tagged_half.sql → 下载为 data/training_pu_half.parquet

cd model
python scripts/train.py --config config_half.yaml --data data/training_pu_half.parquet
```

**同事 TGI 时间切分**（train 窗 9:1 + test 从 with_credit 全量宽表按日期，不调参）：

```bash
# 1) Hive：sql/zyy_fxj_expansion_samples_train_val_test.sql
#    train: days_dt_zx < 2026-06-22 → ..._train_tagged（同事样本表）
#    test:  days_dt_zx >= 2026-06-22 从 ..._feature_with_credit 全量宽表筛选
#           → fxj_ayh_seed_users_expansion_with_credit_test
#           勿用 fxj_ayh_seed_users_expansion_tgi_result（TGI 打分结果表）

# 2) 导出
# model/sql/export_training_data_train_window.sql → data/training_pu_train_window.parquet
# model/sql/export_test_window_data.sql           → data/test_window.parquet

cd model
python scripts/train.py --config config_train_window.yaml --data data/training_pu_train_window.parquet

# 3) test 评估（不参与 fit；test 为全量背景，行数可能远大于 train 窗）
python scripts/predict.py \
  --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
  --data data/test_window.parquet \
  --out data/test_window_scores.parquet

# 4) 完整评估报告（串行低内存：train → valid → test）
python scripts/report_eval.py \
  --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
  --train-data data/training_pu_train_window.parquet \
  --test-data data/test_window.parquet \
  --chunk-size 30000 \
  --out-dir artifacts/eval_report

# 若仅需 test 快速指标：
# python scripts/evaluate.py --model ... --data data/test_window.parquet

# 已有 test 分数时，仅补算 p99~p96（推荐 --model 避免 join 错位）：
# python scripts/tgi_top_percentiles.py \
#   --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
#   --data data/test_window.parquet \
#   --chunk-size 30000 \
#   --patch-csv artifacts/eval_report/eval_report_*_test_tgi_percentile.csv

# Top10 特征重要度（Column_N → 真实字段名）：
# python scripts/top_feature_importance.py \
#   --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv \
#   --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
#   --top 10 \
#   --out artifacts/top10_feature_importance.csv
```

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
