---
name: clinical-submission
description: Genre template for a clinical study report on the ICH E3 skeleton — Synopsis, Ethics, Investigators/Structure, Objectives, Investigational Plan, Methods (efficacy & safety), Results, Discussion & Conclusions, Tables/Figures/Appendices — situated in the CTD five-module frame (M1–M5). Use when the deliverable must reproduce the clinical-study-report structure of a regulatory submission. Reproduces the submission structure only — not clinical validity or regulatory acceptance.
version: 0.4.0
---

# Genre Template: Clinical Study Report (ICH E3 / CTD)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (carry, do not over-sell):** this genre reproduces the **ICH E3 clinical
> study report structure** within the CTD module frame. It does **not** assert clinical
> validity, statistical adequacy, or regulatory acceptance — the analysis is only as sound
> as the cited findings. Do not market output as a "submittable" CSR.

## Target Audience

A clinical, regulatory-affairs, or medical reviewer who expects a study write-up in ICH E3
order and understands where it sits in the CTD common-technical-document structure.

## Altitude

`regulatory-scientific`. Report objectives, methods, and results precisely and in order;
separate efficacy from safety; state every result with its measure of uncertainty. Claims
beyond the data are not admissible.

## Section Structure (ordered, ICH E3 CSR skeleton)

1. **Synopsis** — a structured summary of the study and its principal results.
2. **Ethics** — ethics-committee review, informed consent, and conduct standards.
3. **Investigators & Study Structure** — administrative structure and investigators.
4. **Objectives** — the primary and secondary study objectives.
5. **Investigational Plan** — study design, randomization/blinding, and rationale.
6. **Methods (Efficacy & Safety)** — endpoints, analysis populations, and statistical
   methods, kept distinct for efficacy and safety.
7. **Results** — efficacy results then safety results, with the analysis populations.
8. **Discussion & Conclusions** — interpretation, limitations, and benefit-risk.
9. **Tables, Figures & Appendices** — the supporting data displays and appendices.

**CTD framing:** situate the report in the five-module Common Technical Document frame —
**M1** regional administrative, **M2** summaries, **M3** quality, **M4** nonclinical study
reports, **M5** clinical study reports — and state that an E3 CSR lives in **Module 5**.

## Citation Style

Scientific / regulatory referencing to source studies and guidance. Every claim still
resolves to a MIF finding `@id` and its source URL (MIF Level 3 floor); no uncited claims.
**FDA eCTD v4.0 electronic packaging is an orthogonal serialization — it is out of scope
for this genre and ships as a separate `ectd` channel pack.** Verify the current ICH E3
guidance live; do not bake a guidance revision into output as settled fact.

## Required Figures & Matter

- **Front matter**: title page identifying the study, and the Synopsis.
- **Figures**: efficacy and safety tables (analysis populations, endpoint results,
  adverse-event summaries); number and caption each and reference it in the text. Any
  efficacy or survival curve is rendered as a Mermaid `xychart-beta`. Any figure, chart,
  or diagram is rendered as a fenced `mermaid` code block (never ASCII art, an image link, or
  Graphviz/DOT), and a required figure is never silently omitted — if the data cannot
  support it, say so in prose. Plain tabular matter stays a Markdown table.
- **Back matter**: appendices and the full reference list.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- State limitations and benefit-risk honestly; the genre reproduces structure, not clinical
  validity or regulatory acceptance — say so. An undiscussed safety signal is a defect.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain claims; present confidence intervals or ranges when sources disagree;
  keep efficacy and safety claims distinct.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into prose.
