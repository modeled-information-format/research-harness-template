---
name: legal-memo
description: Genre template for a predictive legal memorandum — Question Presented, Brief Answer, Statement of Facts, an IRAC Discussion (Issue, Rule, Application, Conclusion per issue), and a Conclusion, with Bluebook practitioner citations. Use when the deliverable is an internal legal analysis that predicts how a question of law resolves on the facts and must show its reasoning issue by issue.
version: 0.4.1
---

# Genre Template: Predictive Legal Memorandum (IRAC)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

> **Scope caveat (carry, do not over-sell):** this genre reproduces the *structure and
> reasoning form* of a predictive legal memorandum. It is not legal advice and asserts no
> legal sufficiency — the analysis is only as sound as the cited findings and the authority
> they point to.

## Target Audience

A supervising attorney or internal decision-maker who must act on a prediction of how a
legal question resolves. They will scrutinize the chain from facts → governing rule →
application before relying on the answer.

## Altitude

`predictive`. State the most likely outcome and the confidence in it, then earn that
prediction issue by issue. Surface adverse authority and counter-arguments honestly; an
unaddressed weakness is a defect, not an omission.

## Section Structure (ordered)

1. **Question Presented** — the legal issue framed as a single yes/no question that joins
   the governing rule to the determinative facts.
2. **Brief Answer** — the predicted conclusion in 2–3 sentences, with the core reason.
3. **Statement of Facts** — the material facts, stated neutrally; no argument here.
4. **Discussion** — the analytical core, in **IRAC per issue**: **I**ssue → **R**ule →
   **A**pplication → **C**onclusion. This ordered sub-structure is the genre's
   distinguishing feature; one IRAC cycle per discrete issue, each cycle citing its
   authority. Address counter-arguments within Application.
5. **Conclusion** — overall disposition, the recommendation, and any open questions or
   next steps.

## Citation Style

Bluebook practitioner format — citations to authority as footnotes or inline cites. Every
citation still resolves to a MIF finding `@id` and its source URL (MIF Level 3 floor); no
uncited claims. **Verify the current Bluebook edition live at authoring time** and follow
it — never bake an edition number into output as settled fact.

## Required Figures & Matter

- **Front matter**: a standard memo heading (To / From / Date / Re), then Question
  Presented and Brief Answer.
- **Figures**: tables where authorities or factors are compared on shared attributes;
  number and caption each and reference it in the text. Any figure, chart, or diagram is
  rendered as a fenced Mermaid code block (a `mermaid` info-string fence), never ASCII art,
  an image link, or Graphviz/DOT; a required figure is never silently omitted — if the data
  cannot support it, say so in prose. Plain tabular matter stays a Markdown table.
- **Back matter**: the full table of authorities / reference list; optional appendix for
  the verification log or extended record.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- State adverse authority and limitations honestly; an undiscussed weakness is a defect.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain predictions; present the range when authorities or sources disagree.
- **Exhaustive coverage**: build the memo from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into prose.
