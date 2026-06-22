---
name: exec-summary
description: Genre template for a 1-2 page decision-oriented executive summary (BLUF, key findings, recommendation, risks). Use when the deliverable is a short brief for decision-makers who will act without reading a full report.
version: 1.0.1
---

# Genre Template: Executive Summary

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

Decision-makers — executives, sponsors, board members — who need the conclusion and the
single recommended action, and who will not read past page two.

## Altitude

`executive`. State conclusions and their business consequence. Do not narrate method,
explore alternatives, or expose intermediate analysis.

## Section Structure (ordered)

1. **BLUF (Bottom Line Up Front)** — one paragraph: the answer and the recommended action,
   stated before any context. Never open with method or background.
   The heading MUST literally contain the acronym "BLUF" (e.g. `## BLUF (Bottom Line Up Front)`)
   so automated checks can locate it.
2. **Key Findings** — 3 to 5 bullets, each a single load-bearing fact with its "so what".
   Every bullet traces to at least one finding's MIF `@id`.
3. **Recommendation** — one bold, specific, actionable directive. Include What / Why / How / Risk.
4. **Risks & Caveats** — the 1 to 3 conditions under which the recommendation fails, plus
   the confidence basis (note any finding whose verdict is `weakened` or `inconclusive`).

## Citation Style

Inline numeric markers `[1]`, `[2]` resolving to a compact footnote list. Each footnote MUST
resolve to the primary-source URL (e.g. `https://example.com/report`). The MIF finding `@id`
is internal traceability metadata only — it MUST NOT appear in the footnote list, the document
body, or anywhere else in the rendered output. Never print `f_<dim>_<n>` handles or `urn:mif:`
URNs in the output. No bibliography — footnotes only.

## Required Figures & Matter

- **Front matter**: title, date, one-line scope statement, decision being supported.
- **Figures**: none required. At most one small table or single chart if it replaces prose;
  prefer text — this genre is read in five minutes.
- **Back matter**: the numbered footnote list. No appendices.

## Rules

- Length is a hard ceiling: 1-2 pages. If it grows, cut — do not continue.
- The summary must stand alone: a reader who reads only this document can act correctly.
- Quantify at least one finding. Never fabricate a number; present a range when sources
  disagree and hedge ("estimated", "data suggests") for uncertain claims.
- Exclude any finding whose verification verdict is `falsified`. A falsified finding leaves
  ZERO trace in the document — do NOT mention its numbers, figures, claims, or source in any
  section, including Risks & Caveats. Do not reference, cite, hedge against, or restate
  anything from a falsified finding. Treat it as if it never existed. If the falsified finding
  would have supplied data that is now absent (e.g. a cost estimate), frame the gap as
  "no validated data exists on this topic" — never as "a figure was considered but excluded"
  or any other allusion to the act of exclusion itself.
- Use active voice throughout. Avoid all passive constructions — including "is drawn from",
  "was found to", "were identified", "is provided by", "it was determined". Rewrite as active:
  write "Three controlled pilots show 40% efficiency gains" not "the 40% reduction is drawn
  from three controlled pilots".
- **Account for every finding**: synthesize across the ENTIRE surviving corpus. Compress to summary altitude, but never silently drop a finding — fold thin, weakened, or inconclusive ones into the picture rather than omitting them (only `falsified` units leave zero trace).
- **MIF level**: rendered through the `report` channel at MIF Level 3 (≥ Level 1 minimum) — never bare, frontmatter-less prose.
