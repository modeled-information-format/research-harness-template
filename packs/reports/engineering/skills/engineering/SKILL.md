---
name: engineering
description: Genre template for a design / evaluation report (problem, options, decision, trade-offs, implementation notes). Use when the deliverable documents a technical decision or evaluation for engineers who will build or maintain the result.
version: 0.1.1
---

# Genre Template: Engineering Report

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

Practitioners — engineers, architects, and tech leads — who must understand the decision,
why the alternatives lost, and what it takes to implement and operate the chosen option.

## Altitude

`practitioner`. Concrete and operational: name the constraints, the trade-offs, and the
consequences for building and maintaining the system. Enough rationale to act, no more.

## Section Structure (ordered)

1. **Problem / Context** — what is being decided or evaluated, and the forces in play
   (requirements, constraints, non-functionals).
2. **Options Considered** — the candidate approaches, each described neutrally.
3. **Trade-offs** — options compared on the decision drivers; a comparison table is required.
4. **Decision** — the chosen option, stated plainly, with the rationale that ties it to the
   trade-offs and the supporting MIF finding `@id`s.
5. **Implementation Notes** — what it takes to build it: dependencies, migration, risks,
   rollout, and operational concerns.
6. **Consequences** — what becomes easier, what becomes harder, and what to revisit later.

## Citation Style

Inline numeric markers `[1]`, `[2]` resolving to a references list; benchmark or measurement
claims cite the originating MIF finding's `@id` / `urn:mif:` citation. Link specs and source
material directly.

## Required Figures & Matter

- **Front matter**: title, date, status (proposed / accepted / superseded), decision drivers.
- **Figures**: an options-vs-criteria **comparison table** is required. Add an architecture
  or sequence diagram (Mermaid) when structure or flow is load-bearing to the decision.
- **Back matter**: references list; optional appendix for benchmark data or alternatives
  rejected early.

## Rules

- Ground the decision in the trade-offs — a decision the comparison table does not support
  is unjustified.
- Make implementation notes actionable: an engineer should be able to start from them.
- Cite measured/benchmarked claims to their MIF findings; exclude `falsified` units and flag
  any `weakened` or `inconclusive` evidence the decision leans on.
- Match existing decision-record conventions in the target repo where one exists.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every surviving finding is treated with its own evidence (claim, citations, entities), never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept frontmatter + falsification verdict); any published projection (blog/book) is at least MIF Level 1 — never bare, frontmatter-less prose.
