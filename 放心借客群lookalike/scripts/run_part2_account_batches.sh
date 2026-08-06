#!/usr/bin/env bash
# 无法调 executor 内存时：Part 2 拆成多份独立 Spark 任务（每份只处理 1/N 的 spine）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NUM_BATCHES="${NUM_BATCHES:-64}"
YARN_QUEUE="${SPARK_YARN_QUEUE:-root.ai.dev}"

for ((k = 0; k < NUM_BATCHES; k++)); do
  echo "======== Part2 batch ${k}/${NUM_BATCHES} ========"
  EXTRA=()
  if [[ "$k" -eq 0 ]]; then
    EXTRA+=(--recreate)
  fi
  spark-submit \
    --master yarn \
    --deploy-mode client \
    --queue "${YARN_QUEUE}" \
    --conf "spark.yarn.queue=${YARN_QUEUE}" \
    --name "fxj_part2_acct_b${k}" \
    scripts/spark_fxj_part2_account_batch.py \
    --num-batches "${NUM_BATCHES}" \
    --batch-id "${k}" \
    --yarn-queue "${YARN_QUEUE}" \
    "${EXTRA[@]}"
done

echo "全部 ${NUM_BATCHES} 批完成: lj_iceberg.ai_decision_dev.fxj_seed_credit_account_base"
