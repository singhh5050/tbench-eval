#!/usr/bin/env python3
"""TerminalBench Results Dashboard — lightweight API + static file server."""

import json
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

RESULTS_DIR = Path(os.path.dirname(os.path.abspath(__file__))) / "results"
DASHBOARD_HTML = Path(os.path.dirname(os.path.abspath(__file__))) / "dashboard.html"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080


def scan_results():
    """Walk the results directory and build a structured summary."""
    import re
    from collections import defaultdict

    runs = []

    # Skip non-result directories and broken/test runs
    SKIP = {
        "summary.csv", "64gb-server", "harbor-results", "VALIDATION_REPORT.txt",
        "gemma-test", "gemma-test-2", "gemma-test-20260319-122347",
        "test-quick", "cloud-test", "frontier-test-20260329",
        "terminus-2-llama32-3b-test", "terminus-2-llama32-manual-test",
        "terminus-2-llama-local-30gb", "terminus-2-phi4-14b",
    }

    def parse_run_name(run_name):
        if run_name.startswith("openhands-"):
            agent, model_tag = "openhands", run_name[len("openhands-"):]
        elif run_name.startswith("terminus-2-"):
            agent, model_tag = "terminus-2", run_name[len("terminus-2-"):]
        else:
            parts = run_name.split("-", 1)
            agent, model_tag = parts[0], parts[1] if len(parts) > 1 else ""
        runtime = "local" if ("local" in model_tag or "64gb" in model_tag) else "cloud"
        return agent, model_tag, runtime

    def process_trial(run_name, agent, model_tag, runtime, trial_dir, traj_base):
        result_file = trial_dir / "result.json"
        if not result_file.exists():
            return None
        try:
            result = json.loads(result_file.read_text())
        except (json.JSONDecodeError, OSError):
            return None

        trial_name = trial_dir.name
        task_name = trial_name.rsplit("__", 1)[0] if "__" in trial_name else trial_name

        reward = None
        reward_file = trial_dir / "verifier" / "reward.txt"
        if reward_file.exists():
            try:
                reward = float(reward_file.read_text().strip())
            except (ValueError, OSError):
                pass
        if reward is None:
            reward = result.get("reward")

        duration = None
        started, finished = result.get("started_at"), result.get("finished_at")
        if started and finished:
            from datetime import datetime
            try:
                s = datetime.fromisoformat(started.replace("Z", "+00:00"))
                f = datetime.fromisoformat(finished.replace("Z", "+00:00"))
                duration = (f - s).total_seconds()
            except Exception:
                pass

        tokens = {"prompt": 0, "completion": 0}
        traj_file = trial_dir / "agent" / "trajectory.json"
        if traj_file.exists():
            try:
                traj = json.loads(traj_file.read_text())
                fm = traj.get("final_metrics", {})
                tokens["prompt"] = fm.get("total_prompt_tokens", 0)
                tokens["completion"] = fm.get("total_completion_tokens", 0)
            except Exception:
                pass

        error = None
        exc_info = result.get("exception_info")
        if exc_info:
            error = exc_info.get("exception_type", "Unknown")

        return {
            "run": run_name, "agent": agent, "model_tag": model_tag,
            "runtime": runtime, "task": task_name, "trial_name": trial_name,
            "reward": reward,
            "duration": round(duration, 1) if duration else None,
            "error": error, "tokens": tokens,
            "has_trajectory": traj_file.exists(),
            "trajectory_path": traj_base,
        }

    TS_RE = re.compile(r'\d{4}-\d{2}-\d{2}__\d{2}-\d{2}-\d{2}')

    for run_dir in sorted(RESULTS_DIR.iterdir()):
        if not run_dir.is_dir() or run_dir.name.startswith((".", "__")):
            continue
        if run_dir.name in SKIP:
            continue

        run_name = run_dir.name
        agent, model_tag, runtime = parse_run_name(run_name)

        for l1 in sorted(run_dir.iterdir()):
            if not l1.is_dir():
                continue

            if TS_RE.match(l1.name):
                # Old format: run/TIMESTAMP/trial__hash/
                for trial in sorted(l1.iterdir()):
                    if not trial.is_dir():
                        continue
                    entry = process_trial(run_name, agent, model_tag, runtime,
                                          trial, f"{run_name}/{l1.name}/{trial.name}")
                    if entry:
                        runs.append(entry)
            else:
                # New format: run/TASK/TIMESTAMP/trial__hash/
                # Use l1.name as the canonical task name (trial dir may be truncated)
                for l2 in sorted(l1.iterdir()):
                    if not l2.is_dir():
                        continue
                    for trial in sorted(l2.iterdir()):
                        if not trial.is_dir():
                            continue
                        entry = process_trial(run_name, agent, model_tag, runtime,
                                              trial, f"{run_name}/{l1.name}/{l2.name}/{trial.name}")
                        if entry:
                            entry['task'] = l1.name  # override with correct task name
                            runs.append(entry)

    # Load the full 37-task list to fill in timeouts as failures
    merged_file = Path(os.path.dirname(os.path.abspath(__file__))) / "easy_tasks_merged.txt"
    all_tasks = set()
    if merged_file.exists():
        for line in merged_file.read_text().splitlines():
            line = line.strip()
            if line:
                # Strip dataset prefix if present (e.g. "terminal-bench@2.0|fix-git" -> "fix-git")
                task = line.split("|")[-1] if "|" in line else line
                all_tasks.add(task)

    if all_tasks:
        # Group existing results by run
        tasks_by_run = defaultdict(set)
        run_info = {}
        for r in runs:
            tasks_by_run[r['run']].add(r['task'])
            if r['run'] not in run_info:
                run_info[r['run']] = (r['agent'], r['model_tag'], r['runtime'])

        # Add missing tasks as timeout failures (reward=0)
        for run_name, (agent, model_tag, runtime) in run_info.items():
            missing = all_tasks - tasks_by_run[run_name]
            for task in missing:
                runs.append({
                    "run": run_name, "agent": agent, "model_tag": model_tag,
                    "runtime": runtime, "task": task, "trial_name": task,
                    "reward": 0, "duration": 600.0,
                    "error": "Timeout", "tokens": {"prompt": 0, "completion": 0},
                    "has_trajectory": False, "trajectory_path": "",
                })

    # Deduplicate: keep best result per (run, task) — reward=1 > reward=0 > reward=None
    best = {}
    for r in runs:
        key = (r['run'], r['task'])
        if key not in best or (r.get('reward') or 0) > (best[key].get('reward') or 0):
            best[key] = r
    runs = list(best.values())

    # Filter out runs with 0% pass rate
    passes_by_run = defaultdict(int)
    total_by_run = defaultdict(int)
    for r in runs:
        total_by_run[r['run']] += 1
        if r.get('reward') == 1:
            passes_by_run[r['run']] += 1
    zero_runs = {run for run in total_by_run if passes_by_run[run] == 0}
    runs = [r for r in runs if r['run'] not in zero_runs]

    return runs


def load_trajectory(traj_path):
    """Load a trajectory file and return cleaned steps."""
    full_path = RESULTS_DIR / traj_path / "agent" / "trajectory.json"
    if not full_path.exists():
        return {"error": "Trajectory not found"}

    try:
        traj = json.loads(full_path.read_text())
    except (json.JSONDecodeError, OSError) as e:
        return {"error": str(e)}

    steps = traj.get("steps", [])
    agent_info = traj.get("agent", {})
    final_metrics = traj.get("final_metrics", {})

    # Also try to load verifier output
    verifier_stdout = ""
    verifier_file = RESULTS_DIR / traj_path / "verifier" / "test-stdout.txt"
    if verifier_file.exists():
        try:
            verifier_stdout = verifier_file.read_text()[:5000]
        except OSError:
            pass

    return {
        "agent": agent_info,
        "steps": steps,
        "final_metrics": final_metrics,
        "verifier_stdout": verifier_stdout,
    }


class DashboardHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "/dashboard":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(DASHBOARD_HTML.read_bytes())

        elif path == "/api/results":
            data = scan_results()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        elif path == "/api/trajectory":
            qs = parse_qs(parsed.query)
            traj_path = qs.get("path", [None])[0]
            if not traj_path:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b'{"error":"missing path param"}')
                return
            data = load_trajectory(traj_path)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")

    def log_message(self, format, *args):
        pass  # Suppress request logging


def main():
    if not RESULTS_DIR.exists():
        print(f"Error: Results directory not found at {RESULTS_DIR}")
        sys.exit(1)
    if not DASHBOARD_HTML.exists():
        print(f"Error: dashboard.html not found at {DASHBOARD_HTML}")
        sys.exit(1)

    server = HTTPServer(("0.0.0.0", PORT), DashboardHandler)
    print(f"Dashboard running at http://localhost:{PORT}")
    print(f"Reading results from {RESULTS_DIR}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
