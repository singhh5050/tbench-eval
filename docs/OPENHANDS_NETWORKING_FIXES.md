# OpenHands Networking Issues & Solutions

## The Problem

OpenHands runs its LLM calls from **inside Docker containers**, not from the host. This breaks:

1. **Local models (Lemonade on localhost:8000)**
   - Error: `Connection refused`
   - Cause: `localhost` inside the container ≠ host machine's localhost

2. **Cloud APIs (Fireworks, Together)**  
   - Error: `SSL certificate verification failed`
   - Cause: Host's corporate proxy CA certs and IPv4 patches are not in the container

**Note**: terminus-2 works fine because it makes LLM calls from the host where all networking fixes are applied.

---

## Solutions

### Solution 1: Docker Host Networking (Simplest ⭐)

**Pros:**
- Simplest - just one config change
- Container shares host's network stack completely
- All host services (localhost) are accessible
- Host's SSL certificates and network config apply automatically

**Cons:**
- Less network isolation
- May have port conflicts

**How to implement:**

1. Use the provided config file:
```bash
cd /scratch/harshsin/tbench-eval
source .env  # Use existing .env with localhost:8000
harbor run --config openhands_hostnet.yaml
```

2. Or pass as agent kwargs:
```bash
harbor run -d terminal-bench@2.0 -a openhands \
  -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  --ak "runtime_kwargs.network_mode=host" \
  -t cobol-modernization ...
```

---

### Solution 2: Use `host.docker.internal` + Mount SSL Certs

**Pros:**
- Maintains container isolation
- Explicit about what's shared

**Cons:**
- Requires multiple changes
- Need to mount SSL certificates into container
- More complex configuration

**How to implement:**

1. Use `.env.openhands` (already created):
```bash
# Local Lemonade - Use host.docker.internal to reach host from Docker container
OPENAI_API_BASE=http://host.docker.internal:8000/api/v1
```

2. Mount SSL certificates and configure Docker:
```bash
cd /scratch/harshsin/tbench-eval
source .env.openhands

harbor run -d terminal-bench@2.0 -a openhands \
  -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  --ak "runtime_kwargs.add_host=host.docker.internal:host-gateway" \
  --ak "runtime_kwargs.volumes=/etc/ssl/certs:/etc/ssl/certs:ro" \
  -t cobol-modernization ...
```

---

### Solution 3: Skip OpenHands, Focus on terminus-2

**Pros:**
- No infrastructure changes needed
- terminus-2 results are already working perfectly
- Saves debugging time

**Cons:**
- Missing OpenHands comparison data

**Rationale:**
- Current OpenHands runs show 0% across all tasks due to infrastructure issues
- Data is meaningless for model capability comparison
- terminus-2 provides valid results for the same models

---

## Recommended Approach

### For Local Models (Lemonade):
**Use Solution 1 (Host Networking)** - It's the simplest and most reliable.

```bash
cd /scratch/harshsin/tbench-eval
source .env  # Keep existing localhost:8000

# Run with host networking
harbor run --config openhands_hostnet.yaml
```

### For Cloud APIs:
**Solution 1 also works** - Host networking inherits all SSL certificates and network config automatically.

### For Quick Results:
**Use Solution 3** - Focus on terminus-2 which already works, and document that OpenHands had infrastructure limitations.

---

## Testing the Fix

1. **Verify Lemonade is running:**
```bash
curl -sf http://localhost:8000/api/v1/models
```

2. **Test with single task:**
```bash
cd /scratch/harshsin/tbench-eval
source .env

# Quick test with one task
harbor run --config openhands_hostnet.yaml \
  -d terminal-bench@2.0 \
  -a openhands \
  -m "openai/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
  -t fix-git \
  --jobs-dir ./results/openhands-test-hostnet
```

3. **Check logs:**
```bash
tail -f ./results/openhands-test-hostnet/*/agent/openhands.txt
```

Look for successful LLM API calls instead of connection errors.

---

## Alternative: Update Existing Scripts

If you want to keep using `run_local.sh`, modify it:

```bash
# In run_local.sh, change the run_combo function to:
harbor run \
  -d terminal-bench@2.0 \
  -a "$AGENT" \
  -m "$MODEL" \
  -n "${N_CONCURRENT:-2}" \
  --jobs-dir "$JOBS_DIR" \
  --ak "runtime_kwargs.network_mode=host" \  # ADD THIS LINE
  "${TASK_FLAGS[@]}" \
  2>&1 | tee "${JOBS_DIR}/run.log"
```

---

## Summary

| Solution | Complexity | Reliability | Recommended |
|----------|------------|-------------|-------------|
| 1. Host networking | Low | High | ✅ Yes |
| 2. host.docker.internal + SSL | High | Medium | ⚠️ If isolation needed |
| 3. Skip OpenHands | None | N/A | ✅ Yes (for quick results) |
