# Lookalike 新兴方法与近年论文（2021–2026）

> 面向「放心借客群 lookalike」扩量场景，**补充**《Lookalike方法调研.md》中偏经典/工业基线的内容，聚焦 **2021 年以来** 学术论文与工业界新趋势，便于与同事讨论「有没有新方法」。
>
> 更新日期：2026-07-31
>
> **飞书粘贴说明**：行内用 `$...$`，块级用单行 `$$...$$`（KaTeX 语法）；`$`/`$$` 须与公式内容同一行。句中公式建议用 `/gs` 插入，避免从 Markdown 整段粘贴时 `_` 被误解析。
>
> **与主文档关系**：主文档覆盖规则、相似度、GBDT、PU、图、ANN 等**常见落地栈**；本文档侧重**近年方法演进**与**可跟踪的前沿方向**。

---

## 1. 同事反馈怎么理解

「以前常用的方法」主要指：

- 种子 vs 随机负例 + LR/GBDT
- 质心/Cosine/KNN、K-Means
- 双塔 embedding + ANN 召回
- 平台上传种子包的黑盒 Lookalike

这些仍是**生产主力**，但 **2023–2025** 顶会/工业论文的主线已转向：

| 趋势 | 一句话 |
| --- | --- |
| 多 campaign 元学习 | 一次学「通用扩量能力」，新种子只做轻量微调 |
| 图 + 知识图谱 | 跨业务、跨行为视图，缓解稀疏与冷启动 |
| LLM 语义增强 | 用文本/评论/商品描述补 ID 特征，少依赖敏感属性 |
| 图上的 PU 学习 | 种子=正例、其余=未标注，并处理图上异配图 |
| 序列 Transformer 用户表示 | 从行为序列异步学 embedding，再构图做相似检索 |
| 因果 / Uplift | 不只要「像」，还要「营销后会转化」 |
| 平台侧范式变化 | Meta 等从「静态 Lookalike 包」转向实时检索与自动化投放 |

下文按**技术主题**组织，并给出**与放心借的关联度**（高/中/低）。

---

## 2. 近年方法地图（按主题）

```text
                    ┌─ MetaHeac（多任务元学习，微信）
多 Campaign 扩量 ─┼─ E-CLM / E-CLM++（360° 视图 + KG）
                    └─ GLoM（图 + LLM，2025）

图与关系扩量 ───────┼─ AudienceLinkNet（预训练 KG + GCN，乐天 2024）
                    ├─ Hi-DGN（解耦图 + 层次传播，CIKM 2024）
                    ├─ GPL（图 PU + 标签传播损失，ICML 2024）
                    └─ 时序知识图谱扩量（物流场景，CIKM 2023）

表示学习 ───────────┼─ ALURE（Transformer 序列 embedding + 图检索，2024）
                    ├─ Walmart 亿级客户 embedding + ANN（2023）
                    └─ Pinterest 两阶段 transfer + 轻量 seed 表示（KDD 2019，仍常被引用为工业范式）

平台与产品形态 ─────┼─ Meta Andromeda / Advantage+（实时检索，弱化手动 LAL）
                    └─ 国内：腾讯/字节一方扩量 + 智能定向（黑盒演进）

因果与价值 ─────────┴─ Uplift / PSM（主文档已述；近年与扩量联合排序增多）
```

---

## 3. 代表性论文与新兴方法（按时间）

### 3.1 多 Campaign 元学习：MetaHeac（KDD 2021，仍属前沿基线）

| 项目 | 内容 |
| --- | --- |
| 论文 | Zhu et al., *Learning to Expand Audience via Meta Hybrid Experts and Critics*, KDD 2021 |
| 链接 | [arXiv:2105.14688](https://arxiv.org/abs/2105.14688) · [GitHub: MetaHeac](https://github.com/easezyc/MetaHeac) |
| 部署 | 微信 Look-alike 系统（内容 + 广告） |

**问题**：每天上百个 campaign，种子小、类目差异大；每个 campaign 单独训模型易过拟合。

**思路（两阶段）**：

```text
离线：在所有历史 campaign 上做元学习，训练「通用」Meta Hybrid Experts and Critics
在线：给定新种子，在通用模型上快速微调 → 得到该 campaign 的定制扩量模型
```

**新兴点**：把 lookalike 从「单任务分类」提升为 **meta-learning 多任务**；与「只训一个全站 GBDT」形成对照。

**放心借关联**：**中**。若未来同时跑「促活、授信、复借、活动」等多类种子包，可借鉴两阶段「通用底座 + 种子微调」，而非每个活动从零训 LightGBM。

---

### 3.2 360° 客户视图 + KG：E-CLM / E-CLM++（SIGIR 2023）

| 项目 | 内容 |
| --- | --- |
| 论文 | Rahman et al., *Exploring 360-Degree View of Customers for Lookalike Modeling*, SIGIR 2023 |
| 链接 | [arXiv:2304.09105](https://arxiv.org/abs/2304.09105) |

**问题**：单一 demographic 或单一购买行为不够；用户在不同业务线行为稀疏、异质。

**方法 E-CLM**：

- 融合多视图：人口统计、忠诚度、电商、出行、家庭等（乐天内部多业务）
- 各视图学 entity embedding，再加权聚合为用户表示
- **E-CLM++**：将 E-CLM 的 embedding 作为预训练特征，喂给传统 baseline，进一步提升

**新兴点**：**跨域/跨产品线联合表示**，与「只拿放心借 D 系列表」形成对比；对**自有特征 + 百行/朴道/腾讯外部字典**的多源融合有参考价值。

**放心借关联**：**高**（思路层面）。不必照搬 KG，但「多源特征分塔/分视图 embedding 再融合」与现有数据资产一致。

---

### 3.3 图 + 预训练 KG：AudienceLinkNet（SIGIR 2024）

| 项目 | 内容 |
| --- | --- |
| 论文 | Rahman et al., *Graph-Based Audience Expansion Model for Marketing Campaigns*, SIGIR 2024 |
| 链接 | [DOI:10.1145/3626772.3661363](https://doi.org/10.1145/3626772.3661363) |
| 场景 | 乐天 AIris Target Prospecting 广告平台 |

**方法**：将扩量建模为图问题；**预训练知识图谱 embedding + GCN**，保留图结构，缓解跨服务数据稀疏与小种子过拟合。

**与 E-CLM 关系**：同一作者线从「多视图 embedding」演进到「**AudienceLinkNet**」图结构版本，可视为乐天 lookalike 技术线的 **2023→2024 迭代**。

**放心借关联**：**中**。需有用户—产品—渠道—设备等**可构图**关系；纯表格特征时需先构相似图或异构图。

---

### 3.4 图 + 大语言模型：GLoM（SIGIR eCom 2025）

| 项目 | 内容 |
| --- | --- |
| 论文 | *Lookalike Audience Expansion: A Graph-Based Model with LLMs (GLoM)*, SIGIR eCom 2025 |
| 链接 | [CEUR Vol-4123](https://ceur-ws.org/Vol-4123/paper_13.pdf) |

**问题**：传统图/深度模型依赖 ID 与敏感属性；商品与用户评论等**文本语义**利用不足；隐私合规趋严。

**方法 GLoM（两阶段）**：

```text
1. 用 LLM 生成用户/商品文本 profile，结合知识图谱结构
2. 图表示学习 + 注意力聚合（GLoM-Mean / GLoM-Attn）做 lookalike 打分
```

**对比基线**：文中包含 LR、Pinterest 式方法、**MetaHeac** 等；GLoM 在 Amazon 多品类公开数据上优于多种基线。

**新兴点**：**LLM + 图** 成为 2025 明确选题；强调少依赖直接敏感特征、用语义行为扩展。

**放心借关联**：**中–低（短期）**。信贷场景文本与 SKU 评论差异大；若仅有结构化 D 系列 + 外部字典，优先度低于 GBDT/PU。若后续有**营销文案、搜索词、产品描述**等，可跟踪。

---

### 3.5 解耦异构图：Hi-DGN（CIKM 2024）

| 项目 | 内容 |
| --- | --- |
| 论文 | *Hierarchical Information Propagation and Aggregation in Disentangled Graph Networks for Audience Expansion*, CIKM 2024 |
| 链接 | [DOI:10.1145/3627673.3680062](https://doi.org/10.1145/3627673.3680062) |

**场景**：物流/长周期签约类 audience expansion（非纯电商点击）。

**方法 Hi-DGN**：

- **解耦 embedding**：把用户表示拆成多侧面，避免纠缠
- **层次传播**：组级 → 个体级信息传播
- **关系聚合**：多关系边融合为全局节点表示

**新兴点**：异构图 + **disentangled** 表示，适合「同一用户在不同关系下角色不同」（借贷 vs 消费 vs 社交）。

**放心借关联**：**中**。有设备图谱、关联申请人、渠道图时可参考；无图时跳过。

---

### 3.6 图上的 PU 学习：GPL（ICML 2024）

> **专文精讲**见 **《GPL模型精读.md》**（方法、理论、实验、lookalike 映射）。

| 项目 | 内容 |
| --- | --- |
| 论文 | Wu et al., *Unraveling the Impact of Heterophilic Structures on Graph Positive-Unlabeled Learning*（GPL）, ICML 2024 |
| 链接 | [PMLR v235](https://proceedings.mlr.press/v235/wu24ad.html) · [arXiv:2405.19919](https://arxiv.org/abs/2405.19919) |

**问题**：lookalike 天然是 PU（种子=正，其余=未标注）；在图上还存在**异配边**（相邻节点不同类），破坏类先验估计与标签传播。

**方法 GPL**：双层优化——内层用 **Label Propagation Loss** 削弱异配边权重；外层训练 PU 分类器。

**新兴点**：把主文档中的 **nnPU** 推进到 **图 + 异配结构**，是 2024 较新的学术增量。

**放心借关联**：**中–高**。若采用「设备/联系人/APP 共现图」且坚持不强行标负例，GPL 类方法比「图 GCN + 随机负采样」更贴问题定义。

---

### 3.7 时序知识图谱扩量（CIKM 2023）

| 项目 | 内容 |
| --- | --- |
| 论文 | Yan et al., *Logistics Audience Expansion via Temporal Knowledge Graph*, CIKM 2023 |
| 链接 | [DOI:10.1145/3583780.3614695](https://doi.org/10.1145/3583780.3614695) |

**新兴点**：在知识图谱上引入**时间维度**，适合行为随时间演化的扩量（签约、留存、复购）。

**放心借关联**：**中**。若有授信/借款/还款**时间序列**与实体关系，可与时序 KG 方向结合；仅横截面特征时优先级较低。

---

### 3.8 亿级客户 Embedding + ANN：Walmart（arXiv 2023）

| 项目 | 内容 |
| --- | --- |
| 论文 | *Finding Lookalike Customers for E-Commerce Marketing*, arXiv:2301.03147 |
| 链接 | [arXiv:2301.03147](https://arxiv.org/abs/2301.03147) |

**方法**：深度学习 customer embedding（稠密 + 稀疏类别 + 地理位置 transfer learning）+ **ANN** 检索 lookalike；支持按 campaign 构造可解释相似度度量。

**新兴点**：工业界继续强化 **「表示学习 + 向量检索」** 而非全量 GBDT 打分；与 Pinterest（KDD 2019）同属一脉，但规模与特征工程更贴近零售全量用户。

**放心借关联**：**高（工程范式）**。与主文档「ANN 两阶段」一致；可作为 **Phase 3 规模化** 的引用依据。

---

### 3.9 序列 Transformer 用户表示：ALURE（2024）

| 项目 | 内容 |
| --- | --- |
| 论文 | *Async Learned User Embeddings for Ads Delivery Optimization*（ALURE）, 2024 |
| 链接 | [arXiv:2406.05898](https://arxiv.org/html/2406.05898) |

**方法**：从**多模态行为序列**（点击、评论、图文/短视频等）用类 Transformer 模块异步学习十亿级用户 embedding；再构建**用户相似图**做广告候选检索。

**新兴点**：**序列大模型式 user encoder + 图检索**，代表广告系统 2024 前后表示学习路线。

**放心借关联**：**中**。依赖丰富行为序列；当前以 D 系列静态特征为主时，可作为「数据成熟后」的升级方向。

---

### 3.10 交互式扩量（KDD 2021）

| 项目 | 内容 |
| --- | --- |
| 论文 | Chan et al., *Interactive Audience Expansion On Large Scale Online Visitor Data*, KDD 2021 |
| 链接 | [作者页 PDF](http://gromitchan.com/assets/papers/chan-kdd2021.pdf) |

**新兴点**：运营可在**查询时**选择种子子集与 trait 子集，系统在大规模稀疏 user×trait 矩阵上交互式扩量。

**放心借关联**：**低–中**。偏广告 trait 矩阵；金融场景可借鉴「运营可配置种子规则 + 特征子集」的产品交互，而非算法核心。

---

### 3.11 平台范式变化：Meta Lookalike → 实时检索（2024–2026 产品层）

| 项目 | 内容 |
| --- | --- |
| 背景 | Meta **Andromeda** 等新一代广告检索；部分目标下传统 Lookalike 更像「建议」而非硬约束 |
| 参考 | [Meta Engineering 博客](https://engineering.fb.com/)（检索架构）；行业解读称 2025 前后全球 rollout |

**新兴点**：**「上传种子 → 固定相似人群包」** 让位于 **实时信号 + 超大规模候选检索**；算法栈从「相似度模型」转向「端到端投放检索系统」。

**放心借关联**：**中（战略）**。对外投放仍可用腾讯/字节人群包，但应理解平台能力在变；**自建 lookalike** 在授信/运营侧的可控性反而更重要。

---

## 4. 新兴技术归纳（给汇报用）

### 4.1 五个「真·近几年」热点

1. **多任务 / 元学习扩量**（MetaHeac 及后续变体）——解决「campaign 多、种子小」。
2. **图 + KG + 跨视图融合**（E-CLM → AudienceLinkNet）——解决「稀疏、多业务数据」。
3. **LLM 增强语义**（GLoM 2025）——解决「ID 特征与隐私限制」。
4. **图 PU / 异配图**（GPL 2024）——解决「无显式负例 + 图结构」。
5. **序列 Transformer + 异步 embedding + 图检索**（ALURE 等）——解决「行为序列与超大规模检索」。

### 4.2 尚未成为信贷主流、但值得跟踪

- **联邦学习 / 隐私计算 lookalike**（联合建模扩量，论文与金融合规需求在增加，顶会专门「lookalike」标题相对少，多落在联邦 GNN、联邦推荐）
- **扩散模型 / 生成式用户表示**（推荐领域更多，lookalike 专用工作仍少）
- **多目标扩量**（相似度 + LTV + 风险 + Uplift 联合优化）——工业实践多，统一论文框架少

### 4.3 与「老方法」的关系（避免非此即彼）

| 老方法 | 近年演进 |
| --- | --- |
| GBDT 二分类 | → PU / 图 PU（GPL）；→ 用 E-CLM++ 式 embedding 作 GBDT 特征 |
| 双塔 + ANN | → Transformer 序列 encoder（ALURE）；→ campaign 级轻量 seed 适配（Pinterest/MetaHeac） |
| GCN 传播 | → KG 预训练 + GCN（AudienceLinkNet）；→ LLM 节点语义（GLoM） |
| 规则/画像 | → 360° 多视图加权（E-CLM） |

---

## 5. 放心借落地建议（结合新兴方向）

### 5.1 短期（0–6 个月）：仍以主文档 Phase 1–2 为主

- **LightGBM + 负采样 / PU（nnPU）** 仍是性价比最高路径。
- 可引入 **E-CLM++ 思路**：对 D 系列、外部字典分视图做 embedding 或 WOE，再并入 GBDT（不必上 GNN）。

### 5.2 中期（有行为序列或多活动种子）

- **MetaHeac 式两阶段**：全站历史活动预训练共享底座，单种子微调。
- **Walmart 式** embedding + ANN 两阶段召回，GBDT 精排。

### 5.3 长期（有图谱、合规允许多源联合）

- **AudienceLinkNet / GPL** 类图方法；关注 **GLoM** 是否能在「少敏感文本特征」下带来增益。

### 5.4 不建议为了「新方法」而新方法

- 无行为序列时强上 **ALURE/GLoM** 投入产出比低。
- 无图结构时 **GPL/Hi-DGN** 无法发挥优势。
- 平台 **Meta LAL** 产品变化不影响**自建名单**在授信/风控侧的核心价值。

---

## 6. 推荐阅读顺序（由近到远）

| 优先级 | 论文 | 年份 | 理由 |
| --- | --- | --- | --- |
| ★★★ | GLoM（图 + LLM） | 2025 | 当前学术前沿代表 |
| ★★★ | GPL（图 PU） | 2024 | 与 lookalike 问题定义最贴 |
| ★★★ | AudienceLinkNet | 2024 | 工业图扩量落地 |
| ★★☆ | E-CLM / E-CLM++ | 2023 | 多源特征融合，贴近放心借数据 |
| ★★☆ | ALURE | 2024 | 序列 + 大规模检索 |
| ★★☆ | MetaHeac | 2021 | 多 campaign 元学习经典 |
| ★☆☆ | Hi-DGN、时序 KG | 2023–2024 | 有图/时序再看 |
| ★☆☆ | Walmart lookalike system | 2023 | 工程规模参考 |

---

## 7. 参考文献（扩展）

1. Zhu et al., Meta Hybrid Experts and Critics (MetaHeac), KDD 2021. [arXiv:2105.14688](https://arxiv.org/abs/2105.14688)
2. Rahman et al., E-CLM 360° Lookalike, SIGIR 2023. [arXiv:2304.09105](https://arxiv.org/abs/2304.09105)
3. Rahman et al., AudienceLinkNet, SIGIR 2024. [DOI:10.1145/3626772.3661363](https://doi.org/10.1145/3626772.3661363)
4. Wu et al., GPL Graph PU Learning, ICML 2024. [PMLR](https://proceedings.mlr.press/v235/wu24ad.html)
5. GLoM: Graph-Based Model with LLMs, SIGIR eCom 2025. [CEUR](https://ceur-ws.org/Vol-4123/paper_13.pdf)
6. Hi-DGN, CIKM 2024. [DOI:10.1145/3627673.3680062](https://doi.org/10.1145/3627673.3680062)
7. Yan et al., Temporal KG for Logistics Audience Expansion, CIKM 2023. [DOI:10.1145/3583780.3614695](https://doi.org/10.1145/3583780.3614695)
8. Walmart, Finding Lookalike Customers, arXiv 2023. [arXiv:2301.03147](https://arxiv.org/abs/2301.03147)
9. ALURE, Async Learned User Embeddings, 2024. [arXiv:2406.05898](https://arxiv.org/abs/2406.05898)
10. Chan et al., Interactive Audience Expansion, KDD 2021.
11. Liu et al., Real-time Attention Based Look-alike Model, KDD 2019.（工业注意力扩量，仍常作基线）
12. 主文档：《Lookalike方法调研.md》— 经典方法与公式速查。

---

## 8. 附录：给同事的一句话版本

> 近几年 lookalike 不是抛弃 GBDT，而是在 **多 campaign 元学习、图/KG 多视图、LLM 语义、图 PU、序列 Transformer + 向量检索** 五条线上变深；放心借短期仍建议 **GBDT/PU + 多源特征融合**，中期可看 **embedding 两阶段**，长期有图再跟 **GPL / AudienceLinkNet / GLoM**。
