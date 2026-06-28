---
name: pdf
description: "Produce a styled, print-ready PDF directly FROM THE SOURCES — a research topic's surviving findings corpus and the primary materials its citations point to. Composes a comprehensive document grounded in the findings (one section per finding, with each finding's primary-source citations) and a complete References list, then renders it with pandoc + a title page + rasterized Mermaid diagrams. NEVER built from a rendered report (that would be a copy-of-a-copy). Optional channel; depends on pandoc + a PDF engine, and mermaid-cli for diagrams. Use when the user says 'render to PDF', 'export as PDF', or 'make a PDF'."
version: 0.4.1
argument-hint: "<findings-dir> [-o <output.pdf>] [<topic-name>]"
allowed-tools: Read, Write, Bash, Grep, Glob
---

# PDF Channel — source-grounded

**Non-negotiable: this deliverable is produced from the SOURCES alone.** The input
is the topic's surviving findings corpus (`reports/<topic>/findings/*.json`) and the
primary materials its citations reference — never a rendered report, blog, or other
channel's output. Building a PDF from a synthesized report would be a copy-of-a-copy
(a simulacrum of the sources); it is forbidden. Every section traces to a finding,
and every claim to that finding's primary-source citation.

This is an **optional** channel. It depends on the external `pandoc` toolchain (a PDF engine — `xelatex`, `weasyprint`, or `wkhtmltopdf`) and, for diagram rendering, `@mermaid-js/mermaid-cli` via `npx`. If a dependency is missing, degrade gracefully (see below).

## Dependency Check (run first)

```bash
command -v pandoc >/dev/null 2>&1 || { echo "pandoc not installed — this channel is unavailable. Install with 'brew install pandoc' and retry."; exit 0; }
ENGINE=$(for e in xelatex weasyprint wkhtmltopdf; do command -v "$e" >/dev/null 2>&1 && { echo "$e"; break; }; done)
[ -z "$ENGINE" ] && { echo "No PDF engine found. Install one (e.g. 'brew install --cask mactex-no-gui' or 'pip3 install weasyprint') and retry."; exit 0; }
```

If pandoc or every engine is missing, report the install step and stop — do not error. Mermaid rendering is independently optional: if `mermaid-cli` is unavailable or a diagram fails, leave that block as raw text and continue.

## Phase 0: Load the sources

Resolve `<findings-dir>` to the topic's findings directory. Load **every surviving
finding** (verdict ≠ `falsified`):

```bash
jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "<findings-dir>"/*.json
```

Each finding carries: `title` (the verified claim), `content`, `citations[]` (its
**primary sources** — title + url + type + role), `entities[]`, and
`extensions.harness.dimension`/`verification.verdict`. These are the sources. Read
no rendered report or artifact. Default output is `<findings-dir>/../<topic>.pdf`.

## Phase 1: Compose the document FROM the sources

Author a comprehensive Markdown deliverable grounded in the findings — **exhaustive,
one section per finding**, never a thinned summary:

1. **Title page** — the topic name and date (from the corpus namespace / today).
2. **Body** — for every surviving finding, a `##` section: the claim, its content,
   its key entities, and its **primary-source citations** rendered as links
   (`[title](url)`). Group by dimension if that aids the reader.
3. **References** — a numbered list of **every unique primary source** (citation)
   across all findings: the actual materials the research rests on. This is the
   point — the reader can follow each claim back to its primary source.

Constraints: every claim traces to a finding and its primary source; invent nothing
not in the findings. The body carries **no internal-research identity** — emit
finding claims + public citations only, never finding/concept `@id`s, `urn:mif:`
ids, `reports/<slug>/` paths, or `f_<dim>_<n>` handles. Stamp the PDF with the
topic's MIF identity via document metadata (Phase 3), not in the body.

Write the composed Markdown to `/tmp/<name>-src.md`.

## Phase 2: Pre-process Diagrams

1. Extract every ` ```mermaid ` block you authored, numbered sequentially.
2. For each: write the block to `/tmp/diagram-<name>-<N>.mmd`, write a puppeteer config `{"args":["--no-sandbox","--disable-setuid-sandbox"],"headless":true}` to `/tmp/puppeteer-config.json`, and render to **PNG** (SVG renders textless in headless Chromium):

```bash
npx --yes @mermaid-js/mermaid-cli -i /tmp/diagram-<name>-<N>.mmd -o /tmp/diagram-<name>-<N>.png \
  --theme default --scale 3 -b white --puppeteerConfigFile /tmp/puppeteer-config.json --quiet
```

1. Write `/tmp/<name>-pre.md` — a copy of `/tmp/<name>-src.md` with each successfully rendered block replaced by `![Diagram <N>](/tmp/diagram-<name>-<N>.png)`. On render failure, leave the block as text and warn.
2. Resolve relative image paths to absolute paths so pandoc can find them.

## Phase 3: Convert

Detect fonts (`fc-list | grep -i Inter`, `... 'JetBrains Mono'`; fall back to `Helvetica Neue`/`Menlo`). Ensure the output directory exists, then render the FULL document (`--toc-depth` limits only the table of contents, never the body), stamping the topic's MIF identity into the PDF metadata:

```bash
# Include the LaTeX title page only when Phase 1 generated it (the xelatex path).
# For the non-xelatex path the title <div> was already prepended to <name>-pre.md,
# so no --include-before-body is used — passing a missing file would fail pandoc.
TITLE_OPT=""; [ -f /tmp/<name>-title.tex ] && TITLE_OPT="--include-before-body=/tmp/<name>-title.tex"

pandoc /tmp/<name>-pre.md -o <output.pdf> \
  --pdf-engine="$ENGINE" \
  --metadata title="<topic title>" --metadata author="<namespace>" \
  --metadata subject="urn:mif:pdf:<namespace>:<slug>" \
  --variable geometry:margin=1in --variable fontsize=11pt \
  --variable mainfont="<font>" --variable monofont="<mono>" \
  --variable colorlinks=true --variable linkcolor=blue --variable urlcolor=blue \
  --highlight-style=github --toc --toc-depth=3 \
  -f gfm+pipe_tables+strikethrough+task_lists+autolink_bare_uris \
  --standalone $TITLE_OPT --resource-path=.
```

The
`subject` metadata gives the PDF a traceable MIF Level-1 identity; the binary PDF
format itself is exempt from the L3 I/O conformance gate.

## Phase 4: Verify and Clean Up

1. Confirm the PDF exists and is non-empty (`ls -lh <output.pdf>`); report its size and path.
2. Confirm completeness: the PDF has a section for **every** surviving finding and a References entry for every primary source — spot-check the count.
3. Remove temp files: `/tmp/diagram-<name>-*` `/tmp/<name>-src.md` `/tmp/<name>-pre.md` `/tmp/<name>-title.tex`.

## Non-negotiables

- **Sources only.** Build from the findings corpus + primary citations. Never from a rendered report/blog/book/artifact — that is a copy-of-a-copy and is forbidden.
- **Exhaustive.** Every surviving finding gets a section; every primary source a reference. No truncation.
- **No internal identity in the body.** Finding/concept ids, `urn:mif:`, corpus paths, and `f_<dim>_<n>` handles never render into the PDF; the source's MIF identity rides in PDF metadata.

## Error Handling

- Missing embedded image: warn and continue (pandoc shows a placeholder).
- Mermaid failure on one diagram: warn with the number, keep raw block, continue.
- pandoc failure: surface the full error for diagnosis.
- Empty PDF: warn and suggest checking the composed Markdown for syntax issues.
