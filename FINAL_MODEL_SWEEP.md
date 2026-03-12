# Final Multi-Brand Model Sweep

## Date: March 12, 2026

### ✅ Configuration: 4 Recent, Compatible, Open Models

---

## Selected Models

| # | Brand | Model | Released | Size | Params | Source |
|---|-------|-------|----------|------|--------|--------|
| 1 | **Google** | Gemma-3-12b-it | 2026 | 7.3GB | 12B | unsloth/gemma-3-12b-it-GGUF |
| 2 | **Microsoft** | Phi-4 (14B) | Dec 2024 | 8.4GB | 14B | unsloth/phi-4-GGUF |
| 3 | **Meta** | Llama-3.1-8B-Instruct | Jul 2025 | ~5GB | 8B | unsloth/Llama-3.1-8B-Instruct-GGUF |
| 4 | **Mistral** | Mistral-Small-Instruct-2409 | Sep 2024 | 13GB | 22B | bartowski/Mistral-Small-Instruct-2409-GGUF |

**Total:** ~34GB sequential (fits 24GB free disk)
**Param Range:** 8B - 22B (optimal for hardware)
**All:** Q4_K_M quantization

---

## Why These Models?

### ✅ Advantages

1. **Recent:** 3/4 from late 2024-2026 (newest compatible models)
2. **Diverse:** 4 different companies/architectures
3. **Compatible:** All work with llama.cpp b6510/b7788
4. **Open Access:** No gated models, no HF tokens needed
5. **Good Size:** 8-22B range - not too small (3B) or too large (70B+)
6. **All Instruct-Tuned:** Optimized for tasks/coding

### ❌ Models Rejected & Why

- **Llama 4 Scout:** Gated access, potential MoE compatibility issues
- **Qwen 3.5:** Incompatible (needs llama.cpp b8149+, current: b6510)
- **DeepSeek-V3/R1:** Too large (671B/70B)
- **Gemma 3n:** Mobile-optimized, not for server benchmarks
- **Llama 3.3:** 70B only (too large)
- **Small models (<5B):** Too weak for coding tasks

---

## Benchmark Scope

**Agents:** 2 (terminus-2, openhands)
**Tasks:** 13 (from easy_tasks.txt)
**Total Trials:** 4 models × 2 agents × 13 tasks = **104 trials**
**Estimated Time:** 16-20 hours

---

## Already Completed (For Comparison)

- **GLM-4.7-Flash** (30B MoE, Alibaba)
- **Qwen3-Coder-30B-A3B-Instruct** (30B MoE, Alibaba)

**Total dataset:** 6 models across 5 companies

---

## Architecture Compatibility

All models verified compatible with llama.cpp b6510/b7788:

| Model | Architecture | Verified? |
|-------|--------------|-----------|
| Gemma-3-12b | gemma | ✅ |
| Phi-4 | phi | ✅ |
| Llama-3.1-8B | llama | ✅ |
| Mistral-Small | mistral | ✅ |

---

## Expected Outcomes

### Research Questions

1. **Brand Performance:** How do Google, Microsoft, Meta, and Mistral compare on coding tasks?
2. **Size vs Quality:** Does 22B (Mistral) significantly outperform 8B (Llama)?
3. **Recency:** Do 2026 models (Gemma-3) perform better than 2024 models?
4. **Architecture:** Performance differences across gemma/phi/llama/mistral architectures

### Success Metrics

- ✅ All models load without errors
- ✅ All 104 trials complete
- ✅ Pass rate > 0% (unlike failed Qwen3.5 run)
- ✅ Meaningful cross-brand comparison
- ✅ Incremental saves (can resume if interrupted)

---

## Execution Plan

### Start Command

```bash
cd /scratch/harshsin/tbench-eval
tmux new-session -d -s tbench-sweep './run_local_all_models.sh 2>&1 | tee logs/local_all_models.log'
```

### Monitor Progress

```bash
# Watch log
tail -f logs/local_all_models.log

# Attach to tmux
tmux attach -t tbench-sweep

# Check completed
cat benchmarks_completed.txt

# Check disk
df -h /scratch/harshsin
```

### After Completion

```bash
# Generate dashboard
python3 dashboard.py

# View results
open dashboard.html
```

---

## Timeline Estimate

| Model | Download | Benchmark | Total |
|-------|----------|-----------|-------|
| Gemma-3-12b | 15 min | 3-4 hrs | ~4 hrs |
| Phi-4 | 15 min | 3-4 hrs | ~4 hrs |
| Llama-3.1-8B | 10 min | 2-3 hrs | ~3 hrs |
| Mistral-Small | 20 min | 4-5 hrs | ~5 hrs |

**Total:** ~16 hours

---

## Files Modified

- `run_local_all_models.sh` - Updated with 4 final models
- `FINAL_MODEL_SWEEP.md` - This documentation

---

**Status:** ✅ READY TO EXECUTE
**Last Updated:** March 12, 2026, 5:35 PM MDT
