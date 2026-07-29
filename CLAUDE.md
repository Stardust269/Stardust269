# CLAUDE.md — CreditDemand-FE 项目指令

> Claude Code 在每次会话启动时自动加载本文件。保持简洁，详细内容通过引用 `docs/` 下的文档按需加载。

---

## 项目概述

**CreditDemand-FE**：基于征信报告数据的用户需求预测特征工程项目。

- **完整业务背景与范围** → 读 `docs/project_brief.md`
- **当前进度与待办** → 读 `docs/project_status.md`（每次开工必读，收工必更新）
- **新任务拆解格式** → 使用 `docs/templates/fixed_task_template.md`

---

## 技术栈

- Python 3.10+
- pandas / numpy / pyarrow（数据处理）
- scikit-learn / lightgbm / xgboost（建模）
- shap（可解释性）
- pytest（测试）
- 配置：YAML（`config/` 目录）

---

## 常用命令

```bash
# 环境
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 测试
pytest tests/ -v

# 运行特征流水线（脚手架就绪后）
python -m src.pipeline.run_features --config config/paths.yaml

# 运行基线训练（脚手架就绪后）
python -m src.pipeline.run_train --config config/model.yaml
```

---

## 目录约定

```
docs/           # 项目文档（简报、状态、字典、模板）
config/         # YAML 配置（路径、特征参数、模型参数）
data/           # 数据文件（已 gitignore，禁止提交真实数据）
src/
  data/         # 加载、清洗、标签构建
  features/     # 按特征域拆分的特征计算模块
  models/       # 训练、评估、解释
  pipeline/     # 端到端编排
  utils/        # 日志、IO、时间窗口等工具
notebooks/      # EDA 与探索性实验
tests/          # 单元测试（与 src/ 结构对应）
experiments/    # 实验产出（模型、报告、图表）
```

---

## 开发规范

### 代码风格

- 遵循 PEP 8；函数与变量用 `snake_case`，类用 `PascalCase`
- 所有特征计算函数必须有 docstring，说明输入字段、输出特征、时间窗口
- 魔法数字外置到 `config/features.yaml`
- 每个特征域一个模块，如 `src/features/f03_repayment.py`

### 特征工程规则

- 特征命名：`{域代码}_{聚合}_{窗口}_{字段}`（详见 project_brief 4.3 节）
- **时间泄露禁止**：特征只能使用 `report_date`（或等价快照日）之前的信息
- 每个特征函数配套 pytest 用例，使用合成小数据集验证
- 新特征必须登记到 `docs/feature_dictionary.md`

### 数据安全（强制）

- **禁止**读取、输出或提交 `data/raw/` 中的真实个人信息
- **禁止**将含 PII 的内容写入日志、注释或 git 提交
- 开发调试使用脱敏样例或合成数据（`tests/fixtures/`）
- 大数据文件只通过 `config/paths.yaml` 引用路径

### Git 规范

- 分支命名：`feature/<描述>`、`fix/<描述>`
- 提交信息：`<类型>: <简述>`（feat / fix / docs / test / refactor）
- 不直接推送到 `main`

---

## 工作流程

### 每次会话开始

1. 读取 `docs/project_status.md`，了解当前阶段与阻塞项
2. 读取 `docs/project_brief.md` 中与当前任务相关的章节
3. 确认待办优先级后再动手

### 执行单个任务

1. 用 `docs/templates/fixed_task_template.md` 填写或确认任务卡
2. 先写测试或验证脚本，再实现功能（TDD 优先）
3. 运行 `pytest` 确保无回归
4. 更新 `docs/project_status.md`（完成项、新发现、阻塞项）
5. 若产出新特征/字段，同步更新对应字典文档

### 每次会话结束

- 更新 `docs/project_status.md` 的「会话记录」与「下一步」
- 若有架构决策变更，回写 `docs/project_brief.md` 相关章节

---

## 禁止事项

- 不要在没有真实数据的情况下编造字段统计结果（缺失率、分布等）
- 不要跳过特征单元测试直接提交特征代码
- 不要在 notebook 中写生产逻辑；notebook 仅用于 EDA，可复用逻辑迁入 `src/`
- 不要一次性生成全部 500+ 特征；按特征域分批迭代，每批验证后再扩展
- 不要修改 `.gitignore` 以提交 `data/` 下的真实数据

---

## 参考文档索引

| 文档 | 何时阅读 |
|-----|---------|
| `docs/project_brief.md` | 需要了解业务目标、数据结构、特征规划、评估标准 |
| `docs/project_status.md` | 每次开工/收工 |
| `docs/data_dictionary.md` | 数据接入后；处理具体字段时 |
| `docs/feature_dictionary.md` | 开发或审查特征时 |
| `docs/templates/fixed_task_template.md` | 拆解或领取新任务时 |

---

## 当前阶段

**M0 — 项目初始化**：核心文档与脚手架搭建中。  
**下一优先事项**：接入实际征信数据 → EDA → 确认标签定义 → 特征域 F01 实现。

详细进度见 `docs/project_status.md`。
