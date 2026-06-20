---
name: notebooklm
description: "Render a synthesized deliverable to NotebookLM assets — audio deep-dive, slide deck, infographics, video, mind map. A channel adapter behind the findings→artifact contract: input is the report-synthesizer artifact, output is one or more NotebookLM studio assets. Optional channel; depends on the external `nlm` CLI. Use when the user says 'notebooklm artifacts', 'audio overview', 'generate a podcast from the report', or 'nlm assets'."
version: 1.0.0
argument-hint: "<artifact-path> [--only audio|slides|infographic|video|mindmap] [--force]"
allowed-tools: Read, Write, Bash, Grep, Glob, Monitor
---

# NotebookLM Channel Adapter

Render a synthesized deliverable to NotebookLM studio assets. Input is the
**rendered artifact** produced by `report-synthesizer` (a clean, already-cited
document), not the findings corpus. This adapter only ever touches the artifact,
so internal references never enter the output.

This is an **optional** channel. It depends on the external [`nlm` CLI](https://github.com/) being installed and authenticated. If `nlm` is unavailable, degrade gracefully (see below).

## Phase 0: Resolve the Artifact

1. Resolve `<artifact-path>` to the synthesized deliverable Markdown file. If omitted, glob the topic's output directory for the rendered report artifact and ask which to render if more than one is found.
2. Read the artifact. It is the single source for every asset — read no corpus files.
3. Detect a prior run: a sibling `_assets/manifest.json` marks an **update** (refresh existing assets); its absence marks an **initial** run (create `_assets/` and `slides/`).

## Phase 1: Plan Assets

Infer the most impactful subset from the artifact's structure (headings, tables, summary). Do not use a fixed checklist.

| Asset | Produce when | nlm command |
| --- | --- | --- |
| Audio deep-dive | Always — executive briefing | `nlm audio create <nb> --format deep_dive --length long --focus "<focus>" --confirm` |
| Slide deck (PDF) | Always — presentation deliverable | `nlm slides create <nb> --format detailed_deck --focus "<focus>" --confirm` |
| Infographic | One per major section/insight (3–6) | `nlm infographic create <nb> --style instructional --orientation landscape --detail detailed --focus "<focus>" --confirm` |
| Video | Strong narrative arc | `nlm video create <nb> --focus "<focus>" --confirm` |
| Mind map | Complex entity taxonomy | `nlm mindmap create <nb> --title "<title>" --confirm` |

`--only <type>` restricts the plan to one asset type. On update runs, refresh only assets whose source sections changed (unless `--force`). Output a numbered plan, then proceed to the dependency check before executing.

## Dependency Check (before executing any nlm operations)

```bash
command -v nlm >/dev/null 2>&1 || { echo "nlm CLI not installed — this channel is unavailable. Install nlm and run 'nlm login', then retry."; exit 0; }
nlm login --check || { echo "nlm not authenticated. Run 'nlm login' and retry."; exit 0; }
```

If either check fails, report the install/auth step and stop — do not error. The plan produced in Phase 1 is still visible to the user so they know what will run once nlm is available.

## Phase 2: Notebook + Sources

1. Initial run: `nlm notebook create "<artifact title>"` and capture the notebook id. Update run: reuse the id from `manifest.json`; recreate if deleted, and delete stale sources before re-adding.
2. Add the artifact as a file source: `nlm source add <nb> --file <artifact-path> --title "Report"`. Add any rendered figures the artifact references. Throttle ~2s between additions.

## Phase 3: Generate, Wait, Download

1. For each planned asset, craft a `--focus` string grounded in the artifact's own content — name the actual sections, figures, and conclusions it contains. Submit with `--confirm` and capture the asset id from stdout.
2. After submitting all, use a **single Monitor** to wait for completion, counting assets with `status == "completed"` against the expected total (assets may end in `failed`/`unknown` without passing through `completed`). Use `timeout_ms: 900000`.

```bash
NB=<nb>; EXPECTED=<count>; while true; do
  s=$(nlm studio status "$NB" 2>/dev/null)
  done=$(echo "$s" | python3 -c "import json,sys;a=json.load(sys.stdin);print(len([x for x in a if x['status'] in ('completed','failed','unknown')]))" 2>/dev/null)
  echo "$done/$EXPECTED settled"; [ "$done" -ge "$EXPECTED" ] && { echo ALL_DONE; exit 0; }; sleep 10
done
```

1. After `ALL_DONE`, download each asset with the matching subcommand and `--id`. Slide PDFs go to `slides/`; everything else to `_assets/`. On update runs, archive the prior file as `<name>-<date>-prev.ext` before replacing.

## Phase 4: Manifest

Write `_assets/manifest.json` recording the notebook id, generation timestamp, and per-asset `{type, filename, output_dir, focus_used, asset_id, generated_at, supersedes}`. This drives future update runs.

## Error Handling

- `failed`/`unknown` asset: retry once, then log in the manifest and continue.
- Download failure: retry once, then log and continue.
- Report total assets produced, any failures, and the manifest path.
