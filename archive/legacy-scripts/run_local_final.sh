#!/usr/bin/env bash
# Final local model re-runs with stable Lemonade settings
# Runs: terminus-2 + openhands for GLM-4.7-Flash, openhands for GLM-4.7-Flash
#
# Lemonade settings: ctx-size 32768, no prompt cache (prevents VRAM crash)
# N_CONCURRENT=1 (full GPU per request)
#
# Usage:
#   1. Start Lemonade manually first (see below)
#   2. nohup bash -c './run_local_final.sh > local_final.log 2>&1' &
#
# Before running, start Lemonade in another terminal:
#   lemonade-server run GLM-4.7-Flash-GGUF --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

set -a
source .env
set +a

export N_CONCURRENT=1

TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

LEMONADE_ARGS="--host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args --cache-ram 0"

echo "============================================"
echo "  Final Local Model Runs"
echo "  Started: $(date)"
echo "  ctx-size: 16384, prompt cache: OFF"
echo "  N_CONCURRENT: 1"
echo "============================================"
echo ""

# ─────────────────────────────────────────
# Health check helper
# ─────────────────────────────────────────
check_lemonade() {
  local MODEL="$1"
  if curl -sf http://localhost:8000/api/v1/models 2>/dev/null | grep -q "$MODEL"; then
    return 0
  fi
  return 1
}

wait_for_lemonade() {
  local MODEL="$1"
  echo -n "  Waiting for $MODEL: "
  for i in $(seq 1 120); do
    if check_lemonade "$MODEL"; then
      echo "OK"
      return 0
    fi
    sleep 5
  done
  echo "FAILED after 10 min"
  return 1
}

swap_model() {
  local MODEL="$1"
  echo ">>> Swapping Lemonade to $MODEL"
  lemonade-server stop 2>/dev/null || true
  sleep 5
  lemonade-server run "$MODEL" --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0' &
  wait_for_lemonade "$MODEL"
}

# ─────────────────────────────────────────
# Run helper with health check after each task
# ─────────────────────────────────────────
run_one_agent() {
  local LABEL="$1" AGENT="$2" MODEL_STR="$3" TAG="$4" LEMONADE_MODEL="$5"
  local JOBS_DIR="${SCRIPT_DIR}/results/${AGENT}-${TAG}"

  mkdir -p "$JOBS_DIR"
  echo ">>> [$LABEL] $AGENT + $TAG — started $(date '+%H:%M:%S')"

  if [ "$AGENT" = "terminus-2" ]; then
    harbor run \
      -d terminal-bench@2.0 \
      -a "$AGENT" \
      -m "$MODEL_STR" \
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
      -m "$MODEL_STR" \
      -n 1 \
      --jobs-dir "$JOBS_DIR" \
      "${TASK_FLAGS[@]}" \
      2>&1 | tee "${JOBS_DIR}/run.log" || true
  fi

  echo ">>> [$LABEL] $AGENT + $TAG — finished $(date '+%H:%M:%S')"

  # Health check — restart Lemonade if it died
  if ! check_lemonade "$LEMONADE_MODEL"; then
    echo ">>> ⚠️  Lemonade died! Restarting..."
    swap_model "$LEMONADE_MODEL"
  fi
  echo ""
}

# ═════════════════════════════════════════
# PHASE 1: GLM-4.7-Flash
# ═════════════════════════════════════════
echo "=========================================="
echo "  PHASE 1: GLM-4.7-Flash-GGUF"
echo "=========================================="
echo ""

# Check if Lemonade is running with GLM-Flash, otherwise start it
if ! check_lemonade "GLM-4.7-Flash"; then
  swap_model "GLM-4.7-Flash-GGUF"
fi

# 1a. terminus-2 + GLM-Flash
run_one_agent "1/3" terminus-2 "openai/GLM-4.7-Flash-GGUF" glm47-flash-local-v2 "GLM-4.7-Flash"

# 1b. openhands + GLM-Flash
run_one_agent "2/3" openhands "openai/GLM-4.7-Flash-GGUF" glm47-flash-local-v2 "GLM-4.7-Flash"

# ═════════════════════════════════════════
# PHASE 2: Qwen3-Coder-30B (openhands only — terminus-2 already valid)
# Swap Lemonade to Qwen
# ═════════════════════════════════════════
echo "=========================================="
echo "  PHASE 2: Qwen3-Coder-30B (openhands re-run with --ctx-size 32768)"
echo "=========================================="
echo ""

# NOTE: openhands + qwen-30b-local already has a clean run (13/13, 46 tok/s GPU)
# Only re-run if you want results with the new ctx-size setting
# Uncomment below to re-run:

# swap_model "Qwen3-Coder-30B-A3B-Instruct-GGUF"
# run_one_agent "3/3" openhands "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local-v2 "Qwen3-Coder-30B-A3B-Instruct"

echo ">>> Skipping openhands + qwen-30b (already have clean 13/13 run)"
echo ""

# ═════════════════════════════════════════
# Summary
# ═════════════════════════════════════════
echo ""
echo "=========================================="
echo "  Verifying results..."
echo "=========================================="

for tag in terminus-2-glm47-flash-local-v2 openhands-glm47-flash-local-v2; do
  dir="${SCRIPT_DIR}/results/${tag}"
  if [ -d "$dir" ]; then
    passes=$(find "$dir" -name "reward.txt" -exec grep "^1$" {} \; 2>/dev/null | wc -l)
    total=$(find "$dir" -name "reward.txt" 2>/dev/null | wc -l)
    errors=$(find "$dir" -name "result.json" -path "*__*" -exec grep -l "exception_info" {} \; 2>/dev/null | wc -l)
    echo "  $tag: $passes/$total pass, $errors errors"
  fi
done

echo ""
echo "=========================================="
echo "  Final local runs complete: $(date)"
echo "=========================================="
