#!/usr/bin/env python3
"""
在 Spark 集群上：用 train 划分统计特征缺失率，剔除高缺失列，物化窄表（Iceberg）。

与 train.py / config.yaml 对齐：
  - 缺失率只在 dataset_split = 'train' 上计算
  - 阈值默认 0.90（缺失率 > 阈值则删列）
  - 入模候选列规则同 src/features.py

运行方式（任选其一）：
  1) 云分析机 Notebook 里已有 SparkSession（队列已配好）：
       import sys; sys.argv = ["", "--yarn-queue", "root.ai.dev"]
       %run scripts/spark_build_narrow_pu_table.py
  2) spark-submit（马消 sta_ai_decision 必须用 root.ai.dev，见 scripts/spark_submit_narrow_pu_table.sh）：
       bash scripts/spark_submit_narrow_pu_table.sh

若报错「当前正在使用的队列为 root.default」：未指定 YARN 队列，请加 --queue root.ai.dev。

完成后 dtools 导出改为读 target 表，仍可 SELECT *（列已变少）。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from features import EXCLUDE_FROM_FEATURES, get_model_feature_columns  # noqa: E402

# 训练/导出必须保留（即使落在 EXCLUDE_FROM_FEATURES 里）
ALWAYS_KEEP = (
    "unique_id",
    "pu_label",
    "dataset_split",
    "zx_has_report_flg",
    "ms13_score",
)

DEFAULT_SOURCE = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training"
DEFAULT_TARGET = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow"


def _get_spark(yarn_queue: str | None = None):
    try:
        from pyspark.sql import SparkSession
    except ImportError as e:
        raise SystemExit("需要 PySpark 环境，请在 Spark 任务或 Notebook 中运行") from e

    active = SparkSession.getActiveSession()
    if active is not None:
        return active

    builder = SparkSession.builder.appName("fxj_pu_narrow_table").enableHiveSupport()
    if yarn_queue:
        builder = builder.config("spark.yarn.queue", yarn_queue)
    return builder.getOrCreate()


def _missing_rate_expr(col_name: str):
    from pyspark.sql import functions as F

    c = F.col(col_name)
    as_str = F.trim(c.cast("string"))
    is_miss = c.isNull() | as_str.isin("", "nan", "NaN", "NULL")
    return F.avg(F.when(is_miss, 1.0).otherwise(0.0)).alias(col_name)


def compute_missing_rates_batched(spark, source_table: str, feature_cols: list[str], batch: int):
    from pyspark.sql import functions as F

    base = (
        spark.table(source_table)
        .filter(F.col("dataset_split") == F.lit("train"))
    )
    rates: dict[str, float] = {}
    for i in range(0, len(feature_cols), batch):
        chunk = feature_cols[i : i + batch]
        exprs = [_missing_rate_expr(c) for c in chunk]
        row = base.agg(*exprs).collect()[0]
        for c in chunk:
            rates[c] = float(row[c] if row[c] is not None else 1.0)
    return rates


def build_keep_columns(
    all_columns: list[str],
    max_missing_rate: float,
    rates: dict[str, float],
) -> tuple[list[str], list[dict]]:
    always = [c for c in ALWAYS_KEEP if c in all_columns]
    feature_cols = get_model_feature_columns(all_columns)
    kept_features: list[str] = []
    dropped: list[dict] = []
    for c in feature_cols:
        rate = rates.get(c, 1.0)
        if rate > max_missing_rate:
            dropped.append({"feature": c, "missing_rate": round(rate, 6)})
        else:
            kept_features.append(c)

    # 保持列顺序：先元数据，再特征（与宽表顺序无关，训练只看列名）
    keep_set = set(always) | set(kept_features)
    # 不把其它 EXCLUDE 列（label、rnk、time_inst 等）带进窄表
    never = (EXCLUDE_FROM_FEATURES - set(ALWAYS_KEEP)) & set(all_columns)
    ordered = [c for c in all_columns if c in keep_set and c not in never]
    return ordered, dropped


def write_narrow_table(spark, source_table: str, target_table: str, keep_columns: list[str]):
    quoted = ",\n  ".join(f"`{c}`" for c in keep_columns)
    sql = f"""
CREATE OR REPLACE TABLE {target_table}
USING iceberg
AS
SELECT
  {quoted}
FROM {source_table}
"""
    spark.sql(sql)


def write_dropped_json(dropped: list[dict], out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(dropped, ensure_ascii=False, indent=2), encoding="utf-8")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description="Spark: 缺失率统计 + 建 PU 训练窄表")
    p.add_argument("--source", default=DEFAULT_SOURCE)
    p.add_argument("--target", default=DEFAULT_TARGET)
    p.add_argument("--max-missing-rate", type=float, default=0.90)
    p.add_argument("--batch-size", type=int, default=120, help="每批聚合列数，过大可能 driver OOM")
    p.add_argument(
        "--dropped-json",
        type=Path,
        default=MODEL_ROOT / "artifacts" / "narrow_table_dropped_features.json",
    )
    p.add_argument("--dry-run", action="store_true", help="只打印保留/剔除列数，不写表")
    p.add_argument(
        "--yarn-queue",
        default=os.environ.get("SPARK_YARN_QUEUE", "root.ai.dev"),
        help="YARN 队列。马消 sta_ai_decision 仅允许 root.ai.dev（勿用 root.default）",
    )
    args = p.parse_args(argv)

    print(f"YARN 队列: {args.yarn_queue}")
    spark = _get_spark(yarn_queue=args.yarn_queue)
    df = spark.table(args.source)
    all_columns = df.columns
    print(f"源表: {args.source}，列数={len(all_columns)}")

    feature_cols = get_model_feature_columns(all_columns)
    print(f"入模候选特征: {len(feature_cols)} 列；在 train 划分上算缺失率…")
    rates = compute_missing_rates_batched(
        spark, args.source, feature_cols, batch=args.batch_size
    )
    keep_columns, dropped = build_keep_columns(
        all_columns, args.max_missing_rate, rates
    )
    print(
        f"阈值<={args.max_missing_rate}: 保留 {len(keep_columns)} 列，"
        f"剔除高缺失特征 {len(dropped)} 列"
    )
    if dropped[:5]:
        print("剔除示例:", dropped[:5])

    write_dropped_json(dropped, args.dropped_json)
    print(f"已写剔除清单: {args.dropped_json}")

    if args.dry_run:
        print("dry-run：未建表")
        return

    print(f"写入窄表: {args.target}")
    write_narrow_table(spark, args.source, args.target, keep_columns)
    n = spark.table(args.target).count()
    print(f"完成。窄表行数={n}，列数={len(keep_columns)}")


if __name__ == "__main__":
    main()
