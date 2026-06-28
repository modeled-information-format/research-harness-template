---
name: market-research-report
description: Genre template for a full ESOMAR/ISO 20252-style market research report (background and objectives, methodology, findings, conclusions and recommendations, technical appendix). Use when the deliverable is a complete market-research study write-up for clients or stakeholders who need traceable evidence, an explicit methodology, and a documented sampling and fieldwork basis.
version: 0.4.1
---

# Genre Template: Market Research Report

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

Commissioning clients, market and insights stakeholders, and decision-makers who will act
on the study. They expect the methodology, sample basis, and fieldwork to be disclosed and
defensible before they trust the findings.

## Altitude

`practitioner`. Lead with the business question and the actionable conclusions, but keep
the methodology and sampling fully transparent in their own section and the technical
appendix. Recommendations are explicit and tied to findings; uncertainty in the data
(sample size, response rate, weakened evidence) is surfaced, never buried.

## Section Structure (ordered)

1. **Background & Objectives** — the commissioning context, the business problem, the
   research objectives, and the scope and definitions of the market under study.
2. **Methodology** — research design, sampling (frame, method, size), the instrument
   (questionnaire / discussion guide), and fieldwork (mode, dates, response/completion).
   State the verification gate and how `falsified` / `weakened` units were handled.
3. **Findings** — the evidence, organized by objective or theme. Each claim traces to its MIF
   finding `@id` — internal traceability only, resolved to a numbered or author-date citation
   marker and never printed — and reports the verification verdict. Quantify where the data allows and
   present comparative tables when multiple segments are measured on shared attributes.
4. **Conclusions & Recommendations** — what the findings mean for the business question and
   the specific, actionable recommendations that follow, each traceable to the evidence.
5. **Technical Appendix** — full methodology detail (sampling and weighting, instrument,
   fieldwork log), data-quality and limitations notes, and ISO 20252 quality notes.

## Citation Style

Numbered inline citation markers (e.g. `[1]`) resolving to a numbered source list in the
Technical Appendix, or author-date in text where a named source is cited. Each reference
derives from a MIF finding's `@id` / `urn:mif:` citation; the citation URL is mandatory
(MIF Level 3). No uncited claims.

## Required Figures & Matter

- **Front matter**: title, client/attribution, date, and a short scope statement.
- **Methodology matter**: an explicit sampling description (frame, method, size) and a
  fieldwork summary (mode, dates, response or completion rate).
- **Figures**: tables and figures as the evidence warrants — include a table whenever
  multiple segments or sources are compared on shared attributes. Number and caption every
  figure; reference each in the text. Any figure, chart, or diagram is rendered as a fenced
  Mermaid code block (a `mermaid` info-string fence) — a market chart as `xychart-beta` or
  `pie` — never ASCII art, an image link, or Graphviz/DOT; a required figure is never
  silently omitted — if the data cannot support it, say so in prose. Plain tabular matter
  stays a Markdown table.
- **Back matter**: the Technical Appendix (methodology detail, data-quality and limitations
  notes, ISO 20252 quality notes) and the numbered source list.
- **Standards caveat**: the report must state the convention-not-standard caveat below; a
  report that claims ESOMAR conformance is a defect.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive` findings,
  annotate them. Exclude only `falsified` units.
- Disclose the sampling and fieldwork basis honestly — an undisclosed sample limitation is
  a defect, not an omission. Hedge uncertain claims; present ranges when sources disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept
  frontmatter + falsification verdict); any published projection (blog/book) is at least
  MIF Level 1 — never bare, frontmatter-less prose. Internal MIF finding `@id` handles and
  `urn:mif:` URNs never appear in the rendered output.
- **ESOMAR/ICC is an ethics/conduct code, not a format mandate.** The ESOMAR structure is
  conventional practice, not a codified report standard. The report must say so and must
  not be mis-sold as "conforms to the ESOMAR standard." ISO 20252 is under active revision
  (AI integration, 2024–2026); anchor any ISO 20252 reference to "verify the current edition
  live at implementation time" rather than baking an edition in as fact.
