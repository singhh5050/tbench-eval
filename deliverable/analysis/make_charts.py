#!/usr/bin/env python3
"""
make_charts.py — generate the figure set (dark + light skins) from VALID-only data.

Charts:
  capability_configs   best model x agent configs by valid pass rate (the hero)
  heatmap              model x agent pass-rate grid
  throughput_by_model  generation tok/s per model (MoE-A3B vs dense)
  frontier_context     our easy slice vs full-benchmark leaderboard (clearly separated)
  ipw_trend            local-intelligence trend (why the gap closes) — cited
  tokens_per_joule     per-model efficiency at the AMD power envelope
  efficiency_frontier  pass-rate vs throughput scatter

All capability numbers are the curated EASY slice and are never conflated with the
full Terminal-Bench 2.0 leaderboard.
"""
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import amd_style as S

DATA = Path(__file__).resolve().parent / "data"

# ---- research constants (documented; see deliverable/research_notes.md) ----
# Intelligence per Watt, arXiv:2511.07885 (Stanford Hazy + Together AI)
IPW_YEARS = [2023, 2025]
IPW_COVERAGE = [23.2, 71.3]          # % of real-world queries local models answer accurately
IPW_MULT = 5.3                       # intelligence-per-watt improvement 2023->2025
# Terminal-Bench 2.0 official leaderboard, full benchmark (tbench.ai, pulled 2026-05-31)
TB2_OPEN_BEST = 52.4                 # GLM-5 (Z.ai), Terminus 2 scaffold
TB2_FRONTIER = 90.2                  # Claude Opus 4.7 (Anthropic), vix agent
# AMD Ryzen AI MAX+ 395 power envelope (AMD cTDP + Notebookcheck measured)
W_SUSTAIN = 65                       # sustained inference bracket (55 default .. 86 peak)

df = pd.read_csv(DATA / "trials_valid.csv")
calls = pd.read_csv(DATA / "calls.csv")
df["passed"] = df["passed"].astype(int)


def red_cmap(c):
    return LinearSegmentedColormap.from_list("amdred", [c["panel"], S.RED_DP, S.RED])


def config_label(run, agent, model):
    return f"{agent} · {model}"


# ---------- 1. capability by config (hero) ----------
def capability_configs(themename):
    c = S.theme(themename)
    g = (df.groupby(["run_name", "agent", "model", "backend"])
           .agg(n=("passed", "size"), p=("passed", "sum")).reset_index())
    g = g[g["n"] >= 5].copy()
    g["rate"] = g["p"] / g["n"] * 100
    # best config per (agent,model) dedup: keep highest-n run
    g = g.sort_values("n", ascending=False).drop_duplicates(["agent", "model"])
    g = g.sort_values("rate").tail(11)
    colors = [S.RED if b == "local" else S.STEEL for b in g["backend"]]
    fig, ax = plt.subplots(figsize=(9, 5.6))
    y = np.arange(len(g))
    ax.barh(y, g["rate"], color=colors, height=0.66, zorder=3)
    ax.set_yticks(y)
    ax.set_yticklabels([config_label(r, a, m) for r, a, m in zip(g["run_name"], g["agent"], g["model"])],
                       fontsize=10.5)
    for yi, (rate, n, p) in enumerate(zip(g["rate"], g["n"], g["p"])):
        ax.text(rate + 1.5, yi, f"{rate:.0f}%  ({p}/{n})", va="center", ha="left",
                color=c["ink"], fontsize=10, fontweight="bold")
    ax.set_xlim(0, 100); ax.set_xlabel("pass rate  ·  easy agentic terminal tasks")
    ax.set_title("What to run on AMD today — best model × agent  (valid runs)",
                 fontsize=14, fontweight="bold", loc="left", pad=12)
    ax.spines["left"].set_visible(False)
    # legend
    ax.scatter([], [], color=S.RED, label="local (on-device)", s=60)
    ax.scatter([], [], color=S.STEEL, label="open model via API", s=60)
    ax.legend(loc="lower right", frameon=False, fontsize=10)
    S.save(fig, "capability_configs", themename)


# ---------- 2. heatmap model x agent ----------
def heatmap(themename):
    c = S.theme(themename)
    loc = df[df["backend"] == "local"]
    piv = loc.pivot_table(index="model", columns="agent", values="passed", aggfunc="mean")
    cnt = loc.pivot_table(index="model", columns="agent", values="passed", aggfunc="size")
    piv = piv.reindex(piv.mean(axis=1).sort_values().index)
    fig, ax = plt.subplots(figsize=(7.6, 7.2))
    data = piv.values * 100
    im = ax.imshow(np.ma.masked_invalid(data), cmap=red_cmap(c), vmin=0, vmax=100, aspect="auto")
    ax.set_xticks(range(len(piv.columns))); ax.set_xticklabels(piv.columns, rotation=0, fontsize=10)
    ax.set_yticks(range(len(piv.index))); ax.set_yticklabels(piv.index, fontsize=9.5)
    for i in range(piv.shape[0]):
        for j in range(piv.shape[1]):
            v = data[i, j]
            if not np.isnan(v):
                ax.text(j, i, f"{v:.0f}", ha="center", va="center",
                        color="#fff" if v > 45 else c["ink_dim"], fontsize=10, fontweight="bold")
    ax.set_title("Pass rate (%) · local model × agent", fontsize=13, fontweight="bold", loc="left", pad=10)
    ax.grid(False)
    cb = fig.colorbar(im, ax=ax, fraction=0.045, pad=0.03); cb.outline.set_visible(False)
    S.save(fig, "heatmap", themename)


# ---------- 3. throughput by model ----------
def throughput_by_model(themename):
    c = S.theme(themename)
    cl = calls.merge(df[["run_name", "trial"]].drop_duplicates(), on=["run_name", "trial"])
    cl = cl[(cl["backend"] == "local") & cl["gen_tok_s"].notna() & (cl["gen_tok_s"] > 0)]
    order = cl.groupby("model")["gen_tok_s"].median().sort_values()
    order = order[cl.groupby("model")["gen_tok_s"].size() >= 20]
    fig, ax = plt.subplots(figsize=(9, 5.8))
    for i, m in enumerate(order.index):
        vals = cl[cl["model"] == m]["gen_tok_s"].values
        x = np.random.default_rng(i).normal(i, 0.06, len(vals))
        dense = order[m] < 30
        ax.scatter(vals, x * 0 + i + np.random.default_rng(i + 1).uniform(-0.16, 0.16, len(vals)),
                   s=7, alpha=0.35, color=S.STEEL if dense else S.RED, zorder=2)
        ax.scatter(order[m], i, s=70, color=c["ink"], zorder=4, marker="|")
        ax.text(order[m], i + 0.28, f"{order[m]:.0f}", ha="center", color=c["ink"], fontsize=9, fontweight="bold")
    ax.set_yticks(range(len(order))); ax.set_yticklabels(order.index, fontsize=9.5)
    ax.set_xlabel("generation throughput  (tok/s, on-device)")
    ax.set_title("Throughput per model — sparse MoE-A3B vs dense", fontsize=13, fontweight="bold", loc="left", pad=10)
    ax.scatter([], [], color=S.RED, label="sparse MoE (≈3B active)", s=40)
    ax.scatter([], [], color=S.STEEL, label="dense (slower, valid)", s=40)
    ax.legend(loc="lower right", frameon=False, fontsize=9.5)
    S.save(fig, "throughput_by_model", themename)


# ---------- 4. frontier context ----------
def frontier_context(themename):
    c = S.theme(themename)
    # best local valid config
    g = (df[df.backend == "local"].groupby(["agent", "model"])
         .agg(n=("passed", "size"), p=("passed", "sum")).reset_index())
    g = g[g.n >= 5]; best = (g.p / g.n * 100).max()
    fig, ax = plt.subplots(figsize=(8.4, 5.2))
    labels = ["Best AMD-local\n(our easy slice)", "GLM-5\n(best open · TB-2.0)", "Claude Opus 4.7\n(frontier · TB-2.0)"]
    vals = [best, TB2_OPEN_BEST, TB2_FRONTIER]
    cols = [S.RED, S.STEEL, c["ink_dim"]]
    bars = ax.bar(labels, vals, color=cols, width=0.6, zorder=3)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width()/2, v + 2, f"{v:.0f}%", ha="center", color=c["ink"], fontweight="bold")
    ax.set_ylim(0, 105); ax.set_ylabel("pass rate")
    ax.set_title("Two different yardsticks — read carefully", fontsize=13, fontweight="bold", loc="left", pad=10)
    S.save(fig, "frontier_context", themename)


# ---------- 5. intelligence-per-watt trend ----------
def ipw_trend(themename):
    c = S.theme(themename)
    fig, ax = plt.subplots(figsize=(8.4, 5.0))
    ax.plot(IPW_YEARS, IPW_COVERAGE, color=S.RED, lw=2.6, marker="o", ms=9, zorder=4)
    ax.fill_between(IPW_YEARS, IPW_COVERAGE, color=S.RED, alpha=0.12, zorder=1)
    for x, yv in zip(IPW_YEARS, IPW_COVERAGE):
        ax.text(x, yv + 4, f"{yv:.0f}%", ha="center", color=c["ink"], fontweight="bold")
    ax.annotate(f"intelligence-per-watt  ×{IPW_MULT}\n(2023 → 2025)",
                xy=(2024, 47), color=S.STEEL, fontsize=11, ha="center", fontweight="bold")
    ax.set_xticks(IPW_YEARS); ax.set_ylim(0, 100)
    ax.set_ylabel("% of queries local models answer")
    ax.set_title("Why “almost” keeps shrinking", fontsize=13, fontweight="bold", loc="left", pad=10)
    S.save(fig, "ipw_trend", themename)


# ---------- 6. tokens per joule ----------
def tokens_per_joule(themename):
    c = S.theme(themename)
    cl = calls.merge(df[["run_name", "trial"]].drop_duplicates(), on=["run_name", "trial"])
    cl = cl[(cl.backend == "local") & cl.gen_tok_s.notna() & (cl.gen_tok_s > 0)]
    med = cl.groupby("model")["gen_tok_s"].median()
    med = med[cl.groupby("model")["gen_tok_s"].size() >= 20].sort_values()
    tpj = med / W_SUSTAIN
    fig, ax = plt.subplots(figsize=(9, 5.4))
    y = np.arange(len(tpj))
    ax.barh(y, tpj.values, color=[S.STEEL if v < 30 else S.RED for v in med.values], height=0.66, zorder=3)
    ax.set_yticks(y); ax.set_yticklabels(tpj.index, fontsize=9.5)
    for yi, v in enumerate(tpj.values):
        ax.text(v + 0.01, yi, f"{v:.2f}", va="center", color=c["ink"], fontsize=9.5, fontweight="bold")
    ax.set_xlabel(f"tokens per joule  (median tok/s ÷ {W_SUSTAIN} W sustained)")
    ax.set_title("Generation efficiency on the AMD power envelope", fontsize=13, fontweight="bold", loc="left", pad=10)
    ax.spines["left"].set_visible(False)
    S.save(fig, "tokens_per_joule", themename)


# ---------- 7. efficiency frontier ----------
def efficiency_frontier(themename):
    c = S.theme(themename)
    loc = df[df.backend == "local"]
    cl = calls.merge(df[["run_name", "trial"]].drop_duplicates(), on=["run_name", "trial"])
    cl = cl[(cl.backend == "local") & cl.gen_tok_s.notna() & (cl.gen_tok_s > 0)]
    tok = cl.groupby("model")["gen_tok_s"].median()
    cap = loc.groupby("model")["passed"].mean() * 100
    n = loc.groupby("model")["passed"].size()
    models = [m for m in cap.index if m in tok.index and n[m] >= 8]
    fig, ax = plt.subplots(figsize=(8.6, 6.0))
    for m in models:
        ax.scatter(tok[m], cap[m], s=40 + n[m] * 9, color=S.RED, alpha=0.85, edgecolor=c["bg"], zorder=3)
        ax.annotate(m, (tok[m], cap[m]), fontsize=8.5, color=c["ink_dim"],
                    xytext=(6, 4), textcoords="offset points")
    ax.set_xlabel("generation throughput (median tok/s)")
    ax.set_ylabel("pass rate (%) · easy slice")
    ax.set_title("Capability vs speed — the local frontier", fontsize=13, fontweight="bold", loc="left", pad=10)
    S.save(fig, "efficiency_frontier", themename)


def main():
    funcs = [capability_configs, heatmap, throughput_by_model, frontier_context,
             ipw_trend, tokens_per_joule, efficiency_frontier]
    for themename in ("dark", "light"):
        for fn in funcs:
            fn(themename)
        print(f"[{themename}] {len(funcs)} charts -> assets/{themename}/")


if __name__ == "__main__":
    main()
