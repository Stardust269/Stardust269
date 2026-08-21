# 放心借 lookalike 建模（LightGBM + PU）

在**马消存量背景人群**（未标注, U）中，学习**低定价放心借种子用户**（正类, P）的共性，输出 lookalike 评分用于扩量营销。

业务定义见 [`../notion/放心借lookalike.md`](../notion/放心借lookalike.md)：

| 角色 | 定义 |
| --- | --- |
| **P（pu_label=1）** | 利率 &lt; 18%，且**借款当日**有征信报告（`days_dt_zx = lend_date_sj`） |
| **U（pu_label=0）** | 宽表中其余用户（背景约千万级；含隐藏正例） |

特征来源：Hive 宽表 `fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit`（放心借 D 变量 + 腾讯/百行/朴道 + 征信 `latest_*` / `zx_*`）。**不入模**种子规则字段（如 `y_loan_base_rate`、`lend_date_sj`），避免标签泄漏。

## 目录

完整文件说明见文末 **[附录：model/ 文件说明](#附录model-文件说明)**；**全部运行命令**见 **[§7 命令速查](#7-命令速查对话中使用的全部命令)**。

```
model/
├── config*.yaml          # 训练/评估配置（多套数据场景）
├── features/             # 入模特征白名单
├── scripts/              # 命令行入口（训练、评估、探查）
├── src/                  # 核心库（数据、PU、指标、模型 IO）
├── tests/                # 单元测试
├── data/                 # 本地 parquet（gitignore，由云查询机导出后拷入）
└── artifacts/            # 模型与报告输出（gitignore）
```

> **环境分工**：**云查询机**跑 Hive SQL（脚本在仓库 `../sql/`，或你司查询机上的副本）；**云分析机**（本目录）只跑 Python，输入为 `data/*.parquet`。

## 1. 数据准备（云查询机）与分析机输入

Hive / Spark SQL **不在 `model/` 内执行**。请在**云查询机**跑仓库 **`../sql/`**（与 `model/` 同级）下的建表脚本，再通过查询机自带的导出功能下载 parquet 到分析机 `model/data/`。

**仓库内不提供 export SQL**（导出走云查询机界面/工具，无法用固定 SQL 文件完成）。

### 1.1 云查询机 SQL（`放心借客群lookalike/sql/`）

| 类型 | 脚本 | 说明 |
| --- | --- | --- |
| 征信宽表 | `fxj_seed_users_attach_credit_feature.sql` | 融合征信特征宽表 |
| 征信宽表（抽样） | `fxj_seed_users_attach_credit_feature_with_credit_1.sql` | with_credit_1 终表 |
| **PU 建表（全量 U）** | `build_pu_training_table.sql` | 千万级背景打 `pu_label` + 9:1 划分 → `fxj_lookalike_pu_training` |
| **PU 建表（抽样）** | `build_pu_training_table_with_credit_1_sample.sql` | with_credit_1 + 负样本抽（量≈正样本）→ `fxj_lookalike_pu_training_1` |
| 同事样本打标签 | `zyy_fxj_expansion_samples_tagged.sql` | 约 71.5 万行，9:1 划分 |
| 时间切分 train/test | `zyy_fxj_expansion_samples_train_val_test.sql` | train 窗 + with_credit 全量 test |
| 半量抽样 | `zyy_fxj_expansion_samples_tagged_half.sql` | 约 35 万行 |
| TGI 召回切分 | `zyy_fxj_expansion_tgi_recall_samples_train_val_test.sql` | TGI 召回后 train/test |

### 1.2 分析机 parquet（`model/data/`，手动导出后拷入）

| 场景 | 云查询机源表（示例） | 分析机文件名 |
| --- | --- | --- |
| 时间切分 train+val | `..._samples_train_tagged` | `training_pu_train_window.parquet` |
| 时间切分 test | `fxj_ayh_seed_users_expansion_with_credit_test` | `test_window.parquet` |
| 半量 train | `..._tagged_half` | `training_pu_half.parquet` |
| TGI train+val | `..._tgi_recall_samples_train_tagged` | `training_pu_tgi_recall.parquet` |
| TGI test | `..._tgi_recall_samples_test_tagged` | `test_tgi_recall.parquet` |
| 旧全量/抽样 PU | `fxj_lookalike_pu_training` / `_1` | `training_pu.parquet` |

分析机 config 的 `data.input_path` / `test_path` 指向上表 parquet 即可。

训练默认仅使用同事筛选的 **4443 列**特征白名单（`features/colleague_selected_features.txt`），parquet 加载时列裁剪。

**内存优化**（`training.memory` 配置，见 `config_half.yaml`）：
- `float32` 矩阵替代 pandas float64 宽表
- **分片加载**：train/val 按 `dataset_split` predicate pushdown 分别读入，避免全表常驻内存
- 分步构建 `x_train` / `x_val` 后释放 DataFrame；`weighted_naive` 在 `lgb.train` 前释放 `x_train`
- LightGBM `free_raw_data`、仅 val early stopping、跳过 train 全量 predict
- `predict.py` 默认读 `--config` 做 parquet 列裁剪（与训练白名单一致）
- 分块打分走 numpy 矩阵，避免每 chunk 构建 float64 DataFrame
- `max_bin: 127`、`num_threads: 2`

半量导出与训练：

```bash
# 云查询机：跑 ../sql/zyy_fxj_expansion_samples_tagged_half.sql 并导出 → data/training_pu_half.parquet

cd model
python scripts/train.py --config config_half.yaml --data data/training_pu_half.parquet
```

**同事 TGI 时间切分**（train 窗 9:1 + test 从 with_credit 全量宽表按日期，不调参）：

```bash
# 1) 云查询机：../sql/zyy_fxj_expansion_samples_train_val_test.sql
#    train: days_dt_zx < 2026-06-22 → ..._train_tagged（同事样本表）
#    test:  days_dt_zx >= 2026-06-22 从 ..._feature_with_credit 全量宽表筛选
#           → fxj_ayh_seed_users_expansion_with_credit_test
#           勿用 fxj_ayh_seed_users_expansion_tgi_result（TGI 打分结果表）
#    导出 → data/training_pu_train_window.parquet / data/test_window.parquet

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
```

**Top1000 特征试验**（数据/PU/超参与 `config_train_window.yaml` 一致；特征取全量模型 gain Top1000）：

```bash
# 0) 前提：已有全量模型 artifacts/lgbm_fxj_lookalike_pu_train_window_*.{txt,feature_importance.csv}

python scripts/top_feature_importance.py \
  --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv \
  --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
  --top 1000 \
  --out artifacts/top1000_train_window_gain.csv \
  --out-features features/top1000_train_window_gain.txt

python scripts/train.py --config config_train_window_top1000.yaml

python scripts/report_eval.py \
  --config config_train_window_top1000.yaml \
  --model artifacts/lgbm_fxj_lookalike_pu_train_window_top1000_*.txt \
  --chunk-size 30000 \
  --out-dir artifacts/eval_report_train_window_top1000
```

```bash
# Top10 特征重要度（Column_N → 真实字段名）：
# python scripts/top_feature_importance.py \
#   --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv \
#   --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
#   --top 10 \
#   --out artifacts/top10_feature_importance.csv

# 决策树探查（Top10，检验是否存在少量规则即可强区分种子/非种子）：
# python scripts/decision_tree_probe.py \
#   --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv \
#   --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt \
#   --data data/training_pu_train_window.parquet \
#   --max-depth 4
# 训练后在 test 上时间外评估（可加 --plot-test 导出 test 节点统计图）：
# python scripts/decision_tree_probe.py ... --test-data data/test_window.parquet --plot-test
# 已有 .joblib，仅在 test 上评估：
# python scripts/decision_tree_probe.py \
#   --artifact artifacts/dt_probe/dt_probe_top10_*.joblib \
#   --test-data data/test_window.parquet
# 已有 .joblib，画 train 决策树图（用 joblib 内缓存的 train 统计）：
# python scripts/plot_decision_tree.py --artifact artifacts/dt_probe/dt_probe_top10_*.joblib
# 画 test 决策树图（节点统计基于 test 样本）：
# python scripts/plot_decision_tree.py \
#   --artifact artifacts/dt_probe/dt_probe_top10_*.joblib \
#   --split test --test-data data/test_window.parquet
# 已有 .joblib，仅在 test 上评估并出图：
# python scripts/decision_tree_probe.py \
#   --artifact artifacts/dt_probe/dt_probe_top10_*.joblib \
#   --test-data data/test_window.parquet
```

**TGI 回归后样本**（训练参数与 `config_train_window.yaml` 完全一致；test TGI 表用固定绝对人数分档）：

```bash
# 1) 云查询机：../sql/zyy_fxj_expansion_tgi_recall_samples_train_val_test.sql
#    train/val: tgi_recall_samples，days_dt_zx < 2026-06-22
#    test:      tgi_recall_samples_test，days_dt_zx >= 2026-06-22
#    导出 → data/training_pu_tgi_recall.parquet / data/test_tgi_recall.parquet

cd model
python scripts/train.py --config config_train_tgi_recall.yaml --data data/training_pu_tgi_recall.parquet

# 3) 评估（TGI 分档=46731/46732 绝对人数，与过滤前 test 对齐；p00=剩余全量）
python scripts/report_eval.py \
  --config config_train_tgi_recall.yaml \
  --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt \
  --chunk-size 30000 \
  --out-dir artifacts/eval_report_tgi_recall
```

**交叉评估（同事对比用）**：TGI 召回后训练的模型 → **TGI 召回前**全量 test（`test_window.parquet`）：

```bash
# 确保已有：
#   - artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt（及 *_features.json）
#   - data/test_window.parquet（过滤前 with_credit test，~93 万行）

python scripts/report_eval.py \
  --config config_eval_tgi_train_pretgi_test.yaml \
  --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt \
  --test-only \
  --chunk-size 20000 \
  --out-dir artifacts/eval_report_tgi_train_on_pretgi_test
```

TGI 表用 **fixed** 固定人数分档，可与过滤前模型的 TGI 表直接对比。

**Elkanoto 对比试验**（同事建议的传统 PU 框架；**比 weighted_naive 更耗内存**）：

```bash
cd model
python scripts/train.py --config config_train_tgi_recall_elkanoto.yaml --data data/training_pu_tgi_recall.parquet

python scripts/report_eval.py \
  --config config_train_tgi_recall_elkanoto.yaml \
  --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_elkanoto_*.joblib \
  --chunk-size 30000 \
  --out-dir artifacts/eval_report_tgi_recall_elkanoto
```

内存差异要点：`weighted_naive` 走原生 `lgb.train`，可用 `free_raw_data`、仅 val early stopping、训练后释放 `x_train`；`elkanoto` 走 `pulearn` + sklearn `LGBMClassifier`，且从未标注中再 hold-out 估计类先验，峰值通常更高。OOM 时优先降 `unlabeled_subsample_ratio` 或先用 `config_half.yaml` 半量数据试跑。

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

---

## 7. 命令速查（对话中使用的全部命令）

以下汇总本项目中**对话与实践里出现过的命令**（默认在 `model/` 目录下执行）。`*` 请替换为实际模型时间戳或 glob 展开后的路径。

**工作目录**（项目迁移后）：

```bash
cd /home/finance/App/jupyter-ide-bigdata.msxf.lo/.IDE/work/ai_decision/jiangchengrun/fxj_lookalike/model
```

### 7.1 环境与依赖

| 命令 | 说明 |
| --- | --- |
| `python -m venv .venv && source .venv/bin/activate` | 创建并激活 Python 虚拟环境 |
| `pip install -r requirements.txt` | 安装 LightGBM、pandas、pyarrow、pulearn 等依赖 |
| `conda install -c conda-forge graphviz` | 安装系统 `dot` 二进制，决策树出图必需（`pip install graphviz` 不够） |
| `python -m pytest tests/ -q` | 运行单元测试（TGI 分档、树图 DOT、Top 特征工具） |

### 7.2 数据准备（云查询机 → parquet）

在**云查询机**执行 Hive SQL（仓库脚本在 `../sql/`），**导出 parquet 用查询机界面/工具**（仓库无 export SQL），拷到分析机 `model/data/`：

| 步骤 | 云查询机 SQL（`../sql/`） | 分析机 parquet |
| --- | --- | --- |
| 征信宽表（前置） | `fxj_seed_users_attach_credit_feature.sql` | — |
| **PU 建表（全量 U，旧路径）** | `build_pu_training_table.sql` | `training_pu.parquet`（可选） |
| **PU 建表（抽样，旧路径）** | `build_pu_training_table_with_credit_1_sample.sql` | — |
| 同事样本打标签 + 9:1 | `zyy_fxj_expansion_samples_tagged.sql` | — |
| 时间切分 train/test | `zyy_fxj_expansion_samples_train_val_test.sql` | `training_pu_train_window.parquet` / `test_window.parquet` |
| 半量抽样（省内存） | `zyy_fxj_expansion_samples_tagged_half.sql` | `training_pu_half.parquet` |
| TGI 召回样本切分 | `zyy_fxj_expansion_tgi_recall_samples_train_val_test.sql` | `training_pu_tgi_recall.parquet` / `test_tgi_recall.parquet` |

> 本目录**不含 SQL 文件**；分析机只读 `data/*.parquet`，不连 Hive。

### 7.3 训练

| 命令 | 说明 |
| --- | --- |
| `python scripts/train.py --data data/training_pu.parquet` | **首次全量训练**（默认 `config.yaml`：elkanoto + U 下采样 20%） |
| `python scripts/train.py --config config_half.yaml --data data/training_pu_half.parquet` | **半量样本** weighted_naive，128G 分析机省内存 |
| `python scripts/train.py --config config_train_window.yaml --data data/training_pu_train_window.parquet` | **主流程**：时间切分 train 窗 + weighted_naive + 全量 U |
| `python scripts/train.py --config config_train_tgi_recall.yaml --data data/training_pu_tgi_recall.parquet` | **TGI 召回后样本**训练，超参与 train_window 一致 |
| `python scripts/train.py --config config_train_tgi_recall_elkanoto.yaml --data data/training_pu_tgi_recall.parquet` | TGI 样本 + **elkanoto** PU（产出 `.joblib`，更耗内存） |
| `python scripts/train.py --config config_train_window_top1000.yaml` | **Top1000 特征**训练（需先生成 `features/top1000_train_window_gain.txt`） |
| `python scripts/generate_demo_data.py --rows 20000` | 无集群数据时生成合成 parquet |
| `python scripts/train.py` | 使用默认 `config.yaml` + 默认数据路径 |

### 7.4 评估与报告

| 命令 | 说明 |
| --- | --- |
| `python scripts/report_eval.py --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --train-data data/training_pu_train_window.parquet --test-data data/test_window.parquet --chunk-size 30000 --out-dir artifacts/eval_report` | **完整报告**：train/val/test AUC + test TGI 百分位表（低内存串行） |
| `python scripts/report_eval.py --config config_train_window.yaml --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --chunk-size 30000 --out-dir artifacts/eval_report` | 同上，路径从 config 读取 |
| `python scripts/report_eval.py --config config_train_tgi_recall.yaml --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt --chunk-size 30000 --out-dir artifacts/eval_report_tgi_recall` | TGI 召回模型评估（fixed 绝对人数分档） |
| `python scripts/report_eval.py --config config_eval_tgi_train_pretgi_test.yaml --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt --test-only --chunk-size 20000 --out-dir artifacts/eval_report_tgi_train_on_pretgi_test` | **交叉评估**：TGI 训模型 → 过滤前 `test_window.parquet` |
| `python scripts/report_eval.py --config config_train_window_top1000.yaml --model artifacts/lgbm_fxj_lookalike_pu_train_window_top1000_*.txt --chunk-size 30000 --out-dir artifacts/eval_report_train_window_top1000` | Top1000 模型完整评估 |
| `python scripts/report_eval.py --config config_train_tgi_recall_elkanoto.yaml --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_elkanoto_*.joblib --chunk-size 30000 --out-dir artifacts/eval_report_tgi_recall_elkanoto` | Elkanoto 模型评估 |
| `python scripts/evaluate.py --config config_train_window.yaml --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --data data/test_window.parquet --chunk-size 30000` | **仅 test** 快速 AUC / precision / recall |
| `python scripts/tgi_top_percentiles.py --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --data data/test_window.parquet --chunk-size 30000 --patch-csv artifacts/eval_report/eval_report_*_test_tgi_percentile.csv` | 已有报告时**仅补算** p99~p96 顶部百分位 |

### 7.5 打分扩量

| 命令 | 说明 |
| --- | --- |
| `python scripts/predict.py --config config_train_window.yaml --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --data data/test_window.parquet --out data/test_window_scores.parquet --chunk-size 30000` | 对 test 集分块打分（`--config` 做列裁剪，省内存） |
| `python scripts/predict.py --config config_train_tgi_recall.yaml --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt --data data/test_tgi_recall.parquet --out data/test_tgi_recall_scores.parquet --chunk-size 30000` | TGI test 打分 |
| `python scripts/predict.py --model artifacts/lgbm_fxj_lookalike_pu_*.joblib --data data/background_scoring.parquet --out data/lookalike_top.parquet --top-k 500000 --chunk-size 30000` | 背景人群 TopK 扩量名单（elkanoto joblib 或任意模型） |

### 7.6 特征重要度与 TopK 筛选

| 命令 | 说明 |
| --- | --- |
| `python scripts/top_feature_importance.py --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --top 10 --out artifacts/top10_feature_importance.csv` | 查看 Top10 gain，并将 `Column_N` 译为真实字段名 |
| `python scripts/top_feature_importance.py --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --top 1000 --out artifacts/top1000_train_window_gain.csv --out-features features/top1000_train_window_gain.txt` | 导出 **Top1000 训练白名单**（供 `config_train_window_top1000.yaml`） |
| `python scripts/repair_lgb_features.py --model artifacts/lgbm_fxj_lookalike_pu_tgi_recall_*.txt --config config_train_tgi_recall.yaml --data data/training_pu_tgi_recall.parquet` | 旧模型仅有 `Column_0` 占位名时，**补写** `*_features.json`（无需重训；否则 AUC=0.5） |

### 7.7 决策树探查与可视化

| 命令 | 说明 |
| --- | --- |
| `python scripts/decision_tree_probe.py --importance artifacts/lgbm_fxj_lookalike_pu_train_window_*_feature_importance.csv --model artifacts/lgbm_fxj_lookalike_pu_train_window_*.txt --data data/training_pu_train_window.parquet --max-depth 4` | Top 特征浅层决策树，检验是否少量规则即可区分种子 |
| `python scripts/decision_tree_probe.py ... --test-data data/test_window.parquet --plot-test` | 在 test 上时间外评估并导出 test 节点统计图 |
| `python scripts/decision_tree_probe.py --artifact artifacts/dt_probe/dt_probe_top10_*.joblib --test-data data/test_window.parquet` | 已有探查 joblib，**跳过训练**仅在 test 上评估 |
| `python scripts/plot_decision_tree.py --artifact artifacts/dt_probe/dt_probe_top10_*.joblib` | 用 joblib 内缓存的 **train** 节点统计出树图 |
| `python scripts/plot_decision_tree.py --artifact artifacts/dt_probe/dt_probe_top10_*.joblib --split test --test-data data/test_window.parquet` | 基于 **test** 样本重算节点统计并出图 |

### 7.8 常用参数说明

| 参数 | 含义 |
| --- | --- |
| `--config` | YAML 配置路径；决定数据路径、白名单、PU 方法、TGI 分档口径 |
| `--data` / `--train-data` / `--test-data` | 覆盖 config 中的 parquet 路径 |
| `--chunk-size 30000`（或 `20000`） | 分块打分/评估行数；OOM 时调小 |
| `--test-only` | `report_eval` 跳过 train/val，仅评 test |
| `--top-k` | `predict` 仅输出分数最高的 K 行 |
| `--out-features` | `top_feature_importance` 导出训练用特征 txt |

---

## 附录：model/ 文件说明

以下为 `model/` 目录下**每个文件**的用途说明（按路径排序）。`data/`、`artifacts/` 为运行时目录，内容不入 git。

### 根目录

| 文件 | 说明 |
| --- | --- |
| `README.md` | 本说明文档：业务背景、训练/评估命令、PU 方法、内存优化、文件索引 |
| `requirements.txt` | Python 依赖（LightGBM、pandas、pyarrow、pulearn、sklearn 等） |
| `.gitignore` | 忽略 `data/*.parquet`、`artifacts/`、虚拟环境等；保留 `features/colleague_selected_features.txt` |
| `训练进展与同事确认事项.md` | 训练进展同步文档：数据链路、内存优化、结果摘要、待同事确认问题 |
| `config.yaml` | **默认/全量**训练配置：`elkanoto` PU、`unlabeled_subsample_ratio: 0.2`、同事 4443 列白名单 |
| `config_half.yaml` | **半量样本**训练（约 35 万行）：`weighted_naive`、省内存，数据 `training_pu_half.parquet` |
| `config_train_window.yaml` | **主流程**：时间切分 train 窗 + weighted_naive；数据 `training_pu_train_window.parquet` |
| `config_train_window_top1000.yaml` | 与 `config_train_window` 同数据/超参，特征换为全量模型 gain **Top1000** 白名单 |
| `config_train_tgi_recall.yaml` | TGI 召回后样本训练；参数与 train_window 一致；含 fixed TGI 分档评估配置 |
| `config_train_tgi_recall_elkanoto.yaml` | TGI 召回样本 + **elkanoto** PU；产出 `.joblib` |
| `config_eval_tgi_train_pretgi_test.yaml` | **仅评估**：TGI 训模型 → 过滤前 `test_window.parquet` 交叉对比 |

### features/（特征白名单）

| 文件 | 说明 |
| --- | --- |
| `colleague_selected_features.txt` | 同事筛选 **4443 列**特征白名单（每行一列）；训练默认 `feature_list_path` |
| `colleague_selected_features.json` | 同上，JSON 数组格式 |
| `top1000_train_window_gain.txt` | **运行时生成**：全量模型 gain Top1000 特征名；由 `top_feature_importance.py --out-features` 产出 |

> **Hive SQL** 不在 `model/` 内。建表脚本在仓库 **`../sql/`**（与 `model/` 同级），在**云查询机**执行；**不提供 export SQL**，parquet 由查询机导出后拷至 `data/`。

### 上级目录 `../sql/`（云查询机，与 model 同级）

| 文件 | 说明 |
| --- | --- |
| `build_pu_training_table.sql` | 全量背景 U 打 `pu_label` + 9:1 → `fxj_lookalike_pu_training` |
| `build_pu_training_table_with_credit_1_sample.sql` | with_credit_1 + 负样本抽样 → `fxj_lookalike_pu_training_1` |
| `fxj_seed_users_attach_credit_feature.sql` | 征信特征宽表 |
| `fxj_seed_users_attach_credit_feature_with_credit_1.sql` | with_credit_1 宽表 |
| `zyy_fxj_expansion_samples_tagged.sql` | 同事样本打标签 + 9:1 |
| `zyy_fxj_expansion_samples_train_val_test.sql` | 时间切分 train/test |
| `zyy_fxj_expansion_samples_tagged_half.sql` | 半量抽样 |
| `zyy_fxj_expansion_tgi_recall_samples_train_val_test.sql` | TGI 召回样本切分 |
| 其他 | `fxj_seed_credit_account_part2_light.sql`、`同事样例_*.sql` 等 |

仓库内**无** `export_*.sql`；Hive 表 → parquet 在云查询机界面导出。

### scripts/（命令行入口）

| 文件 | 说明 |
| --- | --- |
| `train.py` | **训练主入口**：读 config → 加载 parquet → PU + LightGBM → 保存模型与指标 |
| `predict.py` | 对背景人群**分块打分**，输出 lookalike 分数 parquet（支持 `--config` 列裁剪） |
| `report_eval.py` | 生成 **train/val/test** 完整评估报告（AUC + TGI 百分位表，低内存串行） |
| `evaluate.py` | 在带标签 test 上计算 AUC / precision / recall 等（支持 `--scores` 预打分 join） |
| `tgi_top_percentiles.py` | 仅补算 TGI 顶部百分位（p99~p96），无需重跑完整 report_eval |
| `top_feature_importance.py` | 从 `*_feature_importance.csv` 提取 TopK gain，并导出训练用特征 txt |
| `decision_tree_probe.py` | Top 特征浅层决策树探查（规则可读性、train/test 时间外评估） |
| `plot_decision_tree.py` | 从 `dt_probe` 的 joblib 导出带种子数/召回标注的树图（DOT/PNG） |
| `repair_lgb_features.py` | 为旧版 `Column_0` 命名的 `.txt` 模型补写 `*_features.json` sidecar |
| `generate_demo_data.py` | 无集群数据时生成小规模合成 parquet，用于本地冒烟 |
| `materialize_colleague_features.py` | 一次性脚本：将内嵌的同事特征列表写入 `features/colleague_selected_features.*` |

### src/（核心库）

| 文件 | 说明 |
| --- | --- |
| `config_loader.py` | 加载 YAML config；将相对路径解析为相对 config 文件的绝对路径 |
| `dataset.py` | Parquet/CSV 加载、列裁剪、过滤、train/val 分片加载、`to_xy` 矩阵构建 |
| `features.py` | 特征白名单、泄漏字段排除、入模列解析、特征分组统计 |
| `preprocess.py` | 宽表 → float32 numpy 训练矩阵；类别列编码 |
| `memory_utils.py` | 内存相关默认配置（`release_train_matrix`、`load_splits_separately` 等） |
| `train_pu.py` | PU 训练实现：`weighted_naive`（原生 lgb）/ `elkanoto`（pulearn）；模型落盘 |
| `model_io.py` | 模型加载、`ScoringModel` 分块预测、特征 sidecar（`*_features.json`） |
| `metrics.py` | PU 排序指标、TGI 百分位表（ratio/fixed 分档）、`evaluate_scores` |
| `top_features.py` | 特征重要度表解析、TopK 特征名提取、`Column_N` → 真实字段名映射 |
| `tree_viz.py` | 决策树 DOT/PNG 导出；节点种子数、seed%、seed recall 标注 |

### tests/（单元测试）

| 文件 | 说明 |
| --- | --- |
| `test_tgi_fixed_bands.py` | TGI 固定人数分档（`tgi_band_mode: fixed`）逻辑测试 |
| `test_tree_viz_dot.py` | 决策树 DOT 输出语法与标注字段测试 |
| `test_top_features.py` | TopK 特征名提取与特征白名单写入测试 |

### 运行时目录（无固定文件，gitignore）

| 路径 | 说明 |
| --- | --- |
| `data/` | 本地 parquet/csv：训练集、测试集、打分结果等 |
| `artifacts/` | 模型（`.txt` / `.joblib`）、`*_feature_importance.csv`、评估报告、决策树探查产物 |

### 常见产出文件命名（artifacts/）

训练 `weighted_naive` 后典型产物：

- `lgbm_fxj_lookalike_pu_<场景>_<时间戳>.txt` — LightGBM 模型
- `lgbm_*_<时间戳>_features.json` — 入模特征名 sidecar（打分/评估必需）
- `lgbm_*_<时间戳>_feature_importance.csv` — gain 排序，供 TopK 特征筛选
- `lgbm_*_<时间戳>_metrics.json` — 验证集 PU 监控指标

`elkanoto` 产出为 `.joblib`（内含 sklearn 管线 + features 列表）。
