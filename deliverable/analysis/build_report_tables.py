#!/usr/bin/env python3
"""
build_report_tables.py — compute every table the comprehensive report needs, from the
VALID-only dataset, and print them as Markdown. Mirrors (and extends) the structure of a
dense trajectory-analysis report: agent comparison, per-run results, terminal-state failure
counts, premature-success-by-model, token efficiency, pass-vs-fail token spend, step-count
analysis, task difficulty, and model profiles.

Steps/tokens are only logged for terminus-2 and openhands; qwen-coder produces graded rewards
but no structured timing logs, so it appears in capability tables and is marked "—" elsewhere.
"""
import csv
from collections import defaultdict
from pathlib import Path
from statistics import median, mean
import pandas as pd

DATA = Path(__file__).resolve().parent / "data"
OUT = Path(__file__).resolve().parent / "report_tables.md"

valid = pd.read_csv(DATA / "trials_valid.csv")
calls = pd.read_csv(DATA / "calls.csv")
validity = pd.read_csv(DATA / "validity.csv")
fail_model = pd.read_csv(DATA / "failures_by_model.csv")

valid["passed"] = valid["passed"].astype(int)
valid["n_calls"] = valid["n_calls"].astype(int)
valid["sum_completion_tokens"] = valid["sum_completion_tokens"].astype(float)

# per-trial model time (s) = sum(predicted_ms + prompt_ms) across calls
calls["_mt"] = calls[["predicted_ms", "prompt_ms"]].fillna(0).sum(axis=1)
mt = calls.groupby(["run_name", "trial"])["_mt"].sum().div(1000).rename("model_time_s")
valid = valid.merge(mt, on=["run_name", "trial"], how="left")

LOGGED = valid["agent"].isin(["terminus-2", "openhands"])  # agents that log steps/tokens
out = []
def w(s=""): out.append(s)
def tbl(headers, rows):
    w("| " + " | ".join(headers) + " |")
    w("|" + "|".join("---" for _ in headers) + "|")
    for r in rows:
        w("| " + " | ".join(str(x) for x in r) + " |")
    w("")

def run_tag(run):
    return run  # run_name already compact (agent-model-...); keep as-is

# terminal-state per trial (from logged columns, no content re-read)
def terminal_state(row):
    if row["passed"] == 1:
        return "pass"
    if row["agent"] in ("terminus-2", "openhands") and row["n_calls"] == 0:
        return "no_agent_steps"
    if row["agent"] in ("terminus-2", "openhands") and row["sum_completion_tokens"] < 50:
        return "minimal_output"
    if row.get("n_truncated", 0) and row["n_truncated"] > 0:
        return "looped_truncated"
    return "ran_without_solving"
valid["state"] = valid.apply(terminal_state, axis=1)

# ---------- 1. Agent comparison ----------
w("## Agent comparison\n")
rows = []
for ag, g in valid.groupby("agent"):
    logged = ag in ("terminus-2", "openhands")
    n, p = len(g), int(g["passed"].sum())
    rows.append([ag, n, p, f"{p/n*100:.0f}%",
                 f"{g['n_calls'].mean():.1f}" if logged else "—",
                 f"{g['sum_completion_tokens'].mean():,.0f}" if logged else "—",
                 f"{g['model_time_s'].mean():.0f}s" if logged else "—"])
rows.sort(key=lambda r: -float(r[3].rstrip('%')))
tbl(["Agent", "Valid trials", "Passes", "Pass rate", "Avg steps", "Avg comp tok", "Avg model-time"], rows)

# ---------- 2. Per-run results ----------
for ag in ["terminus-2", "openhands", "qwen-coder"]:
    sub = valid[valid["agent"] == ag]
    if not len(sub):
        continue
    w(f"### Per-run results — {ag}\n")
    rows = []
    for run, g in sub.groupby("run_name"):
        n, p = len(g), int(g["passed"].sum())
        top = g[g["passed"] == 0]["state"].value_counts()
        topf = top.index[0] if len(top) else "—"
        steps = f"{g['n_calls'].mean():.1f}" if ag in ("terminus-2", "openhands") else "—"
        rows.append([run.replace(f"{ag}-", ""), n, p, f"{p/n*100:.0f}%", steps, topf, p/n])
    rows.sort(key=lambda r: -r[-1])
    tbl(["Run", "N", "Pass", "Pass%", "Avg steps", "Top failure"], [r[:-1] for r in rows])

# ---------- 3. Terminal-state failure counts per agent ----------
w("## Terminal-state failure taxonomy\n")
for ag in ["terminus-2", "openhands"]:
    sub = valid[(valid["agent"] == ag) & (valid["passed"] == 0)]
    vc = sub["state"].value_counts()
    tot = int(vc.sum())
    w(f"**{ag}** — {tot} failures (valid)\n")
    tbl(["State", "Count", "% of failures"],
        [[s, c, f"{c/tot*100:.0f}%"] for s, c in vc.items()])

# ---------- 4. Premature success by model (terminus-2) ----------
w("## Premature success declarations by model (terminus-2)\n")
rows = []
fm = fail_model[fail_model["agent"] == "terminus-2"]
for _, r in fm.iterrows():
    g = valid[(valid["model"] == r["model"]) & (valid["agent"] == "terminus-2")]
    fails = int((g["passed"] == 0).sum())
    prem = round(r["false_completion_rate"] * r["n_valid"])
    if fails == 0:
        continue
    rows.append([r["model"], fails, prem, f"{prem/fails*100:.0f}%", prem/max(fails,1)])
rows.sort(key=lambda x: -x[-1])
tbl(["Model", "Failures", "Premature decl.", "% of failures"], [r[:-1] for r in rows])

# ---------- 5. Token efficiency ----------
w("## Token efficiency (logged agents)\n")
rows = []
for model, g in valid[LOGGED].groupby("model"):
    if len(g) < 5:
        continue
    pr = g["passed"].mean()
    mct = g["sum_completion_tokens"].mean()
    if mct <= 0:
        continue
    rows.append([model, f"{pr*100:.0f}%", f"{mct:,.0f}", round(pr*1000/mct, 3)])
rows.sort(key=lambda x: -x[3])
tbl(["Model", "Pass rate", "Mean comp tok", "Efficiency (pass·1000/tok)"], rows)

# pass vs fail token spend
w("### Passing vs failing token spend\n")
rows = []
for model, g in valid[LOGGED].groupby("model"):
    pg, fg = g[g["passed"] == 1], g[g["passed"] == 0]
    if len(pg) < 2 or len(fg) < 2:
        continue
    pa, fa = pg["sum_completion_tokens"].mean(), fg["sum_completion_tokens"].mean()
    rows.append([model, f"{pa:,.0f}", f"{fa:,.0f}", f"{fa/pa:.1f}×" + (" (fails fast)" if fa < pa else ""), fa/pa])
rows.sort(key=lambda x: -x[-1])
tbl(["Model", "Pass avg tok", "Fail avg tok", "Ratio"], [r[:-1] for r in rows])

# ---------- 6. Step-count analysis ----------
w("## Step-count analysis\n")
rows = []
for ag in ["terminus-2", "openhands"]:
    g = valid[valid["agent"] == ag]
    pg, fg = g[g["passed"] == 1]["n_calls"], g[g["passed"] == 0]["n_calls"]
    rows.append([ag, int(g["n_calls"].median()), f"{g['n_calls'].mean():.1f}",
                 f"{pg.mean():.1f}" if len(pg) else "—", f"{fg.mean():.1f}" if len(fg) else "—",
                 int(g["n_calls"].max())])
tbl(["Agent", "Median", "Mean", "Pass mean", "Fail mean", "Max"], rows)

w("### Step count by model (terminus-2)\n")
rows = []
for model, g in valid[valid["agent"] == "terminus-2"].groupby("model"):
    if len(g) < 5:
        continue
    pg, fg = g[g["passed"] == 1]["n_calls"], g[g["passed"] == 0]["n_calls"]
    tps = g["sum_completion_tokens"].sum() / max(g["n_calls"].sum(), 1)
    rows.append([model, f"{pg.mean():.1f}" if len(pg) else "—",
                 f"{fg.mean():.1f}" if len(fg) else "—", f"{tps:,.0f}", g["passed"].mean()])
rows.sort(key=lambda x: -x[-1])
tbl(["Model", "Pass steps", "Fail steps", "Tok/step"], [r[:-1] for r in rows])

# ---------- 7. Task difficulty ----------
w("## Task difficulty (valid trials, ≥3 attempts)\n")
rows = []
for task, g in valid.groupby("task"):
    if len(g) < 3:
        continue
    n, p = len(g), int(g["passed"].sum())
    rows.append([task, n, p, p/n])
rows.sort(key=lambda x: x[-1])
w("**Hardest (lowest pass rate):**\n")
tbl(["Task", "Attempts", "Passes", "Pass%"], [[t, n, p, f"{r*100:.0f}%"] for t, n, p, r in rows[:10]])
w("**Easiest (highest pass rate):**\n")
tbl(["Task", "Attempts", "Passes", "Pass%"], [[t, n, p, f"{r*100:.0f}%"] for t, n, p, r in rows[-8:][::-1]])

# ---------- 8. Validity / infrastructure accounting ----------
w("## Validity & infrastructure accounting\n")
vc = validity["reason"].value_counts()
tbl(["Reason", "Trials"], [[k, int(v)] for k, v in vc.items()])

OUT.write_text("\n".join(out) + "\n")
print(f"wrote {OUT}")
print(f"valid={len(valid)} agents={valid['agent'].nunique()} models={valid['model'].nunique()} tasks={valid['task'].nunique()}")
# echo to stdout too
print("\n" + "\n".join(out))
