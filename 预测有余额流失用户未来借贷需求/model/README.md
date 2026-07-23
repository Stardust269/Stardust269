# 模型训练（LightGBM）

预测 **zx_balance_label**：锚点后 60 天内 **外部征信循环贷余额是否上升**（剔马消），即是否有 **外部加杠杆/再借贷需求**。

> 任务定义、征信 vs 马消特征是否合理，见 **[任务与特征合理性.md](任务与特征合理性.md)**。

## 目录结构

```
model/
├── config.yaml              # 训练超参与路径
├── requirements.txt
├── sql/export_training_data.sql   # 从 Hive 导出宽表
├── data/                    # 本地训练数据（git 忽略大文件）
├── artifacts/               # 模型与指标输出
├── scripts/
│   ├── train.py             # 训练入口
│   └── generate_demo_data.py
└── src/                     # 特征工程与训练逻辑
```

## 1. 导出数据

SQL 跑完后，在数据平台执行 `sql/export_training_data.sql`，下载为：

```
model/data/training_full.parquet
```

（也支持 `.csv`）

## 2. 安装依赖

```bash
cd model
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## 3. 训练

```bash
python scripts/train.py
```

指定数据路径：

```bash
python scripts/train.py --data data/training_full.parquet
```

## 4. 本地演示（无 Hive 时）

```bash
python scripts/generate_demo_data.py --rows 5000
python scripts/train.py
```

## 特征说明

### 入模逻辑（是否合理）

- **征信特征（循环贷/查询/逾期/信用卡/资质）**：标签由外部征信余额定义 → **主特征，必须使用**
- **马消特征（余额/额度/提现）**：刻画站内行为与资金压力 → **补充特征，预测「是否转向外部借贷」合理**
- 详见 `任务与特征合理性.md`

### 剔除列

| 类型 | 列 | 原因 |
|------|-----|------|
| 泄漏 | `fwd_first_balance`, `fwd_max_balance`, `zx_report_cnt_fwd_60d` | 标签或同窗口未来信息 |
| cohort 恒定 | `had_0_30_zx`, `had_31_60_zx`, `with_0_30`, `with_31_60`, `no_balance_flg_60` | 五条件下无变异 |
| 元数据 | `uuid`, `user_id`, `dt`, `days_dt`, `label_eligible`, `dataset_split` | 非特征 |

### 缺失值

| 类型 | 处理 |
|------|------|
| 数值特征 | 保持 `NaN`，**不填均值**；LightGBM 分裂时学习缺失方向 |
| 类别特征 `m`, `latest_org_type` | `fillna("__MISSING__")` |
| 标签 `zx_balance_label` 缺失 | **删行**（`apply_filters`） |

### 其他

| 类型 | 列 | 处理 |
|------|-----|------|
| 类别特征 | `m`, `latest_org_type` | LightGBM categorical |
| 派生 | `days_since_last_zx` | `days_dt` − `latest_dt_zx`（仅历史报告日期） |

其余宽表数值列（征信 + 马消）在剔除上述列后全部入模。

## 产出

`artifacts/` 下每次训练生成：

- `lgbm_zx_balance_label_<timestamp>.txt` — LightGBM 模型
- `*_metrics.json` — train/val AUC、KS、F1 等
- `*_feature_importance.csv` — 特征重要性
- `*_manifest.json` — 路径与特征列表

## 与 SQL 链路关系

```
run_all_20260715.sql
  → jcr_credit_feature_label_full_20260715
  → export_training_data.sql
  → model/data/training_full.parquet
  → scripts/train.py
  → model/artifacts/
```
