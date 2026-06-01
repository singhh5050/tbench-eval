#!/usr/bin/env python3
"""
extract_trajectories.py — pull the real turn sequences for a hand-picked set of trials that
serve a rhetorical purpose in the report (a clean success, the doom-loop, false completion,
malformed action). Verbatim content, for rendering as "agent-trace" figures.

Writes data/trajectories.json.
"""
import json, re
from collections import Counter
from pathlib import Path
from extract_metrics import response_from_call
from mine_failures import build_index, ordered_calls, content_and_finish, parse_command, intragen_loop

DATA = Path(__file__).resolve().parent / "data"

# (key, model, task, want) — want="pass" picks a passing trial, "fail" a failing one
PICKS = [
    ("success",       "Qwen3.5-35B-A3B",       "fix-git",            "pass"),
    ("doom_loop",     "Qwen3-Coder-Next-FP8",  "headless-terminal",  "fail"),
    ("false_done",    "GLM-4.7-Flash",         "pypi-server",        "fail"),
    ("malformed",     "phi-4",                 "cobol-modernization","fail"),
    # positive reasoning showcases (strengths)
    ("reason_fast",   "gpt-oss-120b",          "prove-plus-comm",    "pass"),
    ("reason_debug",  "Qwen3.5-35B-A3B",       "broken-python",      "pass"),
    ("reason_crypto", "Qwen3-Coder-Next",      "cryptographic-protocol-verifier", "pass"),
]


def loop_excerpt(content):
    """Return (line, count) for the most-repeated line/token in a looping generation."""
    lines = [l.strip() for l in content.splitlines() if len(l.strip()) > 6]
    if lines:
        top, n = Counter(lines).most_common(1)[0]
        if n >= 4:
            return top, n
    tc = content.count("<tool_call>")
    if tc >= 6:
        # grab a representative window around the repeated call
        m = re.search(r"function=\S+\([^)]*\)", content)
        token = m.group(0) if m else "<tool_call>"
        return token, tc
    return None


def main():
    idx = build_index()
    valid = [json.loads(l) for l in []]  # placeholder; load via csv
    import csv
    valid = list(csv.DictReader(open(DATA / "trials_valid.csv")))
    out = {}
    for key, model, task, want in PICKS:
        cands = [t for t in valid if t["model"] == model and t["task"] == task]
        cands.sort(key=lambda t: -int(t["passed"]) if want == "pass" else int(t["passed"]))
        rec = None
        for t in cands:
            d = idx.get((t["run_name"], t["trial"]))
            if not d:
                continue
            calls = ordered_calls(d)
            if not calls:
                continue
            turns = []
            for i, cf in enumerate(calls):
                content, finish = content_and_finish(cf)
                if not content:
                    continue
                cmd, done, ok = parse_command(content)
                dj = response_from_call(cf)[0] or {}
                usage = dj.get("usage") or {}
                lp = loop_excerpt(content)
                # analysis text for terminus JSON
                analysis = ""
                try:
                    import json as _j
                    s = content.strip()
                    s = re.sub(r"^```[a-zA-Z]*", "", s).strip(); s = re.sub(r"```$", "", s).strip()
                    j = _j.loads(s) if s.startswith("{") else None
                    if isinstance(j, dict):
                        analysis = str(j.get("analysis", ""))
                except Exception:
                    pass
                turns.append({
                    "ep": i,
                    "analysis": analysis[:400],
                    "command": (cmd or "")[:240],
                    "finish": finish,
                    "loop": ({"line": lp[0][:160], "count": lp[1]} if lp else None),
                    "done": bool(done),
                    "ok": ok,
                    "comp_tokens": usage.get("completion_tokens"),
                    "raw": content[:600],
                })
            rec = {"run": t["run_name"], "agent": t["agent"], "model": model, "task": task,
                   "reward": float(t["reward"]) if t["reward"] else 0.0,
                   "n_turns": len(turns), "turns": turns,
                   "sum_completion_tokens": t.get("sum_completion_tokens")}
            break
        out[key] = rec
        print(f"{key:12} {model} · {task}: " + (f"{rec['n_turns']} turns, reward {rec['reward']}" if rec else "NOT FOUND"))
    json.dump(out, open(DATA / "trajectories.json", "w"), indent=1)
    print(f"-> {DATA}/trajectories.json")


if __name__ == "__main__":
    main()
