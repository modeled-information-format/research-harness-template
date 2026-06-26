---
name: academic
description: Genre template for a formal research report (abstract, background, method, findings, discussion, references) with a selectable citation style — author-date (APA) or numbered (Vancouver/IMRaD) — and optional APA Method sub-sections. Use when the deliverable is a scholarly write-up for a technical or research audience that demands traceable evidence and explicit method.
version: 0.3.0
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
   gate and how `falsified` / `weakened` units were handled. *In APA mode (optional), expand
   Method into the APA sub-sections* — **Participants**, **Materials**, **Procedure**,
   **Analysis** — when the work warrants them.
4. **Findings** — the evidence, organized by theme or dimension. Each claim cites its
   MIF finding `@id` and reports the verification verdict.
5. **Discussion** — interpretation, limitations, threats to validity, and open questions.
6. **References** — full citation list.

## Citation Style

**Selectable** — pick one mode and apply it consistently:

- **Author-date (APA, default)** — in text, e.g. `(Source, 2026)`, resolving to a full
  alphabetized reference list. Anchor APA to the **7th Edition** (verify the current edition
  live).
- **Numbered (Vancouver / IMRaD / ICMJE)** — numbered in-text markers, e.g. `[1]`, `[2]`,
  resolving to a numerically ordered reference list. Use this for IMRaD/ICMJE-style work,
  which expects numbered (Vancouver) citations rather than author-date. Anchor to the
  **current ICMJE Recommendations** (updated roughly annually — verify the current revision
  live; do not bake a dated revision in).

Each reference derives from a MIF finding's `@id` / `urn:mif:` citation; the citation URL is
mandatory (MIF Level 3). No uncited claims, regardless of mode.

## Required Figures & Matter

- **Front matter**: title, author/attribution, date, abstract, optional table of contents.
- **Figures**: tables and figures as the evidence warrants — include a table whenever
  multiple findings are compared on shared attributes. Number and caption every figure;
  reference each in the text.
- **Back matter**: full References section; optional appendix for extended data or the
  method's verification log.

## Rules

- **Citation mode is selectable, not standard-certified.** The IMRaD/ICMJE landscape anchor
  is a *weakened* verdict — pick author-date (APA 7th) or numbered (Vancouver/ICMJE) and apply
  it consistently, but do not over-attribute strict standard conformance; verify the live
  edition of whichever you choose. APA Method sub-sections (Participants/Materials/Procedure/
  Analysis) are an optional APA-mode expansion, not a default requirement.
- Every claim is traceable to a cited MIF finding; no orphan facts.
- State limitations honestly — an undiscussed weakness is a defect, not an omission.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive` findings,
  annotate them. Exclude only `falsified` units.
- Hedge uncertain claims; present ranges when sources disagree.
- **Exhaustive coverage**: build the report from the FULL surviving findings corpus — every surviving finding is treated with its own evidence (claim, citations, entities), never condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative concept frontmatter + falsification verdict); any published projection (blog/book) is at least MIF Level 1 — never bare, frontmatter-less prose.
