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
    runs = []

    for run_dir in sorted(RESULTS_DIR.iterdir()):
        if not run_dir.is_dir() or run_dir.name.startswith((".", "__")):
            continue
        if run_dir.name == "summary.csv":
            continue

        run_name = run_dir.name
        # Parse agent and model tag from dir name
        # e.g. "terminus-2-m2.1-fireworks" or "openhands-qwen-30b-local"
        if run_name.startswith("openhands-"):
            agent = "openhands"
            model_tag = run_name[len("openhands-"):]
        elif run_name.startswith("terminus-2-"):
            agent = "terminus-2"
            model_tag = run_name[len("terminus-2-"):]
        else:
            agent = run_name.split("-")[0]
            model_tag = "-".join(run_name.split("-")[1:])

        # Find the job directory (timestamp-named)
        for job_dir in sorted(run_dir.iterdir()):
            if not job_dir.is_dir():
                continue

            # Each subdirectory is a trial
            for trial_dir in sorted(job_dir.iterdir()):
                if not trial_dir.is_dir():
                    continue

                result_file = trial_dir / "result.json"
                if not result_file.exists():
                    continue

                try:
                    result = json.loads(result_file.read_text())
                except (json.JSONDecodeError, OSError):
                    continue

                # Extract task name (strip the __hash suffix)
                trial_name = trial_dir.name
                task_name = trial_name.rsplit("__", 1)[0] if "__" in trial_name else trial_name

                # Get reward
                reward = None
                reward_file = trial_dir / "verifier" / "reward.txt"
                if reward_file.exists():
                    try:
                        reward = float(reward_file.read_text().strip())
                    except (ValueError, OSError):
                        pass

                if reward is None:
                    reward = result.get("reward")

                # Get duration
                duration = None
                started = result.get("started_at")
                finished = result.get("finished_at")
                if started and finished:
                    from datetime import datetime
                    try:
                        s_dt = datetime.fromisoformat(started.replace("Z", "+00:00"))
                        f_dt = datetime.fromisoformat(finished.replace("Z", "+00:00"))
                        duration = (f_dt - s_dt).total_seconds()
                    except Exception:
                        pass

                # Get token counts from trajectory
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

                # Error info
                error = None
                exc_info = result.get("exception_info")
                if exc_info:
                    error = exc_info.get("exception_type", "Unknown")

                has_trajectory = traj_file.exists()

                runs.append({
                    "run": run_name,
                    "agent": agent,
                    "model_tag": model_tag,
                    "task": task_name,
                    "trial_name": trial_name,
                    "reward": reward,
                    "duration": round(duration, 1) if duration else None,
                    "error": error,
                    "tokens": tokens,
                    "has_trajectory": has_trajectory,
                    "trajectory_path": f"{run_name}/{job_dir.name}/{trial_name}",
                })

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
