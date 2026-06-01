#!/usr/bin/env python3
"""
extract_metrics.py — walk results/ and extract per-LLM-call and per-trial metrics.

Two call-storage formats are handled uniformly:
  - terminus-2 / qwen-coder / legacy harbor-results:  agent/**/debug.json
      -> debug["original_response"] (JSON string) -> response dict
  - openhands:                                         agent/completions/*.json
      -> file["response"] (already a dict)        -> response dict

Each response dict carries OpenAI-style `usage`, llama.cpp `timings`
(predicted_per_second = generation tok/s, prompt_per_second = prefill tok/s),
and choices[0].finish_reason (== "length" => context/length truncation).

Trial anchor = the trial-level result.json (the one carrying "trial_name").
Ground-truth reward = verifier/reward.txt (None if the trial never graded).

Outputs (deliverable/analysis/data/):
  calls.csv        one row per LLM call
  trials.csv       one row per trial (reward + aggregated call metrics)
  runs_summary.csv one row per top-level results/<run> directory
"""
import csv, json, os, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RESULTS = REPO / "results"
OUT = Path(__file__).resolve().parent / "data"
OUT.mkdir(exist_ok=True)

HOSTED_HINT = re.compile(r"(together|fireworks|cloud)", re.I)

# longest-match first so "terminus-2"/"mini-swe-agent" win over "terminus"/"swe-agent"
KNOWN_AGENTS = ["mini-swe-agent", "swe-agent", "terminus-2", "qwen-coder", "openhands", "claude-code"]


def agent_from_run(run):
    for a in KNOWN_AGENTS:
        if run.startswith(a):
            return a
    return run.split("-")[0]


def norm_model(m):
    """openai/Qwen3.5-35B-A3B-GGUF -> Qwen3.5-35B-A3B"""
    if not m:
        return ""
    m = m.split("/")[-1]
    m = re.sub(r"^user\.", "", m)          # legacy lemonade prefix
    m = re.sub(r"-GGUF$", "", m, flags=re.I)
    return m


def response_from_call(path):
    """Return (response_dict, extra) from a debug.json or completions/*.json file."""
    try:
        d = json.load(open(path))
    except Exception:
        return None, {}
    if path.name == "debug.json":
        orig = d.get("original_response")
        if isinstance(orig, str):
            try:
                resp = json.loads(orig)
            except Exception:
                return None, {}
        elif isinstance(orig, dict):
            resp = orig
        else:
            return None, {}
        return resp, {"dur_ms": d.get("llm_api_duration_ms"), "model": d.get("model")}
    else:  # completions/*.json
        resp = d.get("response")
        if not isinstance(resp, dict):
            return None, {}
        return resp, {"cost": d.get("cost"), "model": (d.get("kwargs") or {}).get("model")}


def call_metrics(resp, extra):
    usage = resp.get("usage") or {}
    timings = resp.get("timings") or {}
    choices = resp.get("choices") or [{}]
    ch0 = choices[0] if choices else {}
    msg = ch0.get("message") or {}
    content = msg.get("content") or ""
    pdetails = usage.get("prompt_tokens_details") or {}
    return {
        "model": norm_model(extra.get("model") or resp.get("model")),
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "cached_tokens": pdetails.get("cached_tokens"),
        "predicted_n": timings.get("predicted_n"),
        "predicted_ms": timings.get("predicted_ms"),
        "prompt_n": timings.get("prompt_n"),
        "prompt_ms": timings.get("prompt_ms"),
        "gen_tok_s": timings.get("predicted_per_second"),
        "prompt_tok_s": timings.get("prompt_per_second"),
        "finish_reason": ch0.get("finish_reason"),
        "dur_ms": extra.get("dur_ms"),
        "content_len": len(content),
    }


def find_call_files(trial_dir):
    agent = trial_dir / "agent"
    if not agent.is_dir():
        return []
    files = list(agent.rglob("debug.json"))
    files += list((agent / "completions").glob("*.json")) if (agent / "completions").is_dir() else []
    return files


def read_reward(trial_dir):
    rf = trial_dir / "verifier" / "reward.txt"
    if not rf.exists():
        # some layouts: reward.txt anywhere under trial
        cand = list(trial_dir.rglob("reward.txt"))
        if not cand:
            return None
        rf = cand[0]
    try:
        return float(rf.read_text().strip())
    except Exception:
        return None


def main():
    # Discover trial-level result.json files (carry "trial_name").
    trials = []
    calls = []
    n_seen = 0
    for rj in RESULTS.rglob("result.json"):
        try:
            meta = json.load(open(rj))
        except Exception:
            continue
        if "trial_name" not in meta:
            continue  # run-level summary, skip
        n_seen += 1
        trial_dir = rj.parent
        # run_name = first path component under results/
        rel = trial_dir.relative_to(RESULTS)
        run_name = rel.parts[0]
        if run_name == "harbor-results":
            continue  # legacy /var/tmp jobs-dir — verified 100% duplicate of the named -64gb runs
        cfg = meta.get("config") or {}
        agent = ((cfg.get("agent") or {}).get("name")) or agent_from_run(run_name)
        model = norm_model(((cfg.get("agent") or {}).get("model_name")) or "")
        task = meta.get("task_name") or (rel.parts[1] if len(rel.parts) > 1 else "")
        trial_name = meta.get("trial_name") or trial_dir.name
        source = meta.get("source") or ""
        backend = "hosted" if HOSTED_HINT.search(run_name) else "local"
        reward = read_reward(trial_dir)

        # per-call metrics
        cm_list = []
        for cf in find_call_files(trial_dir):
            resp, extra = response_from_call(cf)
            if resp is None:
                continue
            cm = call_metrics(resp, extra)
            cm_list.append(cm)
            row = {"run_name": run_name, "agent": agent, "model": model or cm["model"],
                   "task": task, "trial": trial_name, "backend": backend}
            row.update({k: cm[k] for k in (
                "prompt_tokens", "completion_tokens", "cached_tokens", "predicted_n",
                "predicted_ms", "prompt_n", "prompt_ms", "gen_tok_s", "prompt_tok_s",
                "finish_reason", "dur_ms", "content_len")})
            calls.append(row)

        # recover model from the call logs if the trial config didn't record it
        if not model and cm_list:
            from collections import Counter
            mc = Counter(c["model"] for c in cm_list if c.get("model"))
            if mc:
                model = mc.most_common(1)[0][0]

        # aggregate trial
        def s(key):
            return sum(c[key] for c in cm_list if isinstance(c.get(key), (int, float)))
        sum_pred_n = s("predicted_n")
        sum_pred_ms = s("predicted_ms")
        w_gen = (sum_pred_n / sum_pred_ms * 1000.0) if sum_pred_ms > 0 else None
        prompts = [c["prompt_tokens"] for c in cm_list if isinstance(c.get("prompt_tokens"), (int, float))]
        n_trunc = sum(1 for c in cm_list if c.get("finish_reason") == "length")
        trials.append({
            "run_name": run_name, "agent": agent, "model": model, "task": task,
            "trial": trial_name, "backend": backend, "source": source,
            "reward": reward,
            "graded": 0 if reward is None else 1,
            "passed": 1 if (reward is not None and reward >= 1.0) else 0,
            "n_calls": len(cm_list),
            "sum_completion_tokens": s("completion_tokens"),
            "sum_prompt_tokens": s("prompt_tokens"),
            "max_prompt_tokens": max(prompts) if prompts else 0,
            "weighted_gen_tok_s": round(w_gen, 2) if w_gen else None,
            "n_truncated": n_trunc,
        })

    # write calls.csv
    if calls:
        with open(OUT / "calls.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(calls[0].keys()))
            w.writeheader(); w.writerows(calls)
    # write trials.csv
    with open(OUT / "trials.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(trials[0].keys()))
        w.writeheader(); w.writerows(trials)

    # runs_summary.csv
    runs = {}
    for t in trials:
        r = runs.setdefault(t["run_name"], {
            "run_name": t["run_name"], "agent": t["agent"], "model": t["model"],
            "backend": t["backend"], "n_trials": 0, "n_graded": 0, "n_pass": 0,
            "_gen": [], "total_calls": 0, "total_completion_tokens": 0, "n_truncated": 0})
        r["n_trials"] += 1
        r["n_graded"] += t["graded"]
        r["n_pass"] += t["passed"]
        r["total_calls"] += t["n_calls"]
        r["total_completion_tokens"] += t["sum_completion_tokens"]
        r["n_truncated"] += t["n_truncated"]
        if t["weighted_gen_tok_s"]:
            r["_gen"].append(t["weighted_gen_tok_s"])
    rows = []
    for r in runs.values():
        gens = sorted(r.pop("_gen"))
        r["median_gen_tok_s"] = round(gens[len(gens)//2], 2) if gens else None
        r["pass_rate"] = round(r["n_pass"]/r["n_graded"], 4) if r["n_graded"] else None
        rows.append(r)
    rows.sort(key=lambda x: (x["agent"], x["model"]))
    with open(OUT / "runs_summary.csv", "w", newline="") as f:
        cols = ["run_name", "agent", "model", "backend", "n_trials", "n_graded",
                "n_pass", "pass_rate", "median_gen_tok_s", "total_calls",
                "total_completion_tokens", "n_truncated"]
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in cols})

    print(f"trials(result.json with trial_name): {n_seen}")
    print(f"trials written: {len(trials)}  | graded: {sum(t['graded'] for t in trials)}"
          f"  | passed: {sum(t['passed'] for t in trials)}")
    print(f"LLM calls written: {len(calls)}")
    print(f"runs: {len(rows)}")
    print(f"-> {OUT}/calls.csv, trials.csv, runs_summary.csv")


if __name__ == "__main__":
    main()
