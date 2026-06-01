#!/usr/bin/env bash
# Quick test - just run fix-git task with the fixed YAML config

cd /scratch/harshsin/tbench-eval
source $HOME/.local/bin/env

# Export all variables from .env so child processes (harbor) can see them
set -a
source .env
set +a

echo "Testing OpenHands with host networking fix..."
echo ""

# Check Lemonade
if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "❌ Lemonade not running on :8000"
  exit 1
fi
echo "✅ Lemonade running"
echo ""

# Run single task - pass API credentials via command line
harbor run --config openhands_hostnet.yaml \
  -d terminal-bench@2.0 \
  -t fix-git \
  --jobs-dir ./results/test-quick \
  --ak "api_key=${OPENAI_API_KEY}" \
  --ak "base_url=${OPENAI_API_BASE}"

echo ""
echo "Check logs at: ./results/test-quick/*/agent/openhands.txt"
