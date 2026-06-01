#!/usr/bin/env python3
"""TerminalBench Results Dashboard — lightweight API + static file server."""

import json
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

REPO_ROOT = Path(os.path.dirname(os.path.abspath(__file__))).parent
RESULTS_DIR = REPO_ROOT / "results"
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
        elif run_name.startswith("claude-code-"):
            agent, model_tag = "claude-code", run_name[len("claude-code-"):]
        elif run_name.startswith("swe-agent-"):
            agent, model_tag = "swe-agent", run_name[len("swe-agent-"):]
        elif run_name.startswith("mini-swe-agent-"):
            agent, model_tag = "mini-swe-agent", run_name[len("mini-swe-agent-"):]
        elif run_name.startswith("qwen-coder-"):
            agent, model_tag = "qwen-coder", run_name[len("qwen-coder-"):]
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
    merged_file = REPO_ROOT / "config" / "tasks" / "easy_merged.txt"
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


def normalize_model_tag(model_tag):
    """Normalize model tags for comparison (strip version suffixes, etc.)."""
    import re
    # Remove version suffixes like -v2, -v3
    model = re.sub(r'-v\d+$', '', model_tag)
    # Normalize common patterns
    model = re.sub(r'-gguf-(local|64gb)$', '-gguf-local', model)
    return model


def compute_trends():
    """Compute trend data for the Trends tab."""
    from collections import defaultdict

    runs = scan_results()

    # Group by run
    run_stats = defaultdict(lambda: {"passes": 0, "total": 0, "agent": "", "model_tag": ""})
    task_stats = defaultdict(lambda: {"passes": 0, "total": 0})

    for r in runs:
        run_stats[r['run']]["total"] += 1
        run_stats[r['run']]["agent"] = r['agent']
        run_stats[r['run']]["model_tag"] = r['model_tag']
        if r.get('reward') == 1:
            run_stats[r['run']]["passes"] += 1

        task_stats[r['task']]["total"] += 1
        if r.get('reward') == 1:
            task_stats[r['task']]["passes"] += 1

    # Agent comparison: find models with both OpenHands and Terminus-2
    models_by_agent = defaultdict(dict)
    for run_name, stats in run_stats.items():
        # Normalize model tag for comparison
        model = normalize_model_tag(stats['model_tag'])
        agent = stats['agent']
        if agent in ('openhands', 'terminus-2'):
            rate = stats['passes'] / stats['total'] * 100 if stats['total'] > 0 else 0
            # Keep the better result if multiple runs for same normalized model
            if agent not in models_by_agent[model] or rate > models_by_agent[model][agent].get('rate', 0):
                models_by_agent[model][agent] = {
                    "run": run_name,
                    "passes": stats['passes'],
                    "total": stats['total'],
                    "rate": round(rate, 1)
                }

    agent_comparison = []
    for model, agents in models_by_agent.items():
        if 'openhands' in agents and 'terminus-2' in agents:
            oh = agents['openhands']
            t2 = agents['terminus-2']
            delta = t2['rate'] - oh['rate']
            agent_comparison.append({
                "model": model,
                "openhands": oh,
                "terminus_2": t2,
                "delta": round(delta, 1),
                "winner": "terminus-2" if delta > 0 else "openhands" if delta < 0 else "tie"
            })

    # Sort by delta (Terminus-2 advantage)
    agent_comparison.sort(key=lambda x: -x['delta'])

    # Task difficulty histogram
    buckets = {"0%": 0, "1-25%": 0, "26-50%": 0, "51-75%": 0, "76-100%": 0}
    unsolved_tasks = []
    easy_tasks = []

    for task, stats in task_stats.items():
        rate = stats['passes'] / stats['total'] * 100 if stats['total'] > 0 else 0
        if rate == 0:
            buckets["0%"] += 1
            unsolved_tasks.append(task)
        elif rate <= 25:
            buckets["1-25%"] += 1
        elif rate <= 50:
            buckets["26-50%"] += 1
        elif rate <= 75:
            buckets["51-75%"] += 1
            if rate > 50:
                easy_tasks.append({"task": task, "rate": round(rate, 1)})
        else:
            buckets["76-100%"] += 1
            easy_tasks.append({"task": task, "rate": round(rate, 1)})

    easy_tasks.sort(key=lambda x: -x['rate'])

    # Key insights
    t2_wins = sum(1 for c in agent_comparison if c['winner'] == 'terminus-2')
    oh_wins = sum(1 for c in agent_comparison if c['winner'] == 'openhands')
    total_comparisons = len(agent_comparison)

    avg_delta = sum(c['delta'] for c in agent_comparison) / len(agent_comparison) if agent_comparison else 0

    # Find best overall model
    best_model = max(run_stats.items(), key=lambda x: x[1]['passes'] / x[1]['total'] if x[1]['total'] > 0 else 0)
    best_rate = best_model[1]['passes'] / best_model[1]['total'] * 100 if best_model[1]['total'] > 0 else 0

    insights = {
        "terminus_wins": t2_wins,
        "openhands_wins": oh_wins,
        "total_comparisons": total_comparisons,
        "avg_delta": round(avg_delta, 1),
        "unsolved_count": len(unsolved_tasks),
        "total_tasks": len(task_stats),
        "best_model": {
            "run": best_model[0],
            "agent": best_model[1]['agent'],
            "model_tag": best_model[1]['model_tag'],
            "rate": round(best_rate, 1)
        }
    }

    return {
        "agent_comparison": agent_comparison,
        "task_histogram": buckets,
        "unsolved_tasks": unsolved_tasks[:10],  # Top 10 unsolved
        "easy_tasks": easy_tasks[:10],  # Top 10 easiest
        "insights": insights
    }


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


def compute_analysis():
    """Compute meta-analysis data for errors, tokens, and steps."""
    from collections import defaultdict

    runs = scan_results()

    # Error categorization
    error_counts = defaultdict(int)
    for r in runs:
        if r.get('reward') == 1:
            error_counts['Success'] += 1
        elif r.get('error'):
            err = r['error']
            if 'Timeout' in err:
                error_counts['Timeout'] += 1
            elif 'Connection' in err or 'Network' in err or 'API' in err:
                error_counts['Network/API Error'] += 1
            elif 'Permission' in err or 'Access' in err:
                error_counts['Permission Error'] += 1
            elif 'Memory' in err or 'OOM' in err:
                error_counts['Memory Error'] += 1
            else:
                error_counts['Other Error'] += 1
        else:
            error_counts['Failed (no error)'] += 1

    # Token efficiency by agent
    token_stats_by_agent = defaultdict(lambda: {
        'total_prompt': 0, 'total_completion': 0,
        'success_prompt': 0, 'success_completion': 0,
        'fail_prompt': 0, 'fail_completion': 0,
        'success_count': 0, 'fail_count': 0
    })

    for r in runs:
        agent = r['agent']
        prompt = r['tokens'].get('prompt', 0)
        completion = r['tokens'].get('completion', 0)

        token_stats_by_agent[agent]['total_prompt'] += prompt
        token_stats_by_agent[agent]['total_completion'] += completion

        if r.get('reward') == 1:
            token_stats_by_agent[agent]['success_prompt'] += prompt
            token_stats_by_agent[agent]['success_completion'] += completion
            token_stats_by_agent[agent]['success_count'] += 1
        else:
            token_stats_by_agent[agent]['fail_prompt'] += prompt
            token_stats_by_agent[agent]['fail_completion'] += completion
            token_stats_by_agent[agent]['fail_count'] += 1

    # Compute averages
    token_efficiency = []
    for agent, stats in token_stats_by_agent.items():
        entry = {
            'agent': agent,
            'total_tokens': stats['total_prompt'] + stats['total_completion'],
            'total_tasks': stats['success_count'] + stats['fail_count'],
        }
        if stats['success_count'] > 0:
            entry['avg_tokens_success'] = round(
                (stats['success_prompt'] + stats['success_completion']) / stats['success_count']
            )
        else:
            entry['avg_tokens_success'] = 0

        if stats['fail_count'] > 0:
            entry['avg_tokens_fail'] = round(
                (stats['fail_prompt'] + stats['fail_completion']) / stats['fail_count']
            )
        else:
            entry['avg_tokens_fail'] = 0

        entry['prompt_completion_ratio'] = round(
            stats['total_prompt'] / stats['total_completion'], 2
        ) if stats['total_completion'] > 0 else 0

        token_efficiency.append(entry)

    token_efficiency.sort(key=lambda x: -x['total_tasks'])

    # Step analysis - need to load trajectories
    step_stats_by_agent = defaultdict(lambda: {'steps': [], 'tool_calls': defaultdict(int)})

    for r in runs:
        if not r.get('has_trajectory') or not r.get('trajectory_path'):
            continue
        traj_file = RESULTS_DIR / r['trajectory_path'] / "agent" / "trajectory.json"
        if not traj_file.exists():
            continue
        try:
            traj = json.loads(traj_file.read_text())
            steps = traj.get('steps', [])
            agent_steps = [s for s in steps if s.get('source') == 'agent']
            step_stats_by_agent[r['agent']]['steps'].append(len(agent_steps))

            # Count tool calls
            for step in agent_steps:
                for tc in step.get('tool_calls', []):
                    fn_name = tc.get('function_name', 'unknown')
                    step_stats_by_agent[r['agent']]['tool_calls'][fn_name] += 1
        except (json.JSONDecodeError, OSError):
            continue

    step_analysis = []
    for agent, stats in step_stats_by_agent.items():
        if not stats['steps']:
            continue
        steps_list = stats['steps']
        entry = {
            'agent': agent,
            'avg_steps': round(sum(steps_list) / len(steps_list), 1),
            'min_steps': min(steps_list),
            'max_steps': max(steps_list),
            'total_tasks': len(steps_list),
            'top_tools': sorted(
                stats['tool_calls'].items(),
                key=lambda x: -x[1]
            )[:5]
        }
        step_analysis.append(entry)

    step_analysis.sort(key=lambda x: -x['total_tasks'])

    # Duration analysis by agent
    duration_by_agent = defaultdict(lambda: {'durations': [], 'success_durations': []})
    for r in runs:
        if r.get('duration'):
            duration_by_agent[r['agent']]['durations'].append(r['duration'])
            if r.get('reward') == 1:
                duration_by_agent[r['agent']]['success_durations'].append(r['duration'])

    duration_analysis = []
    for agent, stats in duration_by_agent.items():
        if not stats['durations']:
            continue
        durations = stats['durations']
        success_durations = stats['success_durations']
        entry = {
            'agent': agent,
            'avg_duration': round(sum(durations) / len(durations), 1),
            'avg_success_duration': round(
                sum(success_durations) / len(success_durations), 1
            ) if success_durations else 0,
            'total_tasks': len(durations)
        }
        duration_analysis.append(entry)

    duration_analysis.sort(key=lambda x: -x['total_tasks'])

    return {
        'error_breakdown': dict(error_counts),
        'token_efficiency': token_efficiency,
        'step_analysis': step_analysis,
        'duration_analysis': duration_analysis
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

        elif path == "/api/trends":
            data = compute_trends()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())

        elif path == "/api/analysis":
            data = compute_analysis()
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
