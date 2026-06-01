#!/usr/bin/env bash
# Pre-flight checks before starting multi-brand sweep

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "  Multi-Brand Sweep - Pre-flight Checks"
echo "  $(date)"
echo "============================================"
echo ""

# Check 1: Disk space
echo "✓ Checking disk space..."
AVAILABLE_GB=$(df -BG /scratch/harshsin 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}')
echo "  Available: ${AVAILABLE_GB}GB"
if [ "$AVAILABLE_GB" -lt 20 ]; then
  echo "  ⚠️  WARNING: Less than 20GB available (need 21GB for largest model)"
else
  echo "  ✓ Sufficient space"
fi
echo ""

# Check 2: Required files
echo "✓ Checking required files..."
for FILE in run_local_all_models.sh model_manager.sh easy_tasks.txt .env; do
  if [ -f "$FILE" ]; then
    echo "  ✓ $FILE"
  else
    echo "  ✗ MISSING: $FILE"
  fi
done
echo ""

# Check 3: lemonade-server
echo "✓ Checking lemonade-server..."
if command -v lemonade-server >/dev/null 2>&1; then
  VERSION=$(lemonade-server --version 2>&1 | head -1 || echo "unknown")
  echo "  ✓ lemonade-server installed: $VERSION"
else
  echo "  ✗ lemonade-server not found"
fi
echo ""

# Check 4: Currently installed models
echo "✓ Currently installed models:"
lemonade-server list 2>/dev/null | grep -E "^(user\.|GLM|Qwen)" || echo "  (none)"
echo ""

# Check 5: Check if lemonade is running
echo "✓ Checking lemonade-server status..."
if curl -sf http://localhost:8000/api/v1/models >/dev/null 2>&1; then
  echo "  ⚠️  lemonade-server is RUNNING"
  CURRENT_MODEL=$(curl -s http://localhost:8000/api/v1/models 2>/dev/null | jq -r '.data[0].id // "unknown"')
  echo "  Current model: $CURRENT_MODEL"
  echo "  (Script will stop it before starting)"
else
  echo "  ✓ lemonade-server is stopped (good)"
fi
echo ""

# Check 6: Harbor
echo "✓ Checking harbor..."
if command -v harbor >/dev/null 2>&1; then
  echo "  ✓ harbor installed"
else
  echo "  ✗ harbor not found"
fi
echo ""

# Check 7: Logs directory
echo "✓ Checking logs directory..."
if [ -d "logs" ]; then
  echo "  ✓ logs/ directory exists"
else
  echo "  Creating logs/ directory..."
  mkdir -p logs
  echo "  ✓ Created"
fi
echo ""

# Check 8: Model configuration summary
echo "============================================"
echo "  Models to Benchmark (7 total)"
echo "============================================"
echo ""
echo "Alibaba Qwen (3 models):"
echo "  1. Qwen3-30B-A3B (20GB)"
echo "  2. Qwen2.5-Coder-32B-Instruct (21GB)"
echo "  3. Qwen3-8B (8GB)"
echo ""
echo "Meta Llama (1 model):"
echo "  4. Llama-3.2-3B-Instruct (5GB)"
echo ""
echo "Microsoft Phi (1 model):"
echo "  5. Phi-4-mini-instruct (5GB)"
echo ""
echo "Mistral AI (1 model):"
echo "  6. Devstral-Small-2507 (5GB)"
echo ""
echo "Google Gemma (1 model):"
echo "  7. Gemma-3-4b-it (5GB)"
echo ""

# Check 9: Estimate
echo "============================================"
echo "  Benchmark Estimates"
echo "============================================"
echo ""
echo "Total trials: 7 models × 2 agents × 13 tasks = 182"
echo "Estimated time: 29-35 hours"
echo "Max disk usage: 21GB (one model at a time)"
echo ""

# Check 10: Previous failed runs
echo "✓ Checking for failed Qwen3.5 runs..."
FAILED_DIRS=$(find results -maxdepth 1 -name "*qwen35*" -type d 2>/dev/null | wc -l)
if [ "$FAILED_DIRS" -gt 0 ]; then
  echo "  ⚠️  Found $FAILED_DIRS failed Qwen3.5 result directories"
  echo "  Run: ./cleanup_failed_runs.sh to clean up"
else
  echo "  ✓ No failed runs found"
fi
echo ""

echo "============================================"
echo "  Pre-flight Check Complete!"
echo "============================================"
echo ""
echo "Ready to start? Run:"
echo "  nohup ./run_local_all_models.sh > logs/local_all_models.log 2>&1 &"
echo ""
echo "Monitor with:"
echo "  tail -f logs/local_all_models.log"
echo ""
