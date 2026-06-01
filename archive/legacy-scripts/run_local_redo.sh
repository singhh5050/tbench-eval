#!/usr/bin/env bash
# Re-run local models with ROCm backend (fixing Vulkan/CPU slowness)
# Usage: nohup bash -c './run_local_redo.sh > local_redo.log 2>&1' &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

set -a
source .env
set +a

TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

echo "============================================"
echo "  Local Model Re-runs (ROCm backend)"
echo "  Started: $(date)"
echo "============================================"
echo ""

# ─────────────────────────────────────────
# Clean up old broken runs
# ─────────────────────────────────────────
echo "Expecting old runs to be cleaned up already (requires sudo)."
echo ""

# ─────────────────────────────────────────
# Helper: swap Lemonade model with ROCm
# ─────────────────────────────────────────
load_lemonade_model() {
  local MODEL_NAME="$1"
  echo ">>> Stopping Lemonade..."
  lemonade-server stop 2>/dev/null || true
  sleep 5

  echo ">>> Starting Lemonade with $MODEL_NAME (ROCm backend)..."
  lemonade-server run "$MODEL_NAME" --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0' &
  
  echo -n ">>> Waiting for model to load: "
  for i in $(seq 1 60); do
    if curl -sf http://localhost:8000/api/v1/models 2>/dev/null | grep -q "$MODEL_NAME"; then
      echo "OK"
      return 0
    fi
    sleep 5
  done
  echo "FAILED"
  return 1
}

# ═════════════════════════════════════════
# 1. GLM-4.7-Flash — terminus-2 + OpenHands
# ═════════════════════════════════════════
echo "========== GLM-4.7-Flash-GGUF =========="
if load_lemonade_model "GLM-4.7-Flash-GGUF"; then
  echo ""
  echo ">>> [1/3] terminus-2 + glm47-flash-local — started $(date '+%H:%M:%S')"
  ./run_one.sh terminus-2 "openai/GLM-4.7-Flash-GGUF" glm47-flash-local || true
  echo ">>> [1/3] DONE $(date '+%H:%M:%S')"
  echo ""

  echo ">>> [2/3] openhands + glm47-flash-local — started $(date '+%H:%M:%S')"
  harbor run \
    --config openhands_hostnet.yaml \
    -d terminal-bench@2.0 \
    -a openhands \
    -m "openai/GLM-4.7-Flash-GGUF" \
    -n 1 \
    --jobs-dir "$SCRIPT_DIR/results/openhands-glm47-flash-local" \
    "${TASK_FLAGS[@]}" \
    2>&1 | tee "$SCRIPT_DIR/results/openhands-glm47-flash-local/run.log" || true
  echo ">>> [2/3] DONE $(date '+%H:%M:%S')"
  echo ""
fi

# ═════════════════════════════════════════
# 2. Qwen3-Coder-30B — OpenHands only
# ═════════════════════════════════════════
echo "========== Qwen3-Coder-30B-A3B-Instruct-GGUF =========="
if load_lemonade_model "Qwen3-Coder-30B-A3B-Instruct-GGUF"; then
  echo ""
  echo ">>> [3/3] openhands + qwen-30b-local — started $(date '+%H:%M:%S')"
  harbor run \
    --config openhands_hostnet.yaml \
    -d terminal-bench@2.0 \
    -a openhands \
    -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
    -n 1 \
    --jobs-dir "$SCRIPT_DIR/results/openhands-qwen-30b-local" \
    "${TASK_FLAGS[@]}" \
    2>&1 | tee "$SCRIPT_DIR/results/openhands-qwen-30b-local/run.log" || true
  echo ">>> [3/3] DONE $(date '+%H:%M:%S')"
  echo ""
fi

echo ""
echo "============================================"
echo "  Local re-runs complete: $(date)"
echo "============================================"
