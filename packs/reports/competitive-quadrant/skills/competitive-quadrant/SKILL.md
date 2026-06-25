---
name: competitive-quadrant
description: Genre template for a two-axis competitive-quadrant report (Completeness of Vision x Ability to Execute, four quadrants, per-vendor strengths/cautions). Use when the deliverable ranks vendors in a market on two evaluation axes and places them into Leaders / Challengers / Visionaries / Niche Players.
version: 0.2.0
---

# Genre Template: Competitive Quadrant

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

This genre reproduces a **generic two-axis competitive-analysis structure** — Completeness
of Vision against Ability to Execute, with four resulting quadrants. It is **not** a Gartner
Magic Quadrant and must never claim to be one (see Rules).

## Target Audience

Buyers, analysts, and strategists comparing vendors or offerings in a defined market who
need a defensible side-by-side placement — who leads, who is rising, and where each vendor's
strengths and cautions lie.

## Altitude

`practitioner`. Comparative judgment over exhaustive feature catalogs: place each vendor on
the two axes, justify the placement with cited evidence, and be explicit about the limits of
the comparison.

## Section Structure (ordered)

1. **Market Definition / Inclusion Criteria** — the market under evaluation and the explicit,
   stated criteria a vendor must meet to be included (and what excludes one). No vendor
   appears without satisfying the inclusion criteria.
2. **Two-axis evaluation** — the evaluation framework: **Completeness of Vision** (the
   x-axis) and **Ability to Execute** (the y-axis). State the sub-criteria rolled into each
   axis and how each vendor is scored against them, every score tied to a MIF finding `@id`.
3. **Vendor profiles** — one profile per vendor, each with an explicit **Strengths** list and
   a **Cautions** list, every point source-attributed to cited vendor evidence.
4. **Quadrant placement** — the four quadrants — **Leaders**, **Challengers**, **Visionaries**,
   **Niche Players** — with each vendor assigned to exactly one, justified by its position on
   the two axes. A two-axis quadrant figure is required (see below).
5. **Context & Market Overview** — the market forces, adjacent trends, and conditions that
   frame the placements and would shift them.
6. **Methodology** — how vendors were scored, how evidence was gathered and verified
   (including the falsification gate), and the limits and as-of date of the assessment.

## Citation Style

Source-attributed vendor evidence: every strength, caution, and axis score names its source
and resolves to a references list. Each evidentiary point cites its originating MIF finding's
`@id` / `urn:mif:` citation with a URL, so every placement is traceable to verifiable vendor
evidence. The `report` channel is the MIF Level-3 floor: `@id` + URL per claim, never bare
assertion.

## Required Figures & Matter

- **Front matter**: title, date, the market evaluated, the inclusion criteria summary, and
  the as-of date of the vendor evidence.
- **Figures**: a **two-axis quadrant figure is required** — Completeness of Vision (x) against
  Ability to Execute (y), with the four quadrants labelled Leaders / Challengers /
  Visionaries / Niche Players and each vendor plotted. Per vendor, a **Strengths / Cautions**
  pair is required.
- **Back matter**: references list; optional appendix with the per-axis scoring rubric and
  the raw evidence log.

## Rules

- **Trademark / not-Gartner caveat (load-bearing).** "Magic Quadrant" is a **Gartner
  trademark** and a proprietary methodology. This pack reproduces only a generic two-axis
  competitive-analysis structure (Completeness of Vision x Ability to Execute, four
  quadrants). It **MUST NOT** claim to be a Gartner Magic Quadrant, use the "Magic Quadrant"
  trademark as a conformance or branding claim, or imply Gartner endorsement or methodology.
  The genre is named `competitive-quadrant`, **not** `magic-quadrant`. Reproduce the generic
  structure; never the trademark.
- State inclusion criteria before placing any vendor; an included vendor that does not meet
  the stated criteria is a defect.
- Every axis score, strength, and caution traces to a cited MIF finding `@id`; no orphan
  facts and no uncited placements.
- Assign each vendor to exactly one quadrant and justify it from its two-axis position;
  never assert a quadrant without the underlying scores.
- Report verification verdicts: annotate findings whose verdict is `weakened` or
  `inconclusive` rather than hiding them, and **exclude only `falsified`** units.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept
  frontmatter + falsification verdict); any published projection (blog/book) is at least MIF
  Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifier leaks into reader-
  facing prose.
