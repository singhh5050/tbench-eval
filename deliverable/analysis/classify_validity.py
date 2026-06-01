#!/usr/bin/env python3
"""
classify_validity.py — split trials into VALID vs dropped (infra / integration / test).

Only VALID trials feed capability, throughput, and per-watt analysis. Dropped trials
are accounted for (count + reason) but never used as findings.

Drop rules (priority order), each trial gets exactly one `reason`:
  1. test_run        run is a test-* / cloud-test / claude-code probe (not a real sweep).
  2. agent_integration_failure
                     agent in {swe-agent, mini-swe-agent}: harness crashed before doing
                     real work (swe-agent: literal unexpanded `$(pwd)` -> NoSuchPathError;
                     mini-swe-agent: trajectories never reach an assistant turn). 0 parseable
                     generations, 0 passes -> harness maturity, not model capability.
  3. ungraded        no verifier/reward.txt -> no ground truth (env/agent error mid-run).
  4. infra_slow      generation throughput collapsed: weighted tok/s < max(ABS_FLOOR,
                     SLOW_FRAC x model_baseline). Distinguishes a *server stall* (invalid)
                     from a model that is simply slow-but-working (dense models keep their
                     own low-but-consistent baseline and are NOT dropped).
  5. valid           otherwise.

Outputs: data/validity.csv (per trial) and validity_report.md.
Also writes data/trials_valid.csv — the clean dataset for all downstream charts.
"""
import csv
from pathlib import Path
from statistics import median

DATA = Path(__file__).resolve().parent / "data"
REPORT = Path(__file__).resolve().parent / "validity_report.md"

ABS_FLOOR = 5.0     # tok/s below this = server stall regardless of model
SLOW_FRAC = 0.40    # tok/s below 40% of the model's own baseline = infra-degraded
INTEGRATION_FAIL_AGENTS = {"swe-agent", "mini-swe-agent"}


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    trials = list(csv.DictReader(open(DATA / "trials.csv")))
    for t in trials:
        t["reward_f"] = f(t["reward"])
        t["gen"] = f(t["weighted_gen_tok_s"])
        t["passed"] = int(t["passed"])
        t["graded"] = int(t["graded"])

    # Per-model throughput baseline (median over trials that *have* tok/s and are not
    # already test/integration/ungraded — i.e. plausibly-real generations).
    base_pool = {}
    for t in trials:
        run = t["run_name"]
        if run.startswith(("test-", "cloud-test")) or t["agent"] == "claude-code":
            continue
        if t["agent"] in INTEGRATION_FAIL_AGENTS:
            continue
        if t["gen"] is None:
            continue
        base_pool.setdefault(t["model"], []).append(t["gen"])
    baseline = {m: round(median(v), 2) for m, v in base_pool.items() if v}

    # Classify
    for t in trials:
        run = t["run_name"]
        t["model_baseline"] = baseline.get(t["model"])
        if run.startswith(("test-", "cloud-test")) or t["agent"] == "claude-code":
            t["reason"] = "test_run"
        elif t["agent"] in INTEGRATION_FAIL_AGENTS:
            t["reason"] = "agent_integration_failure"
        elif t["reward_f"] is None:
            t["reason"] = "ungraded"
        elif t["gen"] is not None and t["model_baseline"] and \
                t["gen"] < max(ABS_FLOOR, SLOW_FRAC * t["model_baseline"]):
            t["reason"] = "infra_slow"
        elif t["gen"] is not None and t["gen"] < ABS_FLOOR:
            t["reason"] = "infra_slow"
        else:
            t["reason"] = "valid"
        t["valid"] = int(t["reason"] == "valid")

    # write validity.csv
    cols = ["run_name", "agent", "model", "backend", "task", "trial", "reward",
            "passed", "weighted_gen_tok_s", "model_baseline", "valid", "reason"]
    with open(DATA / "validity.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
        for t in trials:
            w.writerow({k: t.get(k if k != "model_baseline" else "model_baseline") for k in cols})

    # clean valid-only trials dataset
    valid = [t for t in trials if t["valid"]]
    keep = list(csv.DictReader(open(DATA / "trials.csv")).fieldnames)
    with open(DATA / "trials_valid.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keep); w.writeheader()
        vset = {(t["run_name"], t["trial"]) for t in valid}
        for row in csv.DictReader(open(DATA / "trials.csv")):
            if (row["run_name"], row["trial"]) in vset:
                w.writerow(row)

    # ---- report ----
    from collections import Counter
    reasons = Counter(t["reason"] for t in trials)
    n = len(trials)
    lines = []
    lines.append("# Data hygiene & validity report\n")
    lines.append(f"Total trials discovered: **{n}**. "
                 f"Valid (used for all analysis): **{reasons['valid']}**. "
                 f"Dropped: **{n - reasons['valid']}**.\n")
    lines.append("## Drop accounting\n")
    lines.append("| Reason | Trials | Note |")
    lines.append("|---|---:|---|")
    notes = {
        "valid": "used for all capability / throughput / per-watt analysis",
        "agent_integration_failure": "swe-agent `$(pwd)` crash; mini-swe-agent no assistant turn",
        "infra_slow": f"gen tok/s < max({ABS_FLOOR}, {SLOW_FRAC}x model baseline) = server stall",
        "ungraded": "no verifier/reward.txt (env/agent error mid-run)",
        "test_run": "test-* / cloud-test / claude-code probes",
    }
    for r in ["valid", "agent_integration_failure", "infra_slow", "ungraded", "test_run"]:
        if reasons.get(r):
            lines.append(f"| {r} | {reasons[r]} | {notes[r]} |")
    lines.append("")
    lines.append(f"Thresholds: `ABS_FLOOR = {ABS_FLOOR}` tok/s, `SLOW_FRAC = {SLOW_FRAC}` "
                 "of each model's own median throughput.\n")

    # infra_slow detail (the interesting catches)
    slow = [t for t in trials if t["reason"] == "infra_slow"]
    if slow:
        lines.append("## Throughput-collapse trials dropped (infra_slow)\n")
        lines.append("| run | task | gen tok/s | model baseline |")
        lines.append("|---|---|---:|---:|")
        for t in sorted(slow, key=lambda x: x["gen"]):
            lines.append(f"| {t['run_name']} | {t['task']} | {t['gen']:.1f} | "
                         f"{t['model_baseline']:.1f} |")
        lines.append("")

    # per-run valid pass-rate
    lines.append("## Per-run summary (valid only)\n")
    lines.append("| run | agent | backend | valid trials | dropped | valid pass-rate |")
    lines.append("|---|---|---|---:|---:|---:|")
    runs = {}
    for t in trials:
        r = runs.setdefault(t["run_name"], {"agent": t["agent"], "backend": t["backend"],
                                            "v": 0, "d": 0, "p": 0})
        if t["valid"]:
            r["v"] += 1; r["p"] += t["passed"]
        else:
            r["d"] += 1
    for name in sorted(runs, key=lambda k: (runs[k]["v"] and runs[k]["p"]/runs[k]["v"] or 0), reverse=True):
        r = runs[name]
        pr = f"{r['p']/r['v']*100:.0f}% ({r['p']}/{r['v']})" if r["v"] else "—"
        lines.append(f"| {name} | {r['agent']} | {r['backend']} | {r['v']} | {r['d']} | {pr} |")
    REPORT.write_text("\n".join(lines) + "\n")

    print(f"Total trials: {n}")
    for r in ["valid", "agent_integration_failure", "infra_slow", "ungraded", "test_run"]:
        if reasons.get(r):
            print(f"  {r:28} {reasons[r]}")
    print(f"-> {DATA}/validity.csv, trials_valid.csv  +  {REPORT.name}")


if __name__ == "__main__":
    main()
