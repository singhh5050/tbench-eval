# Sources

External sources cited in the report and deck.

## Intelligence per Watt
- **Intelligence per Watt: Measuring Intelligence Efficiency of Local AI**, arXiv:2511.07885
  (Stanford Hazy Research / Scaling Intelligence Lab + Together AI; Saad-Falcon, Narayan,
  Hennessy, Mirhoseini, Ré). https://arxiv.org/abs/2511.07885
  - Local LMs accurately answer **88.7%** of single-turn chat/reasoning queries.
  - Local intelligence efficiency improved **5.3×** (2023→2025): 3.1× model, 1.7× hardware.
  - Local query coverage rose **23.2% → 71.3%** (2023→2025).
  - Qwen3-32B on Apple M4 Max shows only **1.5× lower IPW** than an NVIDIA B200 on the same model.
  - Study scale: 20+ local LMs, 8 accelerators, ~1M real-world queries.
  - Blog: https://hazyresearch.stanford.edu/blog/2025-11-11-ipw

## AMD Ryzen AI MAX+ 395 "Strix Halo"
- 16 Zen 5 cores / 32 threads; Radeon 8060S iGPU (40 CUs, RDNA 3.5); XDNA2 NPU **50 TOPS**.
- Up to **128 GB** unified LPDDR5X-8000, ~**256 GB/s** bandwidth (4 nm TSMC).
- Configurable TDP **45–120 W (default 55 W)**. Measured (Notebookcheck, ROG Flow Z13): ~60 W
  combined CPU+GPU load, ~70 W single-domain, ~86 W brief peak.
- AMD product page: https://www.amd.com/en/products/processors/laptop/ryzen/ai-300-series/amd-ryzen-ai-max-plus-395.html
- Notebookcheck review (measured power): https://www.notebookcheck.net/AMD-Ryzen-AI-Max-395-Analysis-Strix-Halo...963274.0.html
- Power bracket used for tokens/joule estimate: **~65 W sustained** (55 default · 86 peak).

## AMD AI-PC strategy
- "The desktop PC is evolving from a tool you use to an intelligent assistant that works alongside
  you." — Jack Huynh, SVP/GM, AMD. https://www.amd.com/en/newsroom/press-releases/2026-3-2-amd-gives-consumers-and-businesses-more-ai-pc-opti.html
- On-device NPUs offer "data security, privacy, increased responsiveness, and the ability to use
  applications even when not connected to the internet." https://www.amd.com/en/blogs/2025/ai-pcs-superpowers-for-business.html
- AMD frames **2025 as "The Year of the AI PC."**

## Open vs frontier on agentic coding
- **Terminal-Bench 2.0** (https://www.tbench.ai/leaderboard/terminal-bench/2.0): best open-weight
  scaffolds land ~**42–52%** vs frontier (Claude/GPT) ~**85–90%** on the full benchmark.
- **SWE-bench Verified** (https://www.swebench.com): open models (e.g. Qwen3-Coder-480B ≈ 69.6%)
  narrow the gap to frontier (~75–88%) to single digits — open weights *write the fix* well; the
  gap is in *driving the long-horizon agent loop*.

## Why local / on-device (drivers)
- Privacy / data sovereignty (GDPR, on-prem mandates in gov/finance/healthcare).
- Latency / offline operation; cost at sustained volume.
- (Third-party blogs; AMD privacy messaging + the IPW paper are the authoritative backbone.)