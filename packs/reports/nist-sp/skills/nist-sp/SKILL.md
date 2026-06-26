---
name: nist-sp
description: Genre template for a NIST Special Publication (SP 800-series) standards/guidance report. Use when the deliverable is a standards or guidance document with front-matter authority, numbered normative sections, defined terms, references, and appendices.
version: 0.3.0
---

# Genre Template: NIST Special Publication

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

This is the *standards-document* genre — a NIST Special Publication (e.g. the SP 800-series),
which is a standards/guidance report, not an engagement deliverable. It is distinct from a
penetration-test report (an engagement deliverable): a NIST SP states normative requirements,
defined terms, and control mappings that an engagement report would reference, not perform.

## Target Audience

Standards authors, control owners, security and privacy program leads, auditors, and
implementers who must read the document as authoritative guidance — understand its authority
and scope, apply its numbered normative requirements, and trace defined terms and control
mappings into their own programs.

## Altitude

`authoritative`. Normative precision over narrative: state requirements in numbered sections
with consistent normative force (shall / should / may), define every term of art, and anchor
each requirement to its evidence. Avoid hedging in normative text; record uncertainty as an
explicit verdict annotation, never as vague phrasing in a requirement.

## Section Structure (ordered)

1. **Authority** — the front-matter statement of the publication's standing: the mandate
   under which it is issued and the standing of its guidance. Mirrors the NIST SP verso /
   authority statement.
2. **Purpose & Scope** — what the publication establishes and the boundary of its
   applicability; what is in and out of scope.
3. **Audience** — the intended readers and the roles expected to apply the guidance.
4. **Abstract** — a self-contained summary of the problem, the guidance, and the principal
   conclusions.
5. **Keywords** — a short controlled list of index terms (NIST caps keywords at ten).
6. **Numbered normative sections** — the body, numbered sequentially with up to four heading
   levels (`1.`, `1.1.`, `1.1.1.`, `1.1.1.1.`). Each normative requirement traces to a cited
   MIF finding `@id`; state normative force explicitly (shall / should / may).
7. **Definitions / Glossary** — every term of art used normatively, defined once.
8. **References** — the numbered reference list (see Citation Style).
9. **Appendices** — supporting matter such as control mappings (e.g. to a control catalog or
   framework), control catalogs, and crosswalks. Lettered (Appendix A, B, …).

## Citation Style

Numbered references in square brackets — `[1]`, `[2]` — resolving to a numbered References
list at the back. Each reference entry is rendered as a human-readable citation (author,
title, source/URL, and the DOI as a complete URL when available — NIST reference format).
The source's MIF finding `@id` (`urn:mif:`) is internal traceability only: it links the
rendered entry back to its finding and is never printed in the output. Every normative
requirement and defined term cites the finding it rests on; no orphan normative claims.

## Required Figures & Matter

- **Front matter**: Authority statement, Purpose & Scope, Audience, Abstract, and Keywords
  (≤ 10), in that order, before the first numbered section.
- **Definitions / Glossary**: required — every normatively-used term of art is defined.
- **Back matter**: a numbered References list is required; **appendices** carry the mappings
  and control catalogs (e.g. a crosswalk table mapping requirements to an external control
  framework, or a catalog of the controls the publication defines).
- **Figures / tables**: a control-mapping or crosswalk table is expected whenever the
  findings support a mapping to an external framework.

## Rules

- Every normative requirement and defined term traces to a cited MIF finding `@id`; no orphan
  facts and no uncited normative claims.
- Report verification verdicts: annotate findings whose verdict is `weakened` or
  `inconclusive` rather than hiding them, and exclude only `falsified` units.
- Do not bake a standard's edition or version number into the text as settled fact unless a
  surviving finding establishes it; anchor edition references to their cited finding and
  verify currency at authoring time.
- **Exhaustive coverage**: build the publication from the FULL surviving findings corpus —
  every surviving finding is treated with its own evidence (claim, citations, entities),
  never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept
  frontmatter + falsification verdict); any published projection (blog/book) is at least MIF
  Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifier leaks into reader-
  facing prose; identifiers resolve to numbered `[N]` references.
