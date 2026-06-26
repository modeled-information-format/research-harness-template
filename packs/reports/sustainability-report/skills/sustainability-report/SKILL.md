---
name: sustainability-report
description: Genre template for a GRI-Standards sustainability/ESG report — GRI 1 Foundation, GRI 2 General Disclosures, GRI 3 Material Topics, topic standards across the GRI 200 (economic) / 300 (environmental) / 400 (social) series, and a GRI content index mapping every disclosure to its location. Use when the deliverable must reproduce the GRI sustainability-reporting structure. Reproduces the GRI structure only — not assured ESG conformance.
version: 0.2.0
---

# Genre Template: Sustainability Report (GRI Standards / ESG)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (carry, do not over-sell):** this genre reproduces the **GRI reporting
> structure**. It does **not** assert assurance, third-party verification, or full
> "in accordance with GRI" conformance — that requires meeting every applicable GRI
> requirement, which the genre cannot guarantee from findings alone. Present output as
> GRI-structured, not GRI-assured.

## Target Audience

An ESG analyst, investor, regulator, or stakeholder who expects sustainability information
organized by the GRI Standards and who will read the materiality determination and the
content index as load-bearing.

## Altitude

`disclosure`. Report impacts and performance against the GRI topic standards plainly, tie
each material topic to its determination, and quantify with the reporting boundary stated.
Claims of progress are evidenced, not asserted.

## Section Structure (ordered, GRI frame)

1. **GRI 1 — Foundation** — the reporting principles and how the report applies them.
2. **GRI 2 — General Disclosures** — organizational profile, governance, strategy, and
   stakeholder engagement.
3. **GRI 3 — Material Topics** — the materiality determination: how material topics were
   identified and prioritized.
4. **Topic Standards** — disclosures for each material topic across the **GRI 200**
   (economic), **GRI 300** (environmental), and **GRI 400** (social) series.
5. **GRI Content Index** — the distinguishing back-matter: a table mapping every GRI
   disclosure to its location in the report (and any omissions with reasons).

## Citation Style

Disclosure-indexed references. Every claim still resolves to a MIF finding `@id` and its
source URL (MIF Level 3 floor); no uncited claims. The GRI content index doubles as the
disclosure map — each indexed disclosure points to the finding(s) behind it. Verify the
current GRI Standards (Universal and applicable topic standards) live; do not bake a
specific standard year into output as settled fact.

## Required Figures & Matter

- **Front matter**: organization and reporting-period identification, and the reporting
  boundary.
- **Figures**: the materiality matrix or material-topic list; performance tables per topic
  standard (number and caption each and reference it in the text).
- **Back matter**: the **GRI content index** table (required) and the full reference list.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- State impacts, omissions, and limitations honestly; the genre reproduces structure, not
  assurance — say so. An undisclosed material impact is a defect.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain claims; present ranges when sources disagree; state the reporting
  boundary for every quantified disclosure.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into prose.
