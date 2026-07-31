# GPL 模型精读（Graph PU Learning with Label Propagation Loss）

> 专文精讲 ICML 2024 论文 *Unraveling the Impact of Heterophilic Structures on Graph Positive-Unlabeled Learning* 中的 **GPL** 方法，面向「放心借客群 lookalike」中 **图结构 + 种子正例 + 未标注候选** 的建模场景。
>
> 更新日期：2026-07-31
>
> **飞书粘贴说明**：行内用 `$...$`，块级用单行 `$$...$$`（KaTeX）；`$`/`$$` 须与公式内容**同一行**。句中公式建议 `/gs` 手输，勿整段 Markdown 粘贴以免 `_` 被误解析。
>
> **关联文档**：《Lookalike方法调研.md》PU/图方法；《Lookalike新兴方法与近年论文.md》新兴方向索引。

---

## 1. 论文信息（核实用）

| 项目 | 内容 |
| --- | --- |
| 全称 | *Unraveling the Impact of Heterophilic Structures on Graph Positive-Unlabeled Learning* |
| 方法名 | **GPL** = Graph PU Learning with **L**abel Propagation **L**oss |
| 作者 | Yuhao Wu, Jiangchao Yao, Bo Han, Lina Yao, Tongliang Liu |
| 会议 | **ICML 2024**（PMLR v235，pp. 53928–53943） |
| arXiv | https://arxiv.org/abs/2405.19919 |
| 官方页 | https://proceedings.mlr.press/v235/wu24ad.html |

**说明**：论文研究 **图上的 PU 学习**，标题不含 “Lookalike”。与扩量场景的对应关系是：**种子用户 = 观测正例**，**候选池中非种子 = 未标注**，若存在用户关系图，则属于 Graph PU 问题。

---

## 2. 要解决什么问题

### 2.1 Graph PU 设定

```text
输入：
  - 图 G = (V, E)，节点特征 x_i，邻接矩阵 A
  - 观测正例集合 P（只有这些节点 y=+1 已知）
  - 未标注集合 U = V \ P（混有隐藏正例与负例）

输出：
  - 对每个 u ∈ U，估计 P(y=+1 | x_u, 局部子图)
```

典型应用：欺诈图中仅标出已发现欺诈节点、传播图中仅标感染节点等。Lookalike 中：**高质量种子 = P**，**全量可营销用户去掉种子 = U**（若还构了相似/共现边，即图 PU）。

### 2.2 朴素两阶段做法及其缺陷

```text
阶段 1：在原始邻接 A 上估计类先验 π_p（正例在未标注中的比例）
阶段 2：用 π_p 在 A 上训练 GNN，做 PU 分类
```

已有 **图 PU** 方法（GRAB、PU-GNN 等）多隐含 **同配图（homophily）**：相邻节点倾向同类。真实图常存在 **异配图（heterophily）**：正节点连到负节点。此时：

1. **类先验估计（CPE）**：经典 CPE 依赖 **不可约假设（irreducibility）**；异配边使正、负在图上纠缠，**不可约条件被破坏** → $\pi_p$ 常被 **高估**。
2. **PU 分类**：GNN 消息传递沿异配边会把正负表示 **混在一起** → 从未标注中区分可靠负例变难，F1 下降。

论文用实验展示：**异配率 $h$ 越高，CPE 误差越大、分类越差**。

### 2.3 GPL 的核心想法（一句话）

在 PU 学习之前/之中，**先学一个「更适合 PU 的图」$\hat{A}$**：削弱异配边权重，再在该图上做 CPE + GNN 分类；用 **只需正例标签** 的 **Label Propagation Loss（LPL）** 驱动调图，并采用 **双层优化** 与分类器交替 refine。

---

## 3. 符号与预备知识

| 符号 | 含义 |
| --- | --- |
| $\mathcal{P}$ | 观测正例节点集 |
| $\mathcal{U}$ | 未标注节点集 |
| $\pi_p$ | 真实类先验：未标注中隐藏正例占比 |
| $\hat{\pi}_p$ | 估计类先验 |
| $A$ | 原始邻接；$\hat{A}$ 为 LPL 优化后的邻接/边权 |
| $f_w$ | GNN 分类器，参数 $w$ |
| $h$ | 边同配率（越大越同配，越小越异配） |

**PU 两子任务**（全文贯穿）：

- **CPE**：估计 $\hat{\pi}_p$。
- **PU 分类**：在 $\hat{\pi}_p$ 下训练 $f_w$，对 $\mathcal{U}$ 打分。

---

## 4. 方法：GPL 三部分

GPL = **LPL（调图）** + **CPE（估先验）** + **GNN PU 分类（式 8）**，封装在 **双层优化** 里。

### 4.1 整体优化形式（概念）

朴素两阶段对应「先 CPE 再分类」。GPL 改为（论文式 4 的精神）：

$$\min_{w} \mathcal{L}_{\mathrm{GNN}}(\hat{\pi}_p, w, \hat{A}) \quad \text{s.t.} \quad \hat{\pi}_p = \mathcal{E}_{\mathrm{CPE}}(\hat{A}), \; \hat{A} = \arg\min_{A} \mathcal{L}_{\mathrm{LPL}}(A)$$

含义：**外层**训 GNN；**约束里**先在 $\hat{A}$ 上估 $\hat{\pi}_p$；**内层**用 LPL 把 $A$ 调成 $\hat{A}$。

### 4.2 标签传播（LPA）与 LPL

**困难**：异配边削弱方法（如部分异配 GNN）常需要 **标注负例**；PU 设定没有真负例。

**思路**：用经典 **标签传播（LPA）**，仅用已知正例初始化，看多轮传播后正节点是否被「推成负类」。异配边会把正例拉向负类 → 最小化「正例被传播成负类」的概率 ≈ 压低异配边贡献。

**可学习边权**：$M \odot A$，$M$ 为可学习正 mask（边权）。

**LPA 更新**（$k$ 为传播步，$\alpha \in (0,1)$，$D$ 为度矩阵）：

$$E^{(k)} = \alpha E^{(k-1)} + (1-\alpha) D^{-1} A E^{(k-1)}$$

**LPL（仅用观测正例 $\mathcal{P}$，式 6）**：最小化正例在 $K$ 步传播后被标为负类的对数概率：

$$\hat{A} = \arg\min_{A} \frac{1}{|\mathcal{P}|} \sum_{x_i \in \mathcal{P}} \log P(y=-1 \mid x_i, \mathcal{G}_{x_i}^{A})^{(K)}$$

直觉：**同配边**帮助正例保持正标签；**异配边**导致正例传播后像负例 → 优化 LPL 会 **减弱异配边权重**。

**增强 LPL（式 9，与分类联训）**：PU 训练时从未标注中按 $\hat{\pi}_p$ 划出临时正集 $\mathcal{S}$ 与临时负集，用预测标签一起约束传播，使 **图结构** 与 **当前分类器** 互相校正。

### 4.3 类先验估计 CPE（式 7）

在优化后的 $\hat{A}$ 上，用 GNN 输出构造分布的 $Q$ 函数，估计：

$$\hat{\pi}_p = \mathcal{E}_{\mathrm{CPE}}(\hat{A}) = \min_{c \in [0,1]} \frac{Q_{\mathrm{u}}^{\hat{A}}(c)}{Q_{\mathrm{p}}^{\hat{A}}(c)}$$

（细节见原文；与 REMPE、TED 等现代 CPE 在图上的扩展一致。）**要点**：先 LPL 再 CPE，异配减轻后 $\hat{\pi}_p$ 更稳。

### 4.4 PU 分类损失（式 8）

对未标注节点按 GNN 正类后验 **排序**：

- 取 top $\hat{\pi}_p$ 比例作为临时正例集 $\mathcal{S}$；
- 其余 $\mathcal{U} \setminus \mathcal{S}$ 作为临时负例；

在 $\mathcal{P} \cup \mathcal{S}$ 上训正类，在 $\mathcal{U} \setminus \mathcal{S}$ 上训负类（交叉熵），图用 $\hat{A}$：

$$\mathcal{L}_{\mathrm{GNN}} = \mathcal{L}_{\mathrm{pos}}(\mathcal{P} \cup \mathcal{S}) + \mathcal{L}_{\mathrm{neg}}(\mathcal{U} \setminus \mathcal{S})$$

这与 **Spy / Reliable Negative** 的「从 U 里挖可靠负例」同族，但是在 **图 + 与 LPL 联训** 的框架内。

### 4.5 训练流程（Algorithm 1，文字版）

```text
输入：P, U, 邻接 A
初始化：GNN f_w，Â ← A
for epoch = 1 .. E:
    repeat until K 步或收敛:
        用式(9)更新 Â（LPL，削弱异配边）
    在 Â 上计算 π̂_p（CPE）
    用式(8)更新 w（GNN PU 分类）
输出：f_w
```

**实现默认**：2 层 **GCN**，hidden=16，Adam lr=0.01，评估 **F1**（类别不平衡）。

**双层含义**：

- **内循环**：固定当前伪 P/N 划分（或仅 P），优化 $\hat{A}$；
- **外循环**：固定 $\hat{A}$，更新 CPE 与 GNN；分类器变好后再反哺 LPL 式(9)。

---

## 5. 理论部分（读文抓重点）

论文第 4 节回答三个「为什么」：

### 5.1 为什么 LPL 能降异配？

定义 **异配影响（HI）**：负节点 $x_b$ 经 $k$ 步传播对正节点 $x_a$ 输出概率的扰动。**Theorem 4.2**：对给定正节点，所有节点造成的 HI 之和 **正比于** 该正节点在 $k$ 步传播后被标为负类的概率。因此 **最小化 LPL**（压低正例被传播成负类）≈ **最小化异配影响** ≈ 削弱异配边。

### 5.2 为什么降异配有利于 CPE？

异配破坏图上的 **不可约条件**（Theorem 2.1），导致 $\pi_p$ 不可辨识或高估。减轻异配后，CPE 假设更接近成立，Table 2 中 **异配率高的数据集** 上 GPL 的 CPE 误差下降最明显。

### 5.3 为什么降异配有利于 PU 分类？

**Theorem 4.5**（简述）：异配边使一步聚合后正负节点表示距离 **缩小**，难分。LPL 压低异配边权后，P/N 在表示空间 **更易区分**，rank-and-select 更可靠。

---

## 6. 实验怎么做的

### 6.1 数据

10 个节点分类数据集：Cora、Pubmed、Citeseer、Wiki-CS（偏同配）到 Cornell、Chameleon、Squirrel、Actor、Wisconsin、Texas（强异配）。异配率 $h$ 约 0.19～0.89。

**转 PU**：最大类为正，其余为负；50% 正节点进 $\mathcal{P}$，其余正 + 全部负进 $\mathcal{U}$；只在 $\mathcal{U}$ 上评测。

### 6.2 对比方法

| 类别 | 方法 |
| --- | --- |
| 基线 | GCN、MLP |
| i.i.d PU + 图/MLP | GCN/MLP + **TED**（NeurIPS 2021）；GCN/MLP + **nnPU**（NeurIPS 2017） |
| 图 PU | **LSDAN**（ICME 2017）；**GRAB**（ICDM 2021）；**PU-GNN**（CIKM 2023） |
| CPE 单评 | KM、DEDPUL、MPE、ReMPE、BBE、TED、GRAB 等 |

### 6.3 主要结论

- **分类 F1**：GPL 在同配～异配全集上最优；**异配越强，领先幅度越大**。
- **CPE 误差**：GPL 在 Table 2 各数据集上类先验绝对误差多数最优。
- **观测正例比例 $r_p$ 从 0.5 降到 0.2**：GPL F1 仍较稳，基线掉得更厉害（种子少时更鲁棒）。
- **消融**：去掉 LPL、去掉双层、去掉伪 P/N 选取都会掉点；**高异配数据集上 LPL 最关键**。

---

## 7. 与相关工作的关系（论文引用脉络）

### 7.1 PU 学习

- 奠基：Elkan & Noto (KDD 2008)；Blanchard 等不可约假设；Bekker & Davis 综述。
- 分类：**nnPU**（Kiryo, NeurIPS 2017）；**TED**（Garg, NeurIPS 2021）。
- CPE：Ivanov DEDPUL；Yao ReMPE；Scott MPE 等。

### 7.2 图 PU（GPL 直接对手）

- **PU-LP**（Ma & Zhang, 2017）：标签传播式 PU。
- **GRAB**（Yoo et al., ICDM 2021）：图 PU，可无已知类先验。
- **PU-GNN**（Yang et al., CIKM 2023）：结构感知图 PU。

GPL 论文指出：它们多依赖 **同配** 调制损失，在 **异配图** 上失效；GPL 用 LPL **改图** 再 PU。

### 7.3 异配图 GNN（不能直搬）

- Zhu et al. NeurIPS 2020（Beyond homophily）；Pei Geom-GCN；Zhu CPGNN；Luan 等。
- 共性：多需 **完整标签** 处理异配；PU 无标注负例 → **GPL 用 LPL + 仅正例** 填缝。

### 7.4 标签传播与影响函数

- Wang & Leskovec：GNN 与 LP 统一视角；Gasteiger PPNP。
- Koh & Liang、Xu et al.：影响函数，用于 Theorem 4.2 的 HI 分析。

---

## 8. 映射到 Lookalike / 放心借

### 8.1 何时 GPL 贴题

| 条件 | 说明 |
| --- | --- |
| 有图 | 设备共现、关联申请、联系人、渠道关系、相似度阈值图等 |
| 标签是 PU | 只信种子为正，不愿把全池随机标负 |
| 图较异配 | 「像种子」的用户与「不像」的用户仍可能相连（交叉营销、家庭设备等） |

### 8.2 何时不必上 GPL

- 只有 **表格特征 D 系列 + 外部字典**，**无边**：用 **nnPU + LightGBM** 更直接。
- 种子极大、规则清晰：**GBDT 二分类** 仍常是首选。
- 工程资源有限：GPL 需构图、双层训练、调参，成本高。

### 8.3 与主文档其他章节的衔接

```text
规则/GBDT（主文档 §6）     → 无图时的主力
nnPU / Spy（主文档 §7）    → 表格 PU
Label Prop / GCN（§9）     → 图传播，但默认同配
GPL（本文）                → 图 PU + 显式处理异配
ANN 两阶段（§11）          → GPL 产出分数或 embedding 后仍可 ANN 扩量
```

### 8.4 落地简化路径（若只做 POC）

```text
1. 用业务规则 + 相似度阈值构稀疏用户图 A
2. 种子 = P，候选 = U
3. 复现 GPL 训练循环（或先 GRAB/PU-GNN 基线，再加 LPL 模块对比）
4. 离线：F1 / PR-AUC + 扩展人群风险分布（D401）校验
5. 在线：小流量 A/B
```

---

## 9. 读论文建议顺序

```text
Abstract + §1 Introduction        → 动机与贡献
§2 Preliminaries + §2.2 Motivation → 图 PU 符号、异配如何伤 CPE/分类
§3 Methodology                    → LPL、式(8)(9)、Algorithm 1（核心）
§4 Theoretical Analysis           → 有时间读 Theorem 4.2、4.5
§5 Experiment                     → Table 1–2、Figure 4、消融 Table 3
§6 Related Work                   → 定位 GRAB、PU-GNN、异配 GNN
```

---

## 10. 附录：推荐引用格式

```text
Wu Y, Yao J, Han B, Yao L, Liu T. Unraveling the Impact of Heterophilic
Structures on Graph Positive-Unlabeled Learning. In: Proceedings of the
41st International Conference on Machine Learning (ICML 2024), PMLR
volume 235, pp. 53928–53943, 2024.
```

方法名在文中写作：**Graph PU Learning with Label Propagation Loss (GPL)**。

---

## 11. 一页纸总结（可截图发同事）

| 维度 | 内容 |
| --- | --- |
| 问题 | 图上只有部分正例标签，未标注里混正负；异配边让 CPE 和 GNN PU 都变差 |
| 方法 | LPL 调边权降异配 → CPE 估 $\pi_p$ → rank 挖伪负例训 GCN |
| 训练 | 双层优化：内层 $\hat{A}$，外层 $w$ 与 $\hat{\pi}_p$ |
| 强项 | 异配率高的图；观测正例比例低时仍较稳 |
| 弱项 | 需要图、训练复杂；无图场景不适用 |
| Lookalike | 种子=P、候选=U、有关系图时，比「GCN+随机负例」更贴 PU 定义 |
