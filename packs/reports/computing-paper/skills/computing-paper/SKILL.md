---
name: computing-paper
description: Genre template for an ACM/IEEE computing conference or journal paper (abstract, related work, approach/system design, evaluation, discussion, conclusion & future work, references) with IEEE numbered citations. Use when the deliverable is a computing/engineering systems paper for an ACM or IEEE venue — distinct from the academic genre's APA/IMRaD structure.
version: 0.3.0
---

# Genre Template: ACM/IEEE Computing Paper

A deliverable-genre template (SPEC §6d). It declares the document's structure, audience,
altitude, citation style, and required matter for a computing/engineering paper targeting
an ACM or IEEE venue. `report-synthesizer` consumes this template, binds the surviving
findings (MIF units validated by `schemas/findings.schema.json`, drawn from
`reports/<topic>/`), and the result renders through any channel.

This genre is **distinct from `academic`**: the academic pack is the APA/IMRaD
empirical-paper structure (author-date citations, Method → Findings → Discussion). This
genre is the ACM/IEEE *conference/journal* taxonomy for computing and engineering —
Related Work, an Approach / System Design section, an explicit Evaluation, and IEEE
numbered citations. Do not overload `academic`; choose this genre for systems and
engineering write-ups.

## Target Audience

Computing and engineering peers — program-committee reviewers and practitioners who will
scrutinize the system design, the soundness of the evaluation (setup, baselines,
results), and the limits of each claim before accepting it.

## Altitude

`academic`. Expose the approach and the evaluation method, qualify every claim, and
surface threats to validity explicitly. Conclusions are earned from the evidence
presented in the Evaluation, not asserted up front.

## Section Structure (ordered)

1. **Abstract** — 150-250 words: problem, approach, principal results, conclusion.
2. **Introduction** — the problem, why it matters, the contribution, and a roadmap.
3. **Related Work** — prior systems and approaches, and how this work differs.
4. **Approach / System Design / Method** — the design or method under study, in enough
   detail to be reproduced.
5. **Evaluation** — experimental setup (datasets, baselines, metrics, environment) and
   results. Each result claim cites its MIF finding `@id` and reports the verdict.
6. **Discussion** — interpretation, threats to validity, limitations, and open questions.
7. **Conclusion & Future Work** — what was shown and the concrete next directions.
8. **References** — numbered reference list, ordered by first appearance.

## Citation Style

**IEEE numbered** bracket citations in text, e.g. `[1]`, `[2]`, ordered by first
appearance and resolving to a numbered reference list (`[1] Author, "Title," Venue,
Year.`). Each numbered reference derives from a MIF finding's `@id` / `urn:mif:` citation;
the citation URL is mandatory (MIF Level 3 floor). No uncited claims. Anchor the format to
the current ACM Primary Article Template (`acmart`) and IEEE `IEEEtran` conventions —
verify these live at implementation time, as the templates revise without fanfare.

## Required Figures & Matter

- **Front matter**: title, author/attribution, abstract, **CCS Concepts** (ACM Computing
  Classification System) and **keywords / index terms** — the indexing matter an ACM/IEEE
  venue requires.
- **Figures & tables**: tables and figures as the evidence warrants — include a results
  table whenever multiple findings or baselines are compared on shared metrics. Number and
  caption every figure; reference each in the text.
- **Back matter**: full numbered References section; optional appendix for extended data
  or the verification log.

## Rules

- Every claim is traceable to a cited MIF finding `@id`; no orphan facts.
- State limitations and threats to validity honestly — an undiscussed weakness is a
  defect, not an omission.
- Report verification verdicts; do not silently drop `weakened` or `inconclusive`
  findings, annotate them. Exclude only `falsified` units.
- Hedge uncertain claims; present ranges when sources disagree.
- **Exhaustive coverage**: build the paper from the FULL surviving findings corpus — every
  surviving finding is treated with its own evidence (claim, citations, entities), never
  condensed to a cherry-picked subset. A silently dropped finding is a defect.
- **MIF level**: rendered through the `report` channel at MIF Level 3 (authoritative
  concept frontmatter + falsification verdict); any published projection (blog/book) is at
  least MIF Level 1 — never bare, frontmatter-less prose. No `urn:mif:` identifiers leak
  into the rendered text.
