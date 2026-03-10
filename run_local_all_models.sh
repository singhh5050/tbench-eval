#!/usr/bin/env bash
# Run TerminalBench 2.0 benchmarks across multiple local models
# Automatically manages disk space by deleting completed models
#
# Target Models (March 2026 - from HuggingFace):
#   - Qwen3.5-35B-A3B (~18GB, MoE, Feb 2026) - fits 24GB
#   - Qwen3.5-27B (~18GB, dense, Feb 2026) - better reasoning
#   - Qwen3.5-9B (~6GB, fast baseline, Mar 2026)
#
# Already completed (skip):
#   - GLM-4.7-Flash-GGUF
#   - Qwen3-Coder-30B-A3B-Instruct-GGUF
#
# Hardware: AMD Ryzen AI MAX+ 395, 30GB RAM, Vulkan
#
# Usage:
#   nohup ./run_local_all_models.sh > logs/local_all_models.log 2>&1 &

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

# ─────────────────────────────────────────
# Model Configuration
# Format: "LOCAL_NAME|TAG|SIZE_GB|HF_CHECKPOINT|VARIANT"
# HF_CHECKPOINT: HuggingFace repo (e.g., unsloth/Qwen3.5-35B-A3B-GGUF)
# VARIANT: GGUF quantization (Q4_K_M, Q5_K_M, etc.)
# ─────────────────────────────────────────
MODELS=(
  "Qwen35-35B-A3B|qwen35-35b-a3b-local|18|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M"
  "Qwen35-27B|qwen35-27b-local|18|unsloth/Qwen3.5-27B-GGUF|Q4_K_M"
  "Qwen35-9B|qwen35-9b-local|6|unsloth/Qwen3.5-9B-GGUF|Q4_K_M"
)

# Agents to benchmark
AGENTS=("terminus-2" "openhands")

# Task list
TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

# ─────────────────────────────────────────
# run_benchmark - Run benchmark for one agent + model
# ─────────────────────────────────────────
run_benchmark() {
  local AGENT="$1"
  local MODEL_STR="$2"
  local TAG="$3"
  local LEMONADE_MODEL="$4"

  local JOBS_DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"
  mkdir -p "$JOBS_DIR"

  echo ">>> Benchmark: $AGENT + $TAG — started $(date '+%H:%M:%S')"

  if [ "$AGENT" = "terminus-2" ]; then
    harbor run \
      -d terminal-bench@2.0 \
      -a "$AGENT" \
      -m "openai/${MODEL_STR}" \
      -n 1 \
      --jobs-dir "$JOBS_DIR" \
      "${TASK_FLAGS[@]}" \
      2>&1 | tee "${JOBS_DIR}/run.log" || true
  else
    # OpenHands needs host networking config
    harbor run \
      --config openhands_hostnet.yaml \
      -d terminal-bench@2.0 \
      -a openhands \
      -m "openai/${MODEL_STR}" \
      -n 1 \
      --jobs-dir "$JOBS_DIR" \
      "${TASK_FLAGS[@]}" \
      2>&1 | tee "${JOBS_DIR}/run.log" || true
  fi

  echo ">>> Benchmark: $AGENT + $TAG — finished $(date '+%H:%M:%S')"

  # Health check — restart Lemonade if it died
  if ! check_lemonade "$LEMONADE_MODEL"; then
    echo ">>> Warning: Lemonade died! Restarting..."
    start_model "$LEMONADE_MODEL"
  fi
}

# ─────────────────────────────────────────
# verify_results - Check results for a model
# ─────────────────────────────────────────
verify_results() {
  local TAG="$1"
  echo "  Verifying results for $TAG..."

  for AGENT in "${AGENTS[@]}"; do
    local DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"
    if [ -d "$DIR" ]; then
      local PASSES=$(find "$DIR" -name "reward.txt" -exec grep "^1$" {} \; 2>/dev/null | wc -l)
      local TOTAL=$(find "$DIR" -name "reward.txt" 2>/dev/null | wc -l)
      local ERRORS=$(find "$DIR" -name "result.json" -path "*__*" -exec grep -l "exception_info" {} \; 2>/dev/null | wc -l)
      echo "    ${AGENT}-${TAG}: ${PASSES}/${TOTAL} pass, ${ERRORS} errors"
    else
      echo "    ${AGENT}-${TAG}: No results directory"
    fi
  done
}

# ═════════════════════════════════════════
# Main Execution
# ═════════════════════════════════════════

echo "============================================"
echo "  TerminalBench 2.0 - Multi-Model Local Run"
echo "  Started: $(date)"
echo "  Models: ${#MODELS[@]}"
echo "  Agents: ${AGENTS[*]}"
echo "  Tasks: $(wc -l < "$TASKS_FILE")"
echo "============================================"
echo ""

TOTAL_MODELS=${#MODELS[@]}
CURRENT_MODEL=0
PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME TAG SIZE_GB HF_CHECKPOINT VARIANT <<< "$MODEL_CONFIG"
  CURRENT_MODEL=$((CURRENT_MODEL + 1))

  # For HuggingFace models, the lemonade name will be user.MODEL_NAME
  if [ -n "$HF_CHECKPOINT" ]; then
    LEMONADE_MODEL="user.${MODEL_NAME}"
  else
    LEMONADE_MODEL="$MODEL_NAME"
  fi

  echo "=========================================="
  echo "  PHASE ${CURRENT_MODEL}/${TOTAL_MODELS}: $MODEL_NAME"
  echo "  Tag: $TAG"
  echo "  Size: ~${SIZE_GB}GB"
  echo "  HF Checkpoint: ${HF_CHECKPOINT:-built-in}"
  echo "  Lemonade Name: $LEMONADE_MODEL"
  echo "  Time: $(date)"
  echo "=========================================="
  echo ""

  # Step 1: Free space if needed by deleting previous model
  if [ -n "$PREVIOUS_MODEL" ]; then
    echo ">>> Cleaning up previous model: $PREVIOUS_MODEL"
    stop_lemonade
    delete_model "$PREVIOUS_MODEL" || true
    echo ""
  fi

  # Step 2: Ensure enough space
  NEEDED_SPACE=$((SIZE_GB + 5))  # Add 5GB buffer
  if ! ensure_space "$NEEDED_SPACE"; then
    echo ">>> ERROR: Not enough disk space for $MODEL_NAME"
    echo ">>> Skipping this model..."
    continue
  fi

  # Step 3: Download model
  echo ">>> Downloading model..."
  if [ -n "$HF_CHECKPOINT" ]; then
    download_model "$MODEL_NAME" "$HF_CHECKPOINT" "$VARIANT" || {
      echo ">>> ERROR: Failed to download $MODEL_NAME from $HF_CHECKPOINT"
      continue
    }
  else
    download_model "$MODEL_NAME" || {
      echo ">>> ERROR: Failed to download $MODEL_NAME"
      continue
    }
  fi
  echo ""

  # Step 4: Start lemonade server
  echo ">>> Starting lemonade server..."
  if ! start_model "$LEMONADE_MODEL"; then
    echo ">>> ERROR: Failed to start lemonade with $LEMONADE_MODEL"
    continue
  fi
  echo ""

  # Step 5: Mark as started
  mark_started "$MODEL_NAME" "$TAG" "$SIZE_GB"

  # Step 6: Run benchmarks for all agents
  for AGENT in "${AGENTS[@]}"; do
    echo ">>> Running $AGENT benchmark..."
    run_benchmark "$AGENT" "$LEMONADE_MODEL" "$TAG" "$LEMONADE_MODEL"
    echo ""
  done

  # Step 7: Verify and mark completed
  verify_results "$TAG"
  mark_completed "$MODEL_NAME" "$TAG" "$SIZE_GB"
  echo ""

  # Track for cleanup in next iteration
  PREVIOUS_MODEL="$LEMONADE_MODEL"
done

# ═════════════════════════════════════════
# Final Summary
# ═════════════════════════════════════════

echo ""
echo "=========================================="
echo "  All benchmarks complete!"
echo "  Finished: $(date)"
echo "=========================================="
echo ""

echo ">>> Final Results Summary:"
for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME TAG SIZE_GB HF_CHECKPOINT VARIANT <<< "$MODEL_CONFIG"
  verify_results "$TAG"
done

echo ""
echo ">>> Run dashboard to see full results:"
echo "    python3 dashboard.py"
echo ""

# Keep last model for potential re-runs (comment out to auto-cleanup)
# if [ -n "$PREVIOUS_MODEL" ]; then
#   echo ">>> Cleaning up final model: $PREVIOUS_MODEL"
#   stop_lemonade
#   delete_model "$PREVIOUS_MODEL" || true
# fi

echo ">>> Generating comparison report..."
python3 collect_results.py || echo ">>> Note: collect_results.py not found or failed"

echo ""
echo "=========================================="
echo "  Done! $(date)"
echo "=========================================="
