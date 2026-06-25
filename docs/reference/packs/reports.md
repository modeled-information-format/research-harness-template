---
diataxis_type: reference
---

# Report packs

Report packs are deliverable-genre templates. Each one declares a document structure,
target audience, altitude, citation style, and required matter. The `report-synthesizer`
skill consumes a genre template, binds surviving findings from the corpus, and the result
renders through any channel.

Report packs are enabled by default in the harness. They do not require an enable command
unless they have been explicitly disabled.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## academic

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a peer-review-style academic paper from the surviving findings corpus. The
genre follows academic conventions: structured abstract, methodology section, results
section with citations, discussion, and a formal bibliography.

### When to use

Use `academic` when the deliverable targets an academic or scholarly audience — a
conference submission, a journal draft, or internal research that follows peer-review
conventions.

### What it provides

- Structured abstract, methodology, results, discussion, conclusion sections
- Formal bibliography with full citations
- Academic prose altitude: precise, hedged where appropriate, method-visible

### Dependencies

None beyond the core engine.

### Benefits

- Enforces peer-review section structure so findings are presented in the order an
  academic reviewer expects
- Formal bibliography keeps all sources traceable to primary material
- Method-visible altitude means the reader can assess the research basis, not just
  accept conclusions

### Enable

```sh
scripts/pack-toggle.sh academic on
```

---

## briefing

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a one-page decision brief from the surviving findings corpus. The genre enforces
a hard one-page ceiling: if the content exceeds that limit, it is cut rather than
continued.

### When to use

Use `briefing` when the deliverable must fit a single page — a meeting pre-read, a
decision memo, or a summary that must be read in two minutes or less.

### What it provides

- One-page structured brief (hard ceiling enforced)
- Key findings and recommendation in condensed form
- Citations present but minimal to preserve density

### Dependencies

None beyond the core engine.

### Benefits

- Hard one-page ceiling prevents scope creep and keeps the deliverable usable in
  time-constrained contexts
- Forced compression surfaces only the most load-bearing findings

### Enable

```sh
scripts/pack-toggle.sh briefing on
```

---

## engineering

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a technical engineering report from the surviving findings corpus. A comparison
table is required. Mermaid architecture diagrams are optional and included when the
findings support a system or component structure worth visualizing.

### When to use

Use `engineering` when the deliverable targets an engineering audience — system design
reviews, technology evaluations, build-vs-buy analyses, or architecture assessments.

### What it provides

- Technical prose at practitioner altitude
- Comparison table (required)
- Mermaid architecture diagrams (optional, included when data supports them)
- Trade-off analysis sections

### Dependencies

None beyond the core engine. Mermaid rendering is optional.

### Benefits

- Mandatory comparison table ensures quantitative or feature-level comparisons are always
  present, not buried in prose
- Optional Mermaid diagrams keep architecture visualizations close to the text without
  requiring external diagramming tools
- Practitioner altitude means the report assumes engineering context and does not
  re-explain fundamentals

### Enable

```sh
scripts/pack-toggle.sh engineering on
```

---

## exec-summary

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a 1-2 page decision-oriented executive summary. Section order is fixed and
enforced:

1. **BLUF (Bottom Line Up Front)** — the heading must literally contain the acronym
   "BLUF" for automated checks to locate it. States the answer and recommended action
   before any context.
2. **Key Findings** — 3 to 5 bullets, each a single load-bearing fact with its "so what",
   each tracing to at least one finding's MIF `@id`.
3. **Recommendation** — one bold, specific, actionable directive covering What / Why /
   How / Risk.
4. **Risks & Caveats** — 1 to 3 conditions under which the recommendation fails, plus
   the confidence basis.

The length ceiling is hard: 1-2 pages. Falsified findings leave zero trace — they are not
mentioned, cited, hedged against, or alluded to anywhere. Internal MIF finding `@id`
handles and `urn:mif:` URNs never appear in the rendered output.

### When to use

Use `exec-summary` when the deliverable targets executives, sponsors, or board members
who need the conclusion and recommended action and will not read past page two.

### What it provides

- Four-section structure with BLUF required as first section
- 3-5 Key Findings bullets with load-bearing facts
- Single actionable Recommendation (What / Why / How / Risk)
- Risks & Caveats section covering failure conditions
- Inline numeric citation markers resolving to a compact footnote list
- Hard 1-2 page ceiling

### Dependencies

None beyond the core engine.

### Benefits

- BLUF-first ordering means the reader gets the answer immediately, regardless of whether
  they read the full document
- Hard length ceiling enforces compression and keeps the summary actionable rather than
  comprehensive
- Automated BLUF heading check (literal "BLUF" in heading) makes structural compliance
  verifiable without human review

### Enable

```sh
scripts/pack-toggle.sh exec-summary on
```

---

## humanities-mla

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces an argumentative humanities essay from the surviving findings corpus in MLA style:
an Introduction stating a thesis, body argument sections, a Conclusion, MLA author-page
in-text citations, and a Works Cited list. There is no Method or Results section.

### When to use

Use `humanities-mla` when the deliverable is a humanities argument that follows MLA
conventions — common in literature and the modern languages — rather than an empirical
IMRaD paper. The author-page in-text form and Works Cited list distinguish it from the
author-date `academic` genre and from footnote-based (Chicago Notes-Bibliography) styles.

### What it provides

- Argumentative structure (thesis introduction, body sections, conclusion)
- MLA author-page in-text citations, e.g. `(Hass 31)`, resolving to a Works Cited list
- Each citation resolves to a MIF finding `@id` + URL
- Verdict-aware handling (weakened annotated, falsified excluded)

### Dependencies

None beyond the core engine.

### Benefits

- Author-page citations and Works Cited match the convention humanities readers in the
  modern languages expect
- The argumentative structure suits interpretive reasoning rather than empirical reporting
- The genre carries the scope caveat so citation conventions are not over-attributed

### Edition currency

MLA Handbook editions evolve (the 9th Edition is current). The genre instructs the author
to verify the current edition live rather than baking an edition number into output.

### Enable

```sh
scripts/pack-toggle.sh humanities-mla on
```

---

## trend-analysis

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a trajectory report tracking how something is changing and projecting forward
under uncertainty. A trajectory or scenario diagram is required — a time-series chart of
the trend and / or a Mermaid state or branch diagram of the scenarios. Every trajectory
claim must be anchored in time; undated trend assertions are not admissible.

Section order:

1. **Trajectory** — current direction and recent history
2. **Signals** — observable indicators, each tied to a finding `@id`, with leading vs.
   lagging and strong vs. weak classification
3. **Drivers & Inhibitors** — forces accelerating or dampening the trend
4. **Scenarios** — 2 to 4 plausible forward paths with conditions, triggers,
   confidence, and unknowns
5. **Implications & Watch-list** — what to monitor and early indicators per scenario

### When to use

Use `trend-analysis` when the deliverable tracks directional change over time and must
present plausible forward scenarios — market trajectory reports, technology adoption
curves, or regulatory trend assessments.

### What it provides

- Five-section structure with trajectory diagram required
- Signal classification (leading / lagging, strong / weak) per finding
- 2-4 forward scenarios with confidence and trigger conditions stated
- Time-anchored trajectory claims (observation date required per data point)
- Optional time-series appendix with underlying signal log

### Dependencies

None beyond the core engine. Mermaid rendering is optional.

### Benefits

- Required trajectory diagram enforces visual representation of directional change rather
  than leaving it to prose description alone
- Signal classification (leading vs. lagging) makes it clear which indicators predict
  versus confirm the trend
- Time-anchoring requirement prevents undated assertions from passing through as facts

### Enable

```sh
scripts/pack-toggle.sh trend-analysis on
```
