---
name: diataxis-docs
description: "Render a research topic's entire surviving findings corpus into a COMPLETE Diátaxis documentation set — a reference page per finding, a per-dimension explanation, how-to, and guided tutorial, plus landing/index pages — every page carrying MIF Level-1 frontmatter and a diataxis_type marker. An OPTIONAL channel pack (enable the `diataxis` pack). Use this skill when the user wants documentation for a research topic, a full docs set from the findings, or to publish the corpus as Diátaxis docs. Triggers on 'diataxis docs', 'documentation channel', 'render docs from research', 'document the findings', 'reference and explanation docs', 'generate the docs site'."
version: 0.3.0
argument-hint: "<findings-dir> <out-dir> [<topic-name>]"
allowed-tools: Read, Bash, Glob, Grep
---

# diataxis-docs — research corpus → complete Diátaxis documentation set

Diátaxis is a documentation channel pack (SPEC §6d): enable the bundled `diataxis`
channel pack to render a research topic into a full documentation tree. It is
**per-topic**, like `book` and `pdf` — it documents one topic's corpus, not the
whole repository.

The set is **exhaustive, not a summary.** It reads the topic's surviving findings
directly (verdict ≠ `falsified`) and emits a document for every piece of the
research that warrants one, so the deliverable scales with the corpus rather than
collapsing it into a handful of pages.

## What Diátaxis is

Four modes that must stay **pure** — never mixed within one document:

- **Tutorial** — learning-oriented. Guided lessons through the research.
- **How-to guide** — task-oriented. Steps to act on a dimension's findings.
- **Reference** — information-oriented. One authoritative page per finding.
- **Explanation** — understanding-oriented. How a dimension's findings connect.

## What it produces

For a corpus of N findings across D dimensions, `render-diataxis.sh` writes:

```text
docs/
  index.md                              # landing page linking the four quadrants
  reference/
    index.md                            # grouped, linked index
    <dimension>/<finding-slug>.md       # ONE page per finding (N pages)
  explanation/
    index.md
    <dimension>.md                      # one per dimension (D pages)
  how-to/
    index.md
    apply-<dimension>.md                # one per dimension (D pages)
  tutorials/
    index.md
    getting-started.md                  # orientation across the whole corpus
    <dimension>.md                      # a guided tour per dimension (D pages)
```

A reference page carries the finding's claim, classification (dimension,
verification verdict), key entities, evidence (its public citations), and links to
related findings (resolved to titles). Explanations weave a dimension's findings
into a connected narrative; how-to guides turn them into ordered steps.

## Pipeline

Run the pack-local, `jq`-only renderer over the topic's findings directory:

```bash
packs/channels/diataxis/scripts/render-diataxis.sh reports/<topic>/findings docs/<topic> <topic-name>
```

It reads the findings corpus (no separate synthesis step), filters falsified
findings, and writes the tree above. Re-run it to regenerate; it is a projection
of the corpus, so change the findings, not the rendered Markdown in place.

## MIF Level-1 identity

Every emitted page carries **MIF Level-1** YAML frontmatter — a base MIF v1.0
concept (`schemas/mif/mif.schema.json`: `@context`, `@type`, `@id`, `conceptType`,
`created`; `content` is the body) plus the `diataxis_type` marker — validated by
`schemas/diataxis-doc.schema.json` and enforced by `verify.sh` gate_m16. The
frontmatter holds the page's **own** `urn:mif:doc:` identity; the body resolves
finding/entity ids to human titles and names, so prose carries no
internal-research identity.

## Non-negotiables

- **Never document a falsified finding** — the renderer filters them.
- **Body prose carries no internal-research identity.** No `urn:mif:concept:` /
  `urn:mif:report:` ids, no `extensions.harness` or `reports/<slug>/` paths, no
  `f_<dim>_<n>` handles. The page's own `urn:mif:doc:` frontmatter `@id` is its
  legitimate L1 identity.
- **Keep every quadrant in its mode.** A tutorial that only states facts, or a
  reference that instructs, breaks Diátaxis compliance.
- **Title in the body H1, never in frontmatter** — a frontmatter `title:` plus a
  body H1 trips markdownlint MD025, and MIF L1 does not require `title`.
- **`diataxis` is MIF Level 1, not Level 3.** It carries typed identity but not the
  L3 additions (provenance, citations, entities, falsification verdict) that
  `findings.schema.json` requires; the canonical L3 source of truth stays the
  `report` channel (`reports/<topic>/<slug>.md`). The channel is therefore
  `mif.exempt` — exempt from the L3 I/O conformance gate while emitting validated
  L1 — and the MIF gate skips and logs it.
