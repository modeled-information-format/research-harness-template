---
name: academic
description: Genre template for a formal research report (abstract, background, method, findings, discussion, references) with formal citations. Use when the deliverable is a scholarly write-up for a technical or research audience that demands traceable evidence and explicit method.
version: 0.1.1
---

# Genre Template: Academic Research Report

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter. `report-synthesizer` consumes this template,
binds the surviving findings (MIF units validated by `schemas/findings.schema.json`, drawn
from `reports/<topic>/`), and the result renders through any channel.

## Target Audience

A research or technical-expert audience — peers who will scrutinize method, evidence, and
the limits of each claim before accepting it.

## Altitude

`academic`. Expose the method, qualify every claim, and surface uncertainty explicitly.
Conclusions are earned from evidence presented in-line, not asserted up front.

## Section Structure (ordered)

1. **Abstract** — 150-250 words: question, method, principal findings, conclusion.
2. **Background / Related Context** — what is already established and the gap this addresses.
3. **Method** — how findings were gathered and adversarially verified; state the verification
   gate and how `falsified` / `weakened` units were handled.
4. **Findings** — the evidence, organized by theme or dimension. Each claim cites its
   MIF finding `@id` and reports the verification verdict.
5. **Discussion** — interpretation, limitations, threats to validity, and open questions.
6. **References** — full citation list.

## Citation Style

Author-date in text, e.g. `(Source, 2026)`, resolving to a full alphabetized reference list.
Each reference derives from a MIF finding's `@id` / `urn:mif:` citation; the citation URL is
mandatory (MIF Level 3). No uncited claims.

## Required Figures & Matter

- **Front matter**: title, author/attribution, date, abstract, optional table of contents.
- **Figures**: tables and figures as the evidence warrants — include a table whenever
  multiple findings are compared on shared attributes. Number and caption every figure;
  reference each in the text.
- **Back matter**: full References section; optional appendix for extended data or the
  method's verification log.

## Rules

- Every claim is traceable to a cited MIF finding; no orphan facts.
- State limitations honestly — an undiscussed weakness is a defect, not an omission.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive` findings,
  annotate them. Exclude only `falsified` units.
- Hedge uncertain claims; present ranges when sources disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every surviving finding is treated with its own evidence (claim, citations, entities), never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept frontmatter + falsification verdict); any published projection (blog/book) is at least MIF Level 1 — never bare, frontmatter-less prose.
