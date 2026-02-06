#!/usr/bin/env bash
# Local eval: GLM-4.7-Flash via Lemonade

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

set -a
source .env
set +a

export N_CONCURRENT=1

echo "============================================"
echo "  Local Eval: GLM-4.7-Flash via Lemonade"
echo "  Started: $(date)"
echo "============================================"

if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "ERROR: Lemonade is not running on :8000"
  exit 1
fi
echo "Lemonade is up"
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

run_combo "1/2" terminus-2 "openai/GLM-4.7-Flash-GGUF" glm-flash-local
run_combo "2/2" openhands  "openai/GLM-4.7-Flash-GGUF" glm-flash-local

echo ">>> Collecting results..."
python3 collect_results.py || true

echo ""
echo "============================================"
echo "  GLM local sweep done: $PASS passed, $FAIL failed"
echo "  Finished: $(date)"
echo "============================================"
