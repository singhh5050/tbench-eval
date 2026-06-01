## Agent comparison

| Agent | Valid trials | Passes | Pass rate | Avg steps | Avg comp tok | Avg model-time |
|---|---|---|---|---|---|---|
| terminus-2 | 255 | 120 | 47% | 20.4 | 8,682 | 163s |
| qwen-coder | 67 | 23 | 34% | — | — | — |
| openhands | 239 | 47 | 20% | 21.6 | 6,817 | 153s |

### Per-run results — terminus-2

| Run | N | Pass | Pass% | Avg steps | Top failure |
|---|---|---|---|---|---|
| qwen3-coder-next-gguf-64gb | 25 | 21 | 84% | 16.8 | ran_without_solving |
| qwen3.5-35b-a3b-gguf-local | 25 | 21 | 84% | 12.2 | ran_without_solving |
| glm47-together | 13 | 10 | 77% | 31.3 | ran_without_solving |
| m2.1-fireworks | 13 | 10 | 77% | 44.4 | ran_without_solving |
| qwen-next-together | 13 | 8 | 62% | 71.2 | ran_without_solving |
| gpt-oss-120b-gguf-64gb | 29 | 16 | 55% | 4.1 | ran_without_solving |
| glm-4.7-flash-gguf-local | 19 | 9 | 47% | 11.6 | ran_without_solving |
| qwen-30b-local | 11 | 4 | 36% | 26.1 | ran_without_solving |
| nemotron-3-nano-30b-a3b-gguf-64gb | 23 | 7 | 30% | 10.2 | ran_without_solving |
| glm47-flash-local-v2 | 10 | 3 | 30% | 19.7 | ran_without_solving |
| qwen3-coder-30b-a3b-instruct-gguf-local | 31 | 9 | 29% | 26.3 | ran_without_solving |
| phi4-14b | 6 | 1 | 17% | 7.0 | ran_without_solving |
| nemotron-3-nano-30b-a3b-gguf-local | 8 | 1 | 12% | 15.4 | ran_without_solving |
| gemma3-12b-it | 1 | 0 | 0% | 39.0 | ran_without_solving |
| gpt-oss-20b-gguf-local | 8 | 0 | 0% | 2.5 | ran_without_solving |
| llama31-8b-instruct | 8 | 0 | 0% | 26.9 | ran_without_solving |
| mistral-small-2409 | 12 | 0 | 0% | 21.0 | ran_without_solving |

### Per-run results — openhands

| Run | N | Pass | Pass% | Avg steps | Top failure |
|---|---|---|---|---|---|
| qwen3.5-35b-a3b-gguf-local | 30 | 16 | 53% | 19.5 | ran_without_solving |
| qwen3-coder-next-gguf-64gb | 14 | 6 | 43% | 23.0 | ran_without_solving |
| qwen3-coder-30b-a3b-instruct-gguf-local | 35 | 13 | 37% | 25.5 | ran_without_solving |
| glm47-together-v2 | 13 | 4 | 31% | 62.6 | ran_without_solving |
| qwen-30b-local | 13 | 3 | 23% | 41.0 | ran_without_solving |
| phi4-14b | 10 | 1 | 10% | 16.7 | ran_without_solving |
| gpt-oss-120b-gguf-64gb | 34 | 3 | 9% | 2.7 | no_agent_steps |
| glm47-flash-local-v2 | 12 | 1 | 8% | 25.0 | ran_without_solving |
| gemma3-12b-it | 12 | 0 | 0% | 0.0 | no_agent_steps |
| llama31-8b-instruct | 12 | 0 | 0% | 42.5 | ran_without_solving |
| m2.1-fireworks-v2 | 13 | 0 | 0% | 0.0 | no_agent_steps |
| mistral-small-2409 | 12 | 0 | 0% | 1.7 | no_agent_steps |
| nemotron-3-nano-30b-a3b-gguf-64gb | 16 | 0 | 0% | 6.6 | ran_without_solving |
| qwen-next-together-v2 | 13 | 0 | 0% | 62.3 | ran_without_solving |

### Per-run results — qwen-coder

| Run | N | Pass | Pass% | Avg steps | Top failure |
|---|---|---|---|---|---|
| qwen3.5-35b-a3b-gguf-local | 33 | 14 | 42% | — | ran_without_solving |
| qwen3-coder-30b-a3b-instruct-gguf-local | 34 | 9 | 26% | — | ran_without_solving |

## Terminal-state failure taxonomy

**terminus-2** — 135 failures (valid)

| State | Count | % of failures |
|---|---|---|
| ran_without_solving | 135 | 100% |

**openhands** — 192 failures (valid)

| State | Count | % of failures |
|---|---|---|
| ran_without_solving | 116 | 60% |
| no_agent_steps | 67 | 35% |
| looped_truncated | 9 | 5% |

## Premature success declarations by model (terminus-2)

| Model | Failures | Premature decl. | % of failures |
|---|---|---|---|
| gpt-oss-120b | 13 | 2 | 15% |
| Nemotron-3-Nano-30B-A3B | 23 | 3 | 13% |
| GLM-4.7-Flash | 17 | 2 | 12% |
| Qwen3-Coder-Next-FP8 | 5 | 0 | 0% |
| minimax-m2p1 | 3 | 0 | 0% |
| Mistral-Small-Instruct-2409 | 12 | 0 | 0% |
| Llama-3.1-8B-Instruct | 8 | 0 | 0% |
| gemma-3-12b-it | 1 | 0 | 0% |
| gpt-oss-20b | 8 | 0 | 0% |

## Token efficiency (logged agents)

| Model | Pass rate | Mean comp tok | Efficiency (pass·1000/tok) |
|---|---|---|---|
| gpt-oss-120b | 30% | 2,323 | 0.13 |
| Qwen3-Coder-Next | 69% | 5,409 | 0.128 |
| Qwen3.5-35B-A3B | 67% | 6,399 | 0.105 |
| Qwen3-Coder-30B-A3B-Instruct | 32% | 6,054 | 0.053 |
| GLM-4.7-Flash | 32% | 6,316 | 0.05 |
| minimax-m2p1 | 38% | 9,088 | 0.042 |
| phi-4 | 12% | 3,517 | 0.036 |
| GLM-4.7 | 54% | 18,789 | 0.029 |
| Nemotron-3-Nano-30B-A3B | 17% | 11,361 | 0.015 |
| Qwen3-Coder-Next-FP8 | 31% | 29,526 | 0.01 |
| Llama-3.1-8B-Instruct | 0% | 6,502 | 0.0 |
| Mistral-Small-Instruct-2409 | 0% | 3,374 | 0.0 |
| gemma-3-12b-it | 0% | 619 | 0.0 |
| gpt-oss-20b | 0% | 3,542 | 0.0 |

### Passing vs failing token spend

| Model | Pass avg tok | Fail avg tok | Ratio |
|---|---|---|---|
| Qwen3-Coder-Next-FP8 | 4,762 | 40,532 | 8.5× |
| GLM-4.7 | 10,306 | 28,687 | 2.8× |
| minimax-m2p1 | 6,396 | 10,771 | 1.7× |
| GLM-4.7-Flash | 4,423 | 7,194 | 1.6× |
| Nemotron-3-Nano-30B-A3B | 7,909 | 12,069 | 1.5× |
| Qwen3-Coder-Next | 4,830 | 6,714 | 1.4× |
| Qwen3-Coder-30B-A3B-Instruct | 5,389 | 6,370 | 1.2× |
| phi-4 | 3,094 | 3,578 | 1.2× |
| Qwen3.5-35B-A3B | 6,572 | 6,043 | 0.9× (fails fast) |
| gpt-oss-120b | 4,317 | 1,461 | 0.3× (fails fast) |

## Step-count analysis

| Agent | Median | Mean | Pass mean | Fail mean | Max |
|---|---|---|---|---|---|
| terminus-2 | 13 | 20.4 | 14.8 | 25.4 | 263 |
| openhands | 11 | 21.6 | 23.0 | 21.2 | 400 |

### Step count by model (terminus-2)

| Model | Pass steps | Fail steps | Tok/step |
|---|---|---|---|
| Qwen3-Coder-Next | 16.1 | 20.5 | 325 |
| Qwen3.5-35B-A3B | 12.3 | 11.5 | 600 |
| GLM-4.7 | 20.9 | 66.0 | 488 |
| minimax-m2p1 | 18.0 | 132.3 | 410 |
| Qwen3-Coder-Next-FP8 | 14.8 | 161.6 | 300 |
| gpt-oss-120b | 4.9 | 3.2 | 993 |
| GLM-4.7-Flash | 12.1 | 16.1 | 484 |
| Qwen3-Coder-30B-A3B-Instruct | 29.1 | 25.0 | 207 |
| Nemotron-3-Nano-30B-A3B | 7.2 | 13.0 | 1,138 |
| phi-4 | 9.0 | 6.6 | 598 |
| Llama-3.1-8B-Instruct | — | 26.9 | 398 |
| Mistral-Small-Instruct-2409 | — | 21.0 | 305 |
| gpt-oss-20b | — | 2.5 | 1,417 |

## Task difficulty (valid trials, ≥3 attempts)

**Hardest (lowest pass rate):**

| Task | Attempts | Passes | Pass% |
|---|---|---|---|
| image-tile-identification | 11 | 0 | 0% |
| legal-summary-extraction | 9 | 0 | 0% |
| polyglot-c-py | 16 | 0 | 0% |
| schemelike-metacircular-eval | 22 | 0 | 0% |
| vimscript-vim-quine | 10 | 0 | 0% |
| build-pov-ray | 21 | 1 | 5% |
| playing-card-recognition | 11 | 1 | 9% |
| code-from-image | 26 | 4 | 15% |
| winning-avg-corewars | 19 | 3 | 16% |
| ekf-localization | 12 | 2 | 17% |

**Easiest (highest pass rate):**

| Task | Attempts | Passes | Pass% |
|---|---|---|---|
| log-summary | 11 | 10 | 91% |
| raft-log-repair-concurrent-access | 10 | 8 | 80% |
| jsonl-aggregator | 12 | 9 | 75% |
| cryptographic-protocol-verifier | 11 | 7 | 64% |
| broken-python | 11 | 7 | 64% |
| jq-data-processing | 12 | 7 | 58% |
| build-merkle-tree-cli-sha512 | 9 | 5 | 56% |
| schedule-vacation | 11 | 6 | 55% |

## Validity & infrastructure accounting

| Reason | Trials |
|---|---|
| valid | 561 |
| agent_integration_failure | 172 |
| ungraded | 101 |
| infra_slow | 8 |
| test_run | 6 |

