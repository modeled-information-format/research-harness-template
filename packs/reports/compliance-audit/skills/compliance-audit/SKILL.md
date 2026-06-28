---
name: compliance-audit
description: Genre template for DRAFTING/MODELING a SOC 2 Type II-shaped controls report (auditor's report, management's assertion, system description, Trust Services Criteria, tests of controls & results). Use when the deliverable models a service organization's controls against the Trust Services Criteria. This template reproduces the report STRUCTURE only — it never issues, implies, or substitutes for an attestation, assurance, or audit opinion.
version: 0.4.0
---

# Genre Template: Compliance Audit (SOC 2 Type II shape)

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

This genre mirrors the **shape** of a SOC 2 Type II report so a service organization can
draft and model its controls narrative and a tests-of-controls matrix. It produces a
*controls report draft*, not an attestation. Read the Rules — the no-attestation caveat is
the load-bearing constraint of this genre.

## Target Audience

Service-organization stakeholders — security, compliance, and engineering leaders, and the
internal readiness team — who need to draft, model, and self-assess a controls narrative
ahead of (or independent of) a formal audit by a licensed CPA firm. The reader is preparing
material, not consuming an issued opinion.

## Altitude

`practitioner`. Controls-and-evidence over narrative flourish: state each control, the test
performed against it, and the result or exception, with citations to the MIF findings that
supply the evidence. Be explicit about which Trust Services Criteria are in scope and which
are excluded.

## Section Structure (ordered)

1. **Independent Service Auditor's Report** — modeled placeholder section that frames the
   report's scope, the period covered, and the criteria applied. It is a DRAFT framing only:
   it must explicitly state that no audit opinion is expressed and that no licensed CPA firm
   has performed an examination. Never write this as if an opinion were rendered.
2. **Management's Assertion** — the service organization's own statement describing the
   system and asserting that controls were suitably designed (and, for a Type II shape,
   operated effectively) over the period. Each assertion ties to a MIF finding `@id`.
3. **System Description** — the boundaries of the system across the five description
   components: **infrastructure**, **software**, **people**, **data**, and **processes**.
   Each component's claims cite their originating findings.
4. **Trust Services Criteria** — the criteria in scope. **Security** (the common criteria)
   is always present; **Availability**, **Processing Integrity**, **Confidentiality**, and
   **Privacy** are included only when the topic's findings cover them. State explicitly
   which of the five are in scope and which are excluded.
5. **Tests of Controls & Results** — the core matrix: each control, the test performed
   against it, and the result or exception observed. Every row traces a control to a finding
   `@id`. Exceptions are reported, never suppressed.
6. **Other Information** — supplementary material provided by management that is outside the
   scope of the criteria (e.g. roadmap items, management's response to exceptions). Clearly
   demarcated as not covered by any testing.

## Citation Style

Control-framework references map each control to the Trust Services Criterion it supports.
Each control, test, and result cites its originating MIF finding's `@id` / `urn:mif:`
citation; the MIF `@id` + source URL is the floor — a control row with no cited finding is
not admissible. Render at the `report` channel's MIF Level 3.

When referencing the AICPA Trust Services Criteria or SSAE 18, anchor the edition at
implementation time — verify the current AICPA TSC and attestation-standard editions live
rather than baking a year into the report as fact.

## Required Figures & Matter

- **Front matter**: title, the period covered (a Type II shape covers a period, not a point
  in time), the as-of / through dates, and the in-scope Trust Services Criteria.
- **Required matter**: a **controls / test-results matrix is required** — a table whose
  columns are, at minimum, **Control**, **Test Performed**, and **Result / Exception**, one
  row per control, each row tracing to a finding `@id`. Any figure, chart, or diagram —
  for instance a control or process flow as a Mermaid `flowchart` — is rendered as a
  fenced `mermaid` code block (never ASCII art, an image link, or Graphviz/DOT), and a
  required figure is never silently omitted — if the data cannot support it, say so in
  prose. Plain tabular matter stays a Markdown table.
- **Back matter**: references list; optional appendix with the full control inventory and
  the evidence log.

## Rules

- **No attestation. No assurance. No audit opinion. Ever.** A genuine SOC 2 report is an
  **attestation engagement performed by a licensed CPA firm under AICPA attestation
  standards (SSAE 18)**. This harness is **not** a CPA firm, performs **no** examination,
  and issues **no** opinion. This template reproduces the report STRUCTURE and a
  controls/test matrix and **nothing more**. The output MUST NOT state, imply, or be
  presented as an attestation, assurance, certification, audit opinion, or evidence of SOC 2
  compliance. The Independent Service Auditor's Report section is a DRAFT placeholder that
  must say so in plain terms. Use this genre to DRAFT or MODEL a controls report for internal
  readiness — never to issue one. Misrepresenting this output as an issued SOC 2 report is a
  defect of the highest severity.
- Every control, test, and result traces to a cited MIF finding `@id`; no orphan controls,
  no uncited assertions.
- Report exceptions honestly — a failed or partially-met control test is reported as an
  exception, never hidden or upgraded to "met".
- State which Trust Services Criteria are in scope and which are excluded; never imply
  coverage of a criterion the findings do not support.
- Surface findings whose verdict is `weakened` or `inconclusive` with an explicit annotation
  rather than hiding them. Exclude `falsified` units.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept
  frontmatter + falsification verdict); any published projection (blog/book) is at least MIF
  Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifier leakage into prose.
