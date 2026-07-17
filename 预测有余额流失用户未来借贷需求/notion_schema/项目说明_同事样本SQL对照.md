# 项目说明：同事样本 SQL 对照分析

> 同事参考脚本：`sql/yye_pril_bal_sample_reference.sql`  
> 我方特征脚本：`sql/yye_credit_feature_process.sql`  
> 标签说明：`项目说明_标签构建.md`

---

## 一、同事 SQL 加工链路（3+2 步）

| 步骤 | 产出表 | 作用 |
|------|--------|------|
| 1 | `yye_pril_bal_info_20260623` | 10 月每日快照，算额度利用率，标 `rk=1`（月内最低利用率日） |
| 2 | `yye_pril_bal_info_20260623_1` | 仅保留 `rk=1`，加工 `no_balance_flg_30/60/90` |
| 3 | `yye_pril_bal_info_20260623_2` | 加工 `had_*_zx`、`with_*`；定义 **`days_dt_1 = date_sub(days_dt, 1)`** |
| 4 | `yye_pril_bal_info_20260623_3/_4` | 关联征信账户明细，算 forward 60 天余额，打 `label` |

我方 **Step 0** 仅执行：`create table jcr_pril_bal_info as select * from yye_pril_bal_info_20260623_2`  
→ 样本字段来自同事 **第 3 步**，征信特征与 label 由我方 Step 1～7 重算。

---

## 二、关键口径（易错点）

### 2.1 样本底池：不是「全渠道 502 万」

同事 Step 1 源表与过滤：

```sql
from lj_iceberg.iayh_mkt.ayh_mkt_yx_cust_type_union_df
where dt between '20251002' and '20251101'
  and sx_rowid = 1
  and prod_cd = '5103'           -- ★ 仅产品 5103，不是全渠道
  and if_lend = '复贷'
  and cust_types_01 = '有余额'
  and crdt_lim_yx > 0            -- ★ 此处仅 >0，>=20000 在后面才加
```

| 口径 | 人数（参考） |
|------|-------------|
| 业务文档「全渠道 ≥2 万」 | **5,022,793** |
| 同事 `prod_cd=5103` 复贷有余额（我方复制的 `_2` 表） | **~4,196,692**（`crdt_lim_yx>=20000`） |

**结论**：502 万与 419 万的差距，主要是 **渠道/产品范围不同**（全渠道 vs `5103`），不是我方特征 SQL 算错。

### 2.2 两个日期字段：days_dt vs days_dt_1

| 字段 | 同事定义 | 用途 |
|------|----------|------|
| `days_dt` | `rk=1` 那天（月内额度利用率**最低**日） | 加工 `no_balance_flg_*` 的起点 |
| `days_dt_1` | **`date_sub(days_dt, 1)`**（最低利用率日的**前一天**） | 加工 `had_*_zx`、`with_*` 的起点；征信 label 窗 `days_dt_1 ~ +60` |

```
        days_dt_1          days_dt (= rk=1 最低利用率日)
           |-------------------|
           |    no_balance 从 days_dt 起算 |
           |-------------------|-------------------> +60/+90 天
     had/with/zx 从 days_dt_1 起算
```

我方特征 Step 5 使用样本表里的 `days_dt_1` 做时间窗，**与同事一致**（前提是 `_2` 表由同事脚本生成）。

### 2.3 had_*_zx 分段（与文档 5401 一致部分）

```sql
had_0_30_zx  : days_dt_zx between days_dt_1 and days_dt_1 + 30
had_31_60_zx : days_dt_zx between days_dt_1 + 31 and days_dt_1 + 60
had_61_90_zx : days_dt_zx between days_dt_1 + 61 and days_dt_1 + 90
```

业务文档 5,401：**第 0～30 日 + 第 31～60 日有征信** → `had_0_30_zx=1 AND had_31_60_zx=1`。

### 2.4 no_balance / with 的锚点不同

| 指标 | 锚点日期 | 同事 SQL |
|------|----------|----------|
| `no_balance_flg_60` | **`days_dt`**（rk=1 日） | `t2.days_dt between t1.days_dt and t1.days_dt+60` |
| `with_0_30/31_60` | **`days_dt_1`** | 提现表 `day_time` 在 `days_dt_1` 起算窗口 |
| `had_*_zx` | **`days_dt_1`** | 征信 `days_dt_zx` 在 `days_dt_1` 起算窗口 |

无余额与提现/征信的锚点相差 **1 天**，这是同事代码的刻意设计，不是我方字段用错。

---

## 三、5401 vs 4797：到底差在哪

### 3.1 三套口径并存（容易混）

| 来源 | 条件摘要 | 预期人数 |
|------|----------|----------|
| **业务文档** | ≥2 万；`days_dt_1` 后 0～60 日；had 0～30 且 31～60 | **5,401** |
| **同事统计 SELECT**（`_2` 表） | ≥2 万；had 0～30、31～60、**61～90、91～120 全为 1** | 另一套统计（更严） |
| **同事 label SELECT**（`_4` 表） | ≥2 万；had 0～30、31～60、61～90；**no_balance_90**；**with 0～90 为 0** | 3511+1890 |
| **我方当前核验 SQL** | ≥2 万；had 0～30、31～60；**no_balance_60**；**with 0～60 为 0**；label 非空 | **4,797** |

### 3.2 我方 4797 vs 文档 5401（差 604）

在 **同一张 `_2` 样本表** 前提下，最可能原因：

| # | 差异点 | 说明 |
|---|--------|------|
| 1 | **文档 5401 可能不含 no_balance / with** | 你文档原文只写了两段 had 征信；604 人可能因多加 `no_balance_60`+`with` 被剔除 |
| 2 | **同事 label 用 90 天，文档写 60 天** | 同事最后一查用 `no_balance_flg_90`、`with_61_90`，与业务文档 0～60 **不一致** |
| 3 | **label 非空** | 我方要求 `label is not null`；同事先圈人再算 `first_balance/balance_max` |
| 4 | **底池** | 文档 502 万为全渠道；我方 419 万为 `5103` 产品 |

### 3.3 建议用同事 `_2` 表直接复现（在你有权限的环境跑）

```sql
-- A. 仅征信两段（对齐文档 5401 字面）
select count(1) as cnt_doc_zx
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1;

-- B. 文档 + 无余额60 + 未贷款60（我方当前口径 → 应接近 4797）
select count(1) as cnt_ours
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;

-- C. 同事 label 口径（最后一查）
select count(1) as cnt_colleague_label
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1 and had_61_90_zx = 1
  and no_balance_flg_90 = 1
  and with_0_30 + with_31_60 + with_61_90 = 0;
```

- 若 **A ≈ 5401** → 5401 只统计两段征信，不含无余额/未贷款；我方应去掉 B 中后两条再对齐文档。  
- 若 **C ≈ 3511+1890** → 以同事最后一查为准做 label  cohort，而非业务文档 60 天版。

---

## 四、我方特征/标签链与同事的差异

| 项目 | 同事 | 我方 `yye_credit_feature_process.sql` |
|------|------|--------------------------------------|
| 样本来源 | 3 步自建 `_2` | 复制 `_2` → `jcr_pril_bal_info` |
| 征信 had 源表 | `credit_loan_summary` | 同左 + 账户级聚合 |
| 提现 with | `dec_intel_eng_user_fact_wdraw_apply_df` | 用样本表预计算字段 |
| label 余额 | `_4` 表 `zx_rank=1` 的 balance vs max | `fwd_first_balance` / `fwd_max_balance`（`bal_sum` 报告级） |
| 剔马消 | `org_manage_code <> T10156530H0001` | 同左 |
| forward 窗 | `days_dt_1 ~ +60` | `flg_fwd_60d`（`days_dt_1 ~ +60`） |

label 正负比例已对齐（~35%），差异主要在 **cohort 圈选条件** 与 **底池范围**。

---

## 五、问题定位结论（给落地用）

1. **502 万 vs 419 万**：全渠道 vs `prod_cd=5103` 复贷有余额，需向同事确认 5401 基于哪个底池。  
2. **5401 vs 4797**：优先在 `_2` 表跑 **3.3 节 A/B/C**，确认 5401 是否包含 no_balance/with。  
3. **业务文档 vs 同事最后一查**：文档写 0～60 天；同事 label 用 90 天无余额 + 90 天未贷款 → **需同事确认以哪个为准**。  
4. **我方特征链路**：样本字段继承 `_2` 正确；Step 5～7 时间锚点用 `days_dt_1` 与同事一致；无需为 4797/5401 改特征宽表逻辑，应先统一 **label cohort WHERE**。

---

## 六、建议下一步

1. 在能访问 `iayh_mkt` / 提现表的环境，用同事完整 3 步重建 `_2`，再复制到 `jcr_pril_bal_info`。  
2. 跑 **3.3 节 A/B/C**，把三个 `cnt` 发同事确认哪个对应文档 5,401。  
3. 确定最终 cohort 后，更新 `项目说明_标签构建.md` §2.2 与 Step 9 核验 SQL（唯一标准口径）。
