---
name: humanities-chicago
description: Genre template for an argumentative humanities essay in Chicago Notes-Bibliography style — introduction with thesis, thematic argument sections (claim, evidence, interpretation), conclusion, numbered footnotes, and a full Bibliography. Use when the deliverable is a humanities argument rather than an empirical IMRaD paper. There is no Method or Results section — that is the distinguishing feature versus the academic genre.
version: 0.4.1
---

# Genre Template: Humanities Essay (Chicago Notes-Bibliography)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (weakened verdict — carry, do not over-attribute):** Chicago
> Notes-Bibliography is a presentation/citation convention, validated less firmly than the
> STEM standards. The genre reproduces the *argumentative structure and citation form*; do
> not over-attribute conformance.

## Target Audience

A humanities reader — a scholar or educated general reader who expects an argument advanced
through close reading and interpretation, with sources documented in footnotes, not an
empirical study.

## Altitude

`argumentative`. Advance a thesis and earn it through evidence and interpretation. Engage
counter-readings; qualify claims the evidence cannot fully bear. The voice is analytical
prose, not a method report.

## Section Structure (ordered)

1. **Introduction** — context and an explicit **thesis** the essay will argue.
2. **Thematic argument sections** — one per major claim, each developing
   **claim → evidence → interpretation**; the sections build the argument cumulatively.
3. **Conclusion** — what the argument establishes and why it matters; no new evidence.
4. **Bibliography** — the full, alphabetized list of sources.

There is **no Method and no Results section** — the essay argues; it does not report an
experiment. This is the distinguishing feature versus the `academic` genre.

## Citation Style

Chicago **Notes-Bibliography**: numbered **footnotes** (or endnotes) carry the citations,
and a full **Bibliography** lists every source alphabetically. Each note carries the
human-readable source citation (URL and bibliographic detail); internally it resolves through
a MIF finding `@id` for traceability (MIF Level 3 floor), but that `@id` is never printed in
the note. No uncited claims. **Verify the
current Chicago Manual of Style edition live** (the 18th Edition supersedes the 17th); do
not bake an edition number into output as settled fact.

## Required Figures & Matter

- **Front matter**: title and, where the convention calls for it, author and date.
- **Figures**: tables or images only where the argument genuinely needs them; caption and
  reference each. Any figure, chart, or diagram is rendered as a fenced Mermaid code block
  (a `mermaid` info-string fence), never ASCII art, an image link, or Graphviz/DOT; a
  required figure is never silently omitted — if the data cannot support it, say so in
  prose. Plain tabular matter stays a Markdown table.
- **Back matter**: the full **Bibliography** (required) — alphabetized, Chicago style.

## Rules

- Every claim carries a numbered footnote with its human-readable source citation; that
  footnote resolves internally to a MIF finding `@id` for traceability (never printed). No
  orphan facts.
- State the limits of the reading honestly; engage counter-interpretations. An unaddressed
  strong counter-reading is a defect.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain interpretations; do not over-attribute when sources are contested.
- **Exhaustive coverage**: build the essay from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into prose or footnotes.
