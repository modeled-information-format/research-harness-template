---
name: notebooklm
description: "Produce NotebookLM assets (audio deep-dive, slide deck, infographics, video, mind map) grounded in THE SOURCES — a research topic's surviving findings and the primary materials its citations point to. Adds the actual cited primary sources to the notebook (so NotebookLM synthesizes from source documents, not a pre-digested report) plus a findings digest. NEVER built from a rendered report (a simulacrum of the sources). Optional channel; depends on the external `nlm` CLI. Use when the user says 'notebooklm assets', 'audio overview', 'podcast from the research', or 'nlm assets'."
version: 0.4.0
argument-hint: "<findings-dir> [--only audio|slides|infographic|video|mindmap] [--force]"
allowed-tools: Read, Write, Bash, Grep, Glob, Monitor
---

# NotebookLM Channel — source-grounded

**Non-negotiable: this deliverable is produced from the SOURCES alone.** NotebookLM's
value is grounding generation in the actual source documents — so it must be given the
research's **primary sources** (the cited URLs/materials), not a pre-written report. A
NotebookLM asset built from a rendered report.md is a simulacrum of the sources (a
copy-of-a-copy) and is forbidden. The input is the topic's surviving findings corpus
(`reports/<topic>/findings/*.json`) and the primary materials its citations reference.

This is an **optional** channel. It depends on the external `nlm` CLI being installed and authenticated. If `nlm` is unavailable, degrade gracefully (see below).

## Phase 0: Load the sources

Resolve `<findings-dir>`. Load **every surviving finding** (verdict ≠ `falsified`):

```bash
jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
```

Collect the **primary sources** — the unique citation URLs across all findings:

```bash
jq -rs '[ .[] | .citations[]? | select((.url // "") != "") | .url ] | unique | .[]' "<findings-dir>"/*.json
```

These citation URLs are the actual research sources. Read no rendered report.

## Dependency Check (before any nlm operations)

```bash
command -v nlm >/dev/null 2>&1 || { echo "nlm CLI not installed — this channel is unavailable. Install nlm and run 'nlm login', then retry."; exit 0; }
nlm login --check || { echo "nlm not authenticated. Run 'nlm login' and retry."; exit 0; }
```

If either fails, report the install/auth step and stop — do not error.

## Phase 1: Notebook + PRIMARY SOURCES

This is the point of the channel — NotebookLM grounds its assets in the sources you add.

1. Create (or reuse) the notebook: `nlm notebook create "<topic> — research sources"`; capture the id. On update runs reuse the id from `_assets/manifest.json`; delete stale sources before re-adding.
2. **Add every primary source** — for each unique citation URL from Phase 0:

   ```bash
   nlm source add <nb> --url "<citation-url>" --title "<citation-title>"   # throttle ~2s between additions
   ```

   These are the cited primary materials (web pages, papers, docs). NotebookLM will synthesize its assets directly from them. For non-URL citations (a book/paper with no URL), add what is addressable and note the rest.
3. **Add a findings digest** as a text/file source — author a Markdown file listing every surviving finding's verified claim and which primary source(s) it rests on, then `nlm source add <nb> --file <digest.md> --title "Research findings"`. This gives NotebookLM the research's structure and conclusions *on top of* the primary sources — it does not replace them. The digest carries no internal-research identity (claims + public citations only; no finding `@id`s, `urn:mif:`, corpus paths, or `f_<dim>_<n>`).

The notebook's sources are now the primary materials + the findings digest — never a rendered report.

## Phase 2: Plan Assets (exhaustive)

Infer the asset set from the findings' breadth, covering the WHOLE corpus — not a cherry-picked subset.

| Asset | Produce when | nlm command |
| --- | --- | --- |
| Audio deep-dive | Always — covers the full set of findings | `nlm audio create <nb> --format deep_dive --length long --focus "<focus>" --confirm` |
| Slide deck (PDF) | Always — a slide per major finding/dimension | `nlm slides create <nb> --format detailed_deck --focus "<focus>" --confirm` |
| Infographic | One per research dimension / major insight (cover all) | `nlm infographic create <nb> --style instructional --orientation landscape --detail detailed --focus "<focus>" --confirm` |
| Video | Strong narrative across the findings | `nlm video create <nb> --focus "<focus>" --confirm` |
| Mind map | The entity/finding taxonomy | `nlm mindmap create <nb> --title "<title>" --confirm` |

`--only <type>` restricts to one asset type. Each `--focus` names the actual findings and primary sources so the asset spans the full corpus. On update runs, refresh only assets whose findings changed (unless `--force`). Output a numbered plan, then execute.

## Phase 3: Generate, Wait, Download

1. Submit each planned asset with `--confirm`; capture the asset id.
2. Use a **single Monitor** to wait for completion (assets may end `failed`/`unknown` without `completed`). `timeout_ms: 900000`:

```bash
NB=<nb>; EXPECTED=<count>; while true; do
  s=$(nlm studio status "$NB" 2>/dev/null)
  done=$(echo "$s" | python3 -c "import json,sys;a=json.load(sys.stdin);print(len([x for x in a if x['status'] in ('completed','failed','unknown')]))" 2>/dev/null)
  echo "$done/$EXPECTED settled"; [ "$done" -ge "$EXPECTED" ] && { echo ALL_DONE; exit 0; }; sleep 10
done
```

1. After `ALL_DONE`, download each asset (`--id`). Slide PDFs go to `slides/`; everything else to `_assets/`. On update runs, archive the prior file as `<name>-<date>-prev.ext` before replacing.

## Phase 4: Manifest

Write `_assets/manifest.json` recording: the notebook id; the **primary sources added** (the citation URLs/titles); the findings digest path; the generation timestamp; and per-asset `{type, filename, output_dir, focus_used, asset_id, generated_at, supersedes}`. The recorded primary sources are the provenance — every asset traces to them.

## Non-negotiables

- **Sources only.** Add the cited primary sources to the notebook. Never feed NotebookLM a rendered report/blog/book as its sole/primary source — that produces assets grounded in a simulacrum, not the evidence.
- **Exhaustive.** The asset set covers every surviving finding / dimension; nothing cherry-picked.
- **No internal identity.** The findings digest and any focus strings carry claims + public citations only — no finding/concept ids, `urn:mif:`, corpus paths, or `f_<dim>_<n>` handles.

## Error Handling

- `failed`/`unknown` asset: retry once, then log in the manifest and continue.
- Source add failure (dead/blocked URL): retry once, then log the unreachable source and continue.
- Download failure: retry once, then log and continue.
- Report total assets produced, primary sources added, any failures, and the manifest path.
