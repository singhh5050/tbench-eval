#!/usr/bin/env bash
# Quick test: Download one small model and run 2 tasks to validate pipeline
# Tests: download, lemonade startup, model compatibility, benchmark execution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment
source "$HOME/.local/bin/env" 2>/dev/null || true
set -a
source .env
set +a

# Load model manager functions
source "${SCRIPT_DIR}/model_manager.sh"

export N_CONCURRENT=1

echo "============================================"
echo "  Quick Test - Single Model"
echo "  Started: $(date)"
echo "============================================"
echo ""

# Test with a small, fast model (Llama-3.2-3B-Instruct)
MODEL_NAME="Llama-3.2-3B-Instruct-GGUF"
TAG="llama32-3b-test"
SIZE_GB=5
HF_CHECKPOINT="unsloth/Llama-3.2-3B-Instruct-GGUF"
VARIANT="Q4_K_M"
LEMONADE_MODEL="user.${MODEL_NAME}"

# Test with just 2 tasks
TEST_TASKS=(
  "bash-easy-1"
  "bash-easy-2"
)

echo "Test Configuration:"
echo "  Model: $MODEL_NAME"
echo "  Size: ${SIZE_GB}GB"
echo "  Tasks: ${TEST_TASKS[*]}"
echo "  Agents: terminus-2, openhands"
echo ""

# Step 1: Check disk space
echo ">>> Checking disk space..."
CURRENT_FREE=$(check_disk_space)
echo "  Available: ${CURRENT_FREE}GB (need ${SIZE_GB}GB)"
if [ "$CURRENT_FREE" -lt "$SIZE_GB" ]; then
  echo "  ERROR: Not enough space"
  exit 1
fi
echo ""

# Step 2: Stop any running lemonade
echo ">>> Stopping any running lemonade-server..."
stop_lemonade
echo ""

# Step 3: Download model
echo ">>> Downloading test model..."
download_model "$MODEL_NAME" "$HF_CHECKPOINT" "$VARIANT" || {
  echo "ERROR: Failed to download"
  exit 1
}
echo ""

# Step 4: Start lemonade
echo ">>> Starting lemonade-server..."
if ! start_model "$LEMONADE_MODEL"; then
  echo "ERROR: Failed to start lemonade"
  exit 1
fi
echo ""

# Step 5: Verify model is loaded
echo ">>> Verifying model loaded correctly..."
if curl -s http://localhost:8000/api/v1/models | grep -q "$LEMONADE_MODEL"; then
  echo "  ✓ Model loaded successfully"
  curl -s http://localhost:8000/api/v1/models | jq -r '.data[0] | "  Model: \(.id)\n  Architecture: \(.architecture // "unknown")"'
else
  echo "  ✗ Model not found in lemonade"
  exit 1
fi
echo ""

# Step 6: Run test benchmarks
for AGENT in terminus-2 openhands; do
  JOBS_DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"
  mkdir -p "$JOBS_DIR"

  echo ">>> Testing $AGENT agent (2 tasks)..."

  if [ "$AGENT" = "terminus-2" ]; then
    harbor run \
      -d terminal-bench@2.0 \
      -a "$AGENT" \
      -m "openai/${LEMONADE_MODEL}" \
      -n 1 \
      --jobs-dir "$JOBS_DIR" \
      -t "${TEST_TASKS[0]}" \
      -t "${TEST_TASKS[1]}" \
      2>&1 | tee "${JOBS_DIR}/test_run.log" || true
  else
    harbor run \
      --config openhands_hostnet.yaml \
      -d terminal-bench@2.0 \
      -a openhands \
      -m "openai/${LEMONADE_MODEL}" \
      -n 1 \
      --jobs-dir "$JOBS_DIR" \
      -t "${TEST_TASKS[0]}" \
      -t "${TEST_TASKS[1]}" \
      2>&1 | tee "${JOBS_DIR}/test_run.log" || true
  fi

  echo ""
done

# Step 7: Check results
echo "============================================"
echo "  Test Results"
echo "============================================"
echo ""

for AGENT in terminus-2 openhands; do
  DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"
  if [ -d "$DIR" ]; then
    PASSES=$(find "$DIR" -name "reward.txt" -exec grep "^1$" {} \; 2>/dev/null | wc -l)
    TOTAL=$(find "$DIR" -name "reward.txt" 2>/dev/null | wc -l)
    ERRORS=$(find "$DIR" -name "result.json" -path "*__*" -exec grep -l "exception_info" {} \; 2>/dev/null | wc -l)

    echo "${AGENT}-${TAG}:"
    echo "  Pass: ${PASSES}/${TOTAL}"
    echo "  Errors: ${ERRORS}"

    # Show individual task results
    for TASK in "${TEST_TASKS[@]}"; do
      REWARD_FILE=$(find "$DIR" -path "*${TASK}*" -name "reward.txt" 2>/dev/null | head -1)
      if [ -f "$REWARD_FILE" ]; then
        REWARD=$(cat "$REWARD_FILE")
        if [ "$REWARD" = "1" ]; then
          echo "    ✓ $TASK: PASS"
        else
          echo "    ✗ $TASK: FAIL (reward=$REWARD)"
        fi
      else
        echo "    ? $TASK: No result"
      fi
    done
    echo ""
  fi
done

# Step 8: Summary
echo "============================================"
echo "  Test Complete!"
echo "  Finished: $(date)"
echo "============================================"
echo ""

echo "Next steps:"
echo "  1. Review results above"
echo "  2. If successful, run full benchmark:"
echo "     ./run_local_all_models.sh"
echo "  3. To clean up test results:"
echo "     rm -rf results/terminus-2-${TAG} results/openhands-${TAG}"
echo "  4. To delete test model:"
echo "     lemonade-server delete ${LEMONADE_MODEL}"
echo ""
