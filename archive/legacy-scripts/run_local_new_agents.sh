#!/usr/bin/env bash
# New Agent Harnesses Easy Tasks Benchmark - Local Models
# Runs swe-agent, mini-swe-agent, qwen-coder against easy tasks
#
# Copied from run_openhands_easy.sh — only change: AGENTS
#
# Usage: nohup ./run_local_new_agents.sh > logs/local_new_agents.log 2>&1 &

set -uo pipefail  # No -e: don't exit on task failures

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

source "$HOME/.local/bin/env" 2>/dev/null || true
source "${SCRIPT_DIR}/model_manager.sh"

# Get host IP for Docker networking
HOST_IP=$(hostname -I | awk '{print $1}')
echo "Host IP: $HOST_IP"

export OPENAI_API_KEY=lemonade
export OPENAI_API_BASE="http://${HOST_IP}:8000/v1"
export OPENAI_BASE_URL="http://${HOST_IP}:8000/v1"

# Agents to benchmark — ONLY CHANGE FROM run_openhands_easy.sh
AGENTS=("swe-agent" "mini-swe-agent" "qwen-coder")

# Models for 30GB server (Q4_K_M quantization)
MODELS=(
  "Qwen3-Coder-30B-A3B-Instruct-GGUF|unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF|Q4_K_M"
  "Qwen3.5-35B-A3B-GGUF|unsloth/Qwen3.5-35B-A3B-GGUF|Q4_K_M"
  "GLM-4.7-Flash-GGUF|unsloth/GLM-4.7-Flash-GGUF|Q4_K_M"
  "gpt-oss-20b-GGUF|ggml-org/gpt-oss-20b-GGUF|Q4_K_M"
)

# Read easy tasks
TASK_FILE="${SCRIPT_DIR}/easy_tasks_merged.txt"
mapfile -t TASKS < <(grep -v '^$' "$TASK_FILE")

mkdir -p logs

echo "============================================"
echo "  New Agents Easy Tasks Benchmark"
echo "  Agents: ${AGENTS[*]}"
echo "  Models: ${#MODELS[@]}"
echo "  Tasks: ${#TASKS[@]}"
echo "  Host IP: $HOST_IP"
echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
echo "============================================"

PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Model: $MODEL_NAME"
  echo "  Time: $(date)"
  echo "=========================================="

  # Clean up previous model
  if [ -n "$PREVIOUS_MODEL" ]; then
    echo ">>> Cleaning up previous model: $PREVIOUS_MODEL"
    stop_llama
    delete_model "$PREVIOUS_MODEL" || true
    echo "  Disk free: $(df -h /scratch | awk 'NR==2{print $4}')"
  fi

  # Download model
  echo ">>> Downloading $MODEL_NAME..."
  if ! download_model "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
    echo "  DOWNLOAD FAILED - skipping"
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  # Start server
  echo ">>> Starting server..."
  if ! start_model "$MODEL_NAME"; then
    echo "  SERVER FAILED - skipping"
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  # Wait for server to be ready
  echo ">>> Waiting for server..."
  for i in {1..30}; do
    if curl -s "http://localhost:8000/v1/models" >/dev/null 2>&1; then
      echo "  Server ready!"
      break
    fi
    sleep 1
  done

  # Run all agents for this model
  for AGENT in "${AGENTS[@]}"; do
    echo ""
    echo "--- Agent: $AGENT ---"

    RESULTS_DIR="${SCRIPT_DIR}/results/${AGENT}-${MODEL_NAME,,}-local"
    mkdir -p "$RESULTS_DIR"

    PASS=0
    FAIL=0
    ERROR=0

    for TASK_ENTRY in "${TASKS[@]}"; do
      # Parse dataset|task format
      if [[ "$TASK_ENTRY" == *"|"* ]]; then
        TASK_DATASET="${TASK_ENTRY%%|*}"
        TASK="${TASK_ENTRY#*|}"
      else
        TASK_DATASET="terminal-bench@2.0"
        TASK="$TASK_ENTRY"
      fi

      echo ""
      echo "  >>> Task: $TASK (dataset: $TASK_DATASET)"

      START_TIME=$(date +%s)

      JOB_DIR="${RESULTS_DIR}/${TASK}"
      mkdir -p "$JOB_DIR"

      if timeout 600 harbor run \
        -d "$TASK_DATASET" \
        -a "$AGENT" \
        -m "openai/${MODEL_NAME}" \
        -n 1 \
        --timeout-multiplier 2.0 \
        --jobs-dir "$JOB_DIR" \
        -t "$TASK" 2>&1 | tee -a "${RESULTS_DIR}/${TASK}.log"; then

        REWARD_FILE=$(find "$JOB_DIR" -name "reward.txt" 2>/dev/null | head -1)
        if [ -n "$REWARD_FILE" ] && [ -f "$REWARD_FILE" ]; then
          REWARD=$(cat "$REWARD_FILE")
          if [ "$REWARD" = "1" ]; then
            echo "      Result: PASS"
            ((PASS++))
          else
            echo "      Result: FAIL (reward=$REWARD)"
            ((FAIL++))
          fi
        else
          echo "      Result: NO_REWARD"
          ((FAIL++))
        fi
      else
        echo "      Result: TIMEOUT/ERROR"
        ((ERROR++))
      fi

      END_TIME=$(date +%s)
      echo "      Duration: $((END_TIME - START_TIME))s"
    done

    TOTAL=${#TASKS[@]}
    echo ""
    echo "  Agent Summary: $AGENT + $MODEL_NAME"
    echo "    Pass: $PASS / $TOTAL"
    echo "    Fail: $FAIL"
    echo "    Error: $ERROR"
  done

  PREVIOUS_MODEL="$MODEL_NAME"
done

# Final cleanup
if [ -n "$PREVIOUS_MODEL" ]; then
  echo ""
  echo ">>> Final cleanup: $PREVIOUS_MODEL"
  stop_llama
  delete_model "$PREVIOUS_MODEL" || true
fi

echo ""
echo "============================================"
echo "  Benchmark Complete! $(date)"
echo "============================================"
