---
name: systematic-review
description: Genre template for a PRISMA 2020 systematic review (structured abstract, methods, results with a PRISMA flow diagram, discussion, registration). Use when the deliverable must make the evidence-selection process legible and reproducible end to end.
version: 0.4.0
---

# Genre Template: Systematic Review (PRISMA 2020)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

The genre anchors to **PRISMA 2020** as its illustrative reporting baseline. Before
authoring, verify the current PRISMA guidance live — confirm which statement is in force
(and what it supersedes) and treat no item count or flow-diagram template as fixed until
checked against the live guidance.

## Target Audience

Researchers, evidence-synthesis practitioners, and reviewers who need a transparent,
reproducible account of how a body of evidence was identified, screened, appraised, and
synthesised — and who must be able to audit every inclusion and exclusion decision.

## Altitude

`researcher`. Reproducibility over narrative: state the eligibility criteria, the search,
and the selection process precisely enough that another reviewer could repeat them. Report
counts at every stage; never collapse the selection process into a summary sentence.

## Section Structure (ordered)

1. **Title / Abstract (structured)** — a structured abstract covering background, objectives,
   eligibility criteria, information sources, methods of synthesis, results, and conclusions.
2. **Introduction** — the **rationale** for the review in the context of existing knowledge,
   and the explicit **objectives** (the review question, framed as a PICO or comparable
   structure where applicable).
3. **Methods** — the reproducible protocol:
   - **Eligibility criteria** — inclusion and exclusion criteria for evidence.
   - **Information sources** — where evidence was sought.
   - **Search strategy** — the search approach and terms.
   - **Selection process** — how records were screened and selected.
   - **Data items** — what was extracted from each included study.
   - **Risk-of-bias assessment** — how the validity of each included study was appraised.
4. **Results** — the study selection and synthesis:
   - **Study selection** with the **PRISMA flow diagram**: the counts at each stage —
     records **identified**, records **screened**, records **excluded** (with reasons),
     and studies **included**.
   - **Synthesis of results** — the synthesised findings across included evidence.
5. **Discussion** — interpretation, **limitations** of the evidence and the review process,
   and **conclusions**.
6. **Registration & Protocol** — registration record and protocol availability (PRISMA 2020
   "Other information"); state explicitly when none exists.
7. **References** — the full reference list.

## Citation Style

Numbered (Vancouver-style) inline markers `[1]`, `[2]` resolving to a references list. Each
included study and every extracted claim cites its originating MIF finding's `@id` /
`urn:mif:` citation and resolving URL. The MIF `@id` + URL floor is mandatory at MIF Level 3.

## Required Figures & Matter

- **Front matter**: title, date, the structured abstract, and the registration record (or an
  explicit statement that the review was not registered).
- **Figures**: the **PRISMA flow diagram is REQUIRED** — a Mermaid `flowchart` (top-down, `flowchart TD`)
  showing the count of records at each stage: **identified → screened → excluded (with
  reasons) → included**. Any figure, chart, or diagram is rendered as a fenced `mermaid` code
  block (never ASCII art, an image link, or Graphviz/DOT), and a required figure is never
  silently omitted — if the data cannot support it, say so in prose. Plain tabular matter
  stays a Markdown table. A risk-of-bias / verification-verdict table is required alongside
  it.
- **Back matter**: the numbered references list; an optional appendix with the full search
  strategy and the per-study data-extraction table.

The harness's own pipeline maps directly onto the PRISMA stages, and the flow diagram should
present that mapping: the dimension **fan-out** is PRISMA **identification**; the gathering of
candidate findings is **screening**; the single adversarial **falsification** gate is
**eligibility** assessment; and **synthesis** of the surviving corpus is **inclusion**. A
`falsified` unit is an excluded record, and its falsification reason is the exclusion reason
recorded in the flow.

## Rules

- Every claim traces to a cited MIF finding `@id`; no orphan facts and no uncited assertions.
- Report the verification verdict of each finding. Annotate `weakened` and `inconclusive`
  units explicitly; **exclude only `falsified`** units — and when one is excluded, record it
  as an excluded record in the flow diagram with its falsification reason.
- The PRISMA flow diagram must reconcile: the stage counts must account for every finding —
  identified minus excluded equals included.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept
  frontmatter + falsification verdict); any published projection (blog/book) is at least MIF
  Level 1 — never bare, frontmatter-less prose. No raw `urn:mif:` identifiers leak into the
  reader-facing prose.
