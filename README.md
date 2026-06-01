# tbench-eval — local coding agents on AMD, measured

This repository holds two things:

1. **A config-driven eval-sweep platform** that benchmarks local GGUF models — served by
   `llama-server` — against the [`harbor`](https://pypi.org/project/harbor/) CLI
   (Terminal-Bench 2.0) across multiple agent harnesses.
2. **The capstone deliverable** built on top of the data those sweeps produced: a written
   report, an executive slide deck, and an interactive dashboard, under `deliverable/` and
   `dashboard/`.

The guiding question: **how close are local, open-weight coding agents running on an AMD
Ryzen AI MAX+ 395 to being genuinely useful?** The short answer is *almost* — a real
capability gap remains, but the trajectory (intelligence-per-watt, query coverage, model
quality) is closing it fast.

---

## The deliverable

| Artifact | Where | For |
|---|---|---|
| **Report** (32 pp) | [`deliverable/report.pdf`](deliverable/report.pdf) · source `deliverable/report.md` | ML engineers — full methodology, results, failure taxonomy, per-watt analysis |
| **Slides** (19) | [`deliverable/slides.pdf`](deliverable/slides.pdf) · source `deliverable/slides.md` | Senior leaders — the distilled, narrative cut |
| **Dashboard** | `dashboard/index.html` (interactive) | Anyone — explore every model, task, and trajectory |

### Headline numbers

- **848** graded trials across **14** local models × 3 agent harnesses; **561** valid after
  data-hygiene filtering; **240.8M** tokens generated.
- On a curated easy agentic-terminal slice, the best local config (terminus-2 + a 35B-A3B MoE)
  **matches or beats** the best API-served open model.
- On the *full* Terminal-Bench 2.0 the gap is still wide (open ~52% vs frontier ~90%) — the
  report keeps these two scopes strictly separate.

---

## Platform

### Layout

```
bin/sweep.sh        The single sweep runner
lib/                Model lifecycle engine (model_manager.sh)
config/
  agents/           One <agent>.conf per agent harness (networking + extra flags)
  models/           Model lists (Name|HF_REPO|VARIANT)
  tasks/            Task lists (bare "task" or "dataset|task")
dashboard/          Interactive dashboard (index.html) + live results browser (dashboard.py)
deliverable/        Report, slides, analysis pipeline, charts, design system
docs/               Setup guide, networking notes, status reports (docs/status/)
archive/            Prior orchestrators, retained for reference
results/            Run outputs — git-ignored (3.2 GB; regenerable via the harness)
```

> **Note on `results/`** — the raw trajectories and logs (3.2 GB) are excluded from version
> control. Every derived artifact the deliverable depends on is committed: the dashboard data
> bundle, charts, analysis CSVs, and the report. To regenerate the raw data, re-run the sweeps.

### Prerequisites

- `harbor` installed (`uv tool install harbor`) and `docker` available.
- `llama-server` built and reachable by `lib/model_manager.sh` (paths configured there).
- See `docs/SETUP_GUIDE.md` for full environment setup and
  `docs/OPENHANDS_NETWORKING_FIXES.md` for the Docker host-networking details.

### Quickstart

```bash
# terminus-2 across the default model/task lists
./bin/sweep.sh -a terminus-2 -m config/models/batch1.txt -t config/tasks/easy.txt

# openhands on the merged easy task set
./bin/sweep.sh -a openhands -t config/tasks/easy_merged.txt

# dry run: prints the exact commands, synthesizes rewards, writes nothing real
./bin/sweep.sh -a terminus-2 -t config/tasks/easy.txt --dry-run
```

Run `./bin/sweep.sh -h` for all flags (`--models`, `--tasks`, `--dataset`, `--timeout`,
`--tm`, `--runs`, `--tag`, `--dry-run`).

### How a sweep works

For each model in the models file:

1. Clean up the previous model (stop server, delete cache).
2. Download the model and start `llama-server` on `:8000`.
3. For each task, run the core command:

   ```bash
   timeout <SECS> harbor run \
     -d <dataset> -a <agent> -m "openai/<model>" \
     <agent-specific flags> \
     -n <runs> --timeout-multiplier <mult> --jobs-dir <job-dir> -t <task>
   ```

4. Grade: a task **passes** when its `reward.txt` is `1`.
5. Append to the per-sweep summary under `results/__sweep-summaries/`.

Results land in `results/<agent>-<model>[-tag]/<task>/`.

### Agent profiles

| Agent | Networking | Notes |
|-------|-----------|-------|
| `terminus-2` | localhost | Native; LLM calls originate on the host. |
| `openhands`  | host IP   | Injects the host endpoint via the `api_base` agent-kwarg. |
| `qwen-coder` | host IP   | Also exports `OPENAI_BASE_URL`. |

Each profile (`config/agents/<agent>.conf`) declares its networking mode and any extra harbor
arguments. **Add a new agent** by copying the closest existing profile and adjusting it.

---

## Dashboard

**Interactive dashboard** (`dashboard/index.html`) — a self-contained, explorable view of the
validated results: capability (model × agent), a full clickable model × task heatmap,
efficiency / tokens-per-watt, the failure taxonomy with quoted generations, and per-trial
trajectory drill-down. Open it directly in a browser — it reads the committed
`dashboard/dashboard_data.js` + `dashboard_traj.js`, no server needed. Rebuild the data bundle
from the analysis pipeline:

```bash
python deliverable/analysis/build_dashboard_full.py   # regenerates dashboard_data.js + dashboard_traj.js
```

**Live results browser** (`dashboard/dashboard.py`) — scans `results/` directly and serves a
trajectory browser (requires the raw `results/`):

```bash
python dashboard/dashboard.py 8080      # http://localhost:8080
```

---

## Reproducing the analysis

The full pipeline lives in `deliverable/analysis/` (Python stdlib + pandas/matplotlib):

```bash
cd deliverable
python analysis/extract_metrics.py        # walk results/ -> data/{calls,trials}.csv, validity.csv
python analysis/mine_failures.py          # failure taxonomy + quoted examples
python analysis/make_charts.py            # publication charts (dark + light themes)
python analysis/build_dashboard_full.py   # dashboard data bundle
```

See `deliverable/RENDER.md` for the report (Pandoc) and slides (Marp) render commands.

---

*Harsh Singh — Research & Advanced Development, AMD. Supervisors: Eddie Richter · Paul Hartke.*
