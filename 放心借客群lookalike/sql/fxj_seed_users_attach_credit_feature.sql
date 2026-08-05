-- =============================================================================
-- 放心借 lookalike：样本表挂征信特征（仅最近一次征信报告，不含马消特征）
-- =============================================================================
-- 输入：
--   lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature
-- 约定：
--   - days_dt_zx、dt_zx：样本侧「最近一次征信报告」日期（不再 row_number 选报告）
--   - 借贷账户：basic 中全部 account_type 参与加工，按类型拆列（宽表）+ 长表中间层
--   - 0 / null：有报告且可从报告/账户明细推出「没有」→ 0；无法推出 → null（如 max/min/util）
--   - 余额类 sum/count 在有报告 (zx_id_unqf 非空) 时对账户聚合 coalesce 为 0
--   - 剔马消机构码 T10156530H0001（仅影响余额/额度类汇总，与 jcr 一致）
-- 数值类型约定（避免 Spark/Hive 除法把比例升成 decimal(38,20) 撑大宽表）：
--   - 金额（元）：decimal(18, 2)（credit_amount / balance / 额度汇总等）
--   - 比例（使用率、余额/额度比，无量纲，通常 0~1）：decimal(10, 6)
-- 比例列清单（凡除法结果均 cast，勿依赖引擎默认精度）：
--   util_rate → util_max / util_min / util_sum → latest_util_* ；
--   credit_util_rate → latest_credit_util_rate
-- 特征金额盖帽（建模用，非人行真值回显；同事约定）：
--   整数部分超过 7 位（|金额| > 9_999_999）→ 1_000_000 元；null 仍为 null
--   适用于余额/授信/逾期金额等；计数、比例、flag 不盖帽
-- 输出：
--   ..._feature_with_credit（样本 + 报告扩展 + 分类型账户宽表 + 全类型合计 latest_*）
-- 中间表：
--   fxj_seed_credit_report_agg_by_type（长表，按 account_type）
-- =============================================================================

-- ########## 0. 探查 ##########
-- desc lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature;
-- select account_type, count(1) from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
-- where dt >= '20240801' and dt < '20260701' group by account_type;

-- ########## 1. 报告锚点 + summary 证件号 ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_zx_spine;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_zx_spine as
select unique_id, dt_zx, days_dt_zx, id_unqf
from (
    select
        sp.unique_id,
        sp.dt_zx,
        sp.days_dt_zx,
        z.id_unqf,
        row_number() over (
            partition by sp.unique_id, sp.dt_zx
            order by z.id_unqf
        ) as rn
    from (
        select distinct
            unique_id,
            dt_zx,
            days_dt_zx
        from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature
        where dt_zx is not null
          and trim(cast(dt_zx as string)) <> ''
    ) sp
    left join (
        select id_unqp, id_unqf, dt
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary
        where dt >= '20240801'
          and dt < '20260701'
        group by id_unqp, id_unqf, dt
    ) z
        on sp.unique_id = z.id_unqp
       and sp.dt_zx = z.dt
) t
where rn = 1
;

-- ########## 2. 借贷账户明细（全部 account_type，仅 spine 上的 uuid + dt_zx）##########
-- 易 OOM（exit 137）：勿先扫全量 PBOC perform 再 join spine；勿在全表 1m_perform 上做 row_number。
-- 顺序：spine 驱动 perform+basic → staging → 仅对 staging 账户键过滤 1m 取 bill_day → account_base。
-- 本段建议单独提交 Spark，并加大 executor memoryOverhead（见 model/sql/spark_oom_notes.md）。

drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_stg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_stg as
select
    t1.id_unqf,
    t1.id_unqp,
    t1.account_no,
    t2.account_id,
    coalesce(
        cast(
            case
                when abs(coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)) > cast(9999999 as decimal(18, 2))
                then cast(1000000 as decimal(18, 2))
                else coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
            end as decimal(18, 2)
        ),
        0
    ) as balance,
    t2.org_manage_type,
    t2.org_manage_code,
    coalesce(
        cast(
            case
                when abs(coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)) > cast(9999999 as decimal(18, 2))
                then cast(1000000 as decimal(18, 2))
                else coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
            end as decimal(18, 2)
        ),
        0
    ) as credit_grant_amount,
    coalesce(nullif(trim(t2.account_type), ''), '_UNK') as account_type,
    t1.dt,
    concat(substr(t1.dt, 1, 4), '-', substr(t1.dt, 5, 2), '-', substr(t1.dt, 7, 2)) as days_dt_zx,
    case
        when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
         and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
        then cast(
            coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
            / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
            as decimal(10, 6)
        )
        else null
    end as util_rate,
    case when coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0 then 1 else 0 end as is_pos_bal_acct,
    case when t2.org_manage_code <> 'T10156530H0001' then 1 else 0 end as is_non_mx
from lj_iceberg.ai_decision_dev.fxj_seed_zx_spine sp
inner join (
    select id_unqf, id_unqp, account_no, close_date, balance, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform
    where dt >= '20240801'
      and dt < '20260701'
      and (close_date is null or cast(close_date as string) = '')
) t1
    on sp.unique_id = t1.id_unqp
   and sp.dt_zx = t1.dt
inner join (
    select id_unqf, id_unqp, account_no, account_id, account_type,
           org_manage_type, org_manage_code, credit_grant_amount, dt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801'
      and dt < '20260701'
) t2
    on t1.id_unqf = t2.id_unqf
   and t1.id_unqp = t2.id_unqp
   and t1.account_no = t2.account_no
   and t1.dt = t2.dt
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base as
select
    s.id_unqf,
    s.id_unqp,
    s.account_no,
    s.account_id,
    s.balance,
    s.org_manage_type,
    s.org_manage_code,
    s.credit_grant_amount,
    s.account_type,
    s.dt,
    s.days_dt_zx,
    case
        when t3.settle_date is null or cast(t3.settle_date as string) = '' then null
        else cast(day(cast(t3.settle_date as date)) as int)
    end as bill_day,
    s.util_rate,
    s.is_pos_bal_acct,
    s.is_non_mx
from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_stg s
left join (
    select id_unqf, id_unqp, account_no, dt, settle_date
    from (
        select
            m.id_unqf,
            m.id_unqp,
            m.account_no,
            m.dt,
            m.settle_date,
            row_number() over (
                partition by m.id_unqf, m.id_unqp, m.account_no, m.dt
                order by coalesce(m.info_dt, m.settle_date) desc, m.month desc
            ) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_1m_perform m
        inner join (
            select distinct id_unqf, id_unqp, account_no, dt
            from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_stg
        ) k
            on m.id_unqf = k.id_unqf
           and m.id_unqp = k.id_unqp
           and m.account_no = k.account_no
           and m.dt = k.dt
        where m.dt >= '20240801'
          and m.dt < '20260701'
    ) x
    where rn = 1
) t3
    on s.id_unqf = t3.id_unqf
   and s.id_unqp = t3.id_unqp
   and s.account_no = t3.account_no
   and s.dt = t3.dt
;

-- ########## 3a. 按 account_type 报告级聚合（长表）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_by_type;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_by_type as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    account_type,
    count(1) as acct_cnt,
    sum(if(is_pos_bal_acct = 1 and is_non_mx = 1, 1, 0)) as pos_bal_acct_cnt,
    cast(
        case
            when abs(sum(if(is_non_mx = 1, balance, 0))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(if(is_non_mx = 1, balance, 0))
        end as decimal(18, 2)
    ) as bal_sum,
    cast(
        case
            when max(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null)) is null then null
            when abs(max(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else max(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null))
        end as decimal(18, 2)
    ) as bal_max,
    cast(
        case
            when min(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null)) is null then null
            when abs(min(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else min(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, null))
        end as decimal(18, 2)
    ) as bal_min,
    cast(
        case
            when abs(sum(if(is_non_mx = 1, credit_grant_amount, 0))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(if(is_non_mx = 1, credit_grant_amount, 0))
        end as decimal(18, 2)
    ) as crdt_sum,
    cast(
        case
            when max(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null)) is null then null
            when abs(max(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else max(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null))
        end as decimal(18, 2)
    ) as crdt_max,
    cast(
        case
            when min(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null)) is null then null
            when abs(min(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else min(if(is_pos_bal_acct = 1 and is_non_mx = 1, credit_grant_amount, null))
        end as decimal(18, 2)
    ) as crdt_min,
    cast(max(if(is_pos_bal_acct = 1 and is_non_mx = 1, util_rate, null)) as decimal(10, 6)) as util_max,
    cast(min(if(is_pos_bal_acct = 1 and is_non_mx = 1, util_rate, null)) as decimal(10, 6)) as util_min,
    cast(
        case
            when sum(if(is_non_mx = 1, credit_grant_amount, 0)) > 0
            then sum(if(is_non_mx = 1, balance, 0))
                 / sum(if(is_non_mx = 1, credit_grant_amount, 0))
            else null
        end as decimal(10, 6)
    ) as util_sum,
    count(distinct if(is_pos_bal_acct = 1 and is_non_mx = 1 and bill_day is not null, bill_day, null)) as bill_day_cnt
from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base
group by id_unqp, id_unqf, dt, days_dt_zx, account_type
;

-- ########## 3b. 全类型合计（兼容 latest_* 命名）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    sum(pos_bal_acct_cnt) as pos_bal_acct_cnt,
    cast(
        case
            when abs(sum(bal_sum)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(bal_sum)
        end as decimal(18, 2)
    ) as bal_sum,
    cast(
        case
            when max(bal_max) is null then null
            when abs(max(bal_max)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else max(bal_max)
        end as decimal(18, 2)
    ) as bal_max,
    cast(
        case
            when min(bal_min) is null then null
            when abs(min(bal_min)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else min(bal_min)
        end as decimal(18, 2)
    ) as bal_min,
    cast(
        case
            when abs(sum(crdt_sum)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(crdt_sum)
        end as decimal(18, 2)
    ) as crdt_sum,
    cast(
        case
            when max(crdt_max) is null then null
            when abs(max(crdt_max)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else max(crdt_max)
        end as decimal(18, 2)
    ) as crdt_max,
    cast(
        case
            when min(crdt_min) is null then null
            when abs(min(crdt_min)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else min(crdt_min)
        end as decimal(18, 2)
    ) as crdt_min,
    cast(max(util_max) as decimal(10, 6)) as util_max,
    cast(min(util_min) as decimal(10, 6)) as util_min,
    cast(
        case when sum(crdt_sum) > 0 then sum(bal_sum) / sum(crdt_sum) else null end
        as decimal(10, 6)
    ) as util_sum,
    sum(bill_day_cnt) as bill_day_cnt
from lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_by_type
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- ########## 3c. 按类型透视宽表（显式枚举 + OTHER；若集群出现新类型请补列或归入 OTHER）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_pivot;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_pivot as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    max(case when account_type = 'D1' then pos_bal_acct_cnt else 0 end) as zx_D1_pos_bal_acct_cnt,
    max(case when account_type = 'D1' then bal_sum else 0 end) as zx_D1_bal_sum,
    max(case when account_type = 'D1' then bal_max else null end) as zx_D1_bal_max,
    max(case when account_type = 'D1' then crdt_sum else 0 end) as zx_D1_crdt_sum,
    max(case when account_type = 'D1' then acct_cnt else 0 end) as zx_D1_acct_cnt,
    max(case when account_type = 'R1' then pos_bal_acct_cnt else 0 end) as zx_R1_pos_bal_acct_cnt,
    max(case when account_type = 'R1' then bal_sum else 0 end) as zx_R1_bal_sum,
    max(case when account_type = 'R1' then bal_max else null end) as zx_R1_bal_max,
    max(case when account_type = 'R1' then crdt_sum else 0 end) as zx_R1_crdt_sum,
    max(case when account_type = 'R1' then acct_cnt else 0 end) as zx_R1_acct_cnt,
    max(case when account_type = 'R2' then pos_bal_acct_cnt else 0 end) as zx_R2_pos_bal_acct_cnt,
    max(case when account_type = 'R2' then bal_sum else 0 end) as zx_R2_bal_sum,
    max(case when account_type = 'R2' then bal_max else null end) as zx_R2_bal_max,
    max(case when account_type = 'R2' then crdt_sum else 0 end) as zx_R2_crdt_sum,
    max(case when account_type = 'R2' then acct_cnt else 0 end) as zx_R2_acct_cnt,
    max(case when account_type = 'R3' then pos_bal_acct_cnt else 0 end) as zx_R3_pos_bal_acct_cnt,
    max(case when account_type = 'R3' then bal_sum else 0 end) as zx_R3_bal_sum,
    max(case when account_type = 'R3' then bal_max else null end) as zx_R3_bal_max,
    max(case when account_type = 'R3' then crdt_sum else 0 end) as zx_R3_crdt_sum,
    max(case when account_type = 'R3' then acct_cnt else 0 end) as zx_R3_acct_cnt,
    max(case when account_type = 'R4' then pos_bal_acct_cnt else 0 end) as zx_R4_pos_bal_acct_cnt,
    max(case when account_type = 'R4' then bal_sum else 0 end) as zx_R4_bal_sum,
    max(case when account_type = 'R4' then bal_max else null end) as zx_R4_bal_max,
    max(case when account_type = 'R4' then crdt_sum else 0 end) as zx_R4_crdt_sum,
    max(case when account_type = 'R4' then acct_cnt else 0 end) as zx_R4_acct_cnt,
    max(case when account_type = 'R5' then pos_bal_acct_cnt else 0 end) as zx_R5_pos_bal_acct_cnt,
    max(case when account_type = 'R5' then bal_sum else 0 end) as zx_R5_bal_sum,
    max(case when account_type = 'R5' then bal_max else null end) as zx_R5_bal_max,
    max(case when account_type = 'R5' then crdt_sum else 0 end) as zx_R5_crdt_sum,
    max(case when account_type = 'R5' then acct_cnt else 0 end) as zx_R5_acct_cnt,
    max(case when account_type = 'D2' then pos_bal_acct_cnt else 0 end) as zx_D2_pos_bal_acct_cnt,
    max(case when account_type = 'D2' then bal_sum else 0 end) as zx_D2_bal_sum,
    max(case when account_type = 'D2' then bal_max else null end) as zx_D2_bal_max,
    max(case when account_type = 'D2' then crdt_sum else 0 end) as zx_D2_crdt_sum,
    max(case when account_type = 'D2' then acct_cnt else 0 end) as zx_D2_acct_cnt,
    max(case when account_type = 'C1' then pos_bal_acct_cnt else 0 end) as zx_C1_pos_bal_acct_cnt,
    max(case when account_type = 'C1' then bal_sum else 0 end) as zx_C1_bal_sum,
    max(case when account_type = 'C1' then bal_max else null end) as zx_C1_bal_max,
    max(case when account_type = 'C1' then crdt_sum else 0 end) as zx_C1_crdt_sum,
    max(case when account_type = 'C1' then acct_cnt else 0 end) as zx_C1_acct_cnt,
    max(case when account_type = 'C2' then pos_bal_acct_cnt else 0 end) as zx_C2_pos_bal_acct_cnt,
    max(case when account_type = 'C2' then bal_sum else 0 end) as zx_C2_bal_sum,
    max(case when account_type = 'C2' then bal_max else null end) as zx_C2_bal_max,
    max(case when account_type = 'C2' then crdt_sum else 0 end) as zx_C2_crdt_sum,
    max(case when account_type = 'C2' then acct_cnt else 0 end) as zx_C2_acct_cnt,
    sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else pos_bal_acct_cnt end) as zx_OTH_pos_bal_acct_cnt,
    cast(
        case
            when abs(sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else bal_sum end))
                > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else bal_sum end)
        end as decimal(18, 2)
    ) as zx_OTH_bal_sum,
    max(case when account_type not in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then bal_max else null end) as zx_OTH_bal_max,
    cast(
        case
            when abs(sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else crdt_sum end))
                > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else crdt_sum end)
        end as decimal(18, 2)
    ) as zx_OTH_crdt_sum,
    sum(case when account_type in ('D1','R1','R2','R3','R4','R5','D2','C1','C2') then 0 else acct_cnt end) as zx_OTH_acct_cnt
from lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_by_type
group by id_unqp, id_unqf, dt, days_dt_zx
;

drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg as
select
    id_unqp,
    id_unqf,
    dt,
    days_dt_zx,
    max(acct_cnt_same_billday) as same_billday_acct_cnt_max,
    cast(
        case
            when abs(max(bal_sum_same_billday)) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else max(bal_sum_same_billday)
        end as decimal(18, 2)
    ) as same_billday_bal_sum_max
from (
    select
        id_unqp,
        id_unqf,
        dt,
        days_dt_zx,
        bill_day,
        sum(if(is_non_mx = 1, is_pos_bal_acct, 0)) as acct_cnt_same_billday,
        sum(if(is_pos_bal_acct = 1 and is_non_mx = 1, balance, 0)) as bal_sum_same_billday
    from lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base
    where is_pos_bal_acct = 1
      and bill_day is not null
      and is_non_mx = 1
    group by id_unqp, id_unqf, dt, days_dt_zx, bill_day
) t
group by id_unqp, id_unqf, dt, days_dt_zx
;

-- ########## 4. 报告扩展（仅依赖 spine + summary，不依赖账户 agg）##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext as
select
    spine.unique_id as id_unqp,
    spine.id_unqf,
    spine.dt_zx as dt,
    spine.days_dt_zx,
    cast(nullif(q.credit_audit_query_org_num_1m, '') as int) as credit_audit_query_org_num_1m,
    cast(nullif(q.loan_audit_query_num_1m, '') as int) as loan_audit_query_num_1m,
    cast(nullif(q.credit_audit_query_num_1m, '') as int) as credit_audit_query_num_1m,
    cast(nullif(q.person_query_num_1m, '') as int) as person_query_num_1m,
    cast(nullif(q.plm_query_num_2y, '') as int) as plm_query_num_2y,
    cast(nullif(q.assure_query_num_2y, '') as int) as assure_query_num_2y,
    cast(nullif(q.sam_query_num_2y, '') as int) as sam_query_num_2y,
    coalesce(cast(nullif(q.loan_audit_query_num_1m, '') as int), 0)
        + coalesce(cast(nullif(q.credit_audit_query_num_1m, '') as int), 0) as hard_query_num_1m,
    pd.pd_num_month_max,
    pd.pd_num_month_sum,
    pd.pd_max_overdue_months,
    pd.pd_max_overdue_amt,
    cast(nullif(cls.credit_account_num, '') as int) as credit_account_num,
    cast(
        case
            when cast(nullif(cls.credit_amount, '') as decimal(18, 2)) is null then null
            when abs(cast(nullif(cls.credit_amount, '') as decimal(18, 2))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else cast(nullif(cls.credit_amount, '') as decimal(18, 2))
        end as decimal(18, 2)
    ) as credit_amount,
    cast(
        case
            when cast(nullif(cls.credit_used_amount, '') as decimal(18, 2)) is null then null
            when abs(cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))) > cast(9999999 as decimal(18, 2))
            then cast(1000000 as decimal(18, 2))
            else cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))
        end as decimal(18, 2)
    ) as credit_used_amount,
    cast(
        case
            when coalesce(cast(nullif(cls.credit_amount, '') as decimal(18, 2)), 0) > 0
            then cast(nullif(cls.credit_used_amount, '') as decimal(18, 2))
                 / cast(nullif(cls.credit_amount, '') as decimal(18, 2))
            else null
        end as decimal(10, 6)
    ) as credit_util_rate,
    case when coalesce(tip.has_house_loan_flg, 0) > 0 or coalesce(bi.has_house_loan_flg, 0) > 0 then 1 else 0 end as has_house_loan_flg,
    case
        when coalesce(tip.has_gjj_loan_flg, 0) > 0 or coalesce(phf.has_gjj_record_flg, 0) > 0
          or coalesce(bi.has_gjj_loan_flg, 0) > 0
        then 1
        else 0
    end as has_gjj_loan_flg,
    job.org_type
from lj_iceberg.ai_decision_dev.fxj_seed_zx_spine spine
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_query_summary q
    on spine.id_unqf = q.id_unqf
   and spine.unique_id = q.id_unqp
   and spine.dt_zx = q.dt
left join (
    select id_unqp, id_unqf, dt,
           max(cast(nullif(num_month, '') as int)) as pd_num_month_max,
           sum(cast(nullif(num_month, '') as int)) as pd_num_month_sum,
           max(cast(nullif(max_amt_pd, '') as int)) as pd_max_overdue_months,
           cast(
               case
                   when max(cast(nullif(amt_pdtotal, '') as decimal(18, 2))) is null then null
                   when abs(max(cast(nullif(amt_pdtotal, '') as decimal(18, 2)))) > cast(9999999 as decimal(18, 2))
                   then cast(1000000 as decimal(18, 2))
                   else max(cast(nullif(amt_pdtotal, '') as decimal(18, 2)))
               end as decimal(18, 2)
           ) as pd_max_overdue_amt
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_pd_summary
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) pd
    on spine.id_unqf = pd.id_unqf
   and spine.unique_id = pd.id_unqp
   and spine.dt_zx = pd.dt
left join lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary cls
    on spine.id_unqf = cls.id_unqf
   and spine.unique_id = cls.id_unqp
   and spine.dt_zx = cls.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when cre_tran_pro_type in ('11', '12') then 1 else 0 end) as has_house_loan_flg,
           max(case when cre_tran_pro_type = '13' then 1 else 0 end) as has_gjj_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summary_tip_detail
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) tip
    on spine.id_unqf = tip.id_unqf
   and spine.unique_id = tip.id_unqp
   and spine.dt_zx = tip.dt
left join (
    select id_unqp, id_unqf, dt,
           max(case when busi_type = '13' or busi_type like '%公积金%' then 1 else 0 end) as has_gjj_loan_flg,
           max(case when busi_type in ('11', '12') or busi_type like '%住房%' then 1 else 0 end) as has_house_loan_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) bi
    on spine.id_unqf = bi.id_unqf
   and spine.unique_id = bi.id_unqp
   and spine.dt_zx = bi.dt
left join (
    select id_unqp, id_unqf, dt, 1 as has_gjj_record_flg
    from lj_iceberg.pboccr2d.dsst_eds_gaa02_phf_record
    where dt >= '20240801'
      and dt < '20260701'
    group by id_unqp, id_unqf, dt
) phf
    on spine.id_unqf = phf.id_unqf
   and spine.unique_id = phf.id_unqp
   and spine.dt_zx = phf.dt
left join (
    select id_unqp, id_unqf, dt, org_type
    from (
        select id_unqp, id_unqf, dt, org_type,
               row_number() over (partition by id_unqf, id_unqp, dt order by update_date desc, time_inst desc) as rn
        from lj_iceberg.pboccr2d.dsst_eds_gaa02_person_job_info
        where dt >= '20240801'
          and dt < '20260701'
    ) x
    where rn = 1
) job
    on spine.id_unqf = job.id_unqf
   and spine.unique_id = job.id_unqp
   and spine.dt_zx = job.dt
;

-- 无账户明细时仍保留报告键，供终表填 0
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_shell;
create table if not exists lj_iceberg.ai_decision_dev.fxj_seed_credit_report_shell as
select
    e.id_unqp,
    e.id_unqf,
    e.dt,
    e.days_dt_zx
from lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext e
where e.id_unqf is not null
;

-- ########## 5. 挂回样本宽表 ##########
drop table if exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit;
create table if not exists lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit as
select
    s.*,
    sh.id_unqf as zx_id_unqf,
    case when sh.id_unqf is not null then 1 else 0 end as zx_has_report_flg,
    case when sh.id_unqf is not null then coalesce(r.pos_bal_acct_cnt, 0) else null end as latest_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(r.bal_sum, 0) else null end as latest_bal_sum,
    case when sh.id_unqf is not null then r.bal_max else null end as latest_bal_max,
    case when sh.id_unqf is not null then r.bal_min else null end as latest_bal_min,
    case when sh.id_unqf is not null then coalesce(r.crdt_sum, 0) else null end as latest_crdt_sum,
    case when sh.id_unqf is not null then r.crdt_max else null end as latest_crdt_max,
    case when sh.id_unqf is not null then r.crdt_min else null end as latest_crdt_min,
    case when sh.id_unqf is not null then cast(r.util_sum as decimal(10, 6)) else null end as latest_util_sum,
    case when sh.id_unqf is not null then cast(r.util_max as decimal(10, 6)) else null end as latest_util_max,
    case when sh.id_unqf is not null then cast(r.util_min as decimal(10, 6)) else null end as latest_util_min,
    case when sh.id_unqf is not null then coalesce(r.bill_day_cnt, 0) else null end as latest_bill_day_cnt,
    case when sh.id_unqf is not null then b.same_billday_acct_cnt_max else null end as latest_same_billday_acct_cnt_max,
    case when sh.id_unqf is not null then b.same_billday_bal_sum_max else null end as latest_same_billday_bal_sum_max,
    e.credit_audit_query_org_num_1m as latest_credit_audit_query_org_num_1m,
    e.loan_audit_query_num_1m as latest_loan_audit_query_num_1m,
    e.credit_audit_query_num_1m as latest_credit_audit_query_num_1m,
    e.person_query_num_1m as latest_person_query_num_1m,
    e.plm_query_num_2y as latest_plm_query_num_2y,
    e.assure_query_num_2y as latest_assure_query_num_2y,
    e.sam_query_num_2y as latest_sam_query_num_2y,
    e.hard_query_num_1m as latest_hard_query_num_1m,
    e.pd_num_month_max as latest_pd_num_month,
    e.pd_num_month_sum as latest_pd_total_overdue_cnt,
    e.pd_max_overdue_months as latest_pd_max_overdue_months,
    e.pd_max_overdue_amt as latest_pd_max_overdue_amt,
    e.has_house_loan_flg as latest_has_house_loan_flg,
    e.has_gjj_loan_flg as latest_has_gjj_loan_flg,
    e.credit_account_num as latest_credit_account_num,
    e.credit_amount as latest_credit_amount,
    e.credit_used_amount as latest_credit_used_amount,
    cast(e.credit_util_rate as decimal(10, 6)) as latest_credit_util_rate,
    e.org_type as latest_org_type,
    case when sh.id_unqf is not null then coalesce(p.zx_D1_pos_bal_acct_cnt, 0) else null end as zx_D1_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_D1_bal_sum, 0) else null end as zx_D1_bal_sum,
    case when sh.id_unqf is not null then p.zx_D1_bal_max else null end as zx_D1_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_D1_crdt_sum, 0) else null end as zx_D1_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_D1_acct_cnt, 0) else null end as zx_D1_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R1_pos_bal_acct_cnt, 0) else null end as zx_R1_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R1_bal_sum, 0) else null end as zx_R1_bal_sum,
    case when sh.id_unqf is not null then p.zx_R1_bal_max else null end as zx_R1_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_R1_crdt_sum, 0) else null end as zx_R1_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_R1_acct_cnt, 0) else null end as zx_R1_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R2_pos_bal_acct_cnt, 0) else null end as zx_R2_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R2_bal_sum, 0) else null end as zx_R2_bal_sum,
    case when sh.id_unqf is not null then p.zx_R2_bal_max else null end as zx_R2_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_R2_crdt_sum, 0) else null end as zx_R2_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_R2_acct_cnt, 0) else null end as zx_R2_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R3_pos_bal_acct_cnt, 0) else null end as zx_R3_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R3_bal_sum, 0) else null end as zx_R3_bal_sum,
    case when sh.id_unqf is not null then p.zx_R3_bal_max else null end as zx_R3_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_R3_crdt_sum, 0) else null end as zx_R3_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_R3_acct_cnt, 0) else null end as zx_R3_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R4_pos_bal_acct_cnt, 0) else null end as zx_R4_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R4_bal_sum, 0) else null end as zx_R4_bal_sum,
    case when sh.id_unqf is not null then p.zx_R4_bal_max else null end as zx_R4_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_R4_crdt_sum, 0) else null end as zx_R4_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_R4_acct_cnt, 0) else null end as zx_R4_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R5_pos_bal_acct_cnt, 0) else null end as zx_R5_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_R5_bal_sum, 0) else null end as zx_R5_bal_sum,
    case when sh.id_unqf is not null then p.zx_R5_bal_max else null end as zx_R5_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_R5_crdt_sum, 0) else null end as zx_R5_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_R5_acct_cnt, 0) else null end as zx_R5_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_D2_pos_bal_acct_cnt, 0) else null end as zx_D2_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_D2_bal_sum, 0) else null end as zx_D2_bal_sum,
    case when sh.id_unqf is not null then p.zx_D2_bal_max else null end as zx_D2_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_D2_crdt_sum, 0) else null end as zx_D2_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_D2_acct_cnt, 0) else null end as zx_D2_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_C1_pos_bal_acct_cnt, 0) else null end as zx_C1_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_C1_bal_sum, 0) else null end as zx_C1_bal_sum,
    case when sh.id_unqf is not null then p.zx_C1_bal_max else null end as zx_C1_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_C1_crdt_sum, 0) else null end as zx_C1_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_C1_acct_cnt, 0) else null end as zx_C1_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_C2_pos_bal_acct_cnt, 0) else null end as zx_C2_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_C2_bal_sum, 0) else null end as zx_C2_bal_sum,
    case when sh.id_unqf is not null then p.zx_C2_bal_max else null end as zx_C2_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_C2_crdt_sum, 0) else null end as zx_C2_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_C2_acct_cnt, 0) else null end as zx_C2_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_OTH_pos_bal_acct_cnt, 0) else null end as zx_OTH_pos_bal_acct_cnt,
    case when sh.id_unqf is not null then coalesce(p.zx_OTH_bal_sum, 0) else null end as zx_OTH_bal_sum,
    case when sh.id_unqf is not null then p.zx_OTH_bal_max else null end as zx_OTH_bal_max,
    case when sh.id_unqf is not null then coalesce(p.zx_OTH_crdt_sum, 0) else null end as zx_OTH_crdt_sum,
    case when sh.id_unqf is not null then coalesce(p.zx_OTH_acct_cnt, 0) else null end as zx_OTH_acct_cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature s
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_shell sh
    on s.unique_id = sh.id_unqp
   and s.dt_zx = sh.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_ext e
    on sh.id_unqp = e.id_unqp
   and sh.id_unqf = e.id_unqf
   and sh.dt = e.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg r
    on sh.id_unqp = r.id_unqp
   and sh.id_unqf = r.id_unqf
   and sh.dt = r.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_pivot p
    on sh.id_unqp = p.id_unqp
   and sh.id_unqf = p.id_unqf
   and sh.dt = p.dt
left join lj_iceberg.ai_decision_dev.fxj_seed_credit_billday_agg b
    on sh.id_unqp = b.id_unqp
   and sh.id_unqf = b.id_unqf
   and sh.dt = b.dt
;

-- ########## 6. 核验 ##########
select
    count(1) as row_cnt,
    count(distinct unique_id) as usr_cnt,
    sum(if(dt_zx is not null, 1, 0)) as has_dt_zx_cnt,
    sum(if(zx_has_report_flg = 1, 1, 0)) as has_zx_report_cnt,
    sum(if(zx_has_report_flg = 1 and latest_bal_sum is not null, 1, 0)) as has_bal_sum_known_cnt,
    sum(if(zx_has_report_flg = 1 and latest_bal_sum = 0, 1, 0)) as bal_sum_zero_cnt,
    sum(if(dt_zx is not null and zx_has_report_flg = 0, 1, 0)) as dt_zx_but_no_summary_cnt,
    sum(if(zx_has_report_flg = 1 and latest_credit_amount > cast(9999999 as decimal(18, 2)), 1, 0)) as cap_credit_amount_cnt,
    sum(if(zx_has_report_flg = 1 and latest_bal_sum > cast(9999999 as decimal(18, 2)), 1, 0)) as cap_bal_sum_cnt
from lj_iceberg.ai_decision_dev.fxj_ayh_seed_users_expansion_tx_cpd_fpd_bh_rzdz_pd_multiloans_feature_with_credit
;

-- 诊断：曾缺循环贷 agg、现应为 0 的人群
-- select count(1)
-- from ..._with_credit
-- where zx_has_report_flg = 1 and latest_bal_sum = 0 and zx_R1_bal_sum = 0 and zx_R2_bal_sum = 0 and zx_R3_bal_sum = 0;

-- 新 account_type 发现（按需加宽表列）：
-- select account_type, count(1)
-- from lj_iceberg.ai_decision_dev.fxj_seed_credit_report_agg_by_type
-- group by account_type order by count(1) desc;
