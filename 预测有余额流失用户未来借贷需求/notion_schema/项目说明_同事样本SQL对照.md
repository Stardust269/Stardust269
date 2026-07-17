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

## 三、5401 口径（已确认）

### 3.1 同事统计查询（`_2` 表，输出 num=5401）

```sql
select count(1) as num, count(distinct uuid) as usr_num
from lj_iceberg.ai_decision_dev.yye_pril_bal_info_20260623_2
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;
```

**不含** `no_balance_flg_*`、`with_*`。我方 `cohort_eligible=1` 与此完全一致。

### 3.2 打 label 子集（同事 `_4` 最后一查，约 3511+1890）

在 5401 上再叠：

```sql
and no_balance_flg_90 = 1
and with_0_30 + with_31_60 + with_61_90 = 0
```

我方对应字段：`label_eligible=1`。

### 3.3 三套口径对照

| 来源 | 条件摘要 | 预期人数 |
|------|----------|----------|
| **同事统计 SELECT**（`_2` 表） | ≥2 万；had 0～30/31～60/61～90/91～120 全为 1 | **5,401** |
| **同事 label SELECT**（`_4` 表） | 5401 子集 + no_balance_90 + with 0～90 为 0 | **~5,401 子集 → 3511+1890** |
| **业务文档（字面）** | ≥2 万；仅 had 0～30、31～60 | 与 5401 不同，勿混用 |

### 3.4 核验 SQL（我方产出）

```sql
-- 应对齐 5401
select count(1) as cohort_cnt, count(distinct uuid) as uuid_cnt
from lj_iceberg.ai_decision_dev.jcr_credit_feature_label_20260623
where cohort_eligible = 1;

-- 在 jcr_pril_bal_info 上直接核验（Step 0c 后）
select count(1) as cohort_5401_cnt
from lj_iceberg.ai_decision_dev.jcr_pril_bal_info_20260623
where crdt_lim_yx >= 20000
  and had_0_30_zx = 1 and had_31_60_zx = 1
  and had_61_90_zx = 1 and had_91_120_zx = 1;
```

---

## 四、我方特征/标签链与同事的差异

| 项目 | 同事 | 我方 `yye_credit_feature_process.sql` |
|------|------|--------------------------------------|
| 样本来源 | 3 步自建 `_2` | Step 0a～0c 自建 `jcr_pril_bal_info` |
| cohort 圈选 | `_2` 统计查询 4 段 had | Step 5 起 `cohort_eligible=1`（5401） |
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
2. **5401**：以同事 `_2` 统计查询为准（4 段 had + `crdt_lim>=20000`），**不含** no_balance/with。  
3. **打 label**：在 5401 上用 `label_eligible`（no_balance_90 + with 0～90=0）。  
4. **最终产出**：`jcr_credit_feature_label_20260623` 中 `cohort_eligible=1` 应为 **5401 行**，含《需要加工的数据》全部特征。

---

## 六、建议下一步

1. 重跑 Step 0a～0c，核验 `jcr_pril_bal_info` 上 cohort 计数 = **5401**。  
2. 重跑 Step 5～7（或全链路），核验 `jcr_credit_feature_label` 行数 = **5401**。  
3. 标签分布：`where cohort_eligible=1 and label_eligible=1 and label is not null`。
