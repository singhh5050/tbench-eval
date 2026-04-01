#!/usr/bin/env bash
# Full Easy Tasks Benchmark - All 5 Models × 13 Tasks
# Estimated runtime: 5-8 hours
# Run with: nohup ./run_easy_tasks_full.sh > logs/easy_tasks_full.log 2>&1 &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$HOME/.local/bin/env" 2>/dev/null || true
source "${SCRIPT_DIR}/model_manager.sh"

export OPENAI_API_KEY=lemonade
export OPENAI_API_BASE=http://localhost:8000/v1

AGENT="terminus-2"
RESULTS_DIR="/var/tmp/harbor-results/easy-tasks-full-$(date +%Y%m%d-%H%M)"
mkdir -p "$RESULTS_DIR"

# Models to test (including the ones that failed fix-git)
MODELS=(
  "Qwen3.5-35B-A3B-GGUF|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M"
  "Nemotron-3-Nano-30B-A3B-GGUF|unsloth/Nemotron-3-Nano-30B-A3B-GGUF|Q4_K_M"
  "GLM-4.7-Flash-GGUF|unsloth/GLM-4.7-Flash-GGUF|Q4_K_M"
  "Qwen3-Coder-30B-A3B-Instruct-GGUF|unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF|Q4_K_M"
  "gpt-oss-20b-GGUF|ggml-org/gpt-oss-20b-GGUF|mxfp4"
)

# Read easy tasks from file
mapfile -t TASKS < <(grep -v '^$' easy_tasks.txt)

SUMMARY="${RESULTS_DIR}/summary.txt"
echo "# Easy Tasks Full Benchmark - $(date)" > "$SUMMARY"
echo "# Models: ${#MODELS[@]}" >> "$SUMMARY"
echo "# Tasks: ${#TASKS[@]}" >> "$SUMMARY"
echo "# Estimated runtime: 5-8 hours" >> "$SUMMARY"
echo "" >> "$SUMMARY"
echo "Model|Task|Result|Time" >> "$SUMMARY"

echo "============================================"
echo "  Easy Tasks Full Benchmark"
echo "  Results: $RESULTS_DIR"
echo "  Models: ${#MODELS[@]}"
echo "  Tasks: ${#TASKS[@]}"
echo "  Estimated: 5-8 hours"
echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
echo "============================================"

PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Model: $MODEL_NAME"
  echo "  Time: $(date)"
  echo "=========================================="

  # Clean up previous model FIRST
  if [ -n "$PREVIOUS_MODEL" ]; then
    echo ">>> Cleaning up previous model: $PREVIOUS_MODEL"
    stop_llama
    delete_model "$PREVIOUS_MODEL" || true
    echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
  fi

  # Download model
  echo ">>> Downloading $MODEL_NAME..."
  if ! download_model "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
    echo "  DOWNLOAD FAILED"
    for TASK in "${TASKS[@]}"; do
      echo "${MODEL_NAME}|${TASK}|DOWNLOAD_FAILED|0s" >> "$SUMMARY"
    done
    continue
  fi

  # Start server
  echo ">>> Starting server..."
  if ! start_model "$MODEL_NAME"; then
    echo "  SERVER FAILED"
    for TASK in "${TASKS[@]}"; do
      echo "${MODEL_NAME}|${TASK}|SERVER_FAILED|0s" >> "$SUMMARY"
    done
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  # Run all tasks for this model
  for TASK in "${TASKS[@]}"; do
    echo ""
    echo "  >>> Testing task: $TASK"

    START_TIME=$(date +%s)
    STATUS="UNKNOWN"

    JOB_DIR="${RESULTS_DIR}/${MODEL_NAME}/${TASK}"

    if timeout 600 harbor run \
      -d terminal-bench@2.0 \
      -a "$AGENT" \
      -m "openai/${MODEL_NAME}" \
      -n 1 \
      --timeout-multiplier 2.0 \
      --jobs-dir "$JOB_DIR" \
      -t "$TASK" 2>&1 | tee -a "${RESULTS_DIR}/${MODEL_NAME}_${TASK}.log"; then

      REWARD_FILE=$(find "$JOB_DIR" -name "reward.txt" 2>/dev/null | head -1)
      if [ -n "$REWARD_FILE" ]; then
        REWARD=$(cat "$REWARD_FILE")
        if [ "$REWARD" = "1" ]; then
          STATUS="PASS"
        else
          STATUS="FAIL"
        fi
      else
        STATUS="NO_REWARD"
      fi
    else
      STATUS="TIMEOUT_OR_ERROR"
    fi

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    echo "      Result: $STATUS (${DURATION}s)"
    echo "${MODEL_NAME}|${TASK}|${STATUS}|${DURATION}s" >> "$SUMMARY"
  done

  PREVIOUS_MODEL="$MODEL_NAME"

  echo ""
  echo "  Completed ${MODEL_NAME} at $(date)"
  echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
done

# Final cleanup
if [ -n "$PREVIOUS_MODEL" ]; then
  echo ""
  echo ">>> Final cleanup: $PREVIOUS_MODEL"
  stop_llama
  delete_model "$PREVIOUS_MODEL" || true
fi

echo ""
echo "============================================"
echo "  Benchmark Complete! $(date)"
echo "============================================"
echo ""

# Generate results table
echo "Results by model:"
for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME _ _ <<< "$MODEL_CONFIG"
  PASS=$(grep "^${MODEL_NAME}|.*|PASS|" "$SUMMARY" | wc -l)
  FAIL=$(grep "^${MODEL_NAME}|.*|FAIL|" "$SUMMARY" | wc -l)
  TOTAL=${#TASKS[@]}
  echo "  ${MODEL_NAME}: ${PASS}/${TOTAL} passed, ${FAIL} failed"
done

echo ""
cat "$SUMMARY"
