#!/usr/bin/env python3
"""
build_dashboard_data.py — bundle the validated analysis into one JSON the interactive
dashboard consumes. Includes config leaderboard, model×agent matrix, throughput, per-watt,
failure taxonomy + quoted examples, validity accounting, and a few full "spotlight"
trajectories for drill-down.
"""
import csv, json, re
from collections import defaultdict, Counter
from pathlib import Path
from statistics import median
from extract_metrics import response_from_call
from mine_failures import build_index, ordered_calls, content_and_finish, parse_command, intragen_loop

ANALYSIS = Path(__file__).resolve().parent
DATA = ANALYSIS / "data"
OUT = ANALYSIS.parents[1] / "dashboard" / "dashboard_data.json"

W_SUSTAIN = 65
IPW = {"years": [2023, 2025], "coverage": [23.2, 71.3], "mult": 5.3,
       "source": "Intelligence per Watt, arXiv:2511.07885 (Stanford Hazy + Together AI)"}
TB2 = {"open_best": 52, "frontier": 88, "note": "full Terminal-Bench 2.0 public leaderboard"}


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def main():
    trials = list(csv.DictReader(open(DATA / "trials.csv")))
    valid = list(csv.DictReader(open(DATA / "trials_valid.csv")))
    validity = list(csv.DictReader(open(DATA / "validity.csv")))
    calls = list(csv.DictReader(open(DATA / "calls.csv")))
    fail_model = list(csv.DictReader(open(DATA / "failures_by_model.csv")))
    fail_ex = json.load(open(DATA / "failure_examples.json"))

    # ---- config leaderboard (valid only) ----
    cfg = defaultdict(lambda: {"n": 0, "p": 0})
    meta = {}
    for t in valid:
        k = t["run_name"]
        cfg[k]["n"] += 1
        cfg[k]["p"] += int(t["passed"])
        meta[k] = (t["agent"], t["model"], t["backend"])
    # per-run median tok/s from calls
    tokrun = defaultdict(list)
    for c in calls:
        g = f(c["gen_tok_s"])
        if g and g > 0:
            tokrun[c["run_name"]].append(g)
    configs = []
    for k, v in cfg.items():
        if v["n"] < 5:
            continue
        ag, mo, be = meta[k]
        med = round(median(tokrun[k]), 1) if tokrun[k] else None
        configs.append({
            "run": k, "agent": ag, "model": mo, "backend": be,
            "n": v["n"], "pass": v["p"], "rate": round(v["p"] / v["n"] * 100, 1),
            "tok_s": med, "tokens_per_joule": round(med / W_SUSTAIN, 3) if med else None})
    configs.sort(key=lambda x: -x["rate"])

    # ---- model x agent matrix (local) ----
    cell = defaultdict(lambda: {"n": 0, "p": 0})
    models, agents = set(), set()
    for t in valid:
        if t["backend"] != "local":
            continue
        cell[(t["model"], t["agent"])]["n"] += 1
        cell[(t["model"], t["agent"])]["p"] += int(t["passed"])
        models.add(t["model"]); agents.add(t["agent"])
    matrix = {"models": sorted(models), "agents": sorted(agents), "cells": []}
    for (m, a), v in cell.items():
        matrix["cells"].append({"model": m, "agent": a, "n": v["n"],
                                "rate": round(v["p"] / v["n"] * 100, 1)})

    # ---- throughput per model (local) ----
    tokmodel = defaultdict(list)
    valset = {(t["run_name"], t["trial"]) for t in valid if t["backend"] == "local"}
    for c in calls:
        if (c["run_name"], c["trial"]) in valset:
            g = f(c["gen_tok_s"])
            if g and g > 0:
                tokmodel[c["model"]].append(g)
    throughput = []
    for m, vals in tokmodel.items():
        if len(vals) < 20:
            continue
        vals.sort()
        throughput.append({"model": m, "median": round(median(vals), 1),
                           "p10": round(vals[len(vals)//10], 1), "p90": round(vals[len(vals)*9//10], 1),
                           "n": len(vals), "dense": median(vals) < 30,
                           "tokens_per_joule": round(median(vals) / W_SUSTAIN, 3)})
    throughput.sort(key=lambda x: -x["median"])

    # ---- failure taxonomy ----
    n_valid = len(valid)
    agg = defaultdict(int)
    keymap = {"truncation_rate": "truncation", "malformed_rate": "malformed",
              "doom_loop_rate": "doom_loop", "false_completion_rate": "false_completion",
              "reasoning_burn_rate": "reasoning_burn"}
    for r in fail_model:
        for col, mode in keymap.items():
            agg[mode] += round(float(r[col]) * int(r["n_valid"]))
    failures = {"overall": {m: {"n": agg[m], "rate": round(agg[m] / n_valid * 100, 1)} for m in agg},
                "by_model": fail_model, "examples": fail_ex}

    # ---- validity accounting ----
    vc = Counter(t["reason"] for t in validity)
    infra = [{"run": t["run_name"], "task": t["task"], "tok_s": f(t["weighted_gen_tok_s"]),
              "baseline": f(t["model_baseline"])} for t in validity if t["reason"] == "infra_slow"]
    validity_out = {"total": len(validity), "counts": dict(vc), "infra_slow": infra}

    # ---- spotlight trajectories (drill-down) ----
    idx = build_index()

    def spotlight(model, task, want):
        # find a valid trial matching model+task with the wanted property
        cands = [t for t in valid if t["model"] == model and t["task"] == task]
        cands.sort(key=lambda t: -int(t["passed"]) if want == "pass" else int(t["passed"]))
        for t in cands:
            d = idx.get((t["run_name"], t["trial"]))
            if not d:
                continue
            eps = []
            for i, cf in enumerate(ordered_calls(d)[:14]):
                content, finish = content_and_finish(cf)
                cmd, done, ok = parse_command(content)
                loop = intragen_loop(content)
                eps.append({"i": i, "finish": finish, "command": (cmd or "")[:180],
                            "done": bool(done), "malformed": (t["agent"] == "terminus-2" and not ok and len(content.strip()) > 10),
                            "loop": bool(loop),
                            "snippet": content[:240].replace("\n", " ").strip()})
            return {"run": t["run_name"], "agent": t["agent"], "model": model, "task": task,
                    "reward": f(t["reward"]), "episodes": eps}
        return None

    spots = []
    for m, tk, w in [("Qwen3.5-35B-A3B", "fix-git", "pass"),
                     ("Llama-3.1-8B-Instruct", "pypi-server", "fail"),
                     ("GLM-4.7-Flash", "headless-terminal", "fail"),
                     ("phi-4", "cobol-modernization", "fail")]:
        s = spotlight(m, tk, w)
        if s:
            spots.append(s)

    best_local = max((c["rate"] for c in configs if c["backend"] == "local"), default=0)
    # scope metrics — magnitude of the study (valid runs)
    valset_all = {(t["run_name"], t["trial"]) for t in valid}
    gen_tok = proc_tok = n_valid_calls = 0
    for c in calls:
        if (c["run_name"], c["trial"]) in valset_all:
            ct, pt = f(c["completion_tokens"]) or 0, f(c["prompt_tokens"]) or 0
            gen_tok += ct; proc_tok += ct + pt; n_valid_calls += 1
    scope = {"trials_run": len(trials), "valid_trials": n_valid,
             "agent_steps": n_valid_calls, "tokens_generated": int(gen_tok),
             "tokens_processed": int(proc_tok), "models": len(set(t["model"] for t in valid)),
             "agents": len(set(t["agent"] for t in valid))}
    bundle = {
        "meta": {"trials_total": len(trials), "valid": n_valid,
                 "calls": len(calls), "best_local_rate": best_local,
                 "power_w": W_SUSTAIN, "ipw": IPW, "tb2": TB2, "scope": scope},
        "configs": configs, "matrix": matrix, "throughput": throughput,
        "failures": failures, "validity": validity_out, "spotlights": spots,
    }
    OUT.write_text(json.dumps(bundle, indent=1))
    # JS wrapper so the dashboard opens straight from file:// (no server/CORS needed)
    (OUT.with_suffix(".js")).write_text("window.DASH_DATA = " + json.dumps(bundle) + ";\n")
    print(f"wrote {OUT}  ({OUT.stat().st_size//1024} KB)  + dashboard_data.js")
    print(f"  configs={len(configs)} throughput={len(throughput)} spotlights={len(spots)}"
          f" best_local={best_local}%")


if __name__ == "__main__":
    main()
