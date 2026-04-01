# Issues Audit - TerminalBench 2.0 Local Benchmarks

Last updated: 2026-03-29

## Error Taxonomy

| Error Type | Count | Affected Models | Root Cause | Fix Applied | Status |
|------------|-------|-----------------|------------|-------------|--------|
| **BadRequestError - Couldn't connect** | 79 | Gemma-3-12b | Intermittent connection drops to localhost:8000 | Server warmup, restart logic | UNRESOLVED |
| **Model mapping warning** | 948 | All HF models | LiteLLM doesn't recognize custom GGUF models | None | UNRESOLVED (non-fatal) |
| **Context overflow (Phi-4)** | ~10 | Phi-4 | Model trained with 16K max, we set 32K | `get_model_ctx_size()` returns 16K for Phi-4 | RESOLVED |
| **Agent timeouts** | Several | All | Default 900s too short | `TIMEOUT_MULTIPLIER=2.0` | RESOLVED |
| **OpenHands 0% pass rate** | 48 trials | All models | Docker networking or config issue | `openhands_hostnet.yaml` | UNRESOLVED |
| **Agent setup failure** | 1 | Mistral-Small | Exit code 100 on polyglot-c-py task | None | UNRESOLVED (isolated) |

## Fixes Applied

### 1. Timeout multiplier (2x)
- **Location**: `run_local_all_models.sh:48`
- **Change**: `TIMEOUT_MULTIPLIER=2.0`
- **Reason**: Default 900s too short for complex tasks on local hardware

### 2. Server connectivity test
- **Location**: `run_local_all_models.sh:84-118`
- **Change**: Added `test_server_connectivity()` function
- **Reason**: Detect server issues before starting benchmark

### 3. Server warmup requests
- **Location**: `model_manager.sh:199-204`
- **Change**: Send 3 warmup requests after server starts
- **Reason**: Ensure server is fully ready before benchmark

### 4. Phi-4 context size detection
- **Location**: `model_manager.sh:160-170`
- **Change**: `get_model_ctx_size()` returns 16K for Phi-4 models
- **Reason**: Phi-4 trained with 16K max context

### 5. LiteLLM debug logging
- **Location**: `run_local_all_models.sh:45`
- **Change**: `LITELLM_LOG="DEBUG"`
- **Reason**: Better visibility into connection issues

### 6. Network state logging
- **Location**: `run_local_all_models.sh:149-150`
- **Change**: Log `ss -tlnp` output before benchmarks
- **Reason**: Debug network issues

### 7. Server restart on failure
- **Location**: `run_local_all_models.sh:180-184`
- **Change**: Auto-restart if health check fails
- **Reason**: Recover from server crashes mid-benchmark

### 8. Switch to llama-server b8580
- **Location**: `model_manager.sh`
- **Change**: Replaced lemonade-server (llama.cpp b6510) with direct llama-server b8580
- **Reason**:
  - Support for Qwen3.5 models (need b8149+)
  - Faster updates, more control
  - Same OpenAI-compatible API at `/v1` instead of `/api/v1`

## Unresolved Issues

### 1. Connection drops (79 occurrences)
**Symptoms:**
- Server is up and responding 200 OK
- Client gets CURL errors intermittently
- BadRequestError: "Couldn't connect to server"

**Potential causes:**
- Race condition between requests
- Resource exhaustion under load
- Network stack issues with AMD GPU

**Investigation needed:**
- Monitor with `tcpdump` during benchmark
- Check `dmesg` for GPU/driver errors
- Try reducing concurrent slots

### 2. OpenHands silent failures (0/48 pass rate)
**Symptoms:**
- All trials return 0 (fail)
- No exception_info in results
- Docker container appears to start

**Potential causes:**
- Docker networking to localhost not working
- Container can't reach llama-server on host
- openhands_hostnet.yaml config incomplete

**Investigation needed:**
- Run single OpenHands task with verbose logging
- Check Docker network mode
- Verify API reachable from container

### 3. Model not mapped warnings (948 occurrences)
**Symptoms:**
- LiteLLM logs: "model not mapped, using 1M fallback context"

**Impact:**
- Non-fatal, just noisy
- May cause issues if context > 1M requested

**Resolution:**
- Could add custom model mapping to LiteLLM config
- Low priority since it doesn't affect results

## Architecture Change (2026-03-29)

```
BEFORE:                           AFTER:
Harbor → LiteLLM                  Harbor → LiteLLM
  → localhost:8000/api/v1           → localhost:8000/v1
  → lemonade-server                 → llama-server (direct)
  → llama.cpp b6510                 → llama.cpp b8580
```

### Benefits
- Support for Qwen3.5 models (requires b8149+)
- Direct control over llama-server flags
- Vulkan GPU acceleration
- Faster model loading

### Files Modified
- `model_manager.sh` - Complete rewrite for llama-server
- `.env` - Changed `/api/v1` to `/v1`
- `run_local_all_models.sh` - Updated function names and API paths
