#!/usr/bin/env bash
# Cloud eval sweep — designed for nohup overnight runs
# Continues even if individual combos fail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Load environment
set -a
source .env
set +a

export N_CONCURRENT=4

CLOUD_LOG="$SCRIPT_DIR/cloud.log"

echo "============================================"
echo "  Cloud Eval Sweep (3 models × 2 agents)"
echo "  Started: $(date)"
echo "  Log: $CLOUD_LOG"
echo "============================================"
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

# ── MiniMax M2.1 on Fireworks ──
run_combo "1/6" terminus-2 "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks
run_combo "2/6" openhands  "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks

# ── Qwen3-Coder-Next on Together ──
run_combo "3/6" terminus-2 "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together
run_combo "4/6" openhands  "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together

# ── GLM-4.7 on Together ──
run_combo "5/6" terminus-2 "together_ai/zai-org/GLM-4.7" glm47-together
run_combo "6/6" openhands  "together_ai/zai-org/GLM-4.7" glm47-together

# ── Collect ──
echo ">>> Collecting cloud results..."
python3 collect_results.py || true

echo ""
echo "============================================"
echo "  Cloud sweep done: $PASS passed, $FAIL failed"
echo "  Finished: $(date)"
echo "============================================"
