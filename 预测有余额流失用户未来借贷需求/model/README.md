# 模型训练（LightGBM）

预测 **zx_balance_label**（未来 60 天征信余额是否增加）的二分类模型。

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

| 类型 | 列 | 处理 |
|------|-----|------|
| 标签 | `zx_balance_label` | 0/1 |
| 划分 | `dataset_split` | 使用 SQL 预划分的 train/val |
| **剔除（泄漏）** | `fwd_first_balance`, `fwd_max_balance` | 标签直接相关 |
| **剔除（元数据）** | `uuid`, `user_id`, `dt`, `days_dt`, `label_eligible` | 不入模 |
| 类别特征 | `m`, `latest_org_type` | LightGBM categorical |
| 派生 | `days_since_last_zx` | 由 `days_dt` - `latest_dt_zx` |

其余宽表数值列（循环贷征信、逾期、查询、信用卡、马消等）全部作为数值特征入模。

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
