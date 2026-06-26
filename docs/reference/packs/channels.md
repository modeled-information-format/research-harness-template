---
diataxis_type: reference
---

# Channel packs

Channel packs are render adapters. Each one takes the surviving findings corpus and
delivers it through a specific output medium. Channel packs are MIF-exempt from Level 3
requirements unless otherwise noted — they consume MIF-annotated findings but their
output prose carries no internal research identity (no `urn:mif:` URNs, no finding `@id`
handles, no corpus paths).

Channel packs are **opt-in**: each is disabled by default and enabled with
`scripts/pack-toggle.sh <name> on`.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## book

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** exempt (output only) | **Skill:** `book:book-author`

### Purpose

Renders the surviving findings corpus into a book chapter or full manuscript. The skill
drives `synthesize-artifact.sh` to assemble surviving findings into a structured outline,
then `render-artifact.sh` to produce polished prose in the requested genre. It covers
technical, children's, fiction, history, and non-fiction genres.

### When to use

Enabling the `book` pack provides the `book-author` skill (`book:book-author`).
Use it when the research outcome is a long-form narrative document — a published
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

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** L1 only (output) | **Skill:** `diataxis:diataxis-docs`

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

Enabling the `diataxis` pack provides the `diataxis-docs` skill
(`diataxis:diataxis-docs`). Use it when research findings need to be published as structured documentation
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

**Version:** 0.2.0 | **Kind:** channel

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

**Version:** 0.2.0 | **Kind:** channel

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

**Version:** 0.2.0 | **Kind:** channel

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

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** L1 in PDF metadata

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

---

## jats

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** L1 in JATS article metadata

### Purpose

Renders the surviving findings corpus into a well-formed JATS (NISO Z39.96) XML
scholarly article. JATS is a machine-readable XML *serialization* of an article — a
render target, the orthogonal analog of the `pdf` channel, not a `reports/` genre. The
article is exhaustive: a `<front>`/`<article-meta>` block, a `<body>` of one `<sec>`
per surviving finding (each linked to its primary source via `<xref ref-type="bibr">`),
and a `<back>`/`<ref-list>` of the primary-source citations. Identity rides in a public,
scheme-free `<article-id>` element — never the `urn:mif:` URN. The serialization is built from the SOURCES —
the findings and their citations — never from a rendered report.

### When to use

Use `jats` when the deliverable must be a machine-readable scholarly-article XML
suitable for journal submission, preprint servers, or archival interchange systems
that ingest NISO Z39.96 JATS.

### What it provides

- One `<body>` `<sec>` per surviving finding with `<xref>` links to a `<ref-list>`
- A `<back>`/`<ref-list>` of every unique primary-source citation
- Identity in a public, scheme-free `<article-id>` element — never the `urn:mif:` URN, never in the rendered body
- Live-verified JATS version anchoring (v1.4, Oct 2024 at this writing)

### Dependencies

- `jq`
- `xmllint` for well-formedness checking (optional)

### Benefits

- Produces a standard, interchange-ready XML serialization without requiring the
  recipient to have the harness installed
- Exhaustive one-section-per-finding structure ensures no finding is silently omitted
- MIF L1 metadata embeds research identity in the article itself, while the
  citation-leak gate keeps internal identity out of the rendered body

### Enable

```sh
scripts/pack-toggle.sh jats on
```

---

## xbrl

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** L1 in XHTML head metadata (exempt)

### Purpose

Renders surviving findings — typically a `regulatory-disclosure` artifact — into an
inline XBRL (iXBRL) document. Inline XBRL embeds machine-readable XBRL facts inside a
human-readable XHTML shell: a regulator's parser reads the tagged facts while a person
reads the rendered page. Quantified claims are tagged as `ix:nonFraction` / `ix:nonNumeric`
facts bound to declared `xbrli:context` and `xbrli:unit` elements and current-taxonomy
concepts. Like `pdf`, iXBRL is a serialization orthogonal to the MIF Level-3 report, so the
channel is `mif.exempt`; the topic's MIF Level-1 identity rides in the XHTML head metadata.

### When to use

Use `xbrl` when the deliverable must be a machine-readable regulatory disclosure — for SEC
inline-XBRL filings, structured financial reporting hand-offs, or any consumer that parses
tagged facts rather than prose.

### What it provides

- A well-formed XHTML inline-XBRL document built directly from the findings + their citations
- Facts tagged with `ix:nonFraction` / `ix:nonNumeric`, bound to `xbrli:context` / `xbrli:unit`
- Concepts anchored to the current SEC inline-XBRL taxonomy (verified live)
- MIF L1 typed identity in the XHTML head metadata, never in the visible body

### Dependencies

- `jq`

### Benefits

- Produces a machine-readable regulatory artifact a regulator's parser can consume directly
- Human-readable and machine-readable in one document — no separate rendering step
- Source-grounded: every tagged fact traces to a surviving finding and its primary source

### Enable

```sh
scripts/pack-toggle.sh xbrl on
```

---

## ectd

**Version:** 0.2.0 | **Kind:** channel | **MIF level:** L1 in backbone metadata (exempt)

### Purpose

Packages a clinical-submission into the FDA eCTD (electronic Common Technical Document)
submission structure directly from the findings corpus. It lays out the five-module
eCTD tree under a sequence directory — M1 (regional administrative), M2 (CTD summaries),
M3 (quality / CMC), M4 (nonclinical study reports), M5 (clinical study reports) — writes
a source-grounded summary leaf into each module, and emits the eCTD XML backbone that
indexes every leaf and declares the resolved eCTD version. eCTD is an electronic
submission packaging/transport format, orthogonal to MIF Level-3 markdown, so the channel
declares `mif.exempt`; the canonical L3 source of truth stays in the `report` channel.
Anchor to FDA eCTD v4.0 and verify the current version live.

### When to use

Use `ectd` when the deliverable must be an FDA-style electronic submission package — for
regulatory hand-offs that expect the M1-M5 module tree and an eCTD backbone rather than a
single prose document.

### What it provides

- The five-module eCTD tree (m1-m5) under a zero-padded submission sequence
- One source-grounded module summary leaf per module, cited to primary sources
- The eCTD XML backbone (`ectd-backbone.xml`) indexing every leaf
- MIF L1 typed identity in the backbone metadata; resolved eCTD version stamped into the backbone's `ectd-version` attribute

### Dependencies

- `jq`

### Benefits

- Produces the regulatory module/backbone container expected by FDA eCTD tooling
- Complete M1-M5 tree ensures no module is silently omitted from the submission
- Backbone metadata embeds research identity and the resolved eCTD version

### Enable

```sh
scripts/pack-toggle.sh ectd on
```
