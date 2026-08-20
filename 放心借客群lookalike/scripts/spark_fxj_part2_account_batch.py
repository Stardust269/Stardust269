#!/usr/bin/env python3
"""
Part 2 分批写入 fxj_seed_credit_account_base（无法调大 executor 时用）。

每批单独跑一个 Spark 应用，只处理 spine 的 1/N 用户，降低单次 shuffle/OOM(137) 风险。

前置：已跑 Part 1，存在 fxj_seed_zx_spine。

用法（在 放心借客群lookalike 目录，队列 root.ai.dev）:
  # 共 64 批，逐批 spark-submit（推荐）
  bash scripts/run_part2_account_batches.sh

  # 单批调试（第 0 批，共 64 批）
  spark-submit --master yarn --deploy-mode client --queue root.ai.dev \\
    scripts/spark_fxj_part2_account_batch.py --num-batches 64 --batch-id 0 --recreate

  # 单批追加（第 3 批）
  spark-submit ... scripts/spark_fxj_part2_account_batch.py --num-batches 64 --batch-id 3

bill_day 本脚本固定为 null（省 1m_perform 开窗）；可选后续 sql/fxj_seed_credit_account_billday_optional.sql。
"""

from __future__ import annotations

import argparse
import os
import sys

TARGET = "lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base"
SPINE = "lj_iceberg.ai_decision_dev.fxj_seed_zx_spine"


def _get_spark(yarn_queue: str):
    from pyspark.sql import SparkSession

    active = SparkSession.getActiveSession()
    if active is not None:
        return active
    builder = SparkSession.builder.appName("fxj_part2_account_batch").enableHiveSupport()
    if yarn_queue:
        builder = builder.config("spark.yarn.queue", yarn_queue)
    return builder.getOrCreate()


def _batch_sql(batch_id: int, num_batches: int) -> str:
    # hash 分桶，与扩量表分桶习惯一致
    bucket = f"pmod(hash(concat(cast(sp.unique_id as string), '_fxj_acct')), {num_batches})"
    return f"""
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
    cast(
        least(
            case
                when coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0) > 0
                 and coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0
                then coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0)
                     / coalesce(cast(nullif(t2.credit_grant_amount, '') as decimal(18, 2)), 0)
                else null
            end,
            cast(9999.999999 as decimal(18, 6))
        ) as decimal(18, 6)
    ) as util_rate,
    case when coalesce(cast(nullif(t1.balance, '') as decimal(18, 2)), 0) > 0 then 1 else 0 end as is_pos_bal_acct,
    case when t2.org_manage_code <> 'T10156530H0001' then 1 else 0 end as is_non_mx
from {SPINE} sp
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
where {bucket} = {batch_id}
"""


def main() -> None:
    p = argparse.ArgumentParser(description="Part2 账户明细分批写入 Iceberg")
    p.add_argument("--num-batches", type=int, default=64)
    p.add_argument("--batch-id", type=int, required=True, help="0 .. num-batches-1")
    p.add_argument(
        "--recreate",
        action="store_true",
        help="batch-id=0 时 drop 目标表后 CTAS；否则 INSERT INTO",
    )
    p.add_argument("--yarn-queue", default=os.environ.get("SPARK_YARN_QUEUE", "root.ai.dev"))
    args = p.parse_args()

    if args.batch_id < 0 or args.batch_id >= args.num_batches:
        raise SystemExit(f"batch-id 须在 [0, {args.num_batches})")

    spark = _get_spark(args.yarn_queue)
    # 不能改 executor 时，仍可在 SQL 层加大 shuffle 分区（若平台允许 set）
    for stmt in (
        "set spark.sql.adaptive.enabled=true",
        "set spark.sql.adaptive.coalescePartitions.enabled=true",
        "set spark.sql.shuffle.partitions=800",
    ):
        try:
            spark.sql(stmt)
        except Exception:
            pass

    body = _batch_sql(args.batch_id, args.num_batches)
    if args.batch_id == 0 and args.recreate:
        print(f"DROP + CTAS {TARGET} batch 0/{args.num_batches}")
        spark.sql(f"drop table if exists {TARGET}")
        spark.sql(f"create table {TARGET} using iceberg as {body}")
    else:
        print(f"INSERT INTO {TARGET} batch {args.batch_id}/{args.num_batches}")
        spark.sql(f"insert into {TARGET} {body}")

    n = spark.table(TARGET).count()
    print(f"完成 batch {args.batch_id}，当前 {TARGET} 行数={n}")


if __name__ == "__main__":
    main()
