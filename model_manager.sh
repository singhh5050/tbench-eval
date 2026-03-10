#!/usr/bin/env bash
# Model Manager - Disk space and model lifecycle management
# Manages downloading, running, and deleting HuggingFace GGUF models
#
# Usage:
#   source model_manager.sh
#   check_disk_space        # Returns available GB
#   delete_model MODEL      # Remove from HF cache
#   download_model MODEL    # lemonade-server pull
#   ensure_space SIZE_GB    # Delete completed models until space available
#   start_model MODEL       # Start lemonade-server with model

set -euo pipefail

# ─────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}"
COMPLETED_FILE="${SCRIPT_DIR:-$(pwd)}/benchmarks_completed.txt"
MIN_FREE_GB=20

# ─────────────────────────────────────────
# check_disk_space - Return available disk space in GB
# ─────────────────────────────────────────
check_disk_space() {
  df -BG "${HF_CACHE}" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo "0"
}

# ─────────────────────────────────────────
# get_model_size - Estimate model size in GB from HF cache
# ─────────────────────────────────────────
get_model_size() {
  local MODEL="$1"
  local MODEL_DIR="${HF_CACHE}/hub/models--${MODEL//\//-}"
  if [ -d "$MODEL_DIR" ]; then
    du -s -BG "$MODEL_DIR" 2>/dev/null | awk '{gsub("G",""); print $1}'
  else
    echo "0"
  fi
}

# ─────────────────────────────────────────
# delete_model - Remove a model using lemonade-server delete
# ─────────────────────────────────────────
delete_model() {
  local MODEL="$1"
  echo "  Deleting $MODEL..."
  if lemonade-server delete "$MODEL" 2>/dev/null; then
    echo "  Deleted: $MODEL"
    return 0
  else
    echo "  Model not found or already deleted: $MODEL"
    return 1
  fi
}

# ─────────────────────────────────────────
# download_model - Pull a model using lemonade-server
# Args: MODEL_NAME [HF_CHECKPOINT] [VARIANT]
# If HF_CHECKPOINT is provided, pulls from HuggingFace and registers as MODEL_NAME
# ─────────────────────────────────────────
download_model() {
  local MODEL="$1"
  local HF_CHECKPOINT="${2:-}"
  local VARIANT="${3:-Q4_K_M}"

  echo "  Downloading $MODEL..."

  if [ -n "$HF_CHECKPOINT" ]; then
    # Pull from HuggingFace with custom name (must use user. prefix)
    local USER_MODEL="user.${MODEL}"
    echo "  Pulling from HuggingFace: $HF_CHECKPOINT:$VARIANT"
    lemonade-server pull "$USER_MODEL" --checkpoint "${HF_CHECKPOINT}:${VARIANT}" --recipe llamacpp
    echo "  Registered as: $USER_MODEL"
  else
    # Pull from lemonade's built-in registry
    lemonade-server pull "$MODEL"
    echo "  Downloaded: $MODEL"
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
# stop_lemonade - Stop any running lemonade-server
# ─────────────────────────────────────────
stop_lemonade() {
  echo "  Stopping lemonade-server..."
  lemonade-server stop 2>/dev/null || true
  sleep 3
  # Force kill if still running
  pkill -f "lemonade-server" 2>/dev/null || true
  sleep 2
}

# ─────────────────────────────────────────
# start_model - Start lemonade-server with a model
# ─────────────────────────────────────────
start_model() {
  local MODEL="$1"
  local PORT="${2:-8000}"
  local CTX_SIZE="${3:-32768}"

  echo "  Starting lemonade-server with $MODEL..."
  stop_lemonade

  lemonade-server run "$MODEL" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --llamacpp vulkan \
    --llamacpp-args '--cache-ram 0' &

  # Wait for model to load
  echo -n "  Waiting for model to load: "
  for i in $(seq 1 180); do
    if curl -sf "http://localhost:${PORT}/api/v1/models" >/dev/null 2>&1; then
      echo "OK (${i}s)"
      return 0
    fi
    sleep 2
  done

  echo "FAILED after 6 min"
  return 1
}

# ─────────────────────────────────────────
# check_lemonade - Check if lemonade is running with expected model
# ─────────────────────────────────────────
check_lemonade() {
  local MODEL="${1:-}"
  if [ -n "$MODEL" ]; then
    curl -sf http://localhost:8000/api/v1/models 2>/dev/null | grep -q "$MODEL"
  else
    curl -sf http://localhost:8000/api/v1/models >/dev/null 2>&1
  fi
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

echo "Model manager loaded. Functions available:"
echo "  check_disk_space, delete_model, download_model, ensure_space"
echo "  start_model, stop_lemonade, check_lemonade"
echo "  mark_completed, mark_started"
