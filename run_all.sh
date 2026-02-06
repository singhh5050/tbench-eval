#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment
set -a
source .env
set +a

echo "============================================"
echo "  TerminalBench 2.0 — Full Eval Sweep"
echo "  $(date)"
echo "============================================"

# ──────────────────────────────────────
# PHASE 0: Verify Lemonade is running
# ──────────────────────────────────────
echo ""
echo ">>> Phase 0: Verifying Lemonade Server..."
if curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "    Lemonade is up on :8000"
else
  echo "    ERROR: Lemonade is not running on port 8000."
  echo "    Start it with: lemonade-server serve --host 0.0.0.0 --ctx-size 32768"
  exit 1
fi

# ──────────────────────────────────────
# PHASE 1: Cloud model runs (parallel)
#   These don't touch Lemonade at all
# ──────────────────────────────────────
echo ""
echo ">>> Phase 1: Cloud models (parallel)"
export N_CONCURRENT=4

# MiniMax M2.1 on Fireworks
./run_one.sh terminus-2 "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks &
PID1=$!
./run_one.sh openhands "fireworks_ai/accounts/fireworks/models/minimax-m2p1" m2.1-fireworks &
PID2=$!

# Qwen3-Coder-Next on Together
./run_one.sh terminus-2 "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together &
PID3=$!
./run_one.sh openhands "together_ai/Qwen/Qwen3-Coder-Next-FP8" qwen-next-together &
PID4=$!

# Wait for all cloud runs
CLOUD_FAIL=0
wait $PID1 || CLOUD_FAIL=$((CLOUD_FAIL+1))
wait $PID2 || CLOUD_FAIL=$((CLOUD_FAIL+1))
wait $PID3 || CLOUD_FAIL=$((CLOUD_FAIL+1))
wait $PID4 || CLOUD_FAIL=$((CLOUD_FAIL+1))
echo ">>> Phase 1 complete ($CLOUD_FAIL failures)"

# ──────────────────────────────────────
# PHASE 2: Local Qwen3-Coder-30B-A3B
#   Sequential — share Lemonade, low concurrency
# ──────────────────────────────────────
echo ""
echo ">>> Phase 2: Local Qwen3-Coder-30B-A3B (sequential)"
export N_CONCURRENT=1

./run_one.sh terminus-2 "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local || true

# OpenHands may fail on local models — be fault-tolerant
set +e
./run_one.sh openhands "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local
set -e

# ──────────────────────────────────────
# PHASE 3: Local GLM-4.7-Flash
#   Lemonade auto-evicts previous model
# ──────────────────────────────────────
echo ""
echo ">>> Phase 3: Local GLM-4.7-Flash (sequential)"
export N_CONCURRENT=1

./run_one.sh terminus-2 "openai/GLM-4.7-Flash-GGUF" glm-flash-local || true

set +e
./run_one.sh openhands "openai/GLM-4.7-Flash-GGUF" glm-flash-local
set -e

# ──────────────────────────────────────
# PHASE 4: Collect results
# ──────────────────────────────────────
echo ""
echo ">>> Phase 4: Collecting results..."
python3 collect_results.py

echo ""
echo "============================================"
echo "  All done. Results in results/summary.csv"
echo "  $(date)"
echo "============================================"
