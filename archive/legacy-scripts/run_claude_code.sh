#!/usr/bin/env bash
# Run Claude Code agent on terminal-bench tasks
# Usage: ./run_claude_code.sh [MODEL] [TAG]
# Example: ./run_claude_code.sh "anthropic/claude-sonnet-4-20250514" "sonnet-4"

MODEL="${1:-anthropic/claude-sonnet-4-20250514}"
TAG="${2:-sonnet-4}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
JOBS_DIR="${SCRIPT_DIR}/results/claude-code-${TAG}"
TASKS_FILE="${SCRIPT_DIR}/easy_tasks_merged.txt"

mkdir -p "$JOBS_DIR"

echo "=== [$(date '+%H:%M:%S')] Running: agent=claude-code model=$MODEL tag=$TAG ==="
echo "=== Results: $JOBS_DIR ==="

# Build -t flags from task list
TASK_FLAGS=()
while IFS= read -r LINE; do
  [ -z "$LINE" ] && continue
  # Extract task name after the | separator (e.g., "terminal-bench@2.0|fix-git" -> "fix-git")
  if [[ "$LINE" == *"|"* ]]; then
    DATASET="${LINE%%|*}"
    TASK="${LINE##*|}"
    # Add both dataset and task
    TASK_FLAGS+=(-d "$DATASET" -t "$TASK")
  else
    TASK_FLAGS+=(-t "$LINE")
  fi
done < "$TASKS_FILE"

harbor run \
  -a claude-code \
  -m "$MODEL" \
  -n "${N_CONCURRENT:-2}" \
  --jobs-dir "$JOBS_DIR" \
  "${TASK_FLAGS[@]}" \
  2>&1 | tee "${JOBS_DIR}/run.log"

EXIT_CODE=${PIPESTATUS[0]}

echo "=== [$(date '+%H:%M:%S')] Done: $JOBS_DIR (exit=$EXIT_CODE) ==="
exit 0  # Always succeed — harbor exit codes reflect task failures, not infra failures
