# Multi-Brand Model Sweep

## Overview

This benchmark run sweeps across **7 models from 5 different companies**, testing different architectures and specializations.

**Execution Date:** March 12, 2026
**Total Models:** 7
**Estimated Runtime:** ~36-48 hours
**Max Disk Usage:** 21GB (one model at a time)

---

## Model Selection

### Alibaba Qwen (3 models)
| Model | Size | Type | Purpose |
|-------|------|------|---------|
| **Qwen3-30B-A3B** | 19.6GB | MoE | Best general-purpose Qwen3 |
| **Qwen2.5-Coder-32B-Instruct** | 20.6GB | Dense | Specialized coding model |
| **Qwen3-8B** | 7.2GB | Dense | Fast baseline |

### Meta Llama (1 model)
| Model | Size | Type | Purpose |
|-------|------|------|---------|
| **Llama-3.2-3B-Instruct** | 4.6GB | Dense | Small instruction-tuned |

### Microsoft Phi (1 model)
| Model | Size | Type | Purpose |
|-------|------|------|---------|
| **Phi-4-mini-instruct** | 5.0GB | Dense | Latest Phi series |

### Mistral AI (1 model)
| Model | Size | Type | Purpose |
|-------|------|------|---------|
| **Devstral-Small-2507** | 4.4GB | Dense | Coding-focused small model |

### Google Gemma (1 model)
| Model | Size | Type | Purpose |
|-------|------|------|---------|
| **Gemma-3-4b-it** | 5.0GB | Dense | Latest Gemma instruction-tuned |

---

## Already Benchmarked (Baseline Comparisons)

- **GLM-4.7-Flash** (Alibaba GLM) - Already completed
- **Qwen3-Coder-30B-A3B-Instruct** (Alibaba Qwen) - Already completed

---

## Architecture Distribution

| Architecture | Count | Models |
|--------------|-------|--------|
| **qwen3** | 1 | Qwen3-30B-A3B, Qwen3-8B |
| **qwen2** | 1 | Qwen2.5-Coder-32B |
| **llama** | 1 | Llama-3.2-3B |
| **phi** | 1 | Phi-4-mini |
| **mistral** | 1 | Devstral-Small |
| **gemma** | 1 | Gemma-3-4b |

All architectures are **compatible** with llama.cpp build b6510/b7788.

---

## Size Distribution

| Size Range | Count | Models |
|------------|-------|--------|
| **Ultra-small** (<5GB) | 1 | Devstral-Small (4.4GB) |
| **Small** (5-8GB) | 4 | Llama-3.2-3B, Phi-4-mini, Gemma-3-4b, Qwen3-8B |
| **Very Large** (19-21GB) | 2 | Qwen3-30B-A3B, Qwen2.5-Coder-32B |

---

## Benchmark Configuration

**Agents:** 2 (terminus-2, openhands)
**Tasks:** 13 (from `easy_tasks.txt`)
**Total Trials:** 7 models × 2 agents × 13 tasks = **182 trials**

### Execution Strategy

1. Download model → Start lemonade-server
2. Run terminus-2 benchmark (13 tasks)
3. Run openhands benchmark (13 tasks)
4. Delete model to free space
5. Repeat for next model

### Disk Management

- Models downloaded one at a time
- Previous model deleted before downloading next
- Never exceeds 21GB disk usage
- 24GB free space available

---

## Expected Outcomes

### Research Questions

1. **Brand Performance:** How do different companies' models compare?
2. **Size vs Quality:** Do larger models always perform better?
3. **Specialization:** Does coding specialization (Qwen2.5-Coder, Devstral) improve results?
4. **Architecture:** How do different architectures (MoE vs dense) perform?

### Success Criteria

- ✅ All models load without architecture errors
- ✅ All 182 trials complete
- ✅ Pass rate > 0% (unlike failed Qwen3.5 run)
- ✅ Meaningful comparison across brands

---

## Files Modified

- `run_local_all_models.sh` - Updated MODELS array with multi-brand selection
- `cleanup_failed_runs.sh` - NEW: Cleanup script for failed Qwen3.5 runs
- `MULTI_BRAND_SWEEP.md` - NEW: This documentation

---

## Execution Commands

### Step 1: Cleanup Failed Runs (Optional)
```bash
cd /scratch/harshsin/tbench-eval
./cleanup_failed_runs.sh
```

### Step 2: Start Benchmark
```bash
cd /scratch/harshsin/tbench-eval
nohup ./run_local_all_models.sh > logs/local_all_models.log 2>&1 &
```

### Step 3: Monitor Progress
```bash
# Watch log output
tail -f logs/local_all_models.log

# Check disk space
df -h /scratch/harshsin

# Check lemonade status
curl -s http://localhost:8000/api/v1/models | jq

# Check completed benchmarks
cat benchmarks_completed.txt
```

### Step 4: Generate Dashboard (After Completion)
```bash
python3 dashboard.py
# Open dashboard.html in browser
```

---

## Timeline Estimates

| Model | Download | terminus-2 | openhands | Total |
|-------|----------|------------|-----------|-------|
| Qwen3-30B-A3B | 30 min | 2-3 hrs | 2-3 hrs | ~6 hrs |
| Qwen2.5-Coder-32B | 30 min | 2-3 hrs | 2-3 hrs | ~6 hrs |
| Qwen3-8B | 15 min | 2-3 hrs | 2-3 hrs | ~5 hrs |
| Llama-3.2-3B | 10 min | 1-2 hrs | 1-2 hrs | ~3 hrs |
| Phi-4-mini | 10 min | 1-2 hrs | 1-2 hrs | ~3 hrs |
| Devstral-Small | 10 min | 1-2 hrs | 1-2 hrs | ~3 hrs |
| Gemma-3-4b | 10 min | 1-2 hrs | 1-2 hrs | ~3 hrs |

**Total Estimated Time:** 29-35 hours

---

## Notes

- All models use Q4_K_M quantization from unsloth
- All models compatible with Vulkan backend (AMD Ryzen AI MAX+ 395)
- No Qwen3.5 models (requires llama.cpp b8149+, current: b6510)
- Script automatically manages disk space (deletes completed models)
