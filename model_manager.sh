#!/usr/bin/env bash
# Model Manager - Disk space and model lifecycle management
# Manages downloading, running, and deleting HuggingFace GGUF models
#
# Switched from lemonade-server to llama-server (b8580+) for Qwen3.5 support
#
# Usage:
#   source model_manager.sh
#   check_disk_space        # Returns available GB
#   delete_model MODEL      # Remove from cache
#   download_model MODEL    # huggingface-cli download
#   ensure_space SIZE_GB    # Delete completed models until space available
#   start_model MODEL       # Start llama-server with model

set -euo pipefail

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
LLAMA_BIN="${HOME}/.local/bin/llama.cpp/llama-b8580/llama-server"
LLAMA_LIB="${HOME}/.local/bin/llama.cpp/llama-b8580"
LLAMA_MODELS_DIR="${HOME}/.cache/llama-models"
LLAMA_PID_FILE="/tmp/llama-server.pid"
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"
COMPLETED_FILE="${SCRIPT_DIR:-$(pwd)}/benchmarks_completed.txt"
MIN_FREE_GB=20

# Ensure models directory exists
mkdir -p "$LLAMA_MODELS_DIR"

# ─────────────────────────────────────────
# check_disk_space - Return available disk space in GB
# ─────────────────────────────────────────
check_disk_space() {
  df -BG "${LLAMA_MODELS_DIR}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0"
}

# ─────────────────────────────────────────
# get_model_size - Estimate model size in GB from cache
# ─────────────────────────────────────────
get_model_size() {
  local MODEL="$1"
  local MODEL_DIR="${LLAMA_MODELS_DIR}/${MODEL}"
  if [ -d "$MODEL_DIR" ]; then
    du -s -BG "$MODEL_DIR" 2>/dev/null | awk '{gsub("G",""); print $1}'
  else
    echo "0"
  fi
}

# ─────────────────────────────────────────
# delete_model - Remove a model from cache
# ─────────────────────────────────────────
delete_model() {
  local MODEL="$1"
  # Strip user. prefix if present (legacy from lemonade)
  MODEL="${MODEL#user.}"

  local MODEL_DIR="${LLAMA_MODELS_DIR}/${MODEL}"
  echo "  Deleting $MODEL..."

  if [ -d "$MODEL_DIR" ]; then
    rm -rf "$MODEL_DIR"
    echo "  Deleted: $MODEL"
    return 0
  else
    echo "  Model not found or already deleted: $MODEL"
    return 1
  fi
}

# ─────────────────────────────────────────
# download_model - Download a model using huggingface-cli
# Args: MODEL_NAME [HF_CHECKPOINT] [VARIANT]
# ─────────────────────────────────────────
download_model() {
  local MODEL="$1"
  local HF_CHECKPOINT="${2:-}"
  local VARIANT="${3:-Q4_K_M}"
  local MODEL_DIR="${LLAMA_MODELS_DIR}/${MODEL}"

  echo "  Downloading $MODEL..."

  if [ -n "$HF_CHECKPOINT" ]; then
    echo "  Pulling from HuggingFace: $HF_CHECKPOINT (variant: *${VARIANT}*)"

    # Use hf CLI to download GGUF files matching the variant
    hf download "$HF_CHECKPOINT" \
      --include "*${VARIANT}*.gguf" \
      --local-dir "$MODEL_DIR"

    # Verify download
    local GGUF_COUNT=$(find "$MODEL_DIR" -name "*.gguf" 2>/dev/null | wc -l)
    if [ "$GGUF_COUNT" -eq 0 ]; then
      echo "  ERROR: No GGUF files found after download"
      return 1
    fi
    echo "  Downloaded $GGUF_COUNT GGUF file(s) to $MODEL_DIR"
  else
    echo "  ERROR: HF_CHECKPOINT required for direct download"
    return 1
  fi
}

# ─────────────────────────────────────────
# ensure_space - Free up disk space by deleting completed models
# ─────────────────────────────────────────
ensure_space() {
  local NEEDED_GB="${1:-$MIN_FREE_GB}"
  local CURRENT_FREE=$(check_disk_space)

  echo "  Disk space: ${CURRENT_FREE}GB free, need ${NEEDED_GB}GB"

  if [ "$CURRENT_FREE" -ge "$NEEDED_GB" ]; then
    echo "  Sufficient space available"
    return 0
  fi

  # Read completed models and delete oldest first
  if [ -f "$COMPLETED_FILE" ]; then
    while IFS='|' read -r MODEL TAG SIZE STATUS TIMESTAMP; do
      [ -z "$MODEL" ] && continue
      [[ "$MODEL" =~ ^# ]] && continue

      # Only delete if marked as completed
      if [ "$STATUS" = "completed" ]; then
        echo "  Freeing space by removing completed model: $MODEL"
        delete_model "$MODEL" || true

        CURRENT_FREE=$(check_disk_space)
        if [ "$CURRENT_FREE" -ge "$NEEDED_GB" ]; then
          echo "  Space freed: ${CURRENT_FREE}GB available"
          return 0
        fi
      fi
    done < "$COMPLETED_FILE"
  fi

  CURRENT_FREE=$(check_disk_space)
  if [ "$CURRENT_FREE" -ge "$NEEDED_GB" ]; then
    return 0
  else
    echo "  WARNING: Could not free enough space. Have ${CURRENT_FREE}GB, need ${NEEDED_GB}GB"
    return 1
  fi
}

# ─────────────────────────────────────────
# stop_llama - Stop any running llama-server
# ─────────────────────────────────────────
stop_llama() {
  echo "  Stopping llama-server..."

  # Try PID file first
  if [ -f "$LLAMA_PID_FILE" ]; then
    local PID=$(cat "$LLAMA_PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null || true
      sleep 2
    fi
    rm -f "$LLAMA_PID_FILE"
  fi

  # Force kill if still running
  pkill -f "llama-server" 2>/dev/null || true
  sleep 2
}

# Legacy alias
stop_lemonade() {
  stop_llama
}

# ─────────────────────────────────────────
# get_model_ctx_size - Return appropriate context size for model
# Phi-4 is trained with 16K max, others can use 32K
# ─────────────────────────────────────────
get_model_ctx_size() {
  local MODEL="$1"
  case "$MODEL" in
    *phi-4*|*phi4*|*Phi-4*|*Phi4*)
      echo "16384"  # Phi-4 trained with 16K max
      ;;
    *)
      echo "32768"  # Default 32K for other models
      ;;
  esac
}

# ─────────────────────────────────────────
# start_model - Start llama-server with a model
# ─────────────────────────────────────────
start_model() {
  local MODEL="$1"
  local PORT="${2:-8000}"
  local CTX_SIZE="${3:-}"

  # Strip user. prefix if present (legacy from lemonade)
  MODEL="${MODEL#user.}"

  # Auto-detect context size if not provided
  if [ -z "$CTX_SIZE" ]; then
    CTX_SIZE=$(get_model_ctx_size "$MODEL")
  fi

  echo "  Starting llama-server with $MODEL..."
  echo "  Context size: $CTX_SIZE"
  stop_llama

  # Find the GGUF file
  local MODEL_DIR="${LLAMA_MODELS_DIR}/${MODEL}"
  local GGUF_FILE=$(find "$MODEL_DIR" -name "*.gguf" -type f 2>/dev/null | head -1)

  if [ -z "$GGUF_FILE" ]; then
    echo "  ERROR: No GGUF file found in $MODEL_DIR"
    return 1
  fi
  echo "  Using GGUF file: $GGUF_FILE"

  # Set library path for llama.cpp shared libraries
  export LD_LIBRARY_PATH="${LLAMA_LIB}:${LD_LIBRARY_PATH:-}"

  # Start llama-server
  "$LLAMA_BIN" \
    --model "$GGUF_FILE" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --threads 16 \
    --flash-attn auto \
    --reasoning-budget 2048 \
    --api-key lemonade &

  # Save PID
  echo $! > "$LLAMA_PID_FILE"

  # Wait for model to load
  echo -n "  Waiting for model to load: "
  for i in $(seq 1 180); do
    if curl -sf "http://localhost:${PORT}/v1/models" >/dev/null 2>&1; then
      echo "OK (${i}s)"

      # Warmup: Send a few test requests to ensure server is fully ready
      echo "  Warming up server with test requests..."
      for w in 1 2 3; do
        curl -sf "http://localhost:${PORT}/v1/models" >/dev/null 2>&1 || true
        sleep 1
      done
      echo "  Server ready."
      return 0
    fi
    sleep 2
  done

  echo "FAILED after 6 min"
  return 1
}

# ─────────────────────────────────────────
# check_llama - Check if llama-server is running with expected model
# ─────────────────────────────────────────
check_llama() {
  local MODEL="${1:-}"
  # Strip user. prefix if present (legacy from lemonade)
  MODEL="${MODEL#user.}"

  if [ -n "$MODEL" ]; then
    # llama-server returns the filename, not the model name, so just check if server responds
    curl -sf http://localhost:8000/v1/models >/dev/null 2>&1
  else
    curl -sf http://localhost:8000/v1/models >/dev/null 2>&1
  fi
}

# Legacy alias
check_lemonade() {
  check_llama "$@"
}

# ─────────────────────────────────────────
# mark_completed - Mark a model as completed in tracking file
# ─────────────────────────────────────────
mark_completed() {
  local MODEL="$1"
  local TAG="$2"
  local SIZE="$3"

  # Create file if it doesn't exist
  if [ ! -f "$COMPLETED_FILE" ]; then
    echo "# MODEL|TAG|SIZE_GB|STATUS|TIMESTAMP" > "$COMPLETED_FILE"
  fi

  echo "${MODEL}|${TAG}|${SIZE}|completed|$(date -Iseconds)" >> "$COMPLETED_FILE"
  echo "  Marked as completed: $MODEL ($TAG)"
}

# ─────────────────────────────────────────
# mark_started - Mark a model as started in tracking file
# ─────────────────────────────────────────
mark_started() {
  local MODEL="$1"
  local TAG="$2"
  local SIZE="$3"

  if [ ! -f "$COMPLETED_FILE" ]; then
    echo "# MODEL|TAG|SIZE_GB|STATUS|TIMESTAMP" > "$COMPLETED_FILE"
  fi

  echo "${MODEL}|${TAG}|${SIZE}|started|$(date -Iseconds)" >> "$COMPLETED_FILE"
  echo "  Started benchmark: $MODEL ($TAG)"
}

echo "Model manager loaded (llama-server b8580). Functions available:"
echo "  check_disk_space, delete_model, download_model, ensure_space"
echo "  start_model, stop_llama, check_llama"
echo "  mark_completed, mark_started"
