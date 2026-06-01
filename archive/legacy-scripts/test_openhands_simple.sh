#!/usr/bin/env bash
# Simple test of OpenHands with host networking (no YAML config)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Load environment
set -a
source .env
set +a

echo "============================================"
echo "  Testing OpenHands with Host Networking"
echo "  Started: $(date)"
echo "============================================"
echo ""

# Verify Lemonade is running
echo "1. Checking Lemonade..."
if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "❌ ERROR: Lemonade not running on :8000"
  exit 1
fi
echo "✅ Lemonade is running"
echo ""

# Test with single task, passing environment kwargs via CLI
echo "2. Running test with fix-git task..."
echo "   Using Docker host networking mode"
echo ""

TEST_DIR="${SCRIPT_DIR}/results/openhands-hostnet-test"

# Use --ok (orchestrator-kwarg) to pass environment settings
# Note: We need to check if Harbor supports passing environment.kwargs this way
harbor run \
  -d terminal-bench@2.0 \
  -a openhands \
  -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  -t fix-git \
  -e docker \
  --jobs-dir "$TEST_DIR" \
  2>&1 | tee "${TEST_DIR}_run.log"

EXIT_CODE=$?

echo ""
echo "============================================"
if [ $EXIT_CODE -eq 0 ]; then
  echo "✅ Test completed"
  
  # Check for connection errors
  if find "$TEST_DIR" -name "openhands.txt" -exec grep -l "Connection refused\|Connection error" {} \; 2>/dev/null | grep -q .; then
    echo "⚠️  Still seeing connection errors in logs"
    echo "    Check: $TEST_DIR/*/agent/openhands.txt"
  else
    echo "✅ No connection errors found!"
  fi
else
  echo "❌ Test failed with exit code $EXIT_CODE"
fi
echo "  Logs: ${TEST_DIR}_run.log"
echo "============================================"
