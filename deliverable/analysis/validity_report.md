# Data hygiene & validity report

Total trials discovered: **848**. Valid (used for all analysis): **561**. Dropped: **287**.

## Drop accounting

| Reason | Trials | Note |
|---|---:|---|
| valid | 561 | used for all capability / throughput / per-watt analysis |
| agent_integration_failure | 172 | swe-agent `$(pwd)` crash; mini-swe-agent no assistant turn |
| infra_slow | 8 | gen tok/s < max(5.0, 0.4x model baseline) = server stall |
| ungraded | 101 | no verifier/reward.txt (env/agent error mid-run) |
| test_run | 6 | test-* / cloud-test / claude-code probes |

Thresholds: `ABS_FLOOR = 5.0` tok/s, `SLOW_FRAC = 0.4` of each model's own median throughput.

## Throughput-collapse trials dropped (infra_slow)

| run | task | gen tok/s | model baseline |
|---|---|---:|---:|
| openhands-glm-4.7-flash-gguf-local | code-from-image | 1.2 | 45.8 |
| openhands-phi4-14b | winning-avg-corewars | 5.1 | 15.9 |
| openhands-phi4-14b | prove-plus-comm | 5.3 | 15.9 |
| openhands-qwen3-coder-next-gguf-64gb | jsonl-aggregator | 7.5 | 48.1 |
| terminus-2-glm47-flash-local-v2 | winning-avg-corewars | 16.7 | 45.8 |
| openhands-nemotron-3-nano-30b-a3b-gguf-64gb | broken-python | 24.0 | 64.2 |
| openhands-nemotron-3-nano-30b-a3b-gguf-64gb | winning-avg-corewars | 24.5 | 64.2 |
| openhands-nemotron-3-nano-30b-a3b-gguf-64gb | amuse-install | 25.2 | 64.2 |

## Per-run summary (valid only)

| run | agent | backend | valid trials | dropped | valid pass-rate |
|---|---|---|---:|---:|---:|
| terminus-2-qwen3.5-35b-a3b-gguf-local | terminus-2 | local | 25 | 7 | 84% (21/25) |
| terminus-2-qwen3-coder-next-gguf-64gb | terminus-2 | local | 25 | 9 | 84% (21/25) |
| terminus-2-glm47-together | terminus-2 | hosted | 13 | 0 | 77% (10/13) |
| terminus-2-m2.1-fireworks | terminus-2 | hosted | 13 | 0 | 77% (10/13) |
| terminus-2-qwen-next-together | terminus-2 | hosted | 13 | 0 | 62% (8/13) |
| terminus-2-gpt-oss-120b-gguf-64gb | terminus-2 | local | 29 | 3 | 55% (16/29) |
| openhands-qwen3.5-35b-a3b-gguf-local | openhands | local | 30 | 3 | 53% (16/30) |
| terminus-2-glm-4.7-flash-gguf-local | terminus-2 | local | 19 | 3 | 47% (9/19) |
| openhands-qwen3-coder-next-gguf-64gb | openhands | local | 14 | 3 | 43% (6/14) |
| qwen-coder-qwen3.5-35b-a3b-gguf-local | qwen-coder | local | 33 | 3 | 42% (14/33) |
| openhands-qwen3-coder-30b-a3b-instruct-gguf-local | openhands | local | 35 | 3 | 37% (13/35) |
| terminus-2-qwen-30b-local | terminus-2 | local | 11 | 2 | 36% (4/11) |
| openhands-glm47-together-v2 | openhands | hosted | 13 | 0 | 31% (4/13) |
| terminus-2-nemotron-3-nano-30b-a3b-gguf-64gb | terminus-2 | local | 23 | 2 | 30% (7/23) |
| terminus-2-glm47-flash-local-v2 | terminus-2 | local | 10 | 3 | 30% (3/10) |
| terminus-2-qwen3-coder-30b-a3b-instruct-gguf-local | terminus-2 | local | 31 | 5 | 29% (9/31) |
| qwen-coder-qwen3-coder-30b-a3b-instruct-gguf-local | qwen-coder | local | 34 | 3 | 26% (9/34) |
| openhands-qwen-30b-local | openhands | local | 13 | 0 | 23% (3/13) |
| terminus-2-phi4-14b | terminus-2 | local | 6 | 7 | 17% (1/6) |
| terminus-2-nemotron-3-nano-30b-a3b-gguf-local | terminus-2 | local | 8 | 0 | 12% (1/8) |
| openhands-phi4-14b | openhands | local | 10 | 3 | 10% (1/10) |
| openhands-gpt-oss-120b-gguf-64gb | openhands | local | 34 | 2 | 9% (3/34) |
| openhands-glm47-flash-local-v2 | openhands | local | 12 | 1 | 8% (1/12) |
| openhands-llama31-8b-instruct | openhands | local | 12 | 1 | 0% (0/12) |
| openhands-qwen-next-together-v2 | openhands | hosted | 13 | 0 | 0% (0/13) |
| openhands-gemma3-12b-it | openhands | local | 12 | 1 | 0% (0/12) |
| openhands-m2.1-fireworks-v2 | openhands | hosted | 13 | 0 | 0% (0/13) |
| test-mini-swe | mini-swe-agent | local | 0 | 1 | — |
| swe-agent-qwen3.5-35b-a3b-gguf-local | swe-agent | local | 0 | 37 | — |
| openhands-mistral-small-2409 | openhands | local | 12 | 1 | 0% (0/12) |
| test-claude-code-v2 | claude-code | local | 0 | 1 | — |
| terminus-2-mistral-small-2409 | terminus-2 | local | 12 | 1 | 0% (0/12) |
| test-claude-code-v4 | claude-code | local | 0 | 1 | — |
| test-claude-code-v3 | claude-code | local | 0 | 1 | — |
| swe-agent-qwen3-coder-30b-a3b-instruct-gguf-local | swe-agent | local | 0 | 37 | — |
| terminus-2-gemma3-12b-it | terminus-2 | local | 1 | 12 | 0% (0/1) |
| test-claude-code | claude-code | local | 0 | 2 | — |
| openhands-glm-4.7-flash-gguf-local | openhands | local | 0 | 17 | — |
| openhands-nemotron-3-nano-30b-a3b-gguf-64gb | openhands | local | 16 | 5 | 0% (0/16) |
| terminus-2-llama31-8b-instruct | terminus-2 | local | 8 | 5 | 0% (0/8) |
| mini-swe-agent-qwen3-coder-30b-a3b-instruct-gguf-local | mini-swe-agent | local | 0 | 37 | — |
| terminus-2-gpt-oss-20b-gguf-local | terminus-2 | local | 8 | 4 | 0% (0/8) |
| swe-agent-glm-4.7-flash-gguf-local | swe-agent | local | 0 | 24 | — |
| mini-swe-agent-qwen3.5-35b-a3b-gguf-local | mini-swe-agent | local | 0 | 37 | — |
