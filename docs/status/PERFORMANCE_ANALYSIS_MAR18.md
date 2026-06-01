# Performance Analysis - Multi-Brand Benchmark
**Date:** March 18, 2026
**Analysis of:** Gemma-3-12b-it, Phi-4, Llama-3.1-8B-Instruct (Mistral incomplete)

---

## Executive Summary

**Bottom Line:** Models are running correctly with acceptable performance, but **overall task success rate is very low** (8.8% for terminus-2, 0% for openhands).

**Key Findings:**
1. ✅ **Inference speed is good** (22.6 TPS average, 4-42 TPS range)
2. ✅ **Models are generating valid responses** (no crashes/errors)
3. ❌ **Low pass rates** indicate either tasks are very hard OR agents aren't effective
4. ❌ **openhands 0% success** suggests configuration/compatibility issue

---

## Inference Performance

### Tokens Per Second (TPS)

**Overall Statistics (1,741 samples):**
- **Average:** 22.6 TPS
- **Min:** 4.0 TPS (long/complex generations)
- **Max:** 42.7 TPS (short/simple generations)
- **Range:** 10x variation (normal for variable-length responses)

**Per-Model Breakdown:**

| Model | Avg Request Time | Approx TPS | Relative Speed |
|-------|------------------|------------|----------------|
| **Llama-3.1-8B** | 16,045 ms | **6.2 TPS** | Fastest ✅ |
| **Gemma-3-12b** | 25,247 ms | **4.0 TPS** | Slowest (3x larger) |
| **Phi-4** | 29,122 ms | **3.4 TPS** | Slowest (14B params) |

**Interpretation:**
- ✅ All models running within acceptable range
- ✅ Smaller models (Llama 8B) ~2x faster than larger (Phi 14B, Gemma 12B)
- ✅ No sign of GPU/CPU bottleneck (consistent performance)
- ✅ Vulkan backend working properly

---

## Task Success Analysis

### Overall Pass Rates

**terminus-2 (Best Agent):**
- Total: 34 trials (across 3 models)
- Passed: 3 trials
- **Pass Rate: 8.8%**

**openhands:**
- Total: 36 trials
- Passed: 0 trials
- **Pass Rate: 0%** ⚠️

### Per-Model Performance

| Model | Brand | Size | terminus-2 Pass | openhands Pass | Best Task |
|-------|-------|------|-----------------|----------------|-----------|
| **Phi-4** | Microsoft | 14B | **2/8 (25%)** | 0/12 (0%) | git-leak-recovery, fix-git |
| **Gemma-3-12b** | Google | 12B | 1/13 (7.7%) | 0/12 (0%) | Unknown |
| **Llama-3.1-8B** | Meta | 8B | 0/8 (0%) | 0/12 (0%) | None |

**Key Observations:**
1. **Phi-4 is the clear winner** (25% vs 7.7% vs 0%)
2. **Smaller model (Llama 8B) failed everything** despite being fastest
3. **Size matters:** 14B > 12B > 8B for task success
4. **Git-related tasks** were the 2 successes (git-leak-recovery, fix-git)

---

## Why Are Pass Rates So Low?

### Hypothesis 1: Tasks Are Very Hard ✅ LIKELY
- These are coding/terminal tasks requiring multi-step reasoning
- 8.8% may be realistic for models in the 8-14B range
- For comparison: Our previous runs with Qwen3-Coder-30B may have done better (need to check)

### Hypothesis 2: Agent Configuration Issue ❌ UNLIKELY (terminus-2)
- terminus-2 got 3 passes, showing it CAN succeed
- No error messages in logs
- Models generating valid JSON/commands

### Hypothesis 3: openhands Broken ✅ VERY LIKELY
- 0/36 pass rate is suspicious
- Even if tasks are hard, some should pass by chance
- Likely configuration mismatch or API compatibility issue

### Hypothesis 4: Context Overflow ⚠️ POSSIBLE
- Some tasks show 31k+ tokens (near 32k limit)
- May cause failures on longer tasks
- But doesn't explain 0% openhands rate

---

## Model Behavior Analysis

### What Models Are Doing

**Token Usage per Trial:**
- Input: 76,146 tokens average (very high! Reading lots of context)
- Output: 7,462 tokens average (reasonable for multi-step tasks)
- Total: ~83k tokens per task (many context resets needed)

**Request Patterns:**
- Average 13 API calls per task
- Each call takes 25-30 seconds (including generation + processing)
- Total time per task: 5-10 minutes

**Observation:**
- ✅ Models are attempting multi-step solutions
- ✅ Generating reasonable amounts of output
- ⚠️ Very high input token counts suggest lots of failed attempts accumulating in context

---

## Why Phi-4 Succeeded Where Others Failed

### Successful Tasks (Phi-4 Only)
1. **git-leak-recovery** - Recovering leaked secrets from git history
2. **fix-git** - Fixing broken git repository

**Common Theme:** Git manipulation tasks

**Why Phi-4 Might Excel Here:**
- **Reasoning focus:** Phi-4 is specifically tuned for reasoning/planning
- **14B params:** Largest model tested (more capacity)
- **Training data:** May have better git/dev tool coverage

**Why Gemma/Llama Failed:**
- Gemma-3 is **multimodal-first** (image + text), may sacrifice pure coding
- Llama-3.1-8B is **too small** for complex multi-step tasks
- Neither are coding-specialized

---

## openhands Investigation Needed

### Evidence of Failure

**Results:**
- 0/12 (Gemma)
- 0/12 (Phi)
- 0/12 (Llama)
- **Total: 0/36 = 0%**

**Why This Is Suspicious:**
1. Even bad models should get ~5-10% by luck/partial credit
2. terminus-2 with SAME models got 8.8%
3. No error messages in logs (silent failures)

### Possible Root Causes

1. **API compatibility issue:** openhands may expect different response format
2. **Timeout too short:** Models generating but agent timing out
3. **Action parsing failure:** openhands can't parse model outputs
4. **Environment issue:** Docker networking problem (we had to use hostnet config)

### Recommended Action
- Check openhands result.json files for exception_info
- Compare successful terminus-2 vs failed openhands trajectories
- May need to re-run openhands with debug logging

---

## Comparison to Baseline (If Available)

**Question:** What were pass rates for previous runs?
- GLM-4.7-Flash (30B MoE)
- Qwen3-Coder-30B (30B MoE, coding-specialized)

**Need to check:**
```bash
find results/terminus-2-glm* -name "reward.txt" -exec grep "^1$" {} \; | wc -l
find results/openhands-qwen-30b* -name "reward.txt" -exec grep "^1$" {} \; | wc -l
```

**Expected:** Larger, coding-specialized models should have higher pass rates (maybe 30-50%?)

---

## Mistral-Small Status

**Partial Results:**
- 6/13 tasks completed on terminus-2
- 0/6 passed
- Process died at 3:55 AM (unknown cause)
- openhands not started

**Impact:**
- Missing largest model (22B params)
- Can't complete 4-brand comparison
- ~2-3 hours needed to finish

---

## Recommendations

### Immediate Actions

1. **Check baseline pass rates** from GLM/Qwen runs
   - If they were also low (8-15%), current results are normal
   - If they were high (30-50%), something is wrong

2. **Debug openhands 0% issue**
   - Read exception_info from failed trials
   - Compare trajectories to terminus-2
   - May need to reconfigure or abandon openhands

3. **Complete Mistral-Small run**
   - Manually restart terminus-2 + openhands for Mistral
   - Get full 4-model comparison
   - See if 22B model performs better

### Analysis Questions

1. **Are these tasks supposed to be this hard?**
   - 8.8% seems low even for difficult tasks
   - Check SWE-bench/HumanEval benchmarks for comparison

2. **Why does model size matter so much?**
   - 8B: 0%, 12B: 7.7%, 14B: 25%
   - Clear correlation with param count
   - Suggests these tasks need substantial capacity

3. **Should we test coding-specialized models?**
   - Current models are general-purpose instruct
   - Qwen-Coder, DeepSeek-Coder, etc. might do better
   - But compatibility issues (need to check llama.cpp support)

---

## Data Quality Assessment

### ✅ Valid Data
- 72 complete trials with full metrics
- Consistent logging/timing
- No infrastructure failures (besides Mistral stop)
- TPS measurements reliable

### ⚠️ Concerns
- openhands 0% may indicate bad data
- Low overall pass rates need baseline comparison
- Missing Mistral limits conclusions
- Only 3 brands fully tested (not 4)

### Next Steps for Validation
1. Compare to previous benchmark baselines
2. Manually inspect successful vs failed task trajectories
3. Verify openhands configuration
4. Consider re-running with coding-specialized models

---

## Final Verdict

**Infrastructure:** ✅ Working great (22.6 TPS avg, stable inference)
**Model Performance:** ⚠️ Low but may be realistic for task difficulty
**Data Quality:** ⚠️ Questionable (openhands 0%, incomplete Mistral)
**Comparison Value:** ⚠️ Limited (only 3 models, need baselines)

**Recommendation:** Complete Mistral, debug openhands, check GLM/Qwen baselines before drawing conclusions.
