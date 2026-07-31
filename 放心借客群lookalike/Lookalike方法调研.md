# Lookalike 方法调研

> 面向「放心借客群 lookalike」扩量场景，梳理业界常用 lookalike（相似人群扩展）方法，说明每类方法的核心思路、具体算法步骤与数学形式，并给出方法对比与落地建议。
>
> 更新日期：2026-07-30
>
> **公式说明**：行内符号使用 `$...$`，块级公式使用 `$$...$$`；语法遵循飞书文档支持的 [KaTeX](https://katex.org/docs/supported.html) 子集（非完整 LaTeX）。**`$`/`$$` 必须与公式内容写在同一行，中间不可换行**，否则飞书无法渲染。附录 C 为块级公式速查。
>

---

## 1. 问题定义

### 1.1 业务目标

给定一批**种子用户（Seed）** $S$，在全量用户池 $U$ 中找到与种子「最相似」的用户集合，用于营销触达、授信促活、风险筛选等。

典型场景（放心借）：

- 种子：历史高价值借款用户、成功转化用户、某活动响应用户
- 候选池：全站可营销用户、某渠道流量、外部联合建模人群
- 输出：Top-K 相似用户或相似度分数，用于投放/电销/短信名单

### 1.2 形式化定义

| 符号 | 含义 |
| --- | --- |
| $S \subset U$ | 种子用户集合，通常规模 $\lvert S \rvert = 10^3 \sim 10^6$ |
| $C = U - S$ | 候选用户池 |
| $\mathbf{x}_u \in \mathbb{R}^d$ | 用户 $u$ 的特征向量（自有特征 D101–D402、征信、外部字典等） |
| $s(u)$ | 用户 $u$ 的 lookalike 分数，分数越高越像种子 |
| $L \subset C$ | 最终扩展人群，如 $L = \text{TopK}_{u \in C}(s(u))$ |

### 1.3 通用建模流程

```text
种子圈选 → 特征工程 → 相似/分类建模 → 全量打分排序 → 阈值截断 → 业务校验 → 投放/触达
```

### 1.4 负样本与标签构造（关键难点）

Lookalike 本质是**单类学习**或**弱监督学习**：

- 正样本：种子用户 $y=1$
- 负样本：通常没有明确标注，常见构造方式：
  1. **随机负采样**：从候选池随机抽 $\lvert S \rvert \times k$ 个用户作负例（Meta/Google 常用）
  2. **曝光未转化**：看过广告/活动但未转化的用户
  3. **PU Learning**：将全部非种子用户视为未标注（Unlabeled），不强行标 0
  4. **业务规则负例**：明确不符合目标客群的用户（如黑名单、已拒绝授信）

---

## 2. 方法总览

| 类别 | 代表方法 | 核心思想 | 典型规模 | 可解释性 |
| --- | --- | --- | --- | --- |
| 规则/画像匹配 | 属性规则、种子画像重叠 | 按统计画像硬匹配 | 任意 | 高 |
| 相似度检索 | Cosine/KNN/质心匹配 | 特征空间距离近 | 10^6–10^8（+ANN） | 中 |
| 聚类扩展 | K-Means/GMM | 找种子所在簇并扩展 | 10^6–10^8 | 中 |
| 分类模型 | LR/GBDT/RF | 种子 vs 非种子二分类 | 10^6–10^9 | 中–高 |
| PU 学习 | Spy/RN/nnPU | 仅正例 + 未标注 | 10^6–10^9 | 中 |
| 协同过滤/Embedding | MF/双塔/DSSM | 学习低维用户表示 | 10^7–10^9 | 低 |
| 图方法 | 相似图/Label Prop/GNN | 利用用户关系传播 | 10^7–10^9 | 低–中 |
| 深度学习 | MLP/DeepFM/Autoencoder | 非线性表示 + 打分 | 10^7–10^9 | 低 |
| 向量检索 | FAISS/HNSW | 大规模近邻搜索 | 10^8–10^10 | 低 |
| 平台内置 | Meta/Google/腾讯广告 | 黑盒相似人群包 | 平台侧 | 低 |

---

## 3. 规则与画像匹配法

### 3.1 方法原理

统计种子用户在各维度上的分布，生成**种子画像（Seed Profile）**，对候选用户计算与画像的匹配度。

### 3.2 算法步骤

**Step 1：构建种子画像**

对离散特征 $f$：

$$P_{\mathrm{seed}}(f = v) = \frac{1}{\lvert S \rvert} \sum_{u \in S} \mathbb{1}(x_{u,f}=v)$$


对连续特征 $f$：

$$\mu_f = \frac{1}{\lvert S \rvert} \sum_{u \in S} x_{u,f}, \quad \sigma_f = \mathrm{std}(x_{u,f})$$


**Step 2：候选用户打分**

离散特征重叠得分（分布相似）：

$$s_{\mathrm{disc}}(u) = \sum_f w_f \cdot P_{\mathrm{seed}}(f = x_{u,f})$$


连续特征高斯匹配：

$$s_{\mathrm{cont}}(u) = \sum_f w_f \cdot \exp\left(-\frac{(x_{u,f}-\mu_f)^2}{2\sigma_f^2}\right)$$


综合：$s(u) = \alpha s_{\mathrm{disc}} + (1-\alpha) s_{\mathrm{cont}}$

**Step 3：规则过滤 + 排序**

```sql
-- 示例：画像规则扩量
WHERE income_level BETWEEN seed_p25 AND seed_p75
  AND risk_level <= seed_p50
  AND city IN (seed_top_cities)
ORDER BY lookalike_score DESC
LIMIT K
```

### 3.3 变体：布尔规则树

将种子画像转化为 AND/OR 规则组合，如：

```text
(收入等级 IN {3,4}) AND (风险等级 <= 3) AND (授信时长 >= 2)
```

可用决策树从种子中自动抽取规则（CART/RuleFit）。

### 3.4 优缺点

| 优点 | 缺点 |
| --- | --- |
| 实现简单、可解释、合规友好 | 无法捕捉特征交叉与非线性 |
| 适合冷启动、种子极少 | 对高维稀疏特征效果差 |
| 便于业务专家调参 | 扩展人群多样性不足 |

### 3.5 放心借适用性

适合作为**基线**或**硬约束层**：用 D401 风险等级、D203 收入评级等做准入过滤，再叠加模型打分。

---

## 4. 相似度检索法

### 4.1 方法原理

将每个用户表示为特征向量，计算候选用户与种子集合的相似度，按相似度排序扩量。

### 4.2 常用相似度度量

#### （1）余弦相似度

$$\mathrm{sim}(\mathbf{x}, \mathbf{y}) = \frac{\mathbf{x}^\top \mathbf{y}}{\|\mathbf{x}\|_2 \|\mathbf{y}\|_2}$$


#### （2）欧氏距离（转化为相似度）

$$\mathrm{sim}(\mathbf{x}, \mathbf{y}) = \frac{1}{1 + \|\mathbf{x}-\mathbf{y}\|_2}$$


#### （3）Jaccard 相似度（集合/多值标签）

$$J(A, B) = \frac{\lvert A \cap B \rvert}{\lvert A \cup B \rvert}$$


适用于用户兴趣标签、产品持有集合等。

#### （4）汉明距离（二值特征）

$$d_H(\mathbf{x}, \mathbf{y}) = \sum_{i=1}^{d} \mathbb{1}(x_i \neq y_i)$$


### 4.3 种子聚合策略

| 策略 | 公式 | 说明 |
| --- | --- | --- |
| 质心法 | $\bar{\mathbf{x}}_S = \frac{1}{\lvert S \rvert} \sum_{u \in S}\mathbf{x}_u$，$s(u)=\mathrm{sim}(\mathbf{x}_u, \bar{\mathbf{x}}_S)$ | 最快，适合大规模 |
| 最大相似 | $s(u) = \max_{v \in S}\mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v)$ | 更精细，计算贵 |
| 平均相似 | $s(u) = \frac{1}{\lvert S \rvert} \sum_{v \in S}\mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v)$ | 折中方案 |
| 加权相似 | $s(u) = \sum_{v \in S} w_v \cdot \mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v)$ | 种子可按价值加权 |

### 4.4 KNN Lookalike 算法

```text
输入：种子集 S，候选池 C，特征矩阵 X，近邻数 K
1. 对特征做标准化/归一化
2. 构建索引结构（KD-Tree / Ball-Tree / ANN）
3. 对每个候选用户 u ∈ C：
     找种子中 K 个最近邻 N_K(u)
     s(u) = 1/K * Σ_{v∈N_K(u)} sim(x_u, x_v)
4. 按 s(u) 降序取 Top-M
输出：扩展人群 L
```

### 4.5 特征预处理

1. **缺失值**：放心借特征中 `-1` 表示缺失，建议单独编码为 missing indicator 或用中位数/种子均值填充
2. **序数特征**：D201–D402 等 1–5 分档，可直接数值化或 one-hot
3. **高维稀疏**：外部字典（百行/朴道/腾讯）建议 PCA/哈希降维后再算相似度

### 4.6 优缺点

| 优点 | 缺点 |
| --- | --- |
| 无需标签，实现快 | 特征尺度敏感，需预处理 |
| 质心法可亚线性扩展 | 线性假设，难捕捉复杂模式 |
| 与 ANN 结合可支撑亿级 | 种子内部异质性大时质心偏移 |

---

## 5. 聚类扩展法

### 5.1 K-Means Lookalike

**算法：**

```text
1. 对 U（或 C∪S）做 K-Means，得到簇 {C_1,...,C_K} 及中心 {μ_1,...,μ_K}
2. 统计种子在各簇的占比：p_k = |S ∩ C_k| / |S|
3. 选取 p_k > τ 的簇作为「种子簇」
4. 从种子簇中取候选用户（可排除已在 S 中的用户）
5. 簇内按到 μ_k 的距离排序
```

**目标函数：**

$$\min_{C_1,\ldots,C_K} \sum_{k=1}^{K} \sum_{u \in C_k} \|\mathbf{x}_u-\mathbf{\mu}_k\|^2$$


### 5.2 高斯混合模型（GMM）

假设数据来自 $K$ 个高斯分布的混合：

$$p(\mathbf{x}) = \sum_{k=1}^{K} \pi_k \mathrm{N}(\mathbf{x} \mid \mathbf{\mu}_k, \mathbf{\Sigma}_k)$$


**Lookalike 打分：**

$$s(u) = \sum_{k,\, p_k > \tau} p_k \cdot \mathrm{N}(\mathbf{x}_u \mid \mathbf{\mu}_k, \mathbf{\Sigma}_k)$$


GMM 比 K-Means 更适合椭圆簇、特征间有相关性的场景。

### 5.3 DBSCAN / HDBSCAN（密度聚类）

适合发现任意形状簇；将**与种子同簇**或**密度可达**的用户作为扩展对象。

```text
1. 对特征空间做 DBSCAN/HDBSCAN
2. 找到包含种子的核心簇
3. 将该簇内非种子用户按核心点距离排序输出
```

### 5.4 优缺点

| 优点 | 缺点 |
| --- | --- |
| 自然形成人群分群，便于解释 | K 值/密度参数敏感 |
| 可发现多模态种子（多个簇） | 高维下距离退化（维度灾难） |
| 计算相对轻量 | 对离群种子敏感 |

---

## 6. 分类模型法（最常用）

### 6.1 方法原理

构造二分类任务：

- 正类（$y=1$）：种子用户
- 负类（$y=0$）：随机采样或业务定义的负例

训练分类器 $f(\mathbf{x}) \to P(y=1 \mid \mathbf{x})$，对全量候选打分，概率越高越像种子。

这是 **Meta/Facebook Lookalike Audience** 的经典思路，也是工业界最主流的 lookalike 方案。

### 6.2 逻辑回归（LR）

**模型：**

$$P(y=1 \mid \mathbf{x}) = \sigma(\mathbf{w}^\top \mathbf{x} + b) = \frac{1}{1 + e^{-(\mathbf{w}^\top \mathbf{x} + b)}}$$


**损失函数（交叉熵）：**

$$\mathcal{L} = -\frac{1}{N} \sum_{i=1}^{N}\left[y_i \log \hat{p}_i + (1-y_i)\log(1-\hat{p}_i)\right] + \lambda \|\mathbf{w}\|_2^2$$


**Lookalike 分数：** $s(u) = P(y=1 \mid \mathbf{x}_u)$

**算法步骤：**

```text
1. 正样本：种子 S
2. 负样本：从 C 随机采样 |S|×ratio 个（ratio 通常 1~10）
3. 特征工程：归一化、交叉特征、WOE 编码（信贷常用）
4. 训练 LR（L1/L2 正则）
5. 对 C 全量预测 P(y=1|x)
6. 取 Top-K 或 P > threshold
```

### 6.3 梯度提升树（GBDT / XGBoost / LightGBM）

**模型：** 加法模型

$$\hat{y} = \sum_{m=1}^{M} \eta \cdot h_m(\mathbf{x})$$


每棵树 $h_m$ 拟合上一轮残差（回归）或对数几率（分类）。

**LightGBM 二分类目标（典型）：**

$$\mathcal{L} = \sum_i \left[ -y_i \log p_i - (1-y_i)\log(1-p_i) \right] + \sum_m \mathrm{pen}(h_m)$$


其中 $p_i = \sigma(\hat{y}_i)$，$\Omega$ 为正则项。

**算法步骤：**

```text
1. 构造训练集 D+ = S, D- = random_sample(C, |S|×ratio)
2. 合并 D = D+ ∪ D-，标签 y∈{0,1}
3. 训练 LightGBM（注意样本不平衡：scale_pos_weight = |D-|/|D+|）
4. 特征重要性分析 → 业务解释
5. 对 C 预测概率，排序扩量
6. 可用 SHAP 解释单用户得分
```

**放心借场景优势：** D101–D402 及外部字典特征以表格为主，GBDT 效果好、训练快、可解释。

### 6.4 随机森林（RF）

多棵决策树 Bagging 投票：

$$\hat{p}(u) = \frac{1}{T} \sum_{t=1}^{T} p_t(\mathbf{x}_u)$$


优点：鲁棒、无需太多调参；缺点：大数据下不如 GBDT 高效。

### 6.5 负采样策略（影响效果的关键）

| 策略 | 做法 | 适用 |
| --- | --- | --- |
| 随机负采样 | 从全量随机抽负例 | 通用基线 |
| 困难负采样 | 选模型当前预测概率较高的非种子用户 | 提升模型区分度 |
| 分层负采样 | 按渠道/城市/年龄段分层抽负例 | 避免人群偏差 |
| 时间窗口负采样 | 同期未转化用户作负例 | 营销场景 |

### 6.6 优缺点

| 优点 | 缺点 |
| --- | --- |
| 工业界验证最充分 | 负样本构造影响大 |
| 可捕捉非线性与特征交叉 | 种子少时易过拟合 |
| GBDT 在表格数据上效果优秀 | 全量打分成本较高（可分批/采样校准） |

---

## 7. PU Learning（正例-未标注学习）

### 7.1 方法原理

更贴合 lookalike 的真实设定：

- 种子 = 确定的正例（Positive）
- 候选池中非种子用户 = **未标注（Unlabeled）**，其中混有正例和负例
- 不强行将未标注用户标为负例

### 7.2 类先验（Class Prior）

设真实正例比例 $\pi = P(y=1)$，PU 学习需估计 $\pi$ 或用鲁棒方法绕过。

**Elkan-Noto 估计：**

从正例集和未标注集中估计 $\pi$，再训练分类器。

### 7.3 Spy 技术（经典 PU 算法）

```text
输入：正例集 P，未标注集 U，间谍比例 q
1. 从 P 中随机抽取 q·|P| 个「间谍」样本 S_spy，混入 U 形成 U'
2. 在 (P \ S_spy) ∪ U' 上训练分类器（将 U' 中样本暂作负例）
3. 用训练好的分类器对 U' 打分
4. 间谍样本的得分分布 → 确定可靠负例阈值 t
5. 将 U 中得分 < t 的样本标为可靠负例 RN
6. 在 P ∪ RN 上重新训练最终分类器
7. 对全量候选预测
```

### 7.4 Reliable Negative (RN) 学习

```text
1. 初始化：P = 种子，U = 候选池非种子
2. 迭代：
   a. 在 P ∪ (部分 U 作临时负例) 上训练分类器 f
   b. 对 U 预测，取低分样本加入可靠负例集 RN
   c. 直到 RN 稳定或达到迭代上限
3. 在 P ∪ RN 上训练最终模型
4. 全量打分
```

### 7.5 nnPU（Non-negative PU Learning）

**无偏风险估计：**

$$\hat{R}(f) = \pi \hat{R}_P^{+}(f) + \max\left(0, \hat{R}_U^{-}(f) - \pi \hat{R}_P^{-}(f)\right)$$


其中 $\hat{R}_P^{+}$ 为正例上的正风险，$\hat{R}_U^{-}$ 为未标注上的负风险。`max(0,·)` 保证风险非负，避免过拟合。

可用神经网络或 GBDT 作为分类器 $f$。

### 7.6 图上的 PU 学习（GPL 等）

当用户间有社交/设备/行为共现关系时，可构建用户图，用 GNN + PU Loss 做扩量（见第 9 节）。异配边与 **GPL** 详见 **《GPL模型精读.md》**（ICML 2024）。

### 7.7 优缺点

| 优点 | 缺点 |
| --- | --- |
| 更贴合「只有种子、无明确负例」 | 算法与调参更复杂 |
| 避免随机负采样偏差 | 类先验估计不准会影响效果 |
| 学术与工业界近年热点 | 工程落地案例相对分类法少 |

### 7.8 放心借建议

当种子质量好但负例难定义时（如「潜在可借用户」混在候选池中），**PU Learning 是比纯随机负采样更合理的建模方式**，建议作为 GBDT 基线的进阶方案。

---

## 8. 协同过滤与 Embedding 方法

### 8.1 矩阵分解（MF）

用户-物品交互矩阵 $R \in \mathbb{R}^{\lvert U \rvert \times \lvert I \rvert}$，分解为：

$$R \approx PQ^\top, \quad P \in \mathbb{R}^{\lvert U \rvert \times k}, Q \in \mathbb{R}^{\lvert I \rvert \times k}$$


**损失：**

$$\mathcal{L} = \sum_{(u,i) \in \mathcal{O}} (r_{ui} - \mathbf{p}_u^\top \mathbf{q}_i)^2 + \lambda(\|P\|^2 + \|Q\|^2)$$


用户 embedding $\mathbf{p}_u$ 用于计算种子质心相似度或训练下游分类器。

### 8.2 Item2Vec / User2Vec

将用户行为序列视为「句子」，用 Word2Vec 训练：

```text
输入：用户行为序列 [item_1, item_2, ..., item_n]
模型：Skip-gram / CBOW
输出：用户/物品 embedding
Lookalike：计算候选用户 embedding 与种子 embedding 质心的余弦相似度
```

### 8.3 双塔模型（Two-Tower / DSSM）

```text
用户塔：user_emb = MLP_user(user_features)
物品塔：item_emb = MLP_item(item_features)
相似度：sim(u,i) = cosine(user_emb, item_emb)
```

训练目标：点击/转化样本为正，随机配对为负（对比学习）。

**Lookalike 用法：**

1. 用种子用户特征过用户塔得 embedding
2. 候选用户同样过用户塔
3. 算 embedding 相似度排序

### 8.4 优缺点

| 优点 | 缺点 |
| --- | --- |
| 可融合行为序列信息 | 需要足够行为数据 |
| embedding 便于 ANN 检索 | 表格特征场景优势不明显 |
| 可预训练后复用 | 训练成本高于 GBDT |

### 8.5 放心借适用性

若后续引入用户**借款/还款/浏览/申请行为序列**，Embedding 方法价值更大；当前以 D 系列静态特征为主时，优先级低于 GBDT。

---

## 9. 图方法

### 9.1 用户相似图构建

构建图 $G = (V, E)$，节点为用户，边权重为相似度：

$$w_{uv} = \mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v) \cdot \mathbb{1}(\mathrm{sim} > \theta)$$


或用共同行为定义边：共同设备、共同联系人、共同 APP 等。

### 9.2 图约束 Lookalike（Yahoo 方案）

**核心公式：**

$$s(u) = \sum_{v \in S} w_{uv} \cdot \mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v)$$


在全局用户相似图上，对每个候选用户聚合与种子的边权，实现亚线性查询（通过图索引/局部搜索）。

```text
1. 离线：构建全局用户相似图（阈值稀疏化）
2. 在线：给定种子 S，对每个候选 u 聚合邻域种子相似度
3. 排序输出
```

### 9.3 标签传播（Label Propagation）

```text
初始化：种子节点 label=1，其余=0
迭代：
  对每个节点 u：
    y_u^(t+1) = α · Σ_{v∈N(u)} w_uv·y_v^(t) / Σw_uv + (1-α)·y_u^(0)
收敛后 y_u 即为 lookalike 分数
```

$\alpha \in (0,1)$ 为传播系数。

### 9.4 图神经网络（GCN / GraphSAGE）

**GCN 一层传播：**

$$\mathbf{H}^{(l+1)} = \sigma\left(\tilde{D}^{-\frac{1}{2}}\tilde{A}\tilde{D}^{-\frac{1}{2}}\mathbf{H}^{(l)}\mathbf{W}^{(l)}\right)$$


- $\tilde{A}$：邻接矩阵 + 自环
- $\mathbf{H}^{(0)} = \mathbf{X}$：节点特征矩阵

**训练：** 种子节点 $y=1$，随机采样子图负节点 $y=0$，最小化交叉熵。

**推断：** 对全图节点输出 $P(y=1 \mid \mathbf{x})$。

### 9.5 优缺点

| 优点 | 缺点 |
| --- | --- |
| 利用关系信息，扩展「二度相似」 | 需要图构建，工程复杂 |
| 适合社交网络、设备图谱 | 隐私与合规约束强（金融场景） |
| 可发现非特征相似的用户 | 大规模图训练成本高 |

### 9.6 放心借适用性

若有**设备指纹图谱、关联申请、共用联系人**等关系数据，图方法可显著提升扩量质量；纯特征表场景下非首选。

---

## 10. 深度学习方法

### 10.1 MLP 分类器

$$\mathbf{h}^{(l)} = \text{ReLU}(\mathbf{W}^{(l)}\mathbf{h}^{(l-1)} + \mathbf{b}^{(l)}), \quad \hat{p} = \sigma(\mathbf{w}^\top \mathbf{h}^{(L)})$$


与 LR 流程相同，用种子/负例训练，输出概率打分。适合高维稀疏特征（配合 Embedding 层处理类别特征）。

### 10.2 Wide & Deep

- **Wide**：线性模型 + 交叉特征（记忆）
- **Deep**：MLP（泛化）

$$P(y=1) = \sigma(\mathbf{w}_{\mathrm{wide}}^\top [\mathbf{x}, \phi(\mathbf{x})] + \text{MLP}(\mathbf{x}))$$


### 10.3 DeepFM

结合 FM 二阶交叉与 Deep 网络：

$$\hat{y} = \sigma\left(y_{\mathrm{FM}} + y_{\mathrm{Deep}}\right)$$

$$y_{\mathrm{FM}} = w_0 + \sum_i w_i x_i + \sum_{i \lt j} \langle \mathbf{v}_i, \mathbf{v}_j \rangle x_i x_j$$


### 10.4 对抗因子分解自编码器（Adversarial FA）

用于学习用户低维表示，使种子与候选在隐空间中可区分又可泛化（广告 lookalike 学术方案）。

**流程：**

```text
1. Autoencoder 学习用户表示 z = Encoder(x)
2. 判别器区分 z 来自种子还是非种子
3. 对抗训练使 Encoder 学到种子分布的「方向」
4. 用 z 的相似度或下游分类器扩量
```

### 10.5 LLM + 知识图谱（新兴方向）

将用户行为、商品文本、属性构建知识图谱，用 LLM 生成实体文本表示，再与结构化 embedding 联合训练（如 GLoM 模型），适合电商/内容场景。

### 10.6 优缺点

| 优点 | 缺点 |
| --- | --- |
| 表达能力强 | 需大量数据，种子少时易过拟合 |
| 可融合多模态 | 训练/推理成本高 |
| 可端到端学习 | 金融场景可解释性要求高 |

### 10.7 放心借建议

当前特征以表格为主、种子规模有限时，**LightGBM 通常优于 MLP/DeepFM**；深度学习可作为特征规模与行为数据丰富后的升级方向。

---

## 11. 向量检索与大规模扩量（ANN）

### 11.1 方法原理

当候选用户达亿级，无法全量跑模型逐条预测时，先用模型/embedding 将用户映射为向量，再用 **近似最近邻（ANN）** 检索。

### 11.2 典型流程

```text
1. 训练阶段：GBDT/双塔 → 用户向量 z_u（或直接用特征向量）
2. 索引构建：FAISS / ScaNN / HNSW 建索引
3. 查询阶段：
   - 计算种子质心 z_S = mean(z_u, u∈S)
   - ANN 检索 Top-K 最近邻
4. 可选精排：对 ANN 召回结果用 GBDT 精排
```

### 11.3 常用 ANN 算法

| 算法 | 原理 | 特点 |
| --- | --- | --- |
| **HNSW** | 分层可导航小世界图 | 召回高、查询快，工业界常用 |
| **IVF** | 倒排聚类，先找近簇再精确搜索 | 适合超大规模 |
| **LSH** | 局部敏感哈希 | 理论保证，召回略低 |
| **Product Quantization** | 向量乘积量化压缩 | 节省内存 |

### 11.4 两阶段架构（召回 + 精排）

```text
粗排（ANN 召回）：亿级 → 百万级
精排（GBDT/深度模型）：百万级 → 万级
业务规则过滤：万级 → 最终名单
```

这是大规模 lookalike 的标准工程架构。

---

## 12. 倾向性评分与 Uplift 方法

### 12.1 适用场景

不仅找「像种子」的用户，更找「被营销后会转化」的用户（因果视角）。

### 12.2 倾向性评分匹配（PSM）

**倾向性得分：**

$$e(\mathbf{x}) = P(T=1 \mid \mathbf{x})$$


$T=1$ 表示被营销/触达。

在得分相近的用户中比较转化差异，或直接用 $e(\mathbf{x})$ 与种子得分分布匹配。

### 12.3 Uplift 模型

估计个体处理效应：

$$\tau(\mathbf{x}) = P(Y=1 \mid T=1, \mathbf{x}) - P(Y=1 \mid T=0, \mathbf{x})$$


**常用算法：**

- **Two-Model**：分别训练 T=1 和 T=0 的转化模型，相减得 uplift
- **Class Transformation**：将标签变换后训练单模型
- **Causal Forest / Meta-Learner**（T/S/X-Learner）

**Lookalike 用法：** 先按相似度/分类模型找像种子的用户，再用 uplift 筛出「营销敏感」人群，提升 ROI。

---

## 13. 广告平台内置 Lookalike

### 13.1 Meta（Facebook）Lookalike Audience

| 项目 | 说明 |
| --- | --- |
| 输入 | 自定义受众（种子），规模建议 ≥ 1000 |
| 相似度范围 | 1%–10%（占平台用户比例） |
| 底层方法 | 未公开；业界推测为大规模 LR/GBDT + 相似度索引 |
| 输出 | 平台侧人群包，直接用于投放 |

### 13.2 Google Similar Audiences（已逐步停用）

基于第一方数据与 Google 生态行为，用相似度/分类模型在 Google 用户中扩展。2023 年起逐步被 **Optimized Targeting** 等替代。

### 13.3 腾讯广告 / 字节巨量引擎

| 平台 | 能力 |
| --- | --- |
| 腾讯 | 一方数据上传 → 拓展人群包；支持相似人群扩展 |
| 字节 | 种子人群包 → Lookalike 扩展；支持多维度相似度 |
| 通用流程 | 上传 seed → 平台建模 → 输出扩展包（黑盒） |

### 13.4 与自建模型对比

| 维度 | 平台内置 | 自建（GBDT/PU 等） |
| --- | --- | --- |
| 数据 | 平台生态行为（广） | 自有 + 外部征信/联合建模 |
| 可控性 | 低（黑盒） | 高（特征、规则、阈值可调） |
| 合规 | 平台负责 | 需自行审计 |
| 跨渠道 | 限平台内 | 可跨渠道复用 |
| 放心借 | 可用于投放引流 | 适合授信/风控/精细化运营 |

---

## 14. 评估指标

### 14.1 离线指标

| 指标 | 公式/说明 | 用途 |
| --- | --- | --- |
| AUC / PR-AUC | 分类区分度 | 模型质量 |
| KS | 正负分布最大差 | 信贷常用 |
| Precision@K | Top-K 中真实正例比例 | 扩量精度 |
| Recall@K | 找回多少潜在正例 | 扩量覆盖 |
| Lift@K | Top-K 转化率 / 随机转化率 | 业务提升 |
| 相似度分布 | 扩展人群与种子的特征分布 KL 散度 | 画像一致性 |

### 14.2 在线指标

- 触达转化率（CTR/CVR）
- 授信通过率 / 借款发起率
- 人均借款金额、风险逾期率
- ROI = 增量收益 / 营销成本

### 14.3 评估设计

```text
1. 时间切分：用 T 月种子训练，T+1 月验证
2. 留出法：20% 种子作验证，不参与训练
3. A/B 测试：扩展人群 vs 随机人群 vs 规则人群
4. 风险校验：扩展人群的 D401 风险分布不应显著差于种子
```

---

## 15. 方法对比与选型建议

### 15.1 综合对比

| 方法 | 实现难度 | 数据需求 | 效果上限 | 可解释性 | 大规模 | 推荐优先级（放心借） |
| --- | --- | --- | --- | --- | --- | --- |
| 规则/画像匹配 | ★☆☆ | 低 | ★★☆ | ★★★ | ★★★ | 基线/准入层 |
| 相似度+质心 | ★★☆ | 低 | ★★☆ | ★★☆ | ★★★ | 快速验证 |
| K-Means/GMM | ★★☆ | 中 | ★★☆ | ★★☆ | ★★★ | 辅助分群 |
| **LR/GBDT 分类** | ★★☆ | 中 | ★★★ | ★★☆ | ★★☆ | **首选** |
| PU Learning | ★★★ | 中 | ★★★ | ★★☆ | ★★☆ | 进阶 |
| Embedding/双塔 | ★★★ | 高 | ★★★ | ★☆☆ | ★★★ | 有行为序列时 |
| 图方法/GNN | ★★★ | 高 | ★★★ | ★☆☆ | ★★☆ | 有图谱时 |
| 深度学习 | ★★★ | 高 | ★★★ | ★☆☆ | ★★☆ | 数据量大时 |
| ANN 两阶段 | ★★★ | 中 | ★★★ | ★☆☆ | ★★★ | 亿级扩量 |
| 平台内置 | ★☆☆ | 中 | ★★☆ | ★☆☆ | ★★★ | 投放引流 |

### 15.2 推荐落地路线（放心借）

```text
Phase 1 — 基线（1–2 周）
  ├── 规则准入：D401 风险、D203 收入等硬过滤
  ├── 质心相似度：D101–D402 + 外部字典降维后 Cosine
  └── GBDT 分类：种子 vs 随机负采样，LightGBM 全量打分

Phase 2 — 优化（2–4 周）
  ├── 负采样优化：分层/困难负采样
  ├── PU Learning：替代随机负例
  ├── 特征交叉：征信 × 外部字典 × 自有 D 系列
  └── 评估：A/B + 风险分布监控

Phase 3 — 规模化（按需）
  ├── 两阶段：ANN 召回 + GBDT 精排
  ├── 多目标：相似度 + Uplift + 风险约束
  └── 平台扩量：腾讯/字节人群包与自建模型融合
```

### 15.3 特征使用建议（结合本项目数据）

| 特征来源 | 用途 | 方法建议 |
| --- | --- | --- |
| D101–D402（放心借特征变量） | 核心建模特征 | GBDT / LR 直接入模 |
| 客群明细表 | 种子圈选、标签 | 定义 Seed |
| 百行/朴道/腾讯外部字典 | 增强区分度 | WOE 编码 + GBDT；或 PCA 后相似度 |
| 征信特征（若后续接入） | 风险校验 | 规则过滤 + 模型特征 |

---

## 16. 参考文献与延伸阅读

1. Ma et al., *A Sub-linear, Massive-scale Look-alike Audience Extension System*, Yahoo!, 2016.
2. Liu et al., *Real-time Attention Based Look-alike Model for Recommender System*, KDD 2019.
3. Doan et al., *Adversarial Factorization Autoencoder for Look-alike Modeling*, CIKM 2019.
4. Zhu et al., *Learning to Expand Audience via Meta Hybrid Experts and Critics*, KDD 2021.
5. Rahman et al., *Exploring 360-Degree View of Customers for Lookalike Modeling*, 2023.
6. Wu et al., *Graph PU Learning with Label Propagation Loss (GPL)*, ICML 2024.
7. *Lookalike Audience Expansion: A Graph-Based Model with LLMs (GLoM)*, SIGIR eCom 2025.
8. Meta Business Help: [About Lookalike Audiences](https://www.facebook.com/business/help/lookalike-audiences)
9. Elkan & Noto, *Learning classifiers from only positive and unlabeled data*, KDD 2008.
10. Kiryo et al., *Positive-Unlabeled Learning with Non-Negative Risk Estimator (nnPU)*, NIPS 2017.

---



## 附录 C：飞书公式 LaTeX 原文（可直接复制）

> 块级公式为单行 `$$...$$`（KaTeX 语法），可直接复制到飞书文档使用。已避免转义花括号、冒号下标等飞书常见不兼容写法。

### 3.2 种子画像（离散特征）

$$P_{\mathrm{seed}}(f = v) = \frac{1}{\lvert S \rvert} \sum_{u \in S} \mathbb{1}(x_{u,f}=v)$$

### 3.2 种子画像（连续特征）

$$\mu_f = \frac{1}{\lvert S \rvert} \sum_{u \in S} x_{u,f}, \quad \sigma_f = \mathrm{std}(x_{u,f})$$

### 3.2 离散重叠得分

$$s_{\mathrm{disc}}(u) = \sum_f w_f \cdot P_{\mathrm{seed}}(f = x_{u,f})$$

### 3.2 连续高斯匹配

$$s_{\mathrm{cont}}(u) = \sum_f w_f \cdot \exp\left(-\frac{(x_{u,f}-\mu_f)^2}{2\sigma_f^2}\right)$$

### 4.2 余弦相似度

$$\mathrm{sim}(\mathbf{x}, \mathbf{y}) = \frac{\mathbf{x}^\top \mathbf{y}}{\|\mathbf{x}\|_2 \|\mathbf{y}\|_2}$$

### 4.2 欧氏距离相似度

$$\mathrm{sim}(\mathbf{x}, \mathbf{y}) = \frac{1}{1 + \|\mathbf{x}-\mathbf{y}\|_2}$$

### 4.2 Jaccard

$$J(A, B) = \frac{\lvert A \cap B \rvert}{\lvert A \cup B \rvert}$$

### 4.2 汉明距离

$$d_H(\mathbf{x}, \mathbf{y}) = \sum_{i=1}^{d} \mathbb{1}(x_i \neq y_i)$$

### 5.1 K-Means 目标

$$\min_{C_1,\ldots,C_K} \sum_{k=1}^{K} \sum_{u \in C_k} \|\mathbf{x}_u-\mathbf{\mu}_k\|^2$$

### 5.2 GMM 密度

$$p(\mathbf{x}) = \sum_{k=1}^{K} \pi_k \mathrm{N}(\mathbf{x} \mid \mathbf{\mu}_k, \mathbf{\Sigma}_k)$$

### 5.2 GMM 打分

$$s(u) = \sum_{k,\, p_k > \tau} p_k \cdot \mathrm{N}(\mathbf{x}_u \mid \mathbf{\mu}_k, \mathbf{\Sigma}_k)$$

### 6.2 LR 模型

$$P(y=1 \mid \mathbf{x}) = \sigma(\mathbf{w}^\top \mathbf{x} + b) = \frac{1}{1 + e^{-(\mathbf{w}^\top \mathbf{x} + b)}}$$

### 6.2 LR 损失

$$\mathcal{L} = -\frac{1}{N} \sum_{i=1}^{N}\left[y_i \log \hat{p}_i + (1-y_i)\log(1-\hat{p}_i)\right] + \lambda \|\mathbf{w}\|_2^2$$

### 6.3 GBDT 加法模型

$$\hat{y} = \sum_{m=1}^{M} \eta \cdot h_m(\mathbf{x})$$

### 6.3 LightGBM 损失

$$\mathcal{L} = \sum_i \left[ -y_i \log p_i - (1-y_i)\log(1-p_i) \right] + \sum_m \mathrm{pen}(h_m)$$

### 6.4 RF 投票

$$\hat{p}(u) = \frac{1}{T} \sum_{t=1}^{T} p_t(\mathbf{x}_u)$$

### 7.5 nnPU 风险

$$\hat{R}(f) = \pi \hat{R}_P^{+}(f) + \max\left(0, \hat{R}_U^{-}(f) - \pi \hat{R}_P^{-}(f)\right)$$

### 8.1 MF 分解

$$R \approx PQ^\top, \quad P \in \mathbb{R}^{\lvert U \rvert \times k}, Q \in \mathbb{R}^{\lvert I \rvert \times k}$$

### 8.1 MF 损失

$$\mathcal{L} = \sum_{(u,i) \in \mathcal{O}} (r_{ui} - \mathbf{p}_u^\top \mathbf{q}_i)^2 + \lambda(\|P\|^2 + \|Q\|^2)$$

### 9.1 图边权

$$w_{uv} = \mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v) \cdot \mathbb{1}(\mathrm{sim} > \theta)$$

### 9.2 Yahoo 打分

$$s(u) = \sum_{v \in S} w_{uv} \cdot \mathrm{sim}(\mathbf{x}_u, \mathbf{x}_v)$$

### 9.4 GCN 传播

$$\mathbf{H}^{(l+1)} = \sigma\left(\tilde{D}^{-\frac{1}{2}}\tilde{A}\tilde{D}^{-\frac{1}{2}}\mathbf{H}^{(l)}\mathbf{W}^{(l)}\right)$$

### 10.1 MLP

$$\mathbf{h}^{(l)} = \text{ReLU}(\mathbf{W}^{(l)}\mathbf{h}^{(l-1)} + \mathbf{b}^{(l)}), \quad \hat{p} = \sigma(\mathbf{w}^\top \mathbf{h}^{(L)})$$

### 10.2 Wide&Deep

$$P(y=1) = \sigma(\mathbf{w}_{\mathrm{wide}}^\top [\mathbf{x}, \phi(\mathbf{x})] + \text{MLP}(\mathbf{x}))$$

### 10.3 DeepFM

$$\hat{y} = \sigma\left(y_{\mathrm{FM}} + y_{\mathrm{Deep}}\right)$$

### 10.3 DeepFM-FM项

$$y_{\mathrm{FM}} = w_0 + \sum_i w_i x_i + \sum_{i \lt j} \langle \mathbf{v}_i, \mathbf{v}_j \rangle x_i x_j$$

### 12.2 倾向性得分

$$e(\mathbf{x}) = P(T=1 \mid \mathbf{x})$$

### 12.3 Uplift

$$\tau(\mathbf{x}) = P(Y=1 \mid T=1, \mathbf{x}) - P(Y=1 \mid T=0, \mathbf{x})$$

## 附录 A：LightGBM Lookalike 最小可行实现（伪代码）

```python
import lightgbm as lgb
import numpy as np

# 1. 构造训练集
seeds = load_seed_users()          # 种子
candidates = load_candidate_pool() # 候选池
neg = candidates.sample(n=len(seeds) * 5, random_state=42)

X_pos = extract_features(seeds)
X_neg = extract_features(neg)
X_train = np.vstack([X_pos, X_neg])
y_train = np.array([1]*len(X_pos) + [0]*len(X_neg))

# 2. 训练
params = {
    "objective": "binary",
    "metric": "auc",
    "scale_pos_weight": len(X_neg) / len(X_pos),
    "num_leaves": 63,
    "learning_rate": 0.05,
}
model = lgb.train(params, lgb.Dataset(X_train, y_train), num_boost_round=500)

# 3. 全量打分
X_all = extract_features(candidates)
scores = model.predict(X_all)

# 4. 业务过滤 + TopK
mask = apply_business_rules(candidates)  # 风险/合规
lookalike = candidates[mask].assign(score=scores[mask]).nlargest(100000, "score")
```

## 附录 B：质心相似度最小可行实现（伪代码）

```python
from sklearn.preprocessing import StandardScaler
from sklearn.metrics.pairwise import cosine_similarity

X_seed = extract_features(seeds)
X_cand = extract_features(candidates)

scaler = StandardScaler()
X_seed_s = scaler.fit_transform(X_seed)
X_cand_s = scaler.transform(X_cand)

centroid = X_seed_s.mean(axis=0, keepdims=True)
scores = cosine_similarity(X_cand_s, centroid).ravel()

lookalike = candidates.assign(score=scores).nlargest(100000, "score")
```
