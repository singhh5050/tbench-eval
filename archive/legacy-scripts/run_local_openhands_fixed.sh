#!/usr/bin/env bash
# Fixed local eval for OpenHands with proper Docker networking
# Addresses both localhost access (Lemonade) and SSL certificate issues

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source $HOME/.local/bin/env

# Load OpenHands-specific environment (with host.docker.internal)
set -a
source .env.openhands
set +a

export N_CONCURRENT=1  # Local models: keep low to avoid OOM

LOCAL_LOG="$SCRIPT_DIR/local_openhands_fixed.log"

echo "============================================"
echo "  OpenHands Local Eval (FIXED)"
echo "  Started: $(date)"
echo "  Log: $LOCAL_LOG"
echo "============================================"
echo ""

# Verify Lemonade is running
if ! curl -sf http://localhost:8000/api/v1/models > /dev/null 2>&1; then
  echo "ERROR: Lemonade is not running on :8000"
  echo "Start it with: lemonade-server serve --host 0.0.0.0 --port 8000 --ctx-size 32768 --llamacpp-args '--cache-ram 0'"
  exit 1
fi
echo "✓ Lemonade is up on :8000"
echo ""

# Verify host.docker.internal will work
echo "Testing Docker host networking..."
docker run --rm --add-host host.docker.internal:host-gateway alpine:latest \
  sh -c 'getent hosts host.docker.internal' > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✓ host.docker.internal networking configured"
else
  echo "⚠ Warning: host.docker.internal test failed"
fi
echo ""

PASS=0
FAIL=0

run_combo() {
  local NUM="$1" AGENT="$2" MODEL="$3" TAG="$4"
  echo ">>> [$NUM] $AGENT + $TAG — started $(date '+%H:%M:%S')"
  
  # Pass agent kwargs to configure Docker runtime with host networking access
  if harbor run \
    -d terminal-bench@2.0 \
    -a "$AGENT" \
    -m "$MODEL" \
    -n "${N_CONCURRENT:-1}" \
    --jobs-dir "${SCRIPT_DIR}/results/${AGENT}-${TAG}-fixed" \
    --ak "runtime=docker" \
    --ak "extra_docker_run_args=--add-host host.docker.internal:host-gateway -v /etc/ssl/certs:/etc/ssl/certs:ro" \
    -t cobol-modernization \
    -t fix-git \
    -t prove-plus-comm \
    -t build-pmars \
    -t build-pov-ray \
    -t code-from-image \
    -t git-leak-recovery \
    -t headless-terminal \
    -t kv-store-grpc \
    -t polyglot-c-py \
    -t pypi-server \
    -t schemelike-metacircular-eval \
    -t winning-avg-corewars \
    2>&1 | tee -a "$LOCAL_LOG"; then
    echo ">>> [$NUM] $AGENT + $TAG — COMPLETED $(date '+%H:%M:%S')"
    PASS=$((PASS+1))
  else
    echo ">>> [$NUM] $AGENT + $TAG — FAILED $(date '+%H:%M:%S')"
    FAIL=$((FAIL+1))
  fi
  echo ""
}

# ── Qwen3-Coder-30B-A3B via Lemonade ──
run_combo "1/1" openhands "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" qwen-30b-local

echo ""
echo "============================================"
echo "  Fixed OpenHands eval: $PASS passed, $FAIL failed"
echo "  Finished: $(date)"
echo "============================================"
