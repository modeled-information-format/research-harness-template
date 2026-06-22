---
name: trend-analysis
description: Genre template for a trajectory report (trajectory, signals, scenarios over time). Use when the deliverable tracks how something is changing and projects forward under uncertainty.
version: 1.0.0
---

# Genre Template: Trend Analysis

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

Practitioners and planners who need to understand the current trajectory, the signals
driving it, and the plausible forward scenarios so they can plan against an uncertain future.

## Altitude

`practitioner`. Direction-of-travel over precision: state where things are heading, the
evidence for it, and the branches the future could take. Be explicit about confidence.

## Section Structure (ordered)

1. **Trajectory** — the current direction of change and its recent history; the headline
   movement, framed as increasing / decreasing / steady where the evidence supports it.
2. **Signals** — the observable indicators behind the trajectory, each tied to a MIF finding
   `@id`. Distinguish leading from lagging signals and strong from weak ones.
3. **Drivers & Inhibitors** — the forces accelerating or dampening the trend.
4. **Scenarios** — 2 to 4 plausible forward paths over a stated horizon, with the conditions
   and triggers that would select each one. Note the confidence and the unknowns.
5. **Implications & Watch-list** — what to monitor and the early indicators that would
   confirm or break each scenario.

## Citation Style

Inline numeric markers `[1]`, `[2]` resolving to a references list. Each signal and data
point cites its originating MIF finding's `@id` / `urn:mif:` citation, including the
observation's date so trajectory claims are time-anchored.

## Required Figures & Matter

- **Front matter**: title, date, the time horizon and the as-of date of the data.
- **Figures**: a **trajectory or scenario diagram is required** — a time-series chart of the
  trend and/or a Mermaid state/branch diagram of the scenarios. Both when the data supports it.
- **Back matter**: references list; optional appendix with the underlying time-series data
  and signal log.

## Rules

- Anchor every trajectory claim in time — undated trend assertions are not admissible.
- Separate observed signal from projected scenario; never present a forecast as a fact.
- State confidence per scenario; surface findings whose verdict is `weakened` or
  `inconclusive` rather than hiding them. Exclude `falsified` units.
- Present ranges, not false precision, when sources disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every surviving finding is treated with its own evidence (claim, citations, entities), never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept frontmatter + falsification verdict); any published projection (blog/book) is at least MIF Level 1 — never bare, frontmatter-less prose.
