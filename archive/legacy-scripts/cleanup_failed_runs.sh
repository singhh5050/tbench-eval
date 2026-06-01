#!/usr/bin/env bash
# Cleanup failed Qwen3.5 benchmark runs
# Removes incompatible models and failed result directories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "  Cleaning up failed Qwen3.5 runs"
echo "  $(date)"
echo "============================================"
echo ""

# Remove failed result directories
echo ">>> Removing failed result directories..."
REMOVED_COUNT=0

for DIR in results/terminus-2-qwen35-* results/openhands-qwen35-*; do
  if [ -d "$DIR" ]; then
    echo "  - Removing: $DIR"
    rm -rf "$DIR"
    REMOVED_COUNT=$((REMOVED_COUNT + 1))
  fi
done

echo "  Removed $REMOVED_COUNT result directories"
echo ""

# Delete incompatible Qwen3.5 models from lemonade
echo ">>> Deleting incompatible Qwen3.5 models..."
DELETED_COUNT=0

for MODEL in user.Qwen35-9B user.Qwen35-27B user.Qwen35-35B-A3B; do
  if lemonade-server delete "$MODEL" 2>/dev/null; then
    echo "  - Deleted: $MODEL"
    DELETED_COUNT=$((DELETED_COUNT + 1))
  else
    echo "  - Not found (already deleted): $MODEL"
  fi
done

echo "  Deleted $DELETED_COUNT models"
echo ""

# Show current disk space
echo ">>> Current disk space:"
df -h /scratch/harshsin | grep -v "^Filesystem"
echo ""

# Show remaining models
echo ">>> Currently installed models:"
lemonade-server list 2>/dev/null | grep -E "^(user\.|GLM|Qwen)" || echo "  (none found)"
echo ""

echo "============================================"
echo "  Cleanup complete!"
echo "  $(date)"
echo "============================================"
