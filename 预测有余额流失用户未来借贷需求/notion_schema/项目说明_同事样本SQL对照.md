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

我方 **Step 0a～0c** 自建 `jcr_pril_bal_info_20260623`（对齐同事 `_2` 表逻辑）  
→ 征信特征与 label 由我方 Step 1～7 重算；**Step 5 起仅保留 cohort_5401**。

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

## 三、5401 口径（同事 2026-07 确认版）

### 3.1 最后一查 WHERE（**5401 样本**）

```sql
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  -- 不含 had_61_90_zx、had_91_120_zx
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0
```

| 与旧版差异 | 旧（错误） | 新（正确） |
|------------|-----------|-----------|
| had 段数 | 3~4 段 | **仅 0~30、31~60** |
| 无余额 | `no_balance_flg_90` | **`no_balance_flg_60`** |
| 无提现 | 90 天窗 | **60 天窗** `with_0_30+with_31_60=0` |

我方 `cohort_eligible=1` 与此完全一致。

### 3.2 统计 SELECT（_2 表，非 5401 来源）

第一段统计查询仍用 4 段 had，其 `num` 在我方约 33 万；**5401 来自最后一查，不是该 num**。

### 3.3 核验

```sql
select count(1) as cnt_cohort
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and no_balance_flg_60 = 1
  and with_0_30 + with_31_60 = 0;
```

完整脚本：`sql/verify_cohort_5401.sql`

---

## 四、我方特征/标签链与同事的差异

| 项目 | 同事 | 我方 `yye_credit_feature_process.sql` |
|------|------|--------------------------------------|
| 样本来源 | 3 步自建 `_2` | Step 0a～0c 自建 `jcr_pril_bal_info` |
| cohort 圈选 | 最后一查（2 had + nb60 + with60） | Step 5 起 `cohort_eligible=1`（5401） |
| label 子集 | `_4` 最后一查 | `label_eligible=1` |
| 征信 had 源表 | `credit_loan_summary` | 同左 + 账户级聚合 |
| 提现 with | `dec_intel_eng_user_fact_wdraw_apply_df` | 用样本表预计算字段 |
| label 余额 | `_4` 表 `zx_rank=1` 的 balance vs max | `fwd_first_balance` / `fwd_max_balance`（`bal_sum` 报告级） |
| 剔马消 | `org_manage_code <> T10156530H0001` | 同左 |
| forward 窗 | `days_dt_1 ~ +60` | `flg_fwd_60d`（`days_dt_1 ~ +60`） |

label 正负比例已对齐（~35%），差异主要在 **底池范围**（全渠道 vs `5103`）。

---

## 五、问题定位结论（给落地用）

1. **502 万 vs 419 万**：全渠道 vs `prod_cd=5103` 复贷有余额。  
2. **5401**：同事最后一查 — 2 段 had + `no_balance_60` + 60 天无提现。  
3. **重跑**：drop B1 → Step 5~7（样本 Step 0 可保留）。  
4. **最终产出**：`jcr_credit_feature_label_20260623` 中 `cohort_eligible=1` 应为 **5401 行**（需用同事 `yye_pril_bal_info_20260623_2` 复制样本；自建 Step0 目前约 **488** 行）。

---

## 六、历史排查：488 的原因

曾用错误口径（3 段 had + `no_balance_90` + 90 天无提现）仅筛出 ~488 人。  
改为同事确认版（2 段 had + `no_balance_60` + 60 天无提现）后应 ≈ **5401**。

---

## 七、建议下一步

1. 在 `jcr_pril_bal_info` 跑 `verify_cohort_5401.sql` 第 1 条，应 ≈ 5401。  
2. drop B1 后重跑 Step 5~7。  
3. `cohort_eligible=1` 应 ≈ 5401。
