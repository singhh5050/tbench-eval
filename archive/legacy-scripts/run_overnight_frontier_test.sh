#!/usr/bin/env bash
# Overnight Frontier Model Test
# Tests new frontier models with 1 task each to verify compatibility
#
# Models tested:
#   1. Qwen 3.5-35B-A3B (Apache 2.0, 76% SWE-bench)
#   2. GLM-4.7-Flash (MIT, 94% HumanEval)
#   3. GPT-oss-120B (Apache 2.0, OpenAI's open model)
#   4. Nemotron-3-Nano-30B-A3B (NVIDIA, may have bugs)
#
# Usage:
#   nohup ./run_overnight_frontier_test.sh > logs/overnight_frontier.log 2>&1 &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment
source "$HOME/.local/bin/env" 2>/dev/null || true
set -a
source .env
set +a

# Load model manager
source "${SCRIPT_DIR}/model_manager.sh"

# Test configuration
TEST_TASK="fix-git"  # Simple task for quick validation
AGENT="terminus-2"
TIMEOUT_MULTIPLIER=2.0

# Models to test (format: NAME|HF_REPO|VARIANT|NOTES)
FRONTIER_MODELS=(
  "Qwen3.5-35B-A3B-GGUF|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M|Latest Qwen MoE"
  "GLM-4.7-Flash-GGUF|unsloth/GLM-4.7-Flash-GGUF|Q4_K_M|MIT license coding model"
  "gpt-oss-120b-GGUF|ggml-org/gpt-oss-120b-GGUF|Q4_K_M|OpenAI open model - may need offload"
  "Nemotron-3-Nano-30B-A3B-GGUF|unsloth/Nemotron-3-Nano-30B-A3B-GGUF|Q4_K_M|NVIDIA - may have bugs"
)

LOG_DIR="${SCRIPT_DIR}/logs"
RESULTS_DIR="${SCRIPT_DIR}/results/frontier-test-$(date +%Y%m%d)"
mkdir -p "$LOG_DIR" "$RESULTS_DIR"

echo "============================================"
echo "  Overnight Frontier Model Test"
echo "  Started: $(date)"
echo "  Task: $TEST_TASK"
echo "  Agent: $AGENT"
echo "  Models: ${#FRONTIER_MODELS[@]}"
echo "============================================"
echo ""

# Clean up any existing model to free space
echo ">>> Cleaning up disk space..."
stop_llama
# Delete the test model we downloaded earlier
delete_model "Llama-3.1-8B-Instruct-GGUF" 2>/dev/null || true
echo ""

RESULTS_SUMMARY="${RESULTS_DIR}/summary.txt"
echo "# Frontier Model Test Results - $(date)" > "$RESULTS_SUMMARY"
echo "# Task: $TEST_TASK" >> "$RESULTS_SUMMARY"
echo "" >> "$RESULTS_SUMMARY"

for MODEL_CONFIG in "${FRONTIER_MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT NOTES <<< "$MODEL_CONFIG"

  echo "=========================================="
  echo "  Testing: $MODEL_NAME"
  echo "  Repo: $HF_REPO"
  echo "  Notes: $NOTES"
  echo "  Time: $(date)"
  echo "=========================================="
  echo ""

  MODEL_LOG="${LOG_DIR}/${MODEL_NAME}.log"
  MODEL_RESULT_DIR="${RESULTS_DIR}/${AGENT}-${MODEL_NAME}"
  mkdir -p "$MODEL_RESULT_DIR"

  # Track timing
  START_TIME=$(date +%s)
  STATUS="UNKNOWN"

  {
    echo "=== Download Phase ==="
    # Download model
    if download_model "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
      echo "Download: SUCCESS"

      echo ""
      echo "=== Start Server Phase ==="
      # Start server
      if start_model "$MODEL_NAME"; then
        echo "Server: SUCCESS"

        echo ""
        echo "=== Benchmark Phase ==="
        # Run single benchmark
        harbor run \
          -d terminal-bench@2.0 \
          -a "$AGENT" \
          -m "openai/${MODEL_NAME}" \
          -n 1 \
          --timeout-multiplier "$TIMEOUT_MULTIPLIER" \
          --jobs-dir "$MODEL_RESULT_DIR" \
          -t "$TEST_TASK" \
          2>&1 || echo "Benchmark returned non-zero"

        # Check result
        if [ -f "${MODEL_RESULT_DIR}/"*"/reward.txt" ]; then
          REWARD=$(cat "${MODEL_RESULT_DIR}/"*"/reward.txt" 2>/dev/null || echo "0")
          if [ "$REWARD" = "1" ]; then
            STATUS="PASS"
          else
            STATUS="FAIL (reward=$REWARD)"
          fi
        else
          STATUS="NO_RESULT"
        fi

      else
        STATUS="SERVER_FAILED"
        echo "Server: FAILED"
      fi
    else
      STATUS="DOWNLOAD_FAILED"
      echo "Download: FAILED"
    fi

  } 2>&1 | tee "$MODEL_LOG"

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))

  # Log result
  echo "${MODEL_NAME}|${STATUS}|${DURATION}s|${NOTES}" >> "$RESULTS_SUMMARY"
  echo ""
  echo ">>> Result: $MODEL_NAME = $STATUS (${DURATION}s)"
  echo ""

  # Cleanup for next model
  echo ">>> Cleaning up $MODEL_NAME..."
  stop_llama
  delete_model "$MODEL_NAME" || true
  echo ""

  # Brief pause between models
  sleep 5
done

echo ""
echo "=========================================="
echo "  Overnight Test Complete!"
echo "  Finished: $(date)"
echo "=========================================="
echo ""
echo ">>> Results Summary:"
cat "$RESULTS_SUMMARY"
echo ""
echo ">>> Detailed logs in: $LOG_DIR"
echo ">>> Results in: $RESULTS_DIR"
