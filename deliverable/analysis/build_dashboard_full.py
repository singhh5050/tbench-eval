#!/usr/bin/env python3
"""
build_dashboard_full.py — export the FULL interactive dataset for the dashboard (static, so it
still hosts on Vercel): the existing summary bundle PLUS a full model×task heatmap, a complete
trials index for filtering/browsing, and the turn-by-turn trajectory for EVERY valid trial so any
one can be clicked into.

Outputs (into dashboard/):
  dashboard_data.js   window.DASH_DATA  — summary bundle + heatmap_full + trials_index
  dashboard_traj.js   window.DASH_TRAJ  — {trial_id: {meta, turns[]}} for all valid trials
"""
import csv, json, re
from collections import defaultdict
from pathlib import Path
from extract_metrics import response_from_call
from mine_failures import build_index, ordered_calls, content_and_finish, intragen_loop

ANALYSIS = Path(__file__).resolve().parent
DATA = ANALYSIS / "data"
DASH = ANALYSIS.parents[1] / "dashboard"


def f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def extract_turns(trial_dir, agent):
    turns = []
    for i, cf in enumerate(ordered_calls(trial_dir)[:30]):
        content, finish = content_and_finish(cf)
        if not content:
            continue
        analysis, cmd, done, ok = "", "", False, True
        s = content.strip()
        s = re.sub(r"^```[a-zA-Z]*", "", s).strip()
        s = re.sub(r"```$", "", s).strip()
        j = None
        if s.startswith("{"):
            try:
                j = json.loads(s[:s.rfind("}") + 1])
            except Exception:
                j = None
        if isinstance(j, dict):
            analysis = str(j.get("analysis", "") or j.get("thought", ""))[:320]
            done = bool(j.get("is_task_complete"))
            cmds = j.get("commands")
            if isinstance(cmds, list) and cmds:
                cmd = " ; ".join(str(c.get("keystrokes", "")).strip() for c in cmds
                                 if isinstance(c, dict))[:220]
            elif j.get("command"):
                cmd = str(j.get("command"))[:220]
        else:
            ok = agent != "terminus-2"
        lp = intragen_loop(content)
        turns.append({
            "ep": i, "analysis": analysis, "cmd": cmd, "finish": finish, "done": done,
            "loop": (lp[1] if lp else 0),
            "malformed": (agent == "terminus-2" and not ok and len(content.strip()) > 10),
            "snippet": content[:260].replace("\n", " ").strip(),
        })
    return turns


def main():
    bundle = json.load(open(DASH / "dashboard_data.json"))
    valid = list(csv.DictReader(open(DATA / "trials_valid.csv")))
    calls = list(csv.DictReader(open(DATA / "calls.csv")))

    # per-trial gen tok/s from calls
    tok = defaultdict(list)
    for c in calls:
        g = f(c["gen_tok_s"])
        if g and g > 0:
            tok[(c["run_name"], c["trial"])].append(g)

    # ---- full model × task heatmap ----
    cell = defaultdict(lambda: {"n": 0, "p": 0, "trials": []})
    models, tasks = set(), set()
    for t in valid:
        k = (t["model"], t["task"])
        cell[k]["n"] += 1
        cell[k]["p"] += int(t["passed"])
        cell[k]["trials"].append(t["trial"])
        models.add(t["model"]); tasks.add(t["task"])
    heatmap_full = {
        "models": sorted(models, key=lambda m: -sum(c["p"] for (mm, _), c in cell.items() if mm == m)
                          / max(1, sum(c["n"] for (mm, _), c in cell.items() if mm == m))),
        "tasks": sorted(tasks),
        "cells": [{"model": m, "task": tk, "n": c["n"], "pass": c["p"],
                   "rate": round(c["p"] / c["n"] * 100)} for (m, tk), c in cell.items()],
    }

    # ---- trials index (for filtering / browsing) ----
    idx = build_index()
    trials_index, traj = [], {}
    for t in valid:
        key = (t["run_name"], t["trial"])
        med = tok.get(key)
        tok_s = round(sorted(med)[len(med)//2], 1) if med else None
        rec = {"id": t["trial"], "run": t["run_name"], "agent": t["agent"], "model": t["model"],
               "task": t["task"], "reward": f(t["reward"]), "passed": int(t["passed"]),
               "steps": int(t["n_calls"]), "tok_s": tok_s, "backend": t["backend"],
               "comp_tok": int(float(t["sum_completion_tokens"]))}
        trials_index.append(rec)
        d = idx.get(key)
        if d:
            turns = extract_turns(d, t["agent"])
            if turns:
                traj[t["trial"]] = {"meta": rec, "turns": turns}

    bundle["heatmap_full"] = heatmap_full
    bundle["trials_index"] = trials_index

    (DASH / "dashboard_data.json").write_text(json.dumps(bundle))
    (DASH / "dashboard_data.js").write_text("window.DASH_DATA = " + json.dumps(bundle) + ";\n")
    (DASH / "dashboard_traj.js").write_text("window.DASH_TRAJ = " + json.dumps(traj) + ";\n")
    print(f"trials_index: {len(trials_index)} | heatmap models×tasks: "
          f"{len(heatmap_full['models'])}×{len(heatmap_full['tasks'])} | trajectories: {len(traj)}")
    print(f"dashboard_data.js: {(DASH/'dashboard_data.js').stat().st_size//1024} KB | "
          f"dashboard_traj.js: {(DASH/'dashboard_traj.js').stat().st_size//1024} KB")


if __name__ == "__main__":
    main()
