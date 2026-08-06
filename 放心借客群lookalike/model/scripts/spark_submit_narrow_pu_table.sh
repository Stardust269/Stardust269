#!/usr/bin/env bash
# 马消云分析机 sta_ai_decision 项目：须用 root.ai.dev，不能用 root.default
# 用法（在 model 目录下）:
#   bash scripts/spark_submit_narrow_pu_table.sh
#   bash scripts/spark_submit_narrow_pu_table.sh --dry-run

set -euo pipefail
MODEL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$MODEL_ROOT"

YARN_QUEUE="${SPARK_YARN_QUEUE:-root.ai.dev}"

export PYTHONPATH="${MODEL_ROOT}/src:${PYTHONPATH:-}"

exec spark-submit \
  --master yarn \
  --deploy-mode client \
  --queue "${YARN_QUEUE}" \
  --conf "spark.yarn.queue=${YARN_QUEUE}" \
  --name fxj_pu_narrow_table \
  scripts/spark_build_narrow_pu_table.py \
  --yarn-queue "${YARN_QUEUE}" \
  --source lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training \
  --target lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_narrow \
  --max-missing-rate 0.90 \
  "$@"
