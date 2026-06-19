---
name: pdf
description: "Render a synthesized deliverable to a styled PDF — GitHub-flavored Markdown, a generated title page, a table of contents, and rasterized Mermaid diagrams. A channel adapter behind the findings→artifact contract: input is the report-synthesizer artifact, output is a print-ready PDF. Optional channel; depends on pandoc plus a PDF engine, and on mermaid-cli for diagrams. Use when the user says 'render to PDF', 'export the report as PDF', or 'make a PDF'."
version: 1.0.0
argument-hint: "<artifact-path> [-o <output.pdf>]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# PDF Channel Adapter

Render a synthesized deliverable to a styled PDF. Input is the **rendered
artifact** from `report-synthesizer` (a clean, already-cited document), not the
findings corpus. This adapter only ever touches the artifact.

This is an **optional** channel. It depends on the external `pandoc` toolchain (a PDF engine — `xelatex`, `weasyprint`, or `wkhtmltopdf`) and, for diagram rendering, `@mermaid-js/mermaid-cli` via `npx`. If a dependency is missing, degrade gracefully (see below).

## Dependency Check (run first)

```bash
command -v pandoc >/dev/null 2>&1 || { echo "pandoc not installed — this channel is unavailable. Install with 'brew install pandoc' and retry."; exit 0; }
ENGINE=$(for e in xelatex weasyprint wkhtmltopdf; do command -v "$e" >/dev/null 2>&1 && { echo "$e"; break; }; done)
[ -z "$ENGINE" ] && { echo "No PDF engine found. Install one (e.g. 'brew install --cask mactex-no-gui' or 'pip3 install weasyprint') and retry."; exit 0; }
```

If pandoc or every engine is missing, report the install step and stop — do not error. Mermaid rendering is independently optional: if `mermaid-cli` is unavailable or a diagram fails, leave that block as raw text and continue.

## Phase 0: Resolve the Artifact

Resolve `<artifact-path>` to the synthesized deliverable Markdown file. If omitted, glob the topic's output directory for the rendered report and ask which to render if more than one is found. Read no corpus files. Default output is `<artifact-dir>/<name>.pdf` unless `-o` is given.

## Phase 1: Title Page

Build a title page from the artifact's own header. Read the first lines of the artifact for any `**Title**`, `**Date**`, `**Scope**`, or `**Confidence**` fields and the leading `#` heading.

- If the engine is `xelatex`: write a LaTeX `titlepage` block to `/tmp/<name>-title.tex` (title, "Report", date, scope) and include it via `--include-before-body`.
- Otherwise: prepend a centered HTML title `<div>` (with `page-break-after: always`) to the preprocessed Markdown.

## Phase 2: Pre-process Diagrams

1. Read the artifact and extract every ` ```mermaid ` block, numbered sequentially.
2. For each: write the block to `/tmp/diagram-<name>-<N>.mmd`, write a puppeteer config `{"args":["--no-sandbox","--disable-setuid-sandbox"],"headless":true}` to `/tmp/puppeteer-config.json`, and render to **PNG** (SVG renders textless in headless Chromium):

```bash
npx --yes @mermaid-js/mermaid-cli -i /tmp/diagram-<name>-<N>.mmd -o /tmp/diagram-<name>-<N>.png \
  --theme default --scale 3 -b white --puppeteerConfigFile /tmp/puppeteer-config.json --quiet
```

1. Write `/tmp/<name>-pre.md` — a copy of the artifact with each successfully rendered block replaced by `![Diagram <N>](/tmp/diagram-<name>-<N>.png)`. On render failure, leave the block as text and warn.
2. Resolve relative image paths in the artifact (e.g. `./_assets/...`) to absolute paths so pandoc can find them.

## Phase 3: Convert

Detect fonts (`fc-list | grep -i Inter`, `... 'JetBrains Mono'`; fall back to `Helvetica Neue`/`Menlo`). Ensure the output directory exists, then:

```bash
pandoc /tmp/<name>-pre.md -o <output.pdf> \
  --pdf-engine="$ENGINE" \
  --variable geometry:margin=1in --variable fontsize=11pt \
  --variable mainfont="<font>" --variable monofont="<mono>" \
  --variable colorlinks=true --variable linkcolor=blue --variable urlcolor=blue \
  --highlight-style=github --toc --toc-depth=3 \
  -f gfm+pipe_tables+strikethrough+task_lists+autolink_bare_uris \
  --standalone --include-before-body=/tmp/<name>-title.tex --resource-path=.
```

(Omit `--include-before-body` when the title page was prepended as HTML.)

## Phase 4: Verify and Clean Up

1. Confirm the PDF exists and is non-empty (`ls -lh <output.pdf>`); report its size and path.
2. Remove temp files: `/tmp/diagram-<name>-*` `/tmp/<name>-pre.md` `/tmp/<name>-title.tex`.

## Error Handling

- Missing embedded image: warn and continue (pandoc shows a placeholder).
- Mermaid failure on one diagram: warn with the number, keep raw block, continue.
- pandoc failure: surface the full error for diagnosis.
- Empty PDF: warn and suggest checking the artifact for syntax issues.
