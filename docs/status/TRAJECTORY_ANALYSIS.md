# TerminalBench 2.0 — Trajectory Analysis Report

**Generated:** 2026-05-06
**Corpus:** 597 trajectories across 32 agent/model runs
**Overall pass rate:** 168 / 597 = **28.1%**

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Agent Comparison](#2-agent-comparison)
3. [Per-Run Results](#3-per-run-results)
4. [Failure Mode Taxonomy](#4-failure-mode-taxonomy)
5. [Behavioral Patterns](#5-behavioral-patterns)
6. [Token Efficiency](#6-token-efficiency)
7. [Step Count Analysis](#7-step-count-analysis)
8. [Task Difficulty](#8-task-difficulty)
9. [Infrastructure Failures](#9-infrastructure-failures)
10. [Model-Specific Profiles](#10-model-specific-profiles)
11. [Key Findings & Recommendations](#11-key-findings--recommendations)

---

## 1. Executive Summary

Across 32 runs spanning 20 distinct models and 2 agents (terminus-2, openhands), the benchmark reveals a handful of dominant failure patterns that account for the majority of losses:

- **Step limit exhaustion** is the single largest failure mode for both agents (~60% of failures). Models get stuck in iterative loops and never converge.
- **Premature success declarations** are a critical model-side issue — some models (Qwen3-Coder-30B, Qwen-30B) declare task completion in 80–90% of their failures without actually solving the task.
- **Zero-step infrastructure failures** account for 31% of openhands failures — the harness or model never produces an agent turn at all.
- **terminus-2** significantly outperforms openhands overall (34.2% vs 19.5%), primarily because openhands suffers from more infrastructure failures and has fewer mechanisms to recover from loops.
- The best-performing configuration is **terminus-2 + Qwen3.5-35B-A3B / Qwen3-Coder-Next** at 60%, and **terminus-2 + GLM-4.7 (Together cloud)** / **MiniMax M2.1 (Fireworks)** at 77%.

---

## 2. Agent Comparison

| Agent | Trajectories | Passes | Pass Rate | Avg Steps | Avg Comp Tokens | Avg Duration |
|---|---|---|---|---|---|---|
| terminus-2 | 351 | 120 | **34.2%** | 21.0 | 10,270 | 477s |
| openhands | 246 | 48 | **19.5%** | 25.2 | 9,060 | 279s |

**Key differences:**

- terminus-2 passes with **fewer steps** (14.8 avg on pass vs 24.2 for openhands), indicating more decisive behavior when it does succeed.
- openhands fails faster on infrastructure issues (zero-step cases pull its step avg down), but when it does engage, it uses similar step counts to terminus-2.
- terminus-2's failure mode is almost entirely exhaustion loops (97% of failures show debug loop markers). openhands has a more varied failure distribution.
- openhands tools: `execute_bash` (2698), `str_replace_editor` (805), `think` (110), `finish` (81). Heavy reliance on bash, low use of structured thinking.
- terminus-2 tools: `bash_command` (13,277), `mark_task_complete` (531). Purely bash-driven with explicit completion signaling.

---

## 3. Per-Run Results

### terminus-2

| Run | N | Pass | Pass% | Avg Steps | Avg Comp Tok | Avg Duration | Top Failure Mode |
|---|---|---|---|---|---|---|---|
| terminus-2-glm47-together | 13 | 10 | **77%** | 31.2 | 15,271 | 450s | hit_step_limit |
| terminus-2-m2.1-fireworks | 13 | 10 | **77%** | 44.3 | 18,177 | 1,117s | hit_step_limit |
| terminus-2-qwen-next-together | 13 | 8 | **62%** | 71.2 | 21,349 | 1,264s | hit_step_limit |
| terminus-2-qwen3-coder-next-gguf-64gb | 35 | 21 | **60%** | 20.8 | 7,338 | 255s | hit_step_limit |
| terminus-2-qwen3.5-35b-a3b-gguf-local | 35 | 21 | **60%** | 16.0 | 9,333 | 265s | hit_step_limit |
| terminus-2-gpt-oss-120b-gguf-64gb | 35 | 16 | **46%** | 5.8 | 5,882 | 213s | ended_with_error |
| terminus-2-qwen-30b-local | 13 | 4 | 31% | 33.0 | 6,307 | 305s | hit_step_limit |
| terminus-2-glm-4.7-flash-gguf-local | 35 | 9 | 26% | 16.8 | 9,901 | 368s | hit_step_limit |
| terminus-2-glm47-flash-local-v2 | 13 | 3 | 23% | 29.5 | 11,738 | 883s | hit_step_limit |
| terminus-2-nemotron-3-nano-30b-a3b-gguf-64gb | 34 | 7 | 21% | 11.7 | 14,320 | 299s | hit_step_limit |
| terminus-2-qwen3-coder-30b-a3b-instruct-gguf-local | 34 | 9 | 26% | 30.7 | 6,851 | 162s | hit_step_limit |
| terminus-2-nemotron-3-nano-30b-a3b-gguf-local | 13 | 1 | 8% | 15.0 | 18,533 | 344s | hit_step_limit |
| terminus-2-phi4-14b | 13 | 1 | 8% | 12.9 | 6,468 | 470s | hit_step_limit |
| terminus-2-gpt-oss-20b-gguf-local | 13 | 0 | 0% | 3.1 | 3,841 | 116s | failed_task |
| terminus-2-llama31-8b-instruct | 13 | 0 | 0% | 31.7 | 11,218 | 646s | hit_step_limit |
| terminus-2-mistral-small-2409 | 13 | 0 | 0% | 22.5 | 7,604 | 1,168s | hit_step_limit |
| terminus-2-gemma3-12b-it | 13 | 0 | 0% | 3.0 | 619 | 611s | no_agent_steps |

### openhands

| Run | N | Pass | Pass% | Avg Steps | Avg Comp Tok | Avg Duration | Top Failure Mode |
|---|---|---|---|---|---|---|---|
| openhands-qwen3.5-35b-a3b-gguf-local | 30 | 16 | **53%** | 21.4 | 5,630 | 180s | hit_step_limit |
| openhands-qwen3-coder-next-gguf-64gb | 15 | 7 | **47%** | 21.9 | 4,952 | 220s | hit_step_limit |
| openhands-qwen3-coder-30b-a3b-instruct-gguf-local | 35 | 13 | **37%** | 25.5 | 6,180 | 185s | hit_step_limit |
| openhands-glm47-together-v2 | 13 | 4 | 31% | 123.5 | 22,288 | 827s | hit_step_limit |
| openhands-qwen-30b-local | 13 | 3 | 23% | 41.0 | 7,662 | 265s | hit_step_limit |
| openhands-gpt-oss-120b-gguf-64gb | 34 | 3 | 9% | 2.6 | 799 | 40s | no_agent_steps |
| openhands-glm47-flash-local-v2 | 12 | 1 | 8% | 26.2 | 4,701 | 328s | hit_step_limit |
| openhands-phi4-14b | 12 | 1 | 8% | 20.5 | 3,251 | 457s | hit_step_limit |
| openhands-nemotron-3-nano-30b-a3b-gguf-64gb | 19 | 0 | 0% | 9.3 | 7,053 | 312s | failed_task |
| openhands-llama31-8b-instruct | 12 | 0 | 0% | 44.3 | 3,703 | 213s | hit_step_limit |
| openhands-mistral-small-2409 | 12 | 0 | 0% | 2.3 | 334 | 109s | minimal_output |
| openhands-gemma3-12b-it | 12 | 0 | 0% | 0.0 | 0 | 0s | no_agent_steps |
| openhands-m2.1-fireworks-v2 | 13 | 0 | 0% | 0.0 | 0 | 0s | no_agent_steps |
| openhands-qwen-next-together-v2 | 13 | 0 | 0% | 61.5 | 37,594 | 338s | hit_step_limit |

---

## 4. Failure Mode Taxonomy

Five distinct failure modes were identified. Each trajectory is classified by its terminal state.

### Definitions

| Mode | Description |
|---|---|
| `hit_step_limit` | Agent ran until max steps without resolving the task |
| `no_agent_steps` | Zero agent turns recorded — model never produced a valid response |
| `failed_task` | Agent completed normally but reward=0 with no clear loop/limit indicator |
| `ended_with_error` | Final agent steps contain explicit error content (build failure, exception) |
| `minimal_output` | Model generated <50 completion tokens total — near-silent failure |

### Distribution by Agent

**terminus-2** (231 failures):

| Mode | Count | % of Failures |
|---|---|---|
| `hit_step_limit` | 154 | **67%** |
| `failed_task` | 33 | 14% |
| `ended_with_error` | 30 | 13% |
| `no_agent_steps` | 14 | 6% |

**openhands** (198 failures):

| Mode | Count | % of Failures |
|---|---|---|
| `hit_step_limit` | 96 | **48%** |
| `no_agent_steps` | 61 | **31%** |
| `failed_task` | 27 | 14% |
| `ended_with_error` | 7 | 4% |
| `minimal_output` | 7 | 4% |

**Notable contrast:** openhands has 4× more zero-step failures than terminus-2 in absolute terms (61 vs 14), reflecting greater sensitivity to harness/Docker networking issues and model format incompatibilities. terminus-2 is more likely to engage and run to exhaustion.

---

## 5. Behavioral Patterns

Analysis of the final agent message in each failure case reveals recurring behaviors.

### terminus-2 Behavioral Patterns (217 failures with last message)

| Pattern | Count | % |
|---|---|---|
| Debug/attempt loop ("Analysis:", "Plan:", "let me try") | 210 | **97%** |
| Premature success declaration | 30 | 14% |
| Compilation/build errors | 18 | 8% |
| Stalled/waiting | 2 | 1% |
| Auth/network error | 1 | 0% |

terminus-2's dominant failure is **getting stuck in a reasoning-action loop**. The `Analysis: / Plan:` prefix pattern appears in 97% of failed trajectories — the model keeps narrating what it plans to do without making progress. This is partly structural: the terminus-2 harness prompts models to explain their reasoning at each step, which reinforces verbose loop behavior in weaker models.

### openhands Behavioral Patterns (137 failures with last message)

| Pattern | Count | % |
|---|---|---|
| Hit step limit | 96 | 70% |
| Premature success declaration | 28 | **20%** |
| Running command loop | 23 | 17% |
| Editing files loop | 13 | 9% |
| Debug/attempt loop | 8 | 6% |
| Compilation/build error | 3 | 2% |

openhands has a more varied failure profile. The **"running command" loop** (23 cases) is specific to openhands: the model emits `execute_bash` with the same command repeatedly, often because it isn't reading the output correctly. The **"editing files" loop** (13 cases) occurs when a model repeatedly rewrites the same file without verifying the change took effect.

### Premature Success Declarations by Model

This is the most actionable model-quality signal. A model that declares "task complete" while being wrong wastes steps and inflates apparent confidence.

| Model Tag | Failures | Premature Decl. | % |
|---|---|---|---|
| qwen-30b-local (terminus-2) | 9 | 8 | **89%** |
| qwen3-coder-30b-local (terminus-2) | 25 | 21 | **84%** |
| phi4-14b (terminus-2) | 12 | 5 | 42% |
| nemotron-3-nano-30b-a3b-64gb (terminus-2) | 27 | 14 | 52% |
| qwen3.5-35b-local (terminus-2) | 14 | 3 | 21% |
| gpt-oss-120b-64gb (terminus-2) | 19 | 1 | 5% |
| qwen3-coder-next-64gb (terminus-2) | 14 | 1 | 7% |
| glm47-together (terminus-2) | 3 | 0 | 0% |
| m2.1-fireworks (terminus-2) | 3 | 0 | 0% |

The Qwen3-Coder-30B and Qwen-30B MoE models are severe offenders — they confidently state completion while the reward checker scores 0. This is likely a mix of instruction-following degradation under Q4_K_M quantization and the MoE architecture producing inconsistently confident outputs. The larger/cloud models (GLM-4.7 Together, MiniMax) show 0% false completion — they either solve it or keep trying.

---

## 6. Token Efficiency

**Metric:** Pass rate × 1000 / mean completion tokens. Higher = more passes per token spent.

| Model Tag | Pass Rate | Mean Comp Tokens | Efficiency Score |
|---|---|---|---|
| qwen3-coder-next-gguf-64gb | 56% | 6,592 | **0.085** |
| qwen3.5-35b-a3b-gguf-local | 57% | 7,627 | **0.075** |
| gpt-oss-120b-gguf-64gb | 28% | 3,401 | **0.082** |
| glm47-together | 77% | 15,271 | 0.050 |
| qwen3-coder-30b-local | 32% | 6,550 | 0.049 |
| m2.1-fireworks | 77% | 18,177 | 0.042 |
| qwen-30b-local | 27% | 7,050 | 0.039 |
| qwen-next-together | 62% | 21,349 | 0.029 |
| glm-4.7-flash-gguf-local | 25% | 9,573 | 0.026 |
| glm47-together-v2 | 31% | 22,288 | 0.014 |
| phi4-14b | 8% | 4,919 | 0.016 |
| nemotron-3-nano-30b-a3b-gguf-64gb | 13% | 12,011 | 0.011 |
| nemotron-3-nano-30b-a3b-gguf-local | 8% | 18,533 | 0.004 |
| gemma3-12b-it | 0% | — | 0.000 |
| llama31-8b-instruct | 0% | — | 0.000 |
| mistral-small-2409 | 0% | — | 0.000 |
| gpt-oss-20b-gguf-local | 0% | — | 0.000 |

**Key insight:** The local Qwen3 models (35B and Coder-Next) are the most token-efficient overall — they solve tasks with fewer tokens than cloud models while maintaining competitive pass rates. Cloud models like MiniMax and GLM-4.7 (Together) achieve high pass rates but spend 3–4× more tokens per task.

**Passing vs failing token spend:**

| Model Tag | Pass Avg Comp Tok | Fail Avg Comp Tok | Ratio |
|---|---|---|---|
| glm47-together | 8,144 | 39,027 | **4.8×** more on failures |
| m2.1-fireworks | 6,396 | 57,444 | **9.0×** more on failures |
| qwen-next-together | 4,762 | 47,887 | **10.1×** more on failures |
| qwen3.5-35b-local | 6,572 | 9,012 | 1.4× |
| qwen3-coder-next-64gb | 4,659 | 9,120 | 2.0× |
| gpt-oss-120b-64gb | 4,317 | 3,020 | 0.7× (fails fast) |

Cloud models burn drastically more tokens on failures — they try many approaches before giving up. Local Qwen3 models have a much tighter pass/fail token ratio, suggesting they converge or give up more consistently.

---

## 7. Step Count Analysis

### Summary Statistics

| Agent | Median Steps | Mean Steps | Pass Mean | Fail Mean | Max |
|---|---|---|---|---|---|
| terminus-2 | 14 | 21.0 | **14.8** | 24.3 | 262 |
| openhands | 13 | 25.2 | 24.2 | 25.4 | 494 |

**terminus-2 insight:** Passing trajectories use significantly fewer steps (14.8) than failing ones (24.3). This gap means the agent converges quickly when it's going to succeed — a healthy signal. Failure = getting progressively more lost.

**openhands insight:** Almost no difference between pass (24.2) and fail (25.4) step means. The step count tells you almost nothing about whether openhands will succeed — it runs to approximately the same depth either way. This suggests openhands doesn't have a strong early-termination signal.

### Step Count by Model (terminus-2 only)

| Model Tag | Pass Steps | Fail Steps | Tok/Step |
|---|---|---|---|
| glm47-together | 20.9 | 65.7 | 489 |
| m2.1-fireworks | 18.0 | 132.0 | 410 |
| qwen-next-together | 14.8 | 161.6 | 300 |
| qwen3.5-35b-local | 12.3 | 21.6 | 582 |
| qwen3-coder-next-64gb | 16.1 | 27.7 | 353 |
| gpt-oss-120b-64gb | 4.9 | 6.5 | 1,014 |
| qwen3-coder-30b-local | 30.0 | 31.0 | 223 |
| qwen-30b-local | 27.0 | 35.7 | 191 |
| nemotron-3-nano-30b-a3b-64gb | 6.9 | 12.9 | 1,226 |
| glm-4.7-flash-local | 11.1 | 18.8 | 589 |
| phi4-14b | 9.0 | 13.2 | 500 |
| mistral-small-2409 | — | 22.5 | 339 |
| llama31-8b-instruct | — | 31.7 | 354 |
| gemma3-12b-it | — | 3.0 | 206 |

**Notable:** Cloud models (GLM-Together, MiniMax, Qwen-Next) have extreme fail step counts (65–161) — they keep trying for a very long time before the limit is hit. Local Qwen3 models fail at step counts barely above their pass counts, suggesting they hit a wall and don't recover rather than endlessly exploring.

**gpt-oss-120b** fails very fast (6.5 steps on fail) — it either solves it or encounters an error immediately. Consistent with the `ended_with_error` being its dominant failure mode.

---

## 8. Task Difficulty

Ranked by pass rate across all agent/model combinations (minimum 3 attempts).

### Hardest Tasks (0–20%)

| Task | Attempts | Passes | Pass% | Likely Cause |
|---|---|---|---|---|
| schemelike-metacircular-eval | 27 | 0 | **0%** | Requires deep Scheme interpreter knowledge |
| polyglot-c-py | 21 | 0 | **0%** | Requires precise dual-language file format insight |
| vimscript-vim-quine | 10 | 0 | **0%** | Self-referential Vimscript — novel constraint |
| playing-card-recognition | 10 | 0 | **0%** | Vision input — terminal agents can't process images |
| legal-summary-extraction | 11 | 0 | **0%** | Domain-specific legal reasoning |
| image-tile-identification | 10 | 0 | **0%** | Vision input — structural agent limitation |
| build-pov-ray | 30 | 1 | **3%** | Complex legacy C build with specific deps |
| winning-avg-corewars | 28 | 3 | **11%** | Requires Core War strategy + compilation |
| code-from-image | 31 | 4 | **13%** | Vision-adjacent — interpret image-encoded code |

**Structural impossibilities:** `playing-card-recognition` and `image-tile-identification` require visual processing — terminal agents without vision tools will never solve these. These should either be removed from the easy task set or reserved for vision-capable agents.

**Near-impossible tasks:** `schemelike-metacircular-eval` and `polyglot-c-py` have 0 passes across 21–27 attempts spanning the best models. These are likely ceiling tasks and are valuable benchmarks for future capability jumps.

### Easiest Tasks (60–80%)

| Task | Attempts | Passes | Pass% |
|---|---|---|---|
| log-summary | 10 | 8 | **80%** |
| jsonl-aggregator | 11 | 8 | **73%** |
| cryptographic-protocol-verifier | 10 | 6 | **60%** |
| raft-log-repair-concurrent-acces | 10 | 6 | **60%** |

These are well-scoped, self-contained tasks where the goal is clear and achievable within the step budget. Good canaries for whether a new model/harness is functioning correctly.

### Medium Difficulty (30–50%)

The largest cluster — `fix-git`, `git-leak-recovery`, `pypi-server`, `cobol-modernization`, `prove-plus-comm`, `build-pmars` — represent realistic engineering tasks where top models succeed but weaker ones fail. This is the core discriminating region of the benchmark.

---

## 9. Infrastructure Failures

Several runs had zero-step or near-zero-step failures caused by harness/model compatibility issues rather than model capability.

### Gemma3-12b (Both Agents, 0%)

- **24 zero-step failures** across both terminus-2 (12/13) and openhands (12/12)
- Trajectories contain only system prompts — the model never produces a tool call or agent turn
- Root cause: Gemma-3 uses a different chat template format and does not follow the terminal-bench tool-calling schema
- Not a capability failure — the model simply doesn't understand the harness format

### OpenHands + gpt-oss-120b-64gb (79% zero-step)

- 27 of 34 tasks had zero agent steps despite the model having 34 agent-turn entries in logs
- All affected tasks received the same wrong prompt (`vimscript-vim-quine` task description injected into every task)
- Also received `Missing required parameters for function 'execute_bash': {'security_risk'}` errors — gpt-oss-120b uses a different tool schema variant
- Root cause: Task routing bug in the 64GB run configuration + tool schema mismatch with OpenHands harness
- terminus-2 + gpt-oss-120b-64gb performed fine (46%), confirming it's an OpenHands-specific compatibility issue

### OpenHands + m2.1-fireworks-v2 (100% zero-step)

- All 13 tasks failed silently with no agent turns
- MiniMax M2.1 via Fireworks worked fine with terminus-2 (77% pass rate) in a separate run
- Root cause: Docker host networking configuration (`openhands_hostnet.yaml`) — OpenHands running in Docker couldn't reach the Fireworks API endpoint through the proxy configuration on this run

### Qwen-Next-Together-v2 openhands (0%, but 61.5 avg steps)

- Unlike the above, this run did produce agent turns — 61.5 steps per task on average
- With 37,594 avg completion tokens (highest of any run), the model was very active
- 0% pass rate despite maximum engagement suggests a prompt/format mismatch causing the model to run but not actually execute meaningful tool calls
- Contrast with terminus-2 + Qwen-Next-Together (62% pass rate) — same model, different harness, dramatic outcome difference

---

## 10. Model-Specific Profiles

### Top Tier (>50% on at least one configuration)

**GLM-4.7 via Together AI**
- terminus-2: 77%, 31 steps avg on pass, 0% premature success
- openhands-v2: 31% (same model, different run config/prompt)
- Large token spend (15K+ comp tokens) but consistently solves hard tasks
- Favors long deliberate exploration — cloud API removes token budget pressure

**MiniMax M2.1 via Fireworks**
- terminus-2: 77%, 44 steps avg on pass, 18K comp tokens
- openhands: 0% (infrastructure failure, not model capability)
- Highest step count on passing tasks (44.3) — very thorough, very slow (~18 min/task)
- 0% premature success — when it fails, it genuinely fails

**Qwen3-Coder-Next (64GB server)**
- terminus-2: 60%, 20.8 steps, 7.3K tokens — best efficiency on 64GB hardware
- openhands: 47%
- Solid across both harnesses, consistent behavior, low premature success rate (7%)

**Qwen3.5-35B-A3B (30GB local)**
- terminus-2: 60%, 16 steps — most step-efficient passing model
- openhands: 53% — best openhands result overall
- Best local model for this machine; runs in ~265s per task

### Mid Tier (20–50%)

**Qwen3-Coder-30B-A3B (30GB local)**
- terminus-2: 26%, openhands: 37%
- Unusually high premature success rate (84% of terminus-2 failures) — serious calibration issue under Q4_K_M quantization
- Better with openhands (which doesn't reinforce the "Analysis/Plan" loop pattern)
- 162s avg duration — fastest of any local model

**gpt-oss-120b (64GB)**
- terminus-2: 46%, openhands: 9% (infrastructure issues)
- Extremely fast: 4.9 steps on pass, 6.5 on fail — it either gets it immediately or errors out
- Highest tokens-per-step (1,014) — very verbose single responses
- Dominant failure: `ended_with_error` — hits hard errors rather than looping

**GLM-4.7-Flash (local)**
- terminus-2: 26%, openhands: 8%
- Flash model is significantly weaker than full GLM-4.7 (77% Together cloud)
- Produces longer loops (16.8 steps avg) with moderate token use
- Demonstrates the large gap between quantized local and full cloud versions

### Lower Tier (0–15%)

**Nemotron-3-Nano-30B-A3B**
- 64GB: 21% (terminus-2), 0% (openhands)
- Local: 8% (terminus-2)
- Highest tokens-per-step of any model (1,226 local, 1,014 gpt-oss) — very verbose but inaccurate
- 52% premature success rate on 64GB — overconfident model

**Phi-4 (14B)**
- 8% across both agents
- Reasonable step counts (12.9 avg) but poor task-solving capability
- 42% premature success — inflated confidence relative to capability

**Llama-3.1-8B, Mistral-Small-2409**
- 0% pass rate across all tasks
- Llama-3.1-8B engages (31.7 steps avg) but cannot solve any task
- Mistral produces minimal output (2.3 steps, 334 tokens avg) — near-silent failure
- Both are below the capability floor for terminal-bench tasks

**Gemma-3-12B, gpt-oss-20b**
- 0% pass rate, harness incompatibility or capability floor issues
- Not suitable for terminal-bench evaluation without harness modifications

---

## 11. Key Findings & Recommendations

### Finding 1: Step limit exhaustion is the dominant failure mode

67% of terminus-2 failures and 48% of openhands failures hit the step limit. This means models are not converging — they keep trying without making progress. **Recommendation:** Explore step budgets per task (easy tasks capped lower, hard tasks given more) rather than a uniform limit.

### Finding 2: Premature success declarations are a model quality signal

Qwen3-Coder-30B and Qwen-30B declare false success in 80–89% of their failures. This is not a harness issue — the model genuinely believes it's done. **Recommendation:** Add a "false completion rate" metric to the dashboard; flag models that declare success more than 30% of the time on failing tasks.

### Finding 3: terminus-2 substantially outperforms openhands on local models

The gap is largest for models with openhands harness incompatibilities (gpt-oss-120b: 46% vs 9%; MiniMax: 77% vs 0%). Even for compatible models, terminus-2 leads (Qwen3.5-35B: 60% vs 53%). **Recommendation:** terminus-2 should be the default harness for local model evaluation; openhands adds value primarily for cloud API runs where its Docker recovery mechanisms help.

### Finding 4: Vision tasks are structural failures

`playing-card-recognition`, `image-tile-identification`, and partially `code-from-image` (13%) are unanswerable by terminal-only agents. **Recommendation:** Remove or quarantine these from the easy task set, or track them separately as a "vision-capable agents only" category.

### Finding 5: Local Qwen3 models are the sweet spot for 30GB hardware

Qwen3.5-35B-A3B at 60% (terminus-2) and Qwen3-Coder-30B at 37% (openhands) are the clear winners for the AMD Ryzen AI MAX+ 395 setup. Both use Q4_K_M quantization and fit comfortably. **Recommendation:** These should be the baseline models for any new harness testing on this machine.

### Finding 6: Cloud models spend 3–10× more tokens on failures

MiniMax spends 9× more tokens on failing tasks than passing ones; Qwen-Next-Together spends 10×. Local models have tighter ratios (1.4–2×). This suggests cloud models have longer context windows and persist longer on hard problems. **Recommendation:** For cost-efficiency, use local models for initial harness validation; cloud models for final quality benchmarking.

### Finding 7: The benchmark has a clear difficulty spectrum

- **Ceiling tasks** (0% pass, 20+ attempts): schemelike-metacircular-eval, polyglot-c-py — useful for future capability tracking
- **Discriminating tasks** (20–50%): fix-git, cobol-modernization, pypi-server, prove-plus-comm — core benchmark signal
- **Floor tasks** (>70%): log-summary, jsonl-aggregator — useful for harness sanity checks but not discriminating

### Finding 8: openhands + GLM-4.7-Together has a configuration-specific regression

The v2 run (31%) performs drastically worse than the original terminus-2 run (77%) with the same model. The v2 run averaged 123.5 steps (vs 31.2) and 22K tokens (vs 15K), suggesting the openhands prompt format causes the model to loop far longer without converging. This is a harness-model interaction, not a model capability regression.

---

*Analysis based on 597 ATIF-format trajectory files. Token counts from `final_metrics` or per-step `metrics` fields. Duration computed from first-to-last step timestamp. Failure modes auto-classified by step count, token count, and last-message keyword patterns.*
