---
diataxis_type: reference
---

# Channel packs

Channel packs are render adapters. Each one takes the surviving findings corpus and
delivers it through a specific output medium. Channel packs are MIF-exempt from Level 3
requirements unless otherwise noted — they consume MIF-annotated findings but their
output prose carries no internal research identity (no `urn:mif:` URNs, no finding `@id`
handles, no corpus paths).

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## book

**Version:** 0.1.2 | **Kind:** channel | **MIF level:** exempt (output only)

### Purpose

Renders the surviving findings corpus into a book chapter or full manuscript. The skill
drives `synthesize-artifact.sh` to assemble surviving findings into a structured outline,
then `render-artifact.sh` to produce polished prose in the requested genre. It covers
technical, children's, fiction, history, and non-fiction genres.

### When to use

Use `book` when the research outcome is a long-form narrative document — a published
chapter, a white paper structured as a book, or any manuscript that requires genre-aware
prose rather than a structured report.

### What it provides

- Genre-appropriate manuscript prose from the full surviving findings corpus
- Structured outline assembly before prose generation
- Citation-clean output: no internal finding IDs, URNs, or corpus paths appear in
  the manuscript prose (citation-leak gate enforced)

### Dependencies

None beyond the core engine.

### Benefits

- Produces audience-ready prose without manual reformatting of research outputs
- Enforces the citation-leak gate so manuscript prose never leaks internal identifiers
- Supports five genre modes from a single skill invocation

### Enable

```sh
scripts/pack-toggle.sh book on
```

---

## diataxis

**Version:** 0.1.2 | **Kind:** channel | **MIF level:** L1 only (output)

### Purpose

Emits a Diátaxis documentation site from the findings corpus. The skill runs
`packs/channels/diataxis/scripts/render-diataxis.sh` (jq-only, no external dependencies
beyond jq) and produces a documentation tree rooted at `docs/`:

```text
docs/
├── index.md
├── reference/
├── explanation/
├── how-to/
└── tutorials/
```

Every page it generates carries MIF Level 1 typed-identity frontmatter and a
`diataxis_type` marker classifying the page's quadrant.

### When to use

Use `diataxis` when research findings need to be published as structured documentation
rather than a prose report — for example, turning API research into a reference site or
methodology research into a how-to guide set.

### What it provides

- Full Diátaxis four-quadrant site structure generated from the findings corpus
- MIF L1 frontmatter on every emitted page
- `diataxis_type` quadrant classification per page
- Pure jq rendering pipeline with no additional runtime dependencies

### Dependencies

- `jq`

### Benefits

- Converts research directly into a navigable documentation site without manual
  page-by-page authoring
- Enforces Diátaxis quadrant separation so tutorial, reference, how-to, and explanation
  content stays structurally distinct
- jq-only pipeline means no build toolchain required beyond what the core engine provides

### Enable

```sh
scripts/pack-toggle.sh diataxis on
```

---

## github-discuss

**Version:** 0.1.2 | **Kind:** channel

### Purpose

Posts findings-grounded GitHub Discussions threads. The skill reads the findings corpus
directly (never a rendered report) and creates Discussion posts of three types:
`announce`, `question`, and `anecdotal`. It requires the `gh` CLI authenticated via
`gh auth login`. When `gh` is unavailable it degrades gracefully and writes posts to
local files instead.

### When to use

Use `github-discuss` when research conclusions should feed community discussion —
announcing a finding to project stakeholders, surfacing an open question for community
input, or sharing an anecdotal data point for collective validation.

### What it provides

- Discussion posts typed as `announce`, `question`, or `anecdotal`
- Source-grounded posts drawn from the findings corpus, not from a rendered report
- Graceful degradation to local-file output when `gh` is unavailable

### Dependencies

- `gh` CLI (authenticated via `gh auth login`)
- `jq`

### Benefits

- Closes the loop between research and community by publishing findings where contributors
  already work
- Three post types keep discussion intent explicit and searchable
- Degrades gracefully so the workflow completes even without GitHub access

### Enable

```sh
scripts/pack-toggle.sh github-discuss on
```

---

## github-issues

**Version:** 0.1.2 | **Kind:** channel

### Purpose

Files categorized GitHub Issues from the findings corpus. The skill maps each finding to
one of four categories — `feature`, `enhancement`, `follow-up`, `action-item` — and
assigns a priority tier:

| Priority | Criteria |
| --- | --- |
| P0 | Strong evidence, high impact, blocks progress |
| P1 | Clear evidence, significant impact |
| P2 | Moderate evidence or lower impact |
| P3 | Speculative or exploratory |

When `gh` is unavailable the skill degrades to local-write mode and outputs `issues.json`.

### When to use

Use `github-issues` when research findings map to concrete engineering or product work
items — converting a competitive gap into a feature request, turning a regulatory finding
into a compliance action item, or flagging a follow-up research question.

### What it provides

- Issues categorized as `feature`, `enhancement`, `follow-up`, or `action-item`
- Four-tier priority assignment (P0–P3) grounded in finding evidence strength
- Graceful degradation to `issues.json` when `gh` is unavailable

### Dependencies

- `gh` CLI (authenticated via `gh auth login`)
- `jq`

### Benefits

- Translates research output directly into a tracked backlog without manual transcription
- Priority tiers keep issue triage grounded in evidence rather than subjective judgment
- Degrades gracefully so no work is lost when GitHub access is absent

### Enable

```sh
scripts/pack-toggle.sh github-issues on
```

---

## notebooklm

**Version:** 0.1.2 | **Kind:** channel

### Purpose

Adds the findings corpus to a NotebookLM notebook and triggers export of AI-generated
assets. The skill adds primary citation URLs to the notebook (not a rendered report) plus
a findings digest, then uses the Monitor tool to poll for asset completion. It writes a
`manifest.json` listing completed assets. Supported assets:

- Audio deep-dive
- Slide deck (PDF)
- Infographic
- Video
- Mind map

Requires the external `nlm` CLI authenticated via `nlm login`.

### When to use

Use `notebooklm` when research findings should be delivered as AI-generated media assets
— a podcast-style audio summary, a slide deck for a presentation, or a visual mind map
for stakeholder communication.

### What it provides

- Primary citation URLs and a findings digest added to a NotebookLM notebook
- Polling (via Monitor) for asset generation completion
- `manifest.json` listing all generated assets and their locations

### Dependencies

- `nlm` CLI (authenticated via `nlm login`)
- `jq`
- `python3`

### Benefits

- Delivers research as audio, slide, and visual formats that reach audiences who do not
  read structured reports
- Polling via Monitor means the workflow waits for assets without blocking other work
- `manifest.json` gives downstream consumers a stable index of generated assets

### Enable

```sh
scripts/pack-toggle.sh notebooklm on
```

---

## pdf

**Version:** 0.1.2 | **Kind:** channel | **MIF level:** L1 in PDF metadata

### Purpose

Produces a self-contained PDF report from the findings corpus via pandoc. The PDF is
exhaustive: one section per surviving finding plus a numbered References list. MIF Level 1
typed identity is embedded in the PDF `subject` metadata field. Mermaid diagrams are
rendered via `@mermaid-js/mermaid-cli` when available; the skill degrades gracefully when
it is not. Requires pandoc and one of: xelatex, weasyprint, or wkhtmltopdf.

### When to use

Use `pdf` when the deliverable must be a portable, self-contained document suitable for
distribution outside the repository — for compliance hand-offs, stakeholder packages, or
archival.

### What it provides

- One PDF section per surviving finding with a numbered References list
- MIF L1 typed identity in the PDF `subject` metadata field
- Optional Mermaid diagram rendering (graceful degradation when `mermaid-cli` absent)
- Support for three PDF engines (xelatex, weasyprint, wkhtmltopdf)

### Dependencies

- `pandoc`
- One of: `xelatex`, `weasyprint`, `wkhtmltopdf`
- `jq`
- `@mermaid-js/mermaid-cli` via `npx` (optional)

### Benefits

- Produces a portable, distributable document without requiring the recipient to have
  the harness installed
- Exhaustive one-section-per-finding structure ensures no finding is silently omitted
  from the PDF
- MIF L1 metadata embeds research identity in the document itself, not just the filename

### Enable

```sh
scripts/pack-toggle.sh pdf on
```
