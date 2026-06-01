#!/usr/bin/env bash
# Re-run GLM-Flash local runs (terminus-2 + openhands)
# Lemonade must already be running on GPU with GLM-4.7-Flash loaded!
# Usage: nohup bash -c './run_gpu_redo.sh > gpu_redo.log 2>&1' &

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
echo "  GPU Re-do: GLM-4.7-Flash (Vulkan)"
echo "  Started: $(date)"
echo "============================================"
echo ""

export N_CONCURRENT=1

# Verify Lemonade is running on GPU
echo "Checking Lemonade..."
if ! curl -sf http://localhost:8000/api/v1/models 2>/dev/null | grep -q "GLM-4.7-Flash"; then
  echo "ERROR: Lemonade not running with GLM-4.7-Flash!"
  echo "Start it first: lemonade-server run GLM-4.7-Flash-GGUF --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp vulkan --llamacpp-args '--cache-ram 0'"
  exit 1
fi
echo "✅ Lemonade running with GLM-4.7-Flash"
echo ""

# ── 1/2: terminus-2 ──
echo ">>> [1/2] terminus-2 + glm47-flash-local — started $(date '+%H:%M:%S')"
./run_one.sh terminus-2 "openai/GLM-4.7-Flash-GGUF" glm47-flash-local-gpu || true
echo ">>> [1/2] DONE $(date '+%H:%M:%S')"
echo ""

# ── 2/2: openhands ──
echo ">>> [2/2] openhands + glm47-flash-local — started $(date '+%H:%M:%S')"
harbor run \
  --config openhands_hostnet.yaml \
  -d terminal-bench@2.0 \
  -a openhands \
  -m "openai/GLM-4.7-Flash-GGUF" \
  -n 1 \
  --jobs-dir "$SCRIPT_DIR/results/openhands-glm47-flash-local-gpu" \
  "${TASK_FLAGS[@]}" \
  2>&1 | tee "$SCRIPT_DIR/results/openhands-glm47-flash-local-gpu/run.log" || true
echo ">>> [2/2] DONE $(date '+%H:%M:%S')"

echo ""
echo "============================================"
echo "  GPU re-do complete: $(date)"
echo "============================================"
