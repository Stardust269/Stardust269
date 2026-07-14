# 固定任务模板（Fixed Task Template）

> **用途**：拆解和领取任务时，复制本模板并填写。Claude Code 执行任何开发任务前，应先确认或生成一份任务卡。  
> **存放路径**：`docs/tasks/T-{ID}_{简述}.md`（任务开始后创建）  
> **关联文档**：`docs/project_brief.md` | `docs/project_status.md` | `CLAUDE.md`

---

## 任务卡

```yaml
# ===== 元信息（必填）=====
task_id: T-XXX                    # 与 project_status.md 中的 ID 一致
title: ""                         # 一句话任务标题
priority: P0 | P1 | P2            # 优先级
milestone: M0 | M1 | M2 | M3 | M4 | M5 | M6
status: 待开始 | 进行中 | 已完成 | 阻塞
created_date: YYYY-MM-DD
assignee: Claude Code | 待填写
estimated_hours:                  # 预估工时（可选）
```

---

## 1. 任务背景

<!-- 为什么要做这个任务？与业务目标的关联是什么？ -->

**背景说明**：

**关联里程碑**：

---

## 2. 任务目标

<!-- 完成后应达到什么状态？用可验证的结果描述 -->

**目标陈述**（SMART）：

- [ ] 目标 1
- [ ] 目标 2
- [ ] 目标 3

---

## 3. 范围界定

### 3.1 本任务包含（In Scope）

-

### 3.2 本任务不包含（Out of Scope）

-

---

## 4. 输入与依赖

### 4.1 前置依赖

| 依赖任务/资源 | 状态 | 说明 |
|-------------|------|------|
| | ✅ / ⏳ / 🚫 | |

### 4.2 输入数据/文件

| 输入 | 路径 | 格式 | 说明 |
|-----|------|------|------|
| | | | |

### 4.3 参考文档

- [ ] `docs/project_brief.md` — 第 ___ 节
- [ ] `docs/data_dictionary.md`
- [ ] `docs/feature_dictionary.md`
- [ ] 其他：___

---

## 5. 技术方案

### 5.1 实现思路

<!-- 分步骤描述技术方案，Claude Code 应在动手前写出或确认此节 -->

1. 
2. 
3. 

### 5.2 涉及模块/文件

| 操作 | 文件路径 | 说明 |
|-----|---------|------|
| 新建 | | |
| 修改 | | |
| 删除 | | |

### 5.3 配置变更

| 配置文件 | 变更内容 |
|---------|---------|
| `config/paths.yaml` | |
| `config/features.yaml` | |
| `config/model.yaml` | |

---

## 6. 验收标准

<!-- 必须全部满足方可标记任务完成 -->

### 6.1 功能验收

- [ ] 验收项 1：___
- [ ] 验收项 2：___
- [ ] 验收项 3：___

### 6.2 代码质量

- [ ] 通过 `pytest tests/ -v`（无失败）
- [ ] 新函数/类有 docstring
- [ ] 无硬编码路径（使用 `config/`）
- [ ] 无真实 PII 数据泄露

### 6.3 文档更新

- [ ] 更新 `docs/project_status.md`（任务状态、会话记录）
- [ ] 更新 `docs/feature_dictionary.md`（如涉及新特征）
- [ ] 更新 `docs/data_dictionary.md`（如涉及新字段）

---

## 7. 测试计划

### 7.1 单元测试

| 测试文件 | 测试内容 | 预期结果 |
|---------|---------|---------|
| `tests/...` | | |

### 7.2 手动验证

```bash
# 验证命令（填写后执行）
```

**预期输出**：

---

## 8. 风险与注意事项

| 风险 | 可能性 | 影响 | 缓解措施 |
|-----|-------|------|---------|
| 时间泄露 | 中 | 高 | 特征仅用 report_date 之前数据 |
| 数据质量问题 | 高 | 中 | 先输出质量报告再建模 |
| | | | |

**特别注意**：

---

## 9. 产出物清单

| 产出 | 路径 | 状态 |
|-----|------|------|
| | | ⏳ |

---

## 10. 完成后检查

任务完成时，执行以下动作：

1. 将本任务卡 `status` 改为 `已完成`
2. 在 `docs/project_status.md` 中：
   - 从「进行中」移至「已完成」
   - 更新特征开发进度表（如适用）
   - 添加会话记录
3. 提交 git，commit message 格式：`feat(T-XXX): 简述`

---

## 附录：常用任务模板速查

> 以下为征信特征工程项目的典型任务，可直接复制使用。

---

### 模板 A：数据探索任务（EDA）

```yaml
task_id: T-EDA-XXX
title: "对 {数据集名} 进行探索性数据分析"
milestone: M1
```

**目标**：
- 输出数据概览（行数、列数、 dtypes）
- 统计各字段缺失率、唯一值数
- 识别异常值与时间逻辑错误
- 生成 EDA 报告（notebook 或 markdown）

**产出**：`notebooks/01_eda_{数据集}.ipynb` + `experiments/reports/eda_{日期}.md`

---

### 模板 B：单特征域开发

```yaml
task_id: T-FEAT-XXX
title: "实现特征域 {F0X-域名} 的全部特征"
milestone: M3
```

**目标**：
- 在 `src/features/f{XX}_{name}.py` 实现该域所有计划特征
- 每个特征函数有 docstring 和 pytest 用例
- 在 `docs/feature_dictionary.md` 登记全部新特征
- 在合成数据上验证输出正确性

**验收**：
- [ ] `pytest tests/features/test_f{XX}_*.py -v` 全部通过
- [ ] 特征命名符合 `{域}_{聚合}_{窗口}_{字段}` 规范
- [ ] 无时间泄露（单元测试含边界用例）

---

### 模板 C：标签构建

```yaml
task_id: T-LABEL-XXX
title: "构建用户需求预测标签"
milestone: M2
```

**目标**：
- 根据 `project_brief.md` 2.4 节定义构建标签
- 输出标签分布统计（正负比、各类占比）
- 时间切分方案：训练/验证/测试/OOT

**产出**：`src/data/label_builder.py` + `experiments/reports/label_distribution_{日期}.md`

---

### 模板 D：基线模型训练

```yaml
task_id: T-MODEL-XXX
title: "训练 {模型名} 基线并输出评估报告"
milestone: M4
```

**目标**：
- 使用当前特征集训练基线模型
- 输出 AUC/KS/F1 等指标
- 生成特征重要性 / SHAP 报告
- 记录实验到 `experiments/`

**验收**：
- [ ] 评估指标记录在 `docs/project_status.md` 实验记录表
- [ ] 模型文件存于 `experiments/models/`
- [ ] 可复现（固定 random_seed）

---

### 模板 E：特征筛选与稳定性

```yaml
task_id: T-SELECT-XXX
title: "特征筛选与 PSI 稳定性检验"
milestone: M5
```

**目标**：
- IV 值排序，剔除 IV < 0.02 的特征
- 相关性去冗余（|r| > 0.95）
- 训练集 vs 测试集 PSI 计算
- 输出筛选后特征列表

**产出**：`experiments/reports/feature_selection_{日期}.md`

---

*复制本模板时，删除不需要的章节，但不要删除「验收标准」和「完成后检查」。*
