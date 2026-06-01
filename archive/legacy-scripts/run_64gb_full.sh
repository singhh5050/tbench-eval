#!/usr/bin/env bash
# 64GB Server - Full benchmark with correct task allocation
#
# Batch 1: Qwen3-Coder-Next, gpt-oss-120b → 24 OpenThoughts (have terminal-bench data)
# Batch 2: Nemotron-30B, gemma-4 → 37 merged tasks (no existing data)
#
# Usage: nohup ./run_64gb_full.sh > logs/64gb_full.log 2>&1 &

set -euo pipefail
cd "$(dirname "$0")"

echo "============================================"
echo "  64GB Server Full Benchmark"
echo "  Started: $(date)"
echo "============================================"

echo ""
echo ">>> BATCH 1: Qwen3-Coder-Next + gpt-oss-120b"
echo ">>> 24 OpenThoughts tasks (already have terminal-bench data)"
echo ""

MODELS_FILE=models_batch1.txt \
TASK_FILE=easy_tasks_openthoughts_only.txt \
RUN_NAME=batch1-openthoughts \
sg video -c "sg render -c 'bash /scratch/harshsin/tbench-eval/run_easy_tasks_full.sh'"

echo ""
echo ">>> BATCH 2: Nemotron-30B + gemma-4"
echo ">>> 37 merged tasks (13 terminal-bench + 24 openthoughts)"
echo ""

MODELS_FILE=models_batch2.txt \
TASK_FILE=easy_tasks_merged.txt \
RUN_NAME=batch2-merged \
sg video -c "sg render -c 'bash /scratch/harshsin/tbench-eval/run_easy_tasks_full.sh'"

echo ""
echo "============================================"
echo "  64GB Server Benchmark Complete"
echo "  Finished: $(date)"
echo "============================================"
