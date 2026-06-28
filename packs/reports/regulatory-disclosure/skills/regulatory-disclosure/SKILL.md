---
name: regulatory-disclosure
description: Genre template for an SEC-style annual disclosure report — Business, Risk Factors, Properties/Legal, Selected Financial Data, MD&A, Financial Statements & Supplementary Data, and Controls & Procedures, in Regulation S-K / Form 10-K item order. Use when the deliverable must reproduce the disclosure structure of a public-company annual report. Reproduces the disclosure structure only — not legal/financial sufficiency or audit assurance.
version: 0.4.1
---

# Genre Template: Regulatory Disclosure Report (SEC Reg S-K / Form 10-K)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (weakened verdict — carry, do not over-sell):** this genre reproduces the
> **disclosure structure** of an SEC annual report. It does **not** assert legal or
> financial sufficiency, regulatory conformance, or audit assurance — the disclosure
> standard's *landscape* evidence is weakened. Do not market output as "10-K compliant";
> it is a disclosure-structured narrative grounded only in the cited findings.

## Target Audience

An investor, analyst, or governance reader who expects information in the order and
categories of a public-company annual report, and who will read MD&A and Risk Factors as
the analytical core.

## Altitude

`disclosure`. Lead with material facts, quantify where the findings support it, and state
risk and uncertainty plainly. Forward-looking statements are flagged as such; nothing is
presented with more assurance than the evidence carries.

## Section Structure (ordered, Reg S-K item order, condensed)

1. **Business (Item 1)** — what the organization does; markets, products, operations.
2. **Risk Factors (Item 1A)** — the material risks, most significant first.
3. **Properties & Legal Proceedings (Items 2–3)** — material properties and pending
   legal matters.
4. **Selected Financial Data** — the multi-period financial highlights. **Always emit the
   heading** so the section structure stays stable. **Verify live:** Reg S-K item
   requirements evolve — the former *Item 301 Selected Financial Data* was eliminated by the
   SEC (Release 33-10890, an illustrative example — confirm the current item set at authoring
   time, never treat this as settled fact). When the currently effective Reg S-K no longer
   calls for the section, keep the heading, mark it explicitly *N/A* (state why), and fold
   the highlights into MD&A; otherwise populate it.
5. **Management's Discussion & Analysis (MD&A, Item 7)** — the analytical heart:
   results of operations, liquidity, capital resources, and known trends/uncertainties.
6. **Financial Statements & Supplementary Data (Item 8)** — the statements and notes.
7. **Controls & Procedures** — disclosure controls and internal-control status.

> **Edition currency:** Regulation S-K is amended over time. Verify the currently effective
> item set live at authoring time; never present a particular item list as settled fact.

## Citation Style

Disclosure references to authority and source filings. Every claim still resolves to a MIF
finding `@id` and its source URL (MIF Level 3 floor); no uncited claims. **Inline XBRL
machine-readable tagging is the live SEC mandate but is an orthogonal serialization — it is
out of scope for this genre and ships as a separate `xbrl` channel pack.** This genre
produces the disclosure *narrative structure* only.

## Required Figures & Matter

- **Front matter**: cover identifying the organization and reporting period.
- **Figures**: financial-highlight tables in MD&A (and in Selected Financial Data when that
  section is currently required and populated); number and caption each and reference it in
  the text. Any figure, chart, or diagram is rendered as a fenced Mermaid code block (a
  `mermaid` info-string fence) — a trend chart as `xychart-beta` — never ASCII art, an image
  link, or Graphviz/DOT; a required figure is never silently omitted — if the data cannot
  support it, say so in prose. Plain tabular matter stays a Markdown table.
- **Back matter**: the notes to the financial statements and a full reference list.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- State risks and limitations honestly; the genre reproduces structure, not sufficiency or
  audit assurance — say so. An undiscussed material risk is a defect.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain claims and flag forward-looking statements; present ranges when sources
  disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into prose.
