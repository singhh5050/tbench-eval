#!/usr/bin/env bash
# OpenHands Easy Tasks Benchmark - 64GB Server Large Models
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$HOME/.local/bin/env" 2>/dev/null || true
source "${SCRIPT_DIR}/model_manager.sh"

# Get host IP for Docker networking
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Host IP: $HOST_IP"

export OPENAI_API_KEY=lemonade
export OPENAI_API_BASE="http://${HOST_IP}:8000/v1"

AGENT="openhands"

# Large models for 64GB server
MODELS=(
  "Qwen3-Coder-Next-GGUF|Qwen/Qwen3-Coder-Next-GGUF|Q4_K_M"
  "gpt-oss-120b-GGUF|ggml-org/gpt-oss-120b-GGUF|mxfp4"
  "Nemotron-3-Nano-30B-A3B-GGUF|unsloth/Nemotron-3-Nano-30B-A3B-GGUF|Q4_K_M"
)

TASK_FILE="${SCRIPT_DIR}/easy_tasks_merged.txt"
mapfile -t TASKS < <(grep -v '^$' "$TASK_FILE")

echo "============================================"
echo "  OpenHands 64GB Server Benchmark"
echo "  Models: ${#MODELS[@]}"
echo "  Tasks: ${#TASKS[@]}"
echo "  Host IP: $HOST_IP"
echo "============================================"

PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Model: $MODEL_NAME"
  echo "  Time: $(date)"
  echo "=========================================="

  if [ -n "$PREVIOUS_MODEL" ]; then
    echo ">>> Cleaning up: $PREVIOUS_MODEL"
    stop_llama
    delete_model "$PREVIOUS_MODEL" || true
  fi

  echo ">>> Downloading $MODEL_NAME..."
  if ! download_model "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
    echo "  DOWNLOAD FAILED"
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  echo ">>> Starting server..."
  if ! start_model "$MODEL_NAME"; then
    echo "  SERVER FAILED"
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  # Wait for server
  for i in {1..30}; do
    curl -s "http://localhost:8000/v1/models" >/dev/null 2>&1 && break
    sleep 1
  done

  RESULTS_DIR="${SCRIPT_DIR}/results/openhands-${MODEL_NAME,,}-64gb"
  mkdir -p "$RESULTS_DIR"

  for TASK_ENTRY in "${TASKS[@]}"; do
    if [[ "$TASK_ENTRY" == *"|"* ]]; then
      TASK_DATASET="${TASK_ENTRY%%|*}"
      TASK="${TASK_ENTRY#*|}"
    else
      TASK_DATASET="terminal-bench@2.0"
      TASK="$TASK_ENTRY"
    fi

    echo "  >>> Task: $TASK"
    JOB_DIR="${RESULTS_DIR}/${TASK}"

    timeout 600 harbor run \
      -d "$TASK_DATASET" \
      -a openhands \
      -m "openai/${MODEL_NAME}" \
      --ak "api_base=http://${HOST_IP}:8000/v1" \
      -n 1 \
      --timeout-multiplier 2.0 \
      --jobs-dir "$JOB_DIR" \
      -t "$TASK" 2>&1 | tee -a "${RESULTS_DIR}/${TASK}.log" || true

    REWARD_FILE=$(find "$JOB_DIR" -name "reward.txt" 2>/dev/null | head -1)
    [ -f "$REWARD_FILE" ] && echo "      Reward: $(cat "$REWARD_FILE")"
  done

  PREVIOUS_MODEL="$MODEL_NAME"
done

[ -n "$PREVIOUS_MODEL" ] && { stop_llama; delete_model "$PREVIOUS_MODEL" || true; }

echo "============================================"
echo "  Complete! $(date)"
echo "============================================"
