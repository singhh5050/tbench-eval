#!/usr/bin/env bash
# sweep.sh — config-driven Terminal Bench sweep runner
#
# Runs the harbor CLI (terminal-bench@2.0) for one agent across a list of
# models and tasks. Models are served locally by llama-server via the model
# lifecycle engine in lib/model_manager.sh. A run passes when its reward.txt is "1".
#
# Quickstart:
#   ./bin/sweep.sh -a terminus-2 -m config/models/batch1.txt -t config/tasks/easy.txt
#   ./bin/sweep.sh -a openhands  -t config/tasks/easy_merged.txt
#   ./bin/sweep.sh -a terminus-2 -t config/tasks/easy.txt --dry-run
#
# The per-agent networking mode and any agent-specific harbor flags live in
# config/agents/<agent>.conf — add a new agent by copying one of those.

set -uo pipefail   # intentionally no -e: a failed task or model must not abort the sweep

# ─────────────────────────────────────────
# Paths
# ─────────────────────────────────────────
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

# ─────────────────────────────────────────
# Defaults (overridable by flags or env)
# ─────────────────────────────────────────
AGENT="${AGENT:-}"
MODELS_FILE="${MODELS_FILE:-config/models/batch1.txt}"
TASKS_FILE="${TASKS_FILE:-config/tasks/easy.txt}"
DATASET="${DATASET:-terminal-bench@2.0}"
TASK_TIMEOUT="${TASK_TIMEOUT:-600}"
TIMEOUT_MULT="${TIMEOUT_MULT:-2.0}"
N_RUNS="${N_RUNS:-1}"
RUN_TAG="${RUN_TAG:-}"          # optional suffix on each model's results dir
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bin/sweep.sh -a <agent> [options]

Required:
  -a, --agent NAME       Agent profile (must match config/agents/<agent>.conf)

Options:
  -m, --models FILE      Models file (Name|HF_REPO|VARIANT)   [config/models/batch1.txt]
  -t, --tasks FILE       Tasks file (bare "task" or "dataset|task")  [config/tasks/easy.txt]
  -d, --dataset NAME     Default dataset for bare task lines  [terminal-bench@2.0]
      --timeout SECS     Per-task hard timeout wrapper        [600]
      --tm FLOAT         harbor --timeout-multiplier          [2.0]
  -n, --runs N           harbor -n (trials per task)          [1]
      --tag STR          Suffix appended to each results dir name
      --dry-run          Echo commands, skip download/serve/harbor, synthesize reward
  -h, --help             Show this help

Results land in results/<agent>-<model-lowercased>[-tag]/<task>/ so the dashboard
scanner picks them up. A per-sweep summary is written under results/__sweep-summaries/.
EOF
}

# ─────────────────────────────────────────
# Parse flags
# ─────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -a|--agent)   AGENT="$2"; shift 2 ;;
    -m|--models)  MODELS_FILE="$2"; shift 2 ;;
    -t|--tasks)   TASKS_FILE="$2"; shift 2 ;;
    -d|--dataset) DATASET="$2"; shift 2 ;;
    --timeout)    TASK_TIMEOUT="$2"; shift 2 ;;
    --tm)         TIMEOUT_MULT="$2"; shift 2 ;;
    -n|--runs)    N_RUNS="$2"; shift 2 ;;
    --tag)        RUN_TAG="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$AGENT" ]; then
  echo "ERROR: --agent is required" >&2; usage; exit 2
fi
PROFILE="$REPO/config/agents/${AGENT}.conf"
if [ ! -f "$PROFILE" ]; then
  echo "ERROR: no agent profile at $PROFILE" >&2
  echo "Available: $(ls "$REPO/config/agents" 2>/dev/null | sed 's/\.conf$//' | paste -sd' ' -)" >&2
  exit 2
fi
for f in "$MODELS_FILE" "$TASKS_FILE"; do
  [ -f "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }
done

# ─────────────────────────────────────────
# Engine + agent profile
# ─────────────────────────────────────────
source "$HOME/.local/bin/env" 2>/dev/null || true

# Pin the model-tracking state file at repo root (engine now lives in lib/).
export COMPLETED_FILE="$REPO/benchmarks_completed.txt"
source "$REPO/lib/model_manager.sh"

# Profile contract: defines NET_MODE, EXTRA_HARBOR_ARGS=(), apply_agent_env, build_harbor_args
source "$PROFILE"

# ─────────────────────────────────────────
# Resolve endpoint / networking
# ─────────────────────────────────────────
if [ "${NET_MODE:-localhost}" = "hostnet" ]; then
  HOST_IP="${HOST_IP:-$(hostname -I 2>/dev/null | awk '{print $1}')}"
  if [ -z "$HOST_IP" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      HOST_IP="127.0.0.1"   # placeholder so dry-run smoke tests work off the target host
    else
      echo "ERROR: could not determine HOST_IP (hostname -I empty). Set HOST_IP env." >&2
      exit 1
    fi
  fi
  ENDPOINT="$HOST_IP"
else
  ENDPOINT="localhost"
fi

export OPENAI_API_KEY="${OPENAI_API_KEY:-lemonade}"
export OPENAI_API_BASE="http://${ENDPOINT}:8000/v1"
apply_agent_env          # profile hook (e.g. qwen-coder also exports OPENAI_BASE_URL)
build_harbor_args        # profile hook: sets EXTRA_HARBOR_ARGS using $ENDPOINT

# ─────────────────────────────────────────
# Load models and tasks (skip blank + comment lines)
# ─────────────────────────────────────────
# Portable load (works on bash 3.2+): skip blank + comment lines
MODELS=(); while IFS= read -r _line; do MODELS+=("$_line"); done < <(grep -vE '^[[:space:]]*($|#)' "$MODELS_FILE")
TASKS=();  while IFS= read -r _line; do TASKS+=("$_line");  done < <(grep -vE '^[[:space:]]*($|#)' "$TASKS_FILE")

SUMMARY_DIR="$REPO/results/__sweep-summaries"   # double underscore => skipped by dashboard scanner
mkdir -p "$SUMMARY_DIR"
SUMMARY="$SUMMARY_DIR/${AGENT}-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "# Sweep — $(date)"
  echo "# Agent: $AGENT   Endpoint: http://${ENDPOINT}:8000/v1   Net: ${NET_MODE:-localhost}"
  echo "# Models: ${#MODELS[@]}   Tasks: ${#TASKS[@]}   Dataset(default): $DATASET"
  echo "# Extra harbor args: ${EXTRA_HARBOR_ARGS[*]:-(none)}"
  echo ""
  echo "Model|Task|Result|Time"
} > "$SUMMARY"

DISK_PATH="${LLAMA_MODELS_DIR:-$HOME}"
disk_free() { df -h "$DISK_PATH" 2>/dev/null | awk 'NR==2{print $4}'; }

echo "============================================"
echo "  Terminal Bench Sweep"
echo "  Agent:    $AGENT  (net: ${NET_MODE:-localhost}, endpoint: $ENDPOINT)"
echo "  Models:   ${#MODELS[@]}  ($MODELS_FILE)"
echo "  Tasks:    ${#TASKS[@]}  ($TASKS_FILE)"
echo "  Summary:  $SUMMARY"
echo "  Dry run:  $DRY_RUN"
echo "  Disk free: $(disk_free)"
echo "============================================"

# ─────────────────────────────────────────
# Lifecycle wrappers (honor --dry-run)
# ─────────────────────────────────────────
run_download() { [ "$DRY_RUN" = "1" ] && { echo "  [dry-run] download_model $*"; return 0; }; download_model "$@"; }
run_start()    { [ "$DRY_RUN" = "1" ] && { echo "  [dry-run] start_model $*"; return 0; }; start_model "$@"; }
run_stop()     { [ "$DRY_RUN" = "1" ] && { echo "  [dry-run] stop_llama"; return 0; }; stop_llama; }
run_delete()   { [ "$DRY_RUN" = "1" ] && { echo "  [dry-run] delete_model $*"; return 0; }; delete_model "$@"; }

PREVIOUS_MODEL=""

for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME HF_REPO VARIANT <<< "$MODEL_CONFIG"

  echo ""
  echo "=========================================="
  echo "  Model: $MODEL_NAME   ($(date))"
  echo "=========================================="

  # Dashboard-compatible per-model results dir: results/<agent>-<model>[-tag]/
  MODEL_LC=$(printf '%s' "$MODEL_NAME" | tr '[:upper:]' '[:lower:]')
  RUN_DIR="$REPO/results/${AGENT}-${MODEL_LC}${RUN_TAG:+-$RUN_TAG}"
  mkdir -p "$RUN_DIR"

  # Clean up the previous model first (free disk / port before the next download)
  if [ -n "$PREVIOUS_MODEL" ]; then
    echo ">>> Cleaning up previous model: $PREVIOUS_MODEL"
    run_stop
    run_delete "$PREVIOUS_MODEL" || true
    echo "  Disk free: $(disk_free)"
  fi

  echo ">>> Downloading $MODEL_NAME..."
  if ! run_download "$MODEL_NAME" "$HF_REPO" "$VARIANT"; then
    echo "  DOWNLOAD FAILED"
    for T in "${TASKS[@]}"; do echo "${MODEL_NAME}|${T##*|}|DOWNLOAD_FAILED|0s" >> "$SUMMARY"; done
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  echo ">>> Starting server..."
  if ! run_start "$MODEL_NAME"; then
    echo "  SERVER FAILED"
    for T in "${TASKS[@]}"; do echo "${MODEL_NAME}|${T##*|}|SERVER_FAILED|0s" >> "$SUMMARY"; done
    PREVIOUS_MODEL="$MODEL_NAME"
    continue
  fi

  PASS=0; FAIL=0; ERROR=0

  for TASK_ENTRY in "${TASKS[@]}"; do
    # "dataset|task" overrides the default dataset; otherwise bare "task"
    if [[ "$TASK_ENTRY" == *"|"* ]]; then
      TASK_DATASET="${TASK_ENTRY%%|*}"
      TASK="${TASK_ENTRY#*|}"
    else
      TASK_DATASET="$DATASET"
      TASK="$TASK_ENTRY"
    fi

    echo ""
    echo "  >>> Task: $TASK  (dataset: $TASK_DATASET)"
    JOB_DIR="${RUN_DIR}/${TASK}"
    mkdir -p "$JOB_DIR"

    START_TIME=$(date +%s)
    STATUS="UNKNOWN"

    if [ "$DRY_RUN" = "1" ]; then
      echo "  [dry-run] timeout $TASK_TIMEOUT harbor run -d $TASK_DATASET -a $AGENT -m openai/${MODEL_NAME} ${EXTRA_HARBOR_ARGS[*]:-} -n $N_RUNS --timeout-multiplier $TIMEOUT_MULT --jobs-dir $JOB_DIR -t $TASK"
      echo "1" > "$JOB_DIR/reward.txt"   # synthesize a pass so the parse + summary path executes
    else
      timeout "$TASK_TIMEOUT" harbor run \
        -d "$TASK_DATASET" \
        -a "$AGENT" \
        -m "openai/${MODEL_NAME}" \
        ${EXTRA_HARBOR_ARGS[@]+"${EXTRA_HARBOR_ARGS[@]}"} \
        -n "$N_RUNS" \
        --timeout-multiplier "$TIMEOUT_MULT" \
        --jobs-dir "$JOB_DIR" \
        -t "$TASK" 2>&1 | tee -a "${RUN_DIR}/${TASK}.log" || true
    fi

    # Grade: reward.txt == "1" => PASS
    REWARD_FILE=$(find "$JOB_DIR" -name reward.txt 2>/dev/null | head -1)
    if [ -n "$REWARD_FILE" ] && [ -f "$REWARD_FILE" ]; then
      if [ "$(cat "$REWARD_FILE")" = "1" ]; then STATUS="PASS"; ((PASS++)); else STATUS="FAIL"; ((FAIL++)); fi
    else
      STATUS="NO_REWARD"; ((ERROR++))
    fi

    DURATION=$(( $(date +%s) - START_TIME ))
    echo "      Result: $STATUS (${DURATION}s)"
    echo "${MODEL_NAME}|${TASK}|${STATUS}|${DURATION}s" >> "$SUMMARY"
  done

  echo ""
  echo "  ${MODEL_NAME}: ${PASS}/${#TASKS[@]} pass, ${FAIL} fail, ${ERROR} error"
  PREVIOUS_MODEL="$MODEL_NAME"
done

# Final cleanup
if [ -n "$PREVIOUS_MODEL" ]; then
  echo ""
  echo ">>> Final cleanup: $PREVIOUS_MODEL"
  run_stop
  run_delete "$PREVIOUS_MODEL" || true
fi

echo ""
echo "============================================"
echo "  Sweep complete! $(date)"
echo "============================================"
echo "Results by model:"
for MODEL_CONFIG in "${MODELS[@]}"; do
  IFS='|' read -r MODEL_NAME _ _ <<< "$MODEL_CONFIG"
  P=$(grep -c "^${MODEL_NAME}|.*|PASS|" "$SUMMARY")
  echo "  ${MODEL_NAME}: ${P}/${#TASKS[@]} passed"
done
echo ""
echo "Summary written to: $SUMMARY"
