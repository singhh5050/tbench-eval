#!/usr/bin/env bash
# New Models Stress Test - Qwen3-Coder, Trinity Mini, GPT-OSS-20B
# Run with: nohup ./run_new_models_stress.sh > logs/new_models.log 2>&1 &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$HOME/.local/bin/env" 2>/dev/null || true
source "${SCRIPT_DIR}/model_manager.sh"

export OPENAI_API_KEY=lemonade
export OPENAI_API_BASE=http://localhost:8000/v1

TEST_TASK="fix-git"
AGENT="terminus-2"
RESULTS_DIR="/var/tmp/harbor-results/new-models-$(date +%Y%m%d-%H%M)"
mkdir -p "$RESULTS_DIR"

# New models to test
MODELS=(
  "Qwen3-Coder-30B-A3B-Instruct-GGUF|unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF|Q4_K_M"
  "Trinity-Mini-GGUF|arcee-ai/Trinity-Mini-GGUF|Q4_K_M"
  "gpt-oss-20b-GGUF|ggml-org/gpt-oss-20b-GGUF|Q4_K_M"
)

SUMMARY="${RESULTS_DIR}/summary.txt"
echo "# New Models Stress Test - $(date)" > "$SUMMARY"
echo "# Task: $TEST_TASK" >> "$SUMMARY"
echo "" >> "$SUMMARY"

echo "============================================"
echo "  New Models Stress Test"
echo "  Results: $RESULTS_DIR"
echo "  Models: ${#MODELS[@]}"
echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
echo "============================================"

PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Testing: $MODEL_NAME"
  echo "  Time: $(date)"
  echo "=========================================="

  START_TIME=$(date +%s)
  STATUS="UNKNOWN"

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
    STATUS="DOWNLOAD_FAILED"
    echo "${MODEL_NAME}|${STATUS}|0s" >> "$SUMMARY"
    continue
  fi

  # Start server
  echo ">>> Starting server..."
  if ! start_model "$MODEL_NAME"; then
    STATUS="SERVER_FAILED"
    echo "${MODEL_NAME}|${STATUS}|0s" >> "$SUMMARY"
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  # Run benchmark
  echo ">>> Running benchmark..."
  JOB_DIR="${RESULTS_DIR}/${MODEL_NAME}"

  if timeout 600 harbor run \
    -d terminal-bench@2.0 \
    -a "$AGENT" \
    -m "openai/${MODEL_NAME}" \
    -n 1 \
    --timeout-multiplier 2.0 \
    --jobs-dir "$JOB_DIR" \
    -t "$TEST_TASK" 2>&1; then

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

  echo ">>> Result: $STATUS (${DURATION}s)"
  echo "${MODEL_NAME}|${STATUS}|${DURATION}s" >> "$SUMMARY"

  PREVIOUS_MODEL="$MODEL_NAME"
done

# Final cleanup
if [ -n "$PREVIOUS_MODEL" ]; then
  echo ">>> Final cleanup: $PREVIOUS_MODEL"
  stop_llama
  delete_model "$PREVIOUS_MODEL" || true
fi

echo ""
echo "============================================"
echo "  Test Complete! $(date)"
echo "============================================"
cat "$SUMMARY"
