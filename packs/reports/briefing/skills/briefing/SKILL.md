---
name: briefing
description: Genre template for a one-page briefing or standup update (what's new, why it matters, what's next). Use when the deliverable is a terse status or situational update for a recurring audience.
version: 0.1.1
---

# Genre Template: Briefing

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

A recurring audience already holding context — a standup, a sync, a regular stakeholder
update — who need the delta and the next action, fast.

## Altitude

`executive`. Maximum signal, minimum words. State what changed and what to do; assume the
backdrop is known and skip it.

## Section Structure (ordered)

1. **Headline** — one line: the single most important thing to know right now.
2. **What's New** — 2 to 4 bullets of the latest developments since the last briefing, each
   tied to a MIF finding `@id`. Favor changed / new findings (the delta) over restated ones.
3. **Why It Matters** — one line per item: the implication or so-what.
4. **What's Next / Asks** — the next actions, owners, and any decisions or inputs needed.

## Citation Style

Inline numeric markers `[1]`, `[2]` resolving to a short footnote list, or bare source links
where a footnote is overkill. Markers resolve to the MIF finding's `@id` / `urn:mif:` citation.

## Required Figures & Matter

- **Front matter**: title, date, the period this briefing covers (since last update).
- **Figures**: none required — this is a one-pager. Add a single status indicator or sparkline
  only if it replaces a sentence.
- **Back matter**: the footnote/source list if markers were used. No appendices.

## Rules

- Hard ceiling: one page. If it spills over, cut to the delta — the freshest, most
  decision-relevant items win.
- Lead with the change; do not re-explain standing context.
- Every "what's new" bullet carries a "why it matters" — no orphan updates.
- Exclude `falsified` findings; flag `weakened` / `inconclusive` ones inline rather than
  presenting them as settled.
- **Account for every finding**: synthesize across the ENTIRE surviving corpus. Compress to the delta, but never silently drop a finding — note thin or weakened ones rather than omitting them.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (≥ Level 1 minimum) — never bare, frontmatter-less prose.
