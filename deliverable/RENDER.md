# Rendering the deliverables

All artifacts share one design system (`theme/`). Charts are pre-rendered in `assets/`
(dark for slides, light for the report). Regenerate everything from the validated data with:

```bash
cd deliverable/analysis
python3 extract_metrics.py        # results/ -> data/*.csv
python3 classify_validity.py      # -> validity.csv, trials_valid.csv, validity_report.md
python3 make_charts.py            # -> assets/{dark,light}/*.png
python3 mine_failures.py          # -> failures_report.md, failure_examples.json, failure chart
python3 build_report_tables.py    # -> report_tables.md (all report tables)
python3 build_dashboard_data.py   # -> dashboard/dashboard_data.{json,js}
```

## Report (document) — Pandoc

Light "Editorial Lab" skin of the AMD/Phosphor system.

```bash
cd deliverable
pandoc report.md -s --toc --toc-depth=1 --css theme/report.css \
  -f markdown-native_divs-native_spans -o report.html
# then print report.html to PDF from a browser (Cmd/Ctrl-P), or:
#   wkhtmltopdf --enable-local-file-access report.html report.pdf
#   weasyprint report.html report.pdf
```

(Verified: renders to ~32 pages. The `-f markdown-native_divs-native_spans` flag is required so the
agent-trace figures' raw HTML passes through verbatim. Images are referenced relative to
`deliverable/`, so render from that directory.)

## Slides (deck) — Marp

Dark instrument skin. The `--html` and `--allow-local-files` flags are required (the agent-trace
cards are raw HTML; images are local). Point Marp at the system Chrome to avoid a Chromium download.

```bash
cd deliverable
export CHROME_PATH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"   # macOS
npx -y @marp-team/marp-cli@latest slides.md --theme theme/amd-marp.css \
  --html --allow-local-files --pdf -o slides.pdf
# .pptx:  …same flags… --pptx -o slides.pptx
# .html:  …same flags… -o slides.html   (no Chrome needed)
```

(Verified: renders to 19 slides.)

## Dashboard (interactive)

Open `dashboard/index.html` directly in a browser (reads `dashboard/dashboard_data.js`, no
server needed). For deck screenshots, the captures are in `assets/dashboard/`.

## Submitting

The rendered `report.pdf` / `slides.pdf` are the turn-in artifacts. The `deliverable/` source
can be git-ignored after rendering (add `deliverable/` to `.gitignore`); the platform code,
`dashboard/`, and `results/` stay in the repo.
