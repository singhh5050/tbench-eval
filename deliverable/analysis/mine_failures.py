#!/usr/bin/env python3
"""
mine_failures.py — evidence-grounded failure taxonomy over VALID trials only.

Failure modes detected (per trial), with verbatim example generations:
  truncation        a call ends with finish_reason == "length" (output cut off)
  doom_loop         the same shell command is issued >= 3x within a trial
  malformed_action  (terminus-2) model output is not parseable structured JSON
  false_completion  trial failed (reward < 1) yet the model declared the task done
  reasoning_burn    a single generation runs very long (>= 4000 completion tokens)

Outputs: data/failures_by_model.csv, data/failure_examples.json, failures_report.md,
and assets/{dark,light}/failure_modes.png.
"""
import csv, json, re
from collections import defaultdict, Counter
from pathlib import Path
import numpy as np
import amd_style as S
import matplotlib.pyplot as plt
from extract_metrics import response_from_call

ANALYSIS = Path(__file__).resolve().parent
DATA = ANALYSIS / "data"
RESULTS = ANALYSIS.parents[1] / "results"

DONE_RE = re.compile(r"(task (is )?(complete|solved|finished|done)|successfully (completed|solved|"
                     r"fixed|implemented)|i('?ve| have) (completed|solved|finished))", re.I)


def build_index():
    idx = {}
    for rj in RESULTS.rglob("result.json"):
        try:
            meta = json.load(open(rj))
        except Exception:
            continue
        if "trial_name" in meta:
            run = rj.parent.relative_to(RESULTS).parts[0]
            idx[(run, meta["trial_name"])] = rj.parent
    return idx


def ordered_calls(trial_dir):
    agent = trial_dir / "agent"
    eps = sorted(agent.glob("episode-*/debug.json"),
                 key=lambda p: int(re.search(r"episode-(\d+)", str(p)).group(1)))
    if eps:
        return eps
    comp = trial_dir / "agent" / "completions"
    if comp.is_dir():
        return sorted(comp.glob("*.json"), key=lambda p: p.stat().st_mtime)
    return []


def content_and_finish(path):
    resp, _ = response_from_call(path)
    if not resp:
        return "", None
    ch = (resp.get("choices") or [{}])[0]
    return (ch.get("message") or {}).get("content") or "", ch.get("finish_reason")


def extract_json(content):
    """Lenient: strip fences, then parse, then fall back to the first {...} block.
    Only genuinely-unextractable structure counts as malformed."""
    s = content.strip()
    s = re.sub(r"^```[a-zA-Z]*", "", s).strip()
    s = re.sub(r"```$", "", s).strip()
    try:
        d = json.loads(s)
        return d if isinstance(d, dict) else None
    except Exception:
        pass
    i, j = s.find("{"), s.rfind("}")
    if 0 <= i < j:
        try:
            d = json.loads(s[i:j + 1])
            return d if isinstance(d, dict) else None
        except Exception:
            return None
    return None


def parse_command(content):
    """Return (command, done, ok). ok=False only when no command-JSON can be extracted."""
    d = extract_json(content)
    if d is not None and ("command" in d or "analysis" in d):
        return str(d.get("command", "")).strip(), bool(d.get("is_task_complete", False)), True
    return "", None, False


def intragen_loop(content):
    """Detect a generation that loops on itself (the real 'doom-loop')."""
    lines = [l.strip() for l in content.splitlines() if len(l.strip()) > 6]
    if lines:
        top, n = Counter(lines).most_common(1)[0]
        if n >= 4:
            return top, n
    tc = content.count("<tool_call>")
    if tc >= 6:
        return "<tool_call> emitted repeatedly", tc
    return None


def main():
    idx = build_index()
    valid = [r for r in csv.DictReader(open(DATA / "validity.csv")) if r["valid"] == "1"]

    per_model = defaultdict(lambda: dict(n=0, truncation=0, doom_loop=0, malformed=0,
                                         false_completion=0, reasoning_burn=0, agent=""))
    examples = defaultdict(list)
    EX_CAP = 40

    for t in valid:
        key = (t["run_name"], t["trial"])
        d = idx.get(key)
        if not d:
            continue
        model, agent, task = t["model"], t["agent"], t["task"]
        reward = float(t["reward"]) if t["reward"] else 0.0
        pm = per_model[model]; pm["n"] += 1; pm["agent"] = agent

        commands, trunc_hit, malformed_hit, loop_hit, burn_hit = [], False, False, False, False
        done_quote = None
        calls = ordered_calls(d)
        for cf in calls:
            content, finish = content_and_finish(cf)
            if not content:
                continue
            if finish == "length":
                trunc_hit = True
                if len(examples["truncation"]) < EX_CAP:
                    examples["truncation"].append({
                        "model": model, "agent": agent, "task": task,
                        "quote": content[-200:].replace("\n", " ").strip()})
            # intra-generation loop (the real doom-loop)
            lp = intragen_loop(content)
            if lp:
                loop_hit = True
                if len(examples["doom_loop"]) < EX_CAP:
                    examples["doom_loop"].append({
                        "model": model, "agent": agent, "task": task,
                        "quote": f"{lp[1]}× — {lp[0][:150]}"})
            cmd, done, ok = parse_command(content)
            if agent == "terminus-2":
                if not ok and len(content.strip()) > 10:
                    malformed_hit = True
                    if len(examples["malformed_action"]) < EX_CAP:
                        examples["malformed_action"].append({
                            "model": model, "agent": agent, "task": task,
                            "quote": content[:180].replace("\n", " ").strip()})
                if cmd:
                    commands.append(cmd)
                if done:
                    done_quote = (extract_json(content) or {}).get("analysis", "")[:200]
            elif DONE_RE.search(content):
                done_quote = done_quote or content[max(0, DONE_RE.search(content).start()-40):
                                                  DONE_RE.search(content).end()+60].replace("\n", " ").strip()
            if len(content) > 16000:
                burn_hit = True
                if len(examples["reasoning_burn"]) < EX_CAP:
                    examples["reasoning_burn"].append({
                        "model": model, "agent": agent, "task": task,
                        "quote": f"a single generation of ~{len(content)//1000}K characters before any "
                                 f"action — opening: {content[:150].replace(chr(10),' ').strip()}…"})

        # cross-episode exact command repeat (slower loops)
        if commands:
            top, n = Counter(commands).most_common(1)[0]
            if n >= 3 and len(top) > 3:
                loop_hit = True
                if len(examples["doom_loop"]) < EX_CAP:
                    examples["doom_loop"].append({
                        "model": model, "agent": agent, "task": task,
                        "quote": f"re-issued {n}× across turns — {top[:140]}"})
        if trunc_hit:
            pm["truncation"] += 1
        if malformed_hit:
            pm["malformed"] += 1
        if loop_hit:
            pm["doom_loop"] += 1
        if burn_hit:
            pm["reasoning_burn"] += 1
        if reward < 1.0 and done_quote is not None:
            pm["false_completion"] += 1
            if len(examples["false_completion"]) < EX_CAP and done_quote:
                examples["false_completion"].append({
                    "model": model, "agent": agent, "task": task, "quote": done_quote})

    # write per-model csv
    rows = []
    for m, pm in sorted(per_model.items(), key=lambda kv: -kv[1]["n"]):
        if pm["n"] < 5:
            continue
        rows.append({
            "model": m, "agent": pm["agent"], "n_valid": pm["n"],
            "truncation_rate": round(pm["truncation"]/pm["n"], 3),
            "doom_loop_rate": round(pm["doom_loop"]/pm["n"], 3),
            "malformed_rate": round(pm["malformed"]/pm["n"], 3),
            "false_completion_rate": round(pm["false_completion"]/pm["n"], 3),
            "reasoning_burn_rate": round(pm["reasoning_burn"]/pm["n"], 3),
        })
    with open(DATA / "failures_by_model.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    # dedupe examples by (model, task) for variety
    for mode, lst in examples.items():
        seen, uniq = set(), []
        for e in lst:
            k = (e["model"], e["task"])
            if k in seen:
                continue
            seen.add(k); uniq.append(e)
        examples[mode] = uniq
    json.dump(examples, open(DATA / "failure_examples.json", "w"), indent=1)

    # aggregate rates across all valid trials (overall)
    tot = sum(pm["n"] for pm in per_model.values() if pm["n"] >= 5)
    agg = {k: sum(pm[k] for m, pm in per_model.items() if pm["n"] >= 5)
           for k in ("truncation", "doom_loop", "malformed", "false_completion", "reasoning_burn")}

    # ---- report ----
    L = ["# Failure-mode taxonomy (valid trials)\n",
         f"Across **{tot}** valid trials with parseable generations.\n",
         "| Failure mode | Trials | Rate | What it looks like |",
         "|---|---:|---:|---|"]
    desc = {
        "truncation": "a generation ends with finish_reason=length — output cut mid-command",
        "doom_loop": "the same shell command re-issued ≥3× — no error recovery",
        "malformed": "structured-action JSON the agent can't parse — wasted turn",
        "false_completion": "model declares success on a trial the verifier scored 0",
        "reasoning_burn": "a single generation runs extremely long",
    }
    label = {"truncation": "Context truncation", "doom_loop": "Doom-loop / repetition",
             "malformed": "Malformed action", "false_completion": "False completion",
             "reasoning_burn": "Reasoning-budget burn"}
    for k in ("truncation", "malformed", "doom_loop", "false_completion", "reasoning_burn"):
        L.append(f"| {label[k]} | {agg[k]} | {agg[k]/tot*100:.0f}% | {desc[k]} |")
    L.append("\n## Representative generations\n")
    for mode in ("truncation", "doom_loop", "malformed_action", "false_completion"):
        if examples.get(mode):
            L.append(f"### {mode}\n")
            for e in examples[mode][:4]:
                L.append(f"- **{e['model']} · {e['task']}** — “{e['quote']}”")
            L.append("")
    (ANALYSIS / "failures_report.md").write_text("\n".join(L) + "\n")

    # ---- chart (overall rates) ----
    for themename in ("dark", "light"):
        c = S.theme(themename)
        keys = ["truncation", "malformed", "doom_loop", "false_completion", "reasoning_burn"]
        vals = [agg[k]/tot*100 for k in keys]
        fig, ax = plt.subplots(figsize=(8.6, 5.0))
        y = np.arange(len(keys))
        ax.barh(y, vals, color=S.RED, height=0.62, zorder=3)
        ax.set_yticks(y); ax.set_yticklabels([label[k] for k in keys], fontsize=11)
        for yi, v in enumerate(vals):
            ax.text(v + 0.6, yi, f"{v:.0f}%", va="center", color=c["ink"], fontweight="bold")
        ax.invert_yaxis()
        ax.set_xlabel("% of valid trials exhibiting the failure")
        ax.set_title("How local agents fail — the “almost”", fontsize=14, fontweight="bold", loc="left", pad=12)
        ax.spines["left"].set_visible(False)
        S.save(fig, "failure_modes", themename)

    print(f"valid trials analyzed: {tot}")
    for k in ("truncation", "malformed", "doom_loop", "false_completion", "reasoning_burn"):
        print(f"  {k:18} {agg[k]:4} ({agg[k]/tot*100:.0f}%)")
    print(f"-> failures_by_model.csv, failure_examples.json, failures_report.md, failure_modes.png")


if __name__ == "__main__":
    main()
