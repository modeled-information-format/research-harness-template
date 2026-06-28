---
name: trend-analysis
description: Genre template for a trajectory report (trajectory, signals, scenarios over time), with an optional STEEP/PESTLE environmental scan and a methodology appendix. Use when the deliverable tracks how something is changing and projects forward under uncertainty. Anchored to a foresight convention, not a codified standard.
version: 0.4.1
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

### Optional sub-structure (additive — off by default; render when requested)

- **STEEP / PESTLE environmental scan** — when an explicit environmental scan is requested,
  precede or fold into Drivers & Inhibitors a scan organized by the STEEP (Social,
  Technological, Economic, Environmental, Political) or PESTLE (Political, Economic, Social,
  Technological, Legal, Environmental) dimensions, mirroring IFTF/WEF practice. Each factor
  still ties to a MIF finding `@id`.
- **Methodology Appendix** — when requested, add a back-matter appendix documenting how
  signals and any survey/scan inputs were sourced, scoped, and weighted, so the foresight
  basis is auditable.

These are opt-in; the five-section default and existing behavior are unchanged when they
are not requested.

## Citation Style

Inline numeric markers `[1]`, `[2]` resolving to a references list. Each signal and data
point cites its originating MIF finding's `@id` / `urn:mif:` citation, including the
observation's date so trajectory claims are time-anchored.

## Required Figures & Matter

- **Front matter**: title, date, the time horizon and the as-of date of the data.
- **Figures**: a **trajectory or scenario diagram is required** — a time-series trajectory as
  a Mermaid `xychart-beta` and/or a scenario-evolution diagram as a Mermaid `stateDiagram-v2`.
  Both when the data supports it. Any figure, chart, or diagram is rendered as a fenced
  `mermaid` code block (never ASCII art, an image link, or Graphviz/DOT), and a required figure is
  never silently omitted — if the data cannot support it, say so in prose. Plain tabular
  matter stays a Markdown table.
- **Back matter**: references list; optional appendix with the underlying time-series data
  and signal log.

## Rules

- **Convention, not a codified standard.** No standards body (ISO/NISO/ANSI) has codified a
  foresight/trend-report format; this genre follows a *convention* (IFTF/WEF/APF practice).
  Do not mis-sell output as conforming to a named standard — disclose that the anchor is a
  convention.
- Anchor every trajectory claim in time — undated trend assertions are not admissible.
- Separate observed signal from projected scenario; never present a forecast as a fact.
- State confidence per scenario; surface findings whose verdict is `weakened` or
  `inconclusive` rather than hiding them. Exclude `falsified` units.
- Present ranges, not false precision, when sources disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every surviving finding is treated with its own evidence (claim, citations, entities), never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept frontmatter + falsification verdict); any published projection (blog/book) is at least MIF Level 1 — never bare, frontmatter-less prose.
