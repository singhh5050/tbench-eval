---
marp: true
theme: amd-phosphor
paginate: true
html: true
footer: 'Almost There · local coding agents on an AMD AI PC · Harsh Singh, AMD'
---

<!-- _class: lead -->
<!-- _paginate: false -->
<!-- _footer: '' -->

<img class="logo" src="assets/brand/amd-white.png">

# ALMOST <span class="b">THERE.</span>

Local coding agents on an AMD AI PC — a measured readiness report

<div class="by">Harsh Singh<span class="sub">Research &amp; Advanced Development, AMD &nbsp;·&nbsp; Supervisors: Eddie Richter, Paul Hartke</span></div>

---

<!-- _class: divider -->
<!-- _paginate: false -->
<!-- _footer: '' -->

<div class="lead-num">01 · The question</div>

# Can a laptop-class AMD machine run a *useful* coding agent — today?

<div class="sub">Short answer: <b style="color:#F2F3F5">almost</b> — and the gap is closing fast. We measured it across <b style="color:#F2F3F5">561 valid trials</b> on a single Ryzen AI MAX+ 395. Here is the evidence.</div>

---

<div class="tag">02 · Motivation</div>

## Why local agents, why <span class="amd">AMD</span>

<div class="split even">
<div class="why">

AI inference is moving from the data center to the **device** — the AI-PC era. For a coding agent, running locally means:

- **Privacy & data sovereignty** — your code never leaves the machine.
- **Latency & offline** — no round-trip, works disconnected.
- **Cost** — no per-token API bill at sustained volume.
- **Intelligence per watt** — efficiency is the new scaling axis.

</div>
<div class="spec">
<div class="row"><span class="k">CPU</span><span class="v">16 × Zen 5</span></div>
<div class="row"><span class="k">GPU</span><span class="v">Radeon 8060S · 40 CU</span></div>
<div class="row"><span class="k">NPU</span><span class="v">XDNA2 · 50 TOPS</span></div>
<div class="row"><span class="k">Memory</span><span class="v r">128 GB unified</span></div>
<div class="row"><span class="k">Class</span><span class="v">Ryzen AI MAX+ 395</span></div>
</div>
</div>

<div class="take">Unified memory holds models a discrete consumer GPU can't — and routes Mixture-of-Experts experts with <b>no PCIe transfer cost.</b> The hardware and the model architecture are, in effect, co-designed.</div>

---

<div class="tag">03 · Method</div>

## What we built

<div class="cols">
<div class="why">

**A one-command evaluation platform.** `./bin/sweep.sh -a terminus-2 …` downloads each model, serves it with `llama-server`, and runs Terminal-Bench 2.0 across every model × harness on a single APU — fully reproducible.

**An interactive dashboard.** Every result is explorable down to a single generation — capability, efficiency, failure modes, and individual trajectories. Hosted live for the team.

</div>
<div class="cards">
<div class="card"><div class="v">241M</div><div class="l">tokens processed</div></div>
<div class="card"><div class="v">848 → 561</div><div class="l">trials run → valid</div></div>
<div class="card"><div class="v">14 × 4</div><div class="l">models × harnesses</div></div>
</div>
</div>

<div class="take">Every LLM call is logged with token usage and llama.cpp timings — which is what makes the validity filtering, efficiency, and per-watt analysis possible.</div>

---

<div class="tag">04 · Rigor</div>

## Only valid runs count

<div class="split">
<div class="why">

Raw pass rates conflate model behavior with infrastructure noise, so we classify every trial and report **valid-only**. The discriminator is throughput vs each model's **own baseline** — a model that is simply slow keeps its baseline; a run whose throughput *collapses* is a server stall, and is dropped.

A further **91 duplicate trials** (an early jobs-dir copied into named runs) were de-duplicated before any counting.

</div>
<div class="spec">
<div class="row"><span class="k">valid · used for analysis</span><span class="v r">561</span></div>
<div class="row"><span class="k">agent-integration failures</span><span class="v">172</span></div>
<div class="row"><span class="k">ungraded (env/agent error)</span><span class="v">101</span></div>
<div class="row"><span class="k">server stalls (tok/s collapse)</span><span class="v">8</span></div>
<div class="row"><span class="k">test / probe runs</span><span class="v">6</span></div>
</div>
</div>

<div class="take">848 = 561 + 172 + 101 + 8 + 6. Headline numbers are valid-only; everything dropped is accounted for, never used as a finding.</div>

---

<div class="tag">05 · Capability</div>

## What to run on <span class="amd">AMD</span> today

<div class="split">
<div><img src="assets/dark/capability_configs.png"></div>
<div class="why">
<h3>How to read it</h3>

Pass rate on the easy agentic-terminal slice, **valid runs only**. Red = local on-device; blue = open models served via API.

- **terminus-2 + Qwen3.5-35B-A3B → 84%** — a 30B-class *sparse* model, on a laptop-class APU.
- The **best** local config matches or beats the **best** API-served open model here.
- Everything dense (phi-4, Mistral) sits far lower.

</div>
</div>

<div class="take"><b>Qwen3.5-35B-A3B</b> is the on-device sweet spot: best pass rate, most step-efficient, fits a 30 GB footprint, ~54 tok/s.</div>

---

<div class="tag">06 · The key result</div>

## The harness is half the result

<div class="box3">
<div class="b red"><div class="h">terminus-2</div><div class="n">84%</div><p>Single bash channel; structured action. The model stays in its strongest modality.</p></div>
<div class="b steel"><div class="h">openhands</div><div class="n">53%</div><p>Richer tool surface — more ways to mis-format and more ways to wander.</p></div>
<div class="b dim"><div class="h">qwen-coder</div><div class="n">42%</div><p>A third scaffold; same weights, again a different outcome.</p></div>
</div>

Holding the model fixed at **Qwen3.5-35B-A3B**, the pass rate swings ~2× across harnesses. The scaffold — not just the weights — decides success. This is the **agent-computer-interface thesis** (Yang et al. 2024), reproduced on-device: for a constrained local model, a *narrower* interface is the *better* interface.

<div class="take">A capable model behind a weak loop looks like a weak model. Harness integration is a first-class product problem, not an afterthought.</div>

---

<div class="tag">07 · Evidence — strength</div>

## It can genuinely reason

<div class="split">
<div class="agent-trace">
<div class="at-head"><span class="dot">●</span> <span class="task">fix-git</span> · terminus-2 · Qwen3.5-35B-A3B <span class="verdict pass">REWARD 1.0 · PASS</span></div>
<div class="at-body">
<div class="turn"><div class="ep">ep 5</div><div><div class="analysis">"It failed because no editor is available to write the commit message."</div><div class="cmd">git cherry-pick --continue -m "Move to Stanford"</div></div></div>
<div class="turn"><div class="ep">ep 6</div><div><div class="analysis">"The -m flag is being interpreted as --mainline. I need to abort and use a non-interactive editor."</div><div class="cmd">git status ; GIT_EDITOR=true git cherry-pick --continue</div></div></div>
<div class="turn"><div class="ep">ep 8</div><div><div class="analysis">"The 'Move to Stanford' commit is now HEAD; the tree is clean."</div><span class="flag done">is_task_complete: true</span></div></div>
</div>
<div class="at-foot">Converged in <b>9 turns</b> · diagnosed the <code>-m</code>/<code>--mainline</code> gotcha · <b>reward 1.0</b></div>
</div>
<div class="why">
<h3>What's happening</h3>

A real, unedited trajectory. The model hits three distinct obstacles — a merge conflict, a missing editor, and a CLI flag being mis-parsed — and **reasons its way around each**, verifying before it declares done.

This is genuine problem-solving, not pattern-matching.

</div>
</div>

---

<div class="tag">08 · The frontier</div>

## Two yardsticks — read carefully

<div class="split">
<div><img src="assets/dark/frontier_context.png"></div>
<div class="why">

Our local numbers are an *easy* subset — not comparable to full leaderboards. Two public boards bracket the real gap:

- **Terminal-Bench 2.0:** best open (GLM-5, **52%**) vs frontier (Claude Opus 4.7, **90%**) — ~38 pts, but scaffold-dependent.
- **SWE-bench, same harness:** best open **75.8%** vs frontier **76.8%** — **~1 pt**.

</div>
</div>

<div class="take">Open models can already <b>write the fix</b> (≈1-pt gap); the frontier lead is in <b>driving the loop</b> (≈38 pts). "Almost there" is a discipline gap, not a knowledge gap.</div>

---

<div class="tag">09 · Efficiency</div>

## Sparsity is the on-device unlock

<div class="split">
<div><img src="assets/dark/throughput_by_model.png"></div>
<div class="why">

Throughput tracks **active** parameters, not total size. Sparse Mixture-of-Experts models activate only ~3B parameters per token:

- **Sparse MoE (~3B active):** 43–72 tok/s.
- **Dense models** of similar quality: 12–27 tok/s.

A router picks a few experts per token, so a 35B-capacity model costs ~3B-worth of compute — and 128 GB of unified memory holds the whole expert pool.

</div>
</div>

<div class="take">Sparsity + unified memory is AMD's structural advantage: the capacity of a large model at the compute of a small one.</div>

---

<div class="tag">10 · Efficiency</div>

## Intelligence per watt

<div class="split">
<div><img src="assets/dark/ipw_trend.png"></div>
<div class="why">

*Intelligence per watt* = task accuracy per unit of power — the metric of the AI-PC era (Saad-Falcon et al. 2025).

- On-device generation lands at **~0.66–1.1 tokens/joule** (Ryzen AI MAX+ 395 envelope).
- Local efficiency rose **×5.3 in two years**; coverage 23% → 71%.

Our snapshot is one point on a steep curve — competitive *because* of the hardware, not despite it.

</div>
</div>

<div class="take">The trend is the product: investments in scaffolding compound with a curve that is moving fast in AMD's favor.</div>

---

<div class="tag">11 · How they fail</div>

## The bottleneck is discipline, not coding

<div class="split">
<div><img src="assets/dark/failure_modes.png"></div>
<div class="why">

We mined every valid trajectory and verified each failure against the raw generation:

- **Doom-loop (21%)** — repeating an action until truncated.
- **Malformed action (12%)** — output the harness can't parse.
- **False completion / reasoning-burn / truncation** — the rest.

These are *agentic discipline* failures — loop control, output format, knowing when you're done — not raw coding ability.

</div>
</div>

<div class="take">Most of this budget is recoverable in the harness: loop-detection, format enforcement, and a completion gate.</div>

---

<div class="tag">12 · Evidence — failure</div>

## The doom-loop

<div class="split">
<div class="agent-trace">
<div class="at-head"><span class="dot">●</span> <span class="task">headless-terminal</span> · terminus-2 · Qwen3-Coder-Next-FP8 <span class="verdict fail">REWARD 0 · LOOP</span></div>
<div class="at-body">
<div class="turn loop"><div class="ep">ep 0</div><div>
<div class="analysis">"I'll implement the HeadlessTerminal class… Let me start by exploring the codebase."</div>
<div class="loop-cmd">&lt;tool_call&gt; function=glob(pattern="**/*.py")<br>&lt;tool_call&gt; function=glob(pattern="**/base*.py")<br>&lt;tool_call&gt; function=glob(pattern="**/terminal*.py")</div>
<div class="loop-mark">⟲ &lt;tool_call&gt; emitted ×1,485 — until the 16,384-token cap</div>
</div></div>
</div>
<div class="at-foot"><b>All 7 turns ended this way</b> · 114,688 tokens burned · reward 0</div>
</div>
<div class="why">
<h3>What's happening</h3>

A coherent opening collapses into the **same tool call repeated ~1,500 times** until the context cap — and the model never recovers.

This is the agentic echo of neural-text degeneration (Holtzman et al. 2020): the upside (decisive reasoning) and this failure are two sides of the same model.

</div>
</div>

---

<div class="tag">13 · Evidence — failure</div>

## Confidently wrong

<div class="split">
<div class="agent-trace">
<div class="at-head"><span class="dot">●</span> <span class="task">pypi-server</span> · openhands · GLM-4.7-Flash <span class="verdict fail">REWARD 0 · FALSE COMPLETION</span></div>
<div class="at-body">
<div class="turn"><div class="ep">ep 91</div><div>
<div class="quote">"I have <b style="color:#FF5A4D">successfully completed the task!</b> Here's what was accomplished:<br>1. Created the <b>vectorops</b> package with a <b>dotproduct</b> function…<br>2. Built the package…"</div>
<span class="flag warn">verifier reward: 0 — the package was never correctly built</span>
</div></div>
</div>
<div class="at-foot">Declared success after <b>92 turns</b> · reward 0</div>
</div>
<div class="why">
<h3>What's happening</h3>

The most product-dangerous mode: a confident, detailed declaration of success on a task the verifier scores **0**.

False completion is a **calibration signal** — the strongest models almost never do it (Huang et al. 2024). A verifier gate before "done" would catch it.

</div>
</div>

---

<div class="tag">14 · Both sides</div>

## Two sides of the same models

<div class="split">
<div class="agent-trace">
<div class="at-head"><span class="dot">●</span> <span class="task">prove-plus-comm</span> · terminus-2 · gpt-oss-120b <span class="verdict pass">REWARD 1.0 · PASS</span></div>
<div class="at-body">
<div class="turn"><div class="ep">ep 1</div><div><div class="analysis">"A single Coq file plus_comm.v — inspect it and supply the missing proof tactics."</div><div class="cmd">cat plus_comm.v</div></div></div>
<div class="turn"><div class="ep">ep 2</div><div><div class="analysis">"Write a complete inductive proof of addition commutativity, then compile it."</div><div class="cmd">cat > plus_comm.v &lt;&lt; 'EOF' … Qed. EOF ; coqc plus_comm.v</div></div></div>
<div class="turn"><div class="ep">ep 3</div><div><div class="analysis">"Compiled cleanly with coqc — no errors. The proof is complete."</div><span class="flag done">is_task_complete: true</span></div></div>
</div>
<div class="at-foot">A compiling <b>Coq proof in 4 turns</b> · reward 1.0</div>
</div>
<div class="why">
<h3>The same model, both ways</h3>

gpt-oss-120b writes a complete, **compiling formal proof** of addition commutativity in four turns — decisive theorem-proving, on-device.

Decisive enough to prove a theorem; undisciplined enough to abort early elsewhere. **Both are real** — this report documents the strengths and the weaknesses.

</div>
</div>

---

<div class="tag">15 · The platform</div>

## Explore every result

<div class="split">
<div><img src="assets/dashboard/capability.png"></div>
<div class="why">
<h3>The interactive dashboard</h3>

Not a static chart pile — an explorable instrument:

- **Capability, efficiency, per-watt, failure modes** as live tabs.
- **Drill down**: a model → a trajectory → a single generation.
- Validity-filtered by default; nothing overwhelming.

To be **hosted live** so anyone on the team can interrogate the data.

</div>
</div>

<div class="take">Code (the harness), dashboard, report, and deck — one shared design system, all from the validated data.</div>

---

<div class="tag">16 · Implications</div>

## What this means for <span class="amd">AMD</span>

<div class="box3">
<div class="b red"><div class="h">Hardware</div><div class="n">MoE</div><p>Lead the on-device agent story with ~30B-class sparse MoE on unified memory — capability <i>and</i> efficiency.</p></div>
<div class="b steel"><div class="h">Software</div><div class="n">Harness</div><p>Make the scaffold a product: loop-detection, format enforcement, completion gating recover most failures.</p></div>
<div class="b dim"><div class="h">Timing</div><div class="n">×5.3</div><p>The capability gap is discipline, and it closes fast. Invest where it compounds with the curve.</p></div>
</div>

The headline configuration is unambiguous today: **terminus-2 + Qwen3.5-35B-A3B**, ~30B-class sparse MoE at Q4 or better. Everything dense is a poor on-device fit; the cloud open models are higher-ceiling but 3–10× more expensive per task and unnecessary for this slice.

<div class="take">The hardware is ready. The agent loop is the frontier — and it is a tractable, fast-moving target.</div>

---

<!-- _class: divider -->
<!-- _paginate: false -->
<!-- _footer: '' -->

<div class="lead-num">Conclusion</div>

# Almost there — not parity, but **trajectory.** And the slope is the story.

<div class="sub">A 30B-class sparse model on a single AMD APU already clears 84% of the easy slice. The remaining gap is agentic discipline — closing fast on hardware built for it.</div>

---

<!-- _class: lead -->
<!-- _paginate: false -->
<!-- _footer: '' -->

<img class="logo" src="assets/brand/amd-white.png">

# Thank you

<div class="by">Harsh Singh<span class="sub">Research &amp; Advanced Development, AMD &nbsp;·&nbsp; platform, dashboard, report &amp; data — reproducible end-to-end</span></div>
