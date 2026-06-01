#!/usr/bin/env bash
# Re-run OpenHands with cloud models (Together + Fireworks)
# No GPU needed — all inference via cloud APIs
# Can run in parallel with local model runs
#
# Usage: nohup bash -c './run_cloud_openhands.sh > cloud_openhands.log 2>&1' &

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

set -a
source .env
set +a

# Cloud models use their own API endpoints — unset local Lemonade overrides
unset OPENAI_API_BASE
unset LLM_BASE_URL
unset OPENAI_API_KEY
unset LLM_API_KEY
# Map API keys to the names the OpenHands adapter expects
export TOGETHERAI_API_KEY="${TOGETHER_AI_API_KEY}"
export FIREWORKS_AI_API_KEY="${FIREWORKS_AI_API_KEY}"

TASKS_FILE="${SCRIPT_DIR}/easy_tasks.txt"
TASK_FLAGS=()
while IFS= read -r TASK; do
  [ -z "$TASK" ] && continue
  TASK_FLAGS+=(-t "$TASK")
done < "$TASKS_FILE"

echo "============================================"
echo "  Cloud OpenHands Re-runs"
echo "  Started: $(date)"
echo "  No GPU needed — cloud APIs only"
echo "============================================"
echo ""

run_openhands() {
  local NUM="$1" MODEL="$2" TAG="$3"
  local JOBS_DIR="${SCRIPT_DIR}/results/openhands-${TAG}-v2"
  mkdir -p "$JOBS_DIR"

  echo ">>> [$NUM] openhands + $TAG — started $(date '+%H:%M:%S')"
  echo "    Model: $MODEL"

  harbor run \
    -d terminal-bench@2.0 \
    -a openhands \
    -m "$MODEL" \
    -n 1 \
    -e docker \
    --force-build \
    --override-memory-mb 8192 \
    --override-storage-mb 10240 \
    --jobs-dir "$JOBS_DIR" \
    --ak 'model_info={"max_input_tokens": 131072, "max_output_tokens": 16384}' \
    --ek "network_mode=host" \
    "${TASK_FLAGS[@]}" \
    2>&1 | tee "${JOBS_DIR}/run.log" || true

  echo ">>> [$NUM] openhands + $TAG — finished $(date '+%H:%M:%S')"
  echo ""
}

run_openhands "1/3" "together_ai/zai-org/GLM-4.7" glm47-together
run_openhands "2/3" "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks
run_openhands "3/3" "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together

echo "============================================"
echo "  Cloud re-runs complete: $(date)"
echo "============================================"
