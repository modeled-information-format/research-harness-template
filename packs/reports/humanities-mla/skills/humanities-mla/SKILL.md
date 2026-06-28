---
name: humanities-mla
description: Genre template for an argumentative humanities essay in MLA style — introduction with thesis, body argument sections, conclusion, MLA author-page in-text citations (e.g. (Author 42)), and a Works Cited list. Use when the deliverable is a humanities argument that follows MLA conventions rather than an empirical IMRaD paper. There is no Method or Results section.
version: 0.4.0
---

# Genre Template: Humanities Essay (MLA Author-Page)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (carry, do not over-attribute):** MLA author-page is a
> presentation/citation convention. The genre reproduces the *argumentative structure and
> citation form*; it does not certify scholarly sufficiency.

## Target Audience

A humanities reader — a scholar, student, or educated general reader who expects an
argument advanced through interpretation, with sources cited MLA author-page in text and
listed in Works Cited.

## Altitude

`argumentative`. Advance a thesis and earn it through close reading and interpretation.
Engage counter-readings; qualify claims the evidence cannot fully bear. Analytical prose,
not a method report.

## Section Structure (ordered)

1. **Introduction** — context and an explicit **thesis** the essay will argue.
2. **Body argument sections** — one per major claim, each developing claim, evidence, and
   interpretation; the sections build the argument cumulatively.
3. **Conclusion** — what the argument establishes and why it matters; no new evidence.
4. **Works Cited** — the alphabetized list of sources cited.

There is **no Method and no Results section** — the essay argues; it does not report an
experiment.

## Citation Style

MLA **author-page** in-text citations, e.g. `(Author 42)` — the author's surname and the
page locator in parentheses — resolving to a **Works Cited** list. Each in-text citation
still resolves to a MIF finding `@id` and its source URL (MIF Level 3 floor); no uncited
claims. **Verify the current MLA Handbook edition live** (the 9th Edition is current); do
not bake an edition number into output as settled fact.

## Required Figures & Matter

- **Front matter**: title and, where the convention calls for it, author and date.
- **Figures**: tables or images only where the argument genuinely needs them; caption and
  reference each. Any figure, chart, or diagram is rendered as a fenced Mermaid code block
  (a `mermaid` info-string fence), never ASCII art, an image link, or Graphviz/DOT; a
  required figure is never silently omitted — if the data cannot support it, say so in
  prose. Plain tabular matter stays a Markdown table.
- **Back matter**: the **Works Cited** list (required) — alphabetized, MLA style.

## Rules

- Every claim is traceable to a cited MIF finding `@id` via its author-page citation; no
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
  into prose or citations.
