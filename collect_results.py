#!/usr/bin/env python3
"""Parse Harbor result directories into a single CSV summary."""

import csv
import json
import os
from pathlib import Path

RESULTS_DIR = Path(os.path.dirname(os.path.abspath(__file__))) / "results"
OUTPUT = RESULTS_DIR / "summary.csv"


def main():
    rows = []

    for run_dir in sorted(RESULTS_DIR.iterdir()):
        if not run_dir.is_dir() or run_dir.name.startswith(("__", ".")):
            continue

        # Parse agent-tag from directory name (e.g., "terminus-2-qwen-30b-local")
        run_name = run_dir.name

        # Walk all subdirectories looking for result.json files
        for result_file in run_dir.rglob("result.json"):
            try:
                result = json.loads(result_file.read_text())
            except (json.JSONDecodeError, OSError):
                continue

            # Try to get reward from verifier
            reward = None
            reward_file = result_file.parent / "verifier" / "reward.txt"
            if reward_file.exists():
                try:
                    reward = float(reward_file.read_text().strip())
                except (ValueError, OSError):
                    pass

            # Determine success from result.json or reward.txt
            success = result.get("success", None)
            if success is None and "reward" in result:
                success = result["reward"] == 1.0
            if success is None and reward is not None:
                success = reward == 1.0

            row = {
                "run": run_name,
                "task_id": result.get("task_id", result_file.parent.name),
                "success": success,
                "reward": reward if reward is not None else result.get("reward"),
                "duration_s": result.get("duration"),
                "error": result.get("error"),
            }
            rows.append(row)

    if rows:
        with open(OUTPUT, "w", newline="") as f:
            fieldnames = ["run", "task_id", "success", "reward", "duration_s", "error"]
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

        # Print summary table
        print(f"\nWrote {len(rows)} trial results to {OUTPUT}\n")

        # Aggregate pass rates per run
        from collections import defaultdict

        stats = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0, "total": 0})
        for row in rows:
            run = row["run"]
            stats[run]["total"] += 1
            if row["success"] is True:
                stats[run]["pass"] += 1
            elif row["error"]:
                stats[run]["error"] += 1
            else:
                stats[run]["fail"] += 1

        print(f"{'Run':<45} {'Pass':>5} {'Fail':>5} {'Err':>5} {'Total':>5} {'Rate':>7}")
        print("-" * 80)
        for run, s in sorted(stats.items()):
            rate = s["pass"] / s["total"] * 100 if s["total"] > 0 else 0
            print(
                f"{run:<45} {s['pass']:>5} {s['fail']:>5} {s['error']:>5} {s['total']:>5} {rate:>6.1f}%"
            )
    else:
        print("No results found. Check that Harbor wrote to ./results/")


if __name__ == "__main__":
    main()
