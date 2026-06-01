#!/usr/bin/env bash
# OpenHands eval sweep — all models (cloud + local)
# Designed for nohup: nohup ./run_openhands_all.sh > openhands_all.log 2>&1 &
#
# Prerequisites:
#   - Harbor patched for network_mode: host
#   - Docker permissions fixed (root:docker on socket)
#   - Lemonade installed with models pulled

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Export all env vars so harbor/openhands can see them
set -a
source .env
set +a

LOG="$SCRIPT_DIR/openhands_all.log"
TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"

echo "============================================"
echo "  OpenHands Eval Sweep"
echo "  Started: $(date)"
echo "============================================"
echo ""

PASS=0
FAIL=0

# Build -t flags from task list
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

# ─────────────────────────────────────────────
# Helper: run one OpenHands eval
# ─────────────────────────────────────────────
run_openhands() {
  local NUM="$1" MODEL="$2" TAG="$3"
  local JOBS_DIR="${SCRIPT_DIR}/results/openhands-${TAG}"

  mkdir -p "$JOBS_DIR"
  echo ">>> [$NUM] openhands + $TAG — started $(date '+%H:%M:%S')"
  echo "    Model: $MODEL"
  echo "    Results: $JOBS_DIR"

  if harbor run \
    --config openhands_hostnet.yaml \
    -d terminal-bench@2.0 \
    -a openhands \
    -m "$MODEL" \
    -n 1 \
    --jobs-dir "$JOBS_DIR" \
    "${TASK_FLAGS[@]}" \
    2>&1 | tee "${JOBS_DIR}/run.log"; then
    echo ">>> [$NUM] openhands + $TAG — COMPLETED $(date '+%H:%M:%S')"
    PASS=$((PASS+1))
  else
    echo ">>> [$NUM] openhands + $TAG — FAILED $(date '+%H:%M:%S')"
    FAIL=$((FAIL+1))
  fi
  echo ""
}

# ─────────────────────────────────────────────
# Helper: swap Lemonade model
# ─────────────────────────────────────────────
load_lemonade_model() {
  local MODEL_NAME="$1"
  echo ">>> Loading Lemonade model: $MODEL_NAME"

  # Pull if not downloaded
  if ! lemonade-server list 2>/dev/null | grep "$MODEL_NAME" | grep -q "Yes"; then
    echo "    Pulling $MODEL_NAME..."
    lemonade-server pull "$MODEL_NAME"
  fi

  # Check if server is running
  if curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
    echo "    Server running, loading model..."
    lemonade-server run "$MODEL_NAME" --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0'
  else
    echo "    Starting server with model..."
    lemonade-server run "$MODEL_NAME" --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0' &
    sleep 30  # Wait for model to load
  fi

  # Verify model is loaded
  echo -n "    Verifying: "
  for i in $(seq 1 30); do
    if curl -sf http://localhost:8000/api/v1/models 2>/dev/null | grep -q "$MODEL_NAME"; then
      echo "OK"
      return 0
    fi
    sleep 2
  done
  echo "FAILED to load model!"
  return 1
}

# ═════════════════════════════════════════════
# PART 1: Cloud models (no Lemonade needed)
# ═════════════════════════════════════════════
echo "========== CLOUD MODELS =========="
echo ""

# ── GLM-4.7 on Together ──
run_openhands "1/5" "together_ai/zai-org/GLM-4.7" glm47-together

# ── MiniMax M2.1 on Fireworks ──
run_openhands "2/5" "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks

# ── Qwen3-Coder-Next on Together ──
run_openhands "3/5" "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together

# ═════════════════════════════════════════════
# PART 2: Local models via Lemonade
# ═════════════════════════════════════════════
echo "========== LOCAL MODELS =========="
echo ""

# Point OpenHands at local Lemonade
export OPENAI_API_BASE=http://localhost:8000/api/v1
export OPENAI_API_KEY=lemonade
export LLM_API_KEY=lemonade

# ── GLM-4.7-Flash (NEW) ──
echo "--- GLM-4.7-Flash-GGUF ---"
if load_lemonade_model "GLM-4.7-Flash-GGUF"; then
  # Terminus-2 run (already exists, skip if present)
  if [ -d "${SCRIPT_DIR}/results/terminus-2-glm47-flash-local" ]; then
    echo "    terminus-2-glm47-flash-local already exists, skipping"
  else
    echo "    Running terminus-2 with GLM-4.7-Flash..."
    ./run_one.sh terminus-2 "openai/GLM-4.7-Flash-GGUF" glm47-flash-local || true
  fi

  # OpenHands run
  run_openhands "4/5" "openai/GLM-4.7-Flash-GGUF" glm47-flash-local
fi

# ── Qwen3-Coder-30B (re-run with working networking) ──
echo "--- Qwen3-Coder-30B-A3B-Instruct-GGUF ---"
if load_lemonade_model "Qwen3-Coder-30B-A3B-Instruct-GGUF"; then
  run_openhands "5/5" "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local
fi

# ═════════════════════════════════════════════
# Collect results
# ═════════════════════════════════════════════
echo ">>> Collecting results..."
python3 collect_results.py || true

echo ""
echo "============================================"
echo "  OpenHands sweep done: $PASS passed, $FAIL failed"
echo "  Finished: $(date)"
echo "============================================"
