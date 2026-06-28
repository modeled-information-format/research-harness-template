---
title: "Channel packs"
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

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** exempt (output only) | **Skill:** `book:book-author`

**Source:** [`packs/channels/book/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/book)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh book on`
- MIF-exempt from L3 conformance gate: published prose is orthogonal to MIF L3; canonical L3 source of truth stays in the `report` channel
- Built from the surviving findings corpus (SOURCES); never from a rendered report
- Citation-leak gate enforced: manuscript prose may not contain finding IDs, `urn:mif:` URNs, or `reports/<slug>/` paths

### Goals

- Produce genre-appropriate manuscript prose across five genres (technical, children's, fiction, history, non-fiction) from the full surviving findings corpus
- Outline assembled before prose generation via `synthesize-artifact.sh`; chapter rendered via `render-artifact.sh`
- Manuscript verified citation-leak gate clean; falsified and quarantined findings excluded

### Enable

```sh
scripts/pack-toggle.sh book on
```

---

## diataxis

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** L1 only (output) | **Skill:** `diataxis:diataxis-docs`

**Source:** [`packs/channels/diataxis/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/diataxis)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh diataxis on`
- Requires `jq`; no additional runtime dependencies beyond the core engine
- MIF-exempt from L3 conformance gate: pages carry MIF L1 identity only; canonical L3 source of truth stays in the `report` channel
- Body prose must carry no internal-research identity (no `urn:mif:concept:`, corpus paths, or finding handles); each page's own `urn:mif:doc:` frontmatter is its sole L1 identity
- Every quadrant page must stay mode-pure; tutorial, reference, how-to, and explanation content must not be mixed

### Goals

- Produce a complete four-quadrant Diátaxis documentation set (reference, explanation, how-to, tutorials) from the surviving findings corpus
- Every emitted page carries MIF L1 frontmatter and a `diataxis_type` quadrant marker, validated by `schemas/diataxis-doc.schema.json`
- Falsified findings excluded; output scales with the corpus (one reference page per surviving finding)

### Enable

```sh
scripts/pack-toggle.sh diataxis on
```

---

## github-discuss

**Version:** 0.4.1 | **Kind:** channel

**Source:** [`packs/channels/github-discuss/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/github-discuss)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh github-discuss on`
- Requires `gh` CLI authenticated via `gh auth login`; `jq`
- MIF-exempt: discussion bodies use GitHub's markdown dialect, orthogonal to MIF; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- Degrades gracefully when `gh` is unavailable: reports the missing dependency and stops cleanly

### Goals

- Produce Discussion posts typed as `announce`, `question`, or `anecdotal` from the surviving findings corpus
- Post body derived from findings and primary-source citations; no internal-research identity in the post body
- Duplicate detection for `announce` posts; `--update` mode appends a delta comment to an existing thread

### Enable

```sh
scripts/pack-toggle.sh github-discuss on
```

---

## github-issues

**Version:** 0.4.1 | **Kind:** channel

**Source:** [`packs/channels/github-issues/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/github-issues)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh github-issues on`
- Requires `gh` CLI authenticated via `gh auth login`; `jq`
- MIF-exempt: issue bodies use GitHub's markdown dialect, orthogonal to MIF; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- Degrades gracefully when `gh` is unavailable: issue set written to `issues.json` instead of filed

### Goals

- Produce issues categorized as `feature`, `enhancement`, `follow-up`, or `action-item` from the surviving findings
- Four-tier priority (P0–P3) justified by finding evidence strength and impact; each issue includes ≥2 measurable acceptance criteria
- Issue context cites primary sources only; no internal-research identity in the body; graceful degradation to `issues.json` when GitHub is unavailable

### Enable

```sh
scripts/pack-toggle.sh github-issues on
```

---

## notebooklm

**Version:** 0.4.1 | **Kind:** channel

**Source:** [`packs/channels/notebooklm/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/notebooklm)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh notebooklm on`
- Requires `nlm` CLI authenticated via `nlm login`; `jq`; `python3`
- MIF-exempt: audio/video/slide/infographic outputs are non-text formats orthogonal to MIF; canonical L3 source of truth stays in the `report` channel
- Primary citation URLs (not a rendered report) are added as notebook sources; a findings digest is added as a structured text source
- Degrades gracefully when `nlm` is unavailable: reports the missing dependency and stops cleanly

### Goals

- Add all primary citation URLs and a findings digest to the notebook so NotebookLM synthesizes assets from the actual source documents
- Asset set covers all surviving findings and dimensions (audio deep-dive, slide deck, infographic, video, mind map)
- `manifest.json` records provenance: notebook ID, primary sources added, per-asset metadata, and generation timestamps

### Enable

```sh
scripts/pack-toggle.sh notebooklm on
```

---

## pdf

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** L1 in PDF metadata

**Source:** [`packs/channels/pdf/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/pdf)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh pdf on`
- Requires `pandoc` and one of: `xelatex`, `weasyprint`, or `wkhtmltopdf`; `jq`; `@mermaid-js/mermaid-cli` via `npx` (optional for diagram rendering)
- MIF-exempt from L3 conformance gate: PDF is a binary render format orthogonal to MIF L3; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- No internal-research identity in the body: finding IDs, `urn:mif:` URNs, corpus paths, and finding handles excluded from PDF prose

### Goals

- Produce an exhaustive PDF: one section per surviving finding, numbered References list of every unique primary source
- MIF L1 typed identity embedded in the PDF `subject` metadata field
- Mermaid diagrams rendered to PNG via `@mermaid-js/mermaid-cli` when available; graceful degradation to raw text blocks when absent

### Enable

```sh
scripts/pack-toggle.sh pdf on
```

---

## jats

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** L1 in JATS article metadata

**Source:** [`packs/channels/jats/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/jats)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh jats on`
- Requires `jq`; `xmllint` used for well-formedness checking when available (optional)
- MIF-exempt from L3 conformance gate: JATS XML is a serialization orthogonal to MIF L3; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- Current NISO Z39.96 edition must be verified live before tagging (anchor: JATS v1.4, October 2024; never asserted from memory)

### Goals

- Produce an exhaustive JATS XML article: one `<sec>` per surviving finding linked via `<xref>`, one `<ref>` per unique primary source in the `<ref-list>`
- Well-formedness verified with `xmllint --noout` when available; citation-leak gate clean (no `urn:mif:` string anywhere in the serialization)
- MIF L1 identity in a public, scheme-free `<article-id>` element; internal `urn:mif:` URNs excluded from the article

### Enable

```sh
scripts/pack-toggle.sh jats on
```

---

## xbrl

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** L1 in XHTML head metadata (exempt)

**Source:** [`packs/channels/xbrl/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/xbrl)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh xbrl on`
- Requires `jq`; writes XHTML directly with no external render engine
- MIF-exempt from L3 conformance gate: inline XBRL is a regulatory serialization orthogonal to MIF L3; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- Current SEC inline-XBRL taxonomy edition must be verified live before tagging; never asserted from memory

### Goals

- Produce a well-formed XHTML5 inline-XBRL document with quantified claims tagged as `ix:nonFraction`/`ix:nonNumeric` facts bound to current-taxonomy concepts
- MIF L1 identity in the XHTML `<head>` metadata only; citation-leak gate clean (no internal identity in the visible body)
- Every unique primary source cited in the document's References section; every `contextRef`/`unitRef` resolved to a declared context/unit

### Enable

```sh
scripts/pack-toggle.sh xbrl on
```

---

## ectd

**Version:** 0.4.1 | **Kind:** channel | **MIF level:** L1 in backbone metadata (exempt)

**Source:** [`packs/channels/ectd/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/channels/ectd)

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

### Constraints

- Opt-in: disabled by default; enable with `scripts/pack-toggle.sh ectd on`
- Requires `jq`; no external toolchain (module tree is `mkdir` and backbone is XML written directly)
- MIF-exempt from L3 conformance gate: eCTD is a packaging/transport format orthogonal to MIF L3; canonical L3 source of truth stays in the `report` channel
- Built from the findings corpus and primary-source citations (SOURCES) only; never from a rendered report
- Current eCTD version must be resolved live before packaging (anchor: v4.0; never asserted from memory)

### Goals

- Produce a complete five-module eCTD tree (m1–m5) plus an XML backbone indexing every leaf
- Live-resolved eCTD version stamped into the backbone's `ectd-version` attribute; MIF L1 identity in backbone metadata
- Every surviving finding reflected in at least one module summary; every primary source cited; no internal identity in module leaf bodies

### Enable

```sh
scripts/pack-toggle.sh ectd on
```
