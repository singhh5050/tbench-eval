#!/usr/bin/env bash
# Frontier Model Stress Test - One task per model
# Uses /var/tmp for Docker volume mount compatibility

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$HOME/.local/bin/env" 2>/dev/null || true
source "${SCRIPT_DIR}/model_manager.sh"

export OPENAI_API_KEY=lemonade
export OPENAI_API_BASE=http://localhost:8000/v1

TEST_TASK="fix-git"
AGENT="terminus-2"
RESULTS_DIR="/var/tmp/harbor-results/frontier-stress-$(date +%Y%m%d-%H%M)"
mkdir -p "$RESULTS_DIR"

# Models to test
MODELS=(
  "Qwen3.5-35B-A3B-GGUF|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M"
  "GLM-4.7-Flash-GGUF|unsloth/GLM-4.7-Flash-GGUF|Q4_K_M"
  "gpt-oss-120b-GGUF|ggml-org/gpt-oss-120b-GGUF|Q4_K_M"
  "Nemotron-3-Nano-30B-A3B-GGUF|unsloth/Nemotron-3-Nano-30B-A3B-GGUF|Q4_K_M"
)

SUMMARY="${RESULTS_DIR}/summary.txt"
echo "# Frontier Stress Test - $(date)" > "$SUMMARY"
echo "# Task: $TEST_TASK" >> "$SUMMARY"
echo "" >> "$SUMMARY"

echo "============================================"
echo "  Frontier Model Stress Test"
echo "  Results: $RESULTS_DIR"
echo "  Models: ${#MODELS[@]}"
echo "============================================"

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Testing: $MODEL_NAME"
  echo "  Time: $(date)"
  echo "=========================================="

  START_TIME=$(date +%s)
  STATUS="UNKNOWN"

  # Stop previous model
  stop_llama

  # Delete previous model to save space (keep Qwen since it's already loaded)
  if [[ "$MODEL_NAME" != "Qwen3.5-35B-A3B-GGUF" ]]; then
    # Download model
    echo ">>> Downloading $MODEL_NAME..."
    if ! download_model "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
      STATUS="DOWNLOAD_FAILED"
      echo "${MODEL_NAME}|${STATUS}|0s" >> "$SUMMARY"
      continue
    fi
  fi

  # Start server
  echo ">>> Starting server..."
  if ! start_model "$MODEL_NAME"; then
    STATUS="SERVER_FAILED"
    echo "${MODEL_NAME}|${STATUS}|0s" >> "$SUMMARY"
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

    # Check result
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

  # Cleanup model to save space for next one
  if [[ "$MODEL_NAME" != "Qwen3.5-35B-A3B-GGUF" ]]; then
    echo ">>> Cleaning up $MODEL_NAME..."
    stop_llama
    delete_model "$MODEL_NAME" || true
  fi
done

echo ""
echo "============================================"
echo "  Stress Test Complete!"
echo "  $(date)"
echo "============================================"
echo ""
echo "Results:"
cat "$SUMMARY"
