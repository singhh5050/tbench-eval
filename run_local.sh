#!/usr/bin/env bash
# Local eval via Lemonade — designed for nohup overnight runs
# Continues even if individual combos fail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Load environment
set -a
source .env
set +a

export N_CONCURRENT=1  # Local models: keep low to avoid OOM on 30GB RAM

LOCAL_LOG="$SCRIPT_DIR/local.log"

echo "============================================"
echo "  Local Eval: Qwen3-30B via Lemonade"
echo "  Started: $(date)"
echo "  Log: $LOCAL_LOG"
echo "============================================"
echo ""

# Verify Lemonade is running
if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "ERROR: Lemonade is not running on :8000"
  echo "Start it with: lemonade-server serve --host 0.0.0.0 --ctx-size 32768"
  exit 1
fi
echo "Lemonade is up on :8000"
echo ""

PASS=0
FAIL=0

run_combo() {
  local NUM="$1" AGENT="$2" MODEL="$3" TAG="$4"
  echo ">>> [$NUM] $AGENT + $TAG — started $(date '+%H:%M:%S')"
  if ./run_one.sh "$AGENT" "$MODEL" "$TAG"; then
    echo ">>> [$NUM] $AGENT + $TAG — COMPLETED $(date '+%H:%M:%S')"
    PASS=$((PASS+1))
  else
    echo ">>> [$NUM] $AGENT + $TAG — FAILED $(date '+%H:%M:%S')"
    FAIL=$((FAIL+1))
  fi
  echo ""
}

# ── Qwen3-Coder-30B-A3B via Lemonade ──
run_combo "1/2" terminus-2 "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local
run_combo "2/2" openhands  "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local

# ── Collect ──
echo ">>> Collecting local results..."
python3 collect_results.py || true

echo ""
echo "============================================"
echo "  Local sweep done: $PASS passed, $FAIL failed"
echo "  Finished: $(date)"
echo "============================================"
