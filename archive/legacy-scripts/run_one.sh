#!/usr/bin/env bash
# Run one agent × model × 13 tasks
# Exits 0 even if harbor has task failures (those are expected)
# Only exits non-zero on infrastructure errors

AGENT="$1"    # terminus-2 or openhands
MODEL="$2"    # LiteLLM model string
TAG="$3"      # short name for results dir

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOBS_DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"
TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"

mkdir -p "$JOBS_DIR"

echo "=== [$(date '+%H:%M:%S')] Running: agent=$AGENT model=$MODEL tag=$TAG ==="
echo "=== Results: $JOBS_DIR ==="

# Build -t flags from task list
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

harbor run \
  -d terminal-bench@2.0 \
  -a "$AGENT" \
  -m "$MODEL" \
  -n "${N_CONCURRENT:-2}" \
  --jobs-dir "$JOBS_DIR" \
  "${TASK_FLAGS[@]}" \
  2>&1 | tee "${JOBS_DIR}/run.log"

EXIT_CODE=${PIPESTATUS[0]}

echo "=== [$(date '+%H:%M:%S')] Done: $JOBS_DIR (exit=$EXIT_CODE) ==="
exit 0  # Always succeed — harbor exit codes reflect task failures, not infra failures
