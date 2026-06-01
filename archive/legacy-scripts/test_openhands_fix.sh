#!/usr/bin/env bash
# Quick test of OpenHands networking fix with host networking
# Tests with a single simple task (fix-git) to verify connectivity

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Load environment
set -a
source .env
set +a

echo "============================================"
echo "  Testing OpenHands Networking Fix"
echo "  Started: $(date)"
echo "============================================"
echo ""

# Verify Lemonade is running
echo "1. Checking Lemonade availability..."
if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "❌ ERROR: Lemonade is not running on :8000"
  echo "   Start it with:"
  echo "   lemonade-server serve --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp-args '--cache-ram 0'"
  exit 1
fi
echo "✅ Lemonade is running on :8000"
echo ""

# Show Lemonade models
echo "2. Available models:"
curl -sf http://localhost:8000/api/v1/models 2>/dev/null | head -5
echo ""

# Test with single task using host networking
echo "3. Running single task test (fix-git) with host networking..."
echo "   This will take ~3-5 minutes"
echo ""

TEST_DIR="${SCRIPT_DIR}/results/openhands-test-hostnet-$(date +%s)"

if harbor run \
  --config openhands_hostnet.yaml \
  --jobs-dir "$TEST_DIR" \
  -d terminal-bench@2.0 \
  -a openhands \
  -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  -t fix-git \
  2>&1 | tee "${TEST_DIR}_run.log"; then
  
  echo ""
  echo "✅ Harbor command completed!"
  echo ""
  
  # Check for connection errors in logs
  if grep -q "Connection refused\|Connection error" "${TEST_DIR}"/*/agent/openhands.txt 2>/dev/null; then
    echo "⚠️  WARNING: Still seeing connection errors in logs"
    echo "    Check: ${TEST_DIR}/*/agent/openhands.txt"
  else
    echo "✅ No connection errors found in logs!"
  fi
  
  # Show result
  if [ -f "${TEST_DIR}"/*/result.json ]; then
    echo ""
    echo "Task result:"
    cat "${TEST_DIR}"/*/result.json | python3 -m json.tool 2>/dev/null | grep -A 1 "reward\|error"
  fi
  
else
  echo ""
  echo "❌ Test failed"
  echo "   Check logs: ${TEST_DIR}_run.log"
  exit 1
fi

echo ""
echo "============================================"
echo "  Test Results Directory: $TEST_DIR"
echo "  Full Logs: ${TEST_DIR}_run.log"
echo "  Agent Logs: ${TEST_DIR}/*/agent/openhands.txt"
echo "============================================"
