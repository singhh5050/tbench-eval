# Multi-Brand Benchmark Status Report
**Date:** March 18, 2026
**Original Start:** March 12, 2026 @ 5:39 PM
**Last Activity:** March 13, 2026 @ 3:55 AM (10 hours runtime)
**Status:** ⚠️ **INCOMPLETE** - 3/4 models completed, 1 stopped mid-run

---

## What Happened

The benchmark ran for ~10 hours (overnight) and **silently died** during the Mistral-Small model's terminus-2 phase. No error in logs, processes just stopped.

**Most Likely Cause:** System reboot, OOM kill, or tmux session termination (tmux socket gone: `/tmp/tmux-50102715/default`)

---

## Results Summary

### ✅ Completed Models (3/4)

| Model | Brand | Time | terminus-2 Pass Rate | openhands Pass Rate | Status |
|-------|-------|------|---------------------|---------------------|--------|
| **Gemma-3-12b-it** | Google | 1h 40min | 1/13 (7.7%) | 0/12 (0%) | ✅ Complete |
| **Phi-4** | Microsoft | 2h 38min | 2/8 (25%) | 0/12 (0%) | ✅ Complete |
| **Llama-3.1-8B-Instruct** | Meta | 3h 32min | 0/8 (0%) | 0/12 (0%) | ✅ Complete |

### ⏸️ Incomplete Model (1/4)

| Model | Brand | Status | terminus-2 | openhands |
|-------|-------|--------|------------|-----------|
| **Mistral-Small-Instruct-2409** | Mistral | ⚠️ Stopped at 3:55 AM | 0/6 partial | Not started |

---

## Performance Analysis

### Overall Pass Rates (Completed Models Only)

**terminus-2:**
- Total trials: 34 (13+8+8+6 partial)
- Passed: 3
- **Pass rate: 8.8%**

**openhands:**
- Total trials: 36 (12+12+12)
- Passed: 0
- **Pass rate: 0%**

### Key Findings

1. **Phi-4 performed best** (2/8 = 25% pass rate on terminus-2)
2. **openhands failed everything** (0% across all models)
3. **Most failures are legitimate** (reward=0, not exceptions)
4. **High error counts** but most are actually completed trials that failed to solve tasks

### Timeline

```
Mar 12 17:40 - Gemma-3-12b-it started
Mar 12 19:20 - Gemma-3-12b-it completed (1h 40m)
Mar 12 19:22 - Phi-4 started
Mar 12 22:00 - Phi-4 completed (2h 38m)
Mar 12 22:01 - Llama-3.1-8B started
Mar 13 01:33 - Llama-3.1-8B completed (3h 32m)
Mar 13 01:36 - Mistral-Small started
Mar 13 03:55 - Process died (2h 19m into Mistral)
```

---

## What's Missing

### Mistral-Small-Instruct-2409
- **terminus-2:** 6/13 tasks completed (0 passed), 7 remaining
- **openhands:** 0/13 tasks (not started)
- **Estimated time to complete:** ~2-3 hours

---

## Data Quality

### ✅ Usable Data
- 3 complete model runs (Gemma, Phi, Llama)
- 78 task trials completed
- All have proper result.json files with timing/token metrics

### ⚠️ Issues
- openhands 0% pass rate suspicious (possible configuration issue?)
- Overall low pass rates (8.8% on terminus-2)
- Mistral incomplete (can't compare all 4 brands)

---

## File Locations

**Completed Results:**
- `results/terminus-2-gemma3-12b-it/` - 13 trials
- `results/openhands-gemma3-12b-it/` - 12 trials
- `results/terminus-2-phi4-14b/` - 8 trials (only 8 instead of 13?)
- `results/openhands-phi4-14b/` - 12 trials
- `results/terminus-2-llama31-8b-instruct/` - 8 trials
- `results/openhands-llama31-8b-instruct/` - 12 trials

**Partial Results:**
- `results/terminus-2-mistral-small-2409/` - 6/13 trials

**Tracking:**
- `benchmarks_completed.txt` - Shows Mistral started but not completed

---

## Questions to Investigate

1. **Why did terminus-2 only run 8 tasks for Phi-4 and Llama-3.1?** (Should be 13)
2. **Why is openhands at 0% pass rate across ALL models?** (Configuration issue?)
3. **What killed the Mistral run?** (OOM? Reboot? Manual kill?)
4. **Why such low pass rates overall?** (8.8% vs expected ~30-50%)

---

## Next Steps Options

### Option A: Resume Mistral Only
- Manually run Mistral-Small to completion
- Get full 4-model comparison
- Time: ~3 hours

### Option B: Debug openhands
- Fix whatever is causing 0% pass rate
- Re-run all models with openhands
- Time: ~16 hours (full re-run)

### Option C: Accept partial results
- Analyze 3 complete models
- Note Mistral incomplete
- Focus on terminus-2 data (openhands broken)

### Option D: Full re-run with fixes
- Debug why only 8 tasks ran for some models
- Fix openhands configuration
- Re-run all 4 models from scratch
- Time: ~16-20 hours

---

## Raw Statistics

**Total Execution Time:** ~10 hours
**Models Completed:** 3/4 (75%)
**Total Trials:** 72 completed + 6 partial = 78 trials
**Expected Total:** 104 trials (4 models × 2 agents × 13 tasks)
**Completion Rate:** 75% (78/104)

**Disk Usage:** Unknown (models deleted after completion per script)
**Log Size:** 4.0 MB
