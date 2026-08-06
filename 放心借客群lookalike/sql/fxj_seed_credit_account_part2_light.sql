-- =============================================================================
-- Part 2 轻量版（不调 executor 内存时优先用）
-- =============================================================================
-- 1) 不做 1m_perform / bill_day（bill_day=null，latest_same_billday_* 多为空）
-- 2) 若仍 137：用 scripts/run_part2_account_batches.sh（默认 64 次 spark-submit）
-- 前置：Part 1 fxj_seed_zx_spine 已存在
-- =============================================================================

-- 若平台允许在 SQL 里 set（不能改 YARN 容器时有时仍生效）：
-- set spark.sql.adaptive.enabled=true;
-- set spark.sql.shuffle.partitions=800;

drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_stg;
drop table if exists lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base;

create table lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base
using iceberg
as
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
    cast(null as int) as bill_day,
    case
        when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
         and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
        then cast(
            coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
            / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
            as decimal(12, 6)
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
