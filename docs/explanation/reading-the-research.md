---
id: explanation-reading-the-research
type: semantic
created: '2026-06-28T23:46:18-04:00'
modified: '2026-06-28T23:46:18-04:00'
namespace: docs/explanation
tags:
  - documentation
  - explanation
title: "Explanation: reading the research"
diataxis_type: explanation
---

# Explanation: reading the research

You point the harness at a question. It fans out across the angles you care
about, gathers cited evidence from the live web, puts every claim through a
single adversarial gate that tries to break it, and renders what survives into
the deliverable you asked for. What you get back is not a chat answer you have
to take on faith — it is a **research corpus you can audit**: every claim traces
to a primary source, carries a confidence score, and wears the verdict of the
gate that tried to falsify it. And it **compounds**: every finding is a stable,
addressable MIF object, so the evidence you gather for one topic becomes reusable
material for the next — your research is an appreciating asset, not a throwaway
answer.

> **Every example on this page is real — the harness dogfoods itself.** The
> bundled topic
> [**OKF + MIF as a foundational research knowledge spine**](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/)
> is the project using its own engine to answer a question it actually faced:
> *should MIF be the modeling, provenance, and temporal spine beneath the Open
> Knowledge Format's accessible, git-distributable packaging layer?* It is a
> complete, archived corpus — **36 findings across four dimensions, gated to
> 31 survived / 5 weakened / 0 falsified over 84 unique sources** — and every
> constituent, navigation step, and report genre below links to its real
> rendered output. Open it in a second tab and read along.

This page is the reader's map. It explains **what a research topic produces**,
**how to move through it**, **how to read a single report**, and **what each
report genre is for** — so that when you open `reports/<topic>/` you know what
you are looking at and which file answers your question. For *why* the harness
is built this way, see [architecture](architecture.md), the
[living corpus](living-corpus.md), and the [ontological spine](ontological-spine.md);
for the exhaustive per-pack catalog, see the [pack reference](../reference/packs/index.md).

## What a research topic produces — the constituents

Each topic lives under `reports/<topic>/`. A session leaves behind a small set
of artifacts, each with a distinct job. Read the constituent that matches the
question you are actually asking — the "In the example" column points at the
live OKF + MIF corpus:

| Constituent | Where | What it is | What it gives you | In the example |
| --- | --- | --- | --- | --- |
| **Findings** | `findings/*.json` | The atomic unit — one MIF Concept per claim, with a summary, full content, cited sources, a confidence-scored provenance block, a verification verdict, and typed relationships to other findings. | The evidence itself. Every assertion in every report resolves back to one of these, so nothing is unsourced and nothing is unscored. | 36 findings (technical, landscape, market, trajectory) |
| **Topic README** | `README.md` | The front door — purpose, synthesis-grade key findings, a verdict-aware metadata header, the reports table, and the findings-by-dimension rollup. | One page that tells you what the topic concluded and where to go next. Start here. | [the topic front door](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/) |
| **Reports** | `report-*.md`, `synthesis-*.md` | Human-readable deliverables, each synthesized from the *surviving* findings for a specific audience and shape. | The findings rendered for a reader — pick the genre that fits who needs it (see below). | the full reports table — one rendering per enabled genre |
| **Knowledge graph** | `knowledge-graph.json` | The typed MIF substrate of concepts and entities (`urn:mif:` ids) linked by relationships and mentions, built by the `graph` skill. | Lateral reading — what connects to what, which entities recur — instead of a flat list of files. | built on demand from the 36 findings by the `graph` skill (not pre-rendered) |
| **Concordance** | `reports/concordance.json` | The cross-topic ontological spine: entity types composed across *all* topics in the corpus. | A whole-corpus world view — how this topic's entities line up with everything else you have researched. | built across topics with `graph --concordance`; this topic's typed entities compose into it |
| **Goal** | `goal.json` (+ `goals/` version members) | The content-hashed session goal that initiated and gated the run — its statement, scope, dimensions, completion checks, and bound. | The contract the research was held to. It tells you what "done" meant and what was in scope. | version `gv-722bb7b64725` — 4 dimensions, 9 checks, bound at 3 rounds (detailed below) |
| **Research progress** | `research-progress.md` | The append-only continuity log of how the session unfolded, phase by phase. | The audit trail — what ran, what is pending, and where to resume. | [the session log](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/research-progress/) |

The single most important thing to internalize: **a finding is not a fact, it is
a tested hypothesis.** It carries `provenance.confidence` (0–1), a `trustLevel`,
its source `citations[]` (each marked as it `supports` or `refutes` the claim),
and an `extensions.harness.verification` block holding the gate's `verdict` and
the `verdict_basis` that justifies it. You are meant to weigh findings, not just
read them.

## The goal — the contract the research is held to

Before a single finding exists, the harness writes a **`goal.json`** (validated
by [`schemas/goal.schema.json`](../reference/contracts.md)). It is the one
artifact that turns a vague ask into a measurable, gated session: the
orchestrator fans out, falsifies, and synthesizes *until the goal's checks hold
or its bound is hit*. You rarely write it by hand — the **`/goal-writer`**
assistant develops it with you (detailed below) — and it is the contract you can
hold the research to after the fact.

The example topic's goal makes the whole run legible. Abridged from its real
[`goal.json`](https://github.com/modeled-information-format/research-harness-template/blob/main/reports/example-okf-mif-knowledge-spine/goal.json):

```json
{
  "topic": "example-okf-mif-knowledge-spine",
  "goal_statement": "Enable the decision of whether MIF should serve as the modeling, provenance, and temporal spine layered with OKF as the accessible git-distributable packaging layer … establishing whether that layering is technically feasible, differentiated from prior art, on a favorable adoption trajectory, and addressed to a real market.",
  "scope": {
    "in_scope": ["The OKF data model and its stated minimalism", "MIF capabilities OKF lacks: typed relationships, formal ontologies, provenance objects, temporal modeling", "Prior art: RDF/OWL, PROV-O, SKOS, schema.org, JSON-LD, Frictionless Data", "…"],
    "out_of_scope": ["Implementing an OKF↔MIF converter or runtime", "Pricing a specific commercial product"],
    "non_goals": ["Will NOT ship an OKF–MIF integration", "Will NOT make a build-vs-buy recommendation for a named vendor"]
  },
  "dimensions": ["technical", "landscape", "trajectory", "market"],
  "completion_condition": {
    "summary": "Each dimension carries enough active findings, the falsifiable thesis sub-questions are each answered by a surviving finding, every finding validates against the schema, the gate ran once per finding, and citation integrity holds.",
    "checks": [
      { "id": "coverage_technical", "assertion": "The technical dimension has >=4 active (non-falsified) findings.", "verify": "… active technical findings | wc -l prints >= 4" },
      { "id": "thesis_mif_advantage", "assertion": "MIF's typed relationships, provenance, and temporal/versioning that OKF lacks is established by >=1 surviving finding.", "verify": "… surviving finding matches provenance|temporal|typed relationship|ontolog" },
      { "id": "finding_valid", "assertion": "Every active finding validates against the MIF-backed findings schema.", "verify": "ajv validate -s schemas/findings.schema.json … exits 0" }
    ]
  },
  "bound": { "max_rounds": 3, "min_dimensions_complete": 4 }
}
```

Read it field by field — this is what every research session is steered by:

| Field | What it does | In the example |
| --- | --- | --- |
| `goal_statement` | The decision the research must enable — not a topic, a *question to resolve*. | Should MIF be the spine beneath OKF for a knowledge layer? |
| `scope` | `in_scope` / `out_of_scope` / `non_goals` — the boundary that keeps fan-out honest. | OKF↔MIF mapping and prior art in; building a converter and vendor pricing out. |
| `dimensions` | The config-declared angles the orchestrator fans out across — one analyst each. | technical, landscape, trajectory, market |
| `completion_condition.checks` | **Transcript-verifiable end states, not steps.** Each is an `assertion` plus a `verify` command/fact; the loop runs until they all hold. | 9 checks — 4 dimension-coverage thresholds, 2 falsifiable thesis sub-questions, schema-valid, gate-ran-once, citation-integrity |
| `bound` | The stop condition if the goal cannot be fully met — the runaway guard. | `max_rounds: 3`, `min_dimensions_complete: 4` |

> **Which dimensions are available?** Dimensions are **not a fixed taxonomy** —
> they are whatever `harness.config.json` `dimensions[]` declares, so you can
> rename them or add your own. The shipped harness declares four: **`technical`**
> (feasibility, architecture, implementation), **`landscape`** (prior art and
> alternatives), **`trajectory`** (adoption, standards, momentum), and
> **`market`** (demand, segments, positioning, sizing). A dimension can also be
> **pack-provided**: enabling a methodology pack adds its dimension *and* the
> analysis method behind it — `market-research` contributes `competitive`,
> `customer`, `financial`, `sizing`, and `regulatory`; `trend-modeling`
> contributes `trend`. See the [configuration reference](../reference/configuration.md)
> for the `dimensions[]` field, and the [pack catalog](../reference/packs/index.md)
> for the methodology dimensions.

Two properties make the goal trustworthy rather than decorative:

- **Checks are falsifiable, not aspirational.** "The technical dimension has ≥4
  active (non-falsified) findings" and "MIF's typed-relationship / provenance /
  temporal advantage is established by ≥1 *surviving* finding" are facts a fresh
  reader can re-run — coverage counts, a schema-validation pass (`ajv`), a single
  falsification gate per finding, and the citation-integrity gate. The goal
  cannot be declared met by assertion.
- **Goals are content-hashed and append-only**
  ([ADR-0006](../adr/0006-content-hashed-append-only-goal-versioning.md)). This
  run is version **`gv-722bb7b64725`**; every finding pins
  `extensions.harness.gathered_under: "gv-722bb7b64725"`, and the version's
  membership — which findings belong to it, plus any `stale` / `excluded` /
  `gap_dimensions` — is recorded in
  [`goals/goal-gv-722bb7b64725.members.json`](https://github.com/modeled-information-format/research-harness-template/blob/main/reports/example-okf-mif-knowledge-spine/goals/goal-gv-722bb7b64725.members.json).
  Evolving the goal (`/goal-writer --reshape`) mints a *new* version and
  reclassifies existing findings as carry / gap / stale — it never rewrites the
  record.

### Developing the goal with `/goal-writer`

You do not have to write `goal.json` by hand. **`/goal-writer` is the assisting
tool that turns a plain-language research ask into the measurable contract
above** — hand it a rough ask and it does the goal-engineering with you:

- **It insists on a decision, not a topic.** "Learn about X" is rejected; the
  tool presses the ask into "enable decision Y," because a session that cannot be
  *done* cannot be gated. The example's `goal_statement` — *should MIF be the
  spine beneath OKF?* — is what that insistence produces.
- **It elicits what is ambiguous.** Before writing, it resolves the decision, the
  in-scope / out-of-scope / non-goals boundary, which config dimensions each earn
  a check, the per-dimension coverage and the sub-question a surviving finding
  must answer, the topic id, and the bound — folding any genuinely open question
  into the draft for you to settle rather than guessing a value.
- **It makes every check self-proving.** Each `verify` is drawn from a fixed
  vocabulary of commands the harness actually runs — `ajv` schema validation,
  `jq` / `ls` coverage counts, the citation-integrity gate, the
  falsification-gate log — so "done" is a printable fact a fresh reader can
  re-run, never an opinion.
- **It writes both halves, then stops.** It emits the validated `goal.json` to
  `reports/<topic>/` *and* a short `/goal` prose summary you can paste into Claude
  Code's `/goal`. Authoring the goal is the whole job — it never starts the
  research itself; you run `/start`, which loads the goal and drives the
  orchestrator under the harness's phase machinery.

When the question shifts mid-stream, `/goal-writer --reshape <what changed>`
*evolves* the goal instead of rewriting it: it mints the next content-hashed
version, then classifies every existing finding as **carry** (still in scope),
**gap** (a new check with no evidence yet), or **stale** (needs re-verification),
so `/start --update` re-researches only the gap and the stale and reuses
everything that still holds. For the step-by-step, see
[how to run a research session](../how-to/run-a-research-session.md) and
[how to evolve a goal](../how-to/evolve-a-goal.md).

## How to navigate a topic — the navigation hierarchy

The corpus is designed to be entered from the top and drilled down only as far
as your question needs. Walk the example topic as you read each step; the
hierarchy is the same whether you read it as files on GitHub or as pages on the
rendered site:

1. **Topic README**
   ([the OKF + MIF front door](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/))
   — read the verdict-aware header (here: *Findings 36 — survived 31, weakened
   5; Status archived*) and the **Key Findings** to learn what the topic
   concluded in one screen ("build now, stage the scale-up").
2. **Reports table** — pick the deliverable that matches your audience and the
   depth you need (a one-page brief, a peer-review paper, an exec summary, a
   trajectory report). Each row links to one rendered report.
3. **Findings-by-dimension table** — when you need the evidence rather than the
   narrative, drop from a report to the dimension and into the individual
   finding JSON behind any claim. In the example the split is **technical 12,
   trajectory 9, market 8, landscape 7**.
4. **Knowledge graph / concordance** — read *across* findings and topics instead
   of down one: traverse relationships from a concept or entity, or open the
   concordance for the whole-corpus view.

On the published site the same path is the sidebar: **Reports → the topic → its
README index page → the individual report pages**. The per-topic report tree is
reached from the README index, not from the sidebar, exactly as a per-directory
README reads on GitHub.

## How to read a report

Every report is a MIF object, and reading one well means reading three things
besides the prose:

- **The verdict-aware header.** The README header (and each report's frontmatter)
  states how many findings survived, how many were weakened, and how many were
  falsified, plus the falsification date. The example topic reads *survived 31,
  weakened 5, falsified 0* — a strong evidence base where five claims carry a
  caveat. The header is your trust dial before you read a word of body.
- **The MIF Level-3 source of truth.** The canonical `report` channel
  (`reports/<topic>/<slug>.md`) is the **Level-3 report of record** — each genre
  report is one such rendering, held to the same bar as a finding and graded by
  the falsification gate. The
  [blog **synthesis**](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/synthesis-okf-mif-knowledge-spine/)
  is a first-class *published projection* (MIF Level-1): the readable narrative,
  derived from the same surviving findings. When two renderings disagree, the L3
  report of record wins.
- **Citations and provenance.** Claims trace to finding `@id`s; each finding's
  citations carry a `citationRole` (`supports` or `refutes`), so refuting
  sources travel *with* the claim rather than being hidden. Use
  `provenance.confidence` and `trustLevel` to weight a claim, and read the
  `verdict_basis` to see *why* the gate ruled as it did.

The gate assigns one of four **ordinal verdicts**, and each is a reading
instruction. The example's
[falsification report](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/2026-06-28-falsification-report/)
shows all of this in practice — e.g. two market findings were *weakened* (not
cut) when Gartner's own newsroom contradicted a repeated agentic-AI adoption
statistic, so each was downgraded `high → moderate` confidence and the refuting
citation appended:

| Verdict | What it means | How to read it |
| --- | --- | --- |
| **survived** | Adversarial search could not break the claim. | Load-bearing — rely on it. |
| **weakened** | A specific element (often a number) was contradicted; the thesis held. | Keep the thesis, discount the disputed figure — it travels with a caveat. |
| **falsified** | The claim was refuted. | Excluded from the deliverables; it leaves no trace in the rendered reports. |
| **inconclusive** | Evidence was insufficient either way. | Annotated and retained — treat as an open question. |

## What each report genre is for

Not everything under `reports/<topic>/` is the same *kind* of document. There
are three families, and only some genres are produced by default — the rest are
**packs you enable** (`scripts/pack-toggle.sh <name> on`). The example topic has
enabled many packs, which is why its reports table is long; a fresh harness
shows fewer. Each entry below answers *what question it answers* and *when to
reach for it*, and links to the matching rendered report in the example. The
[pack reference](../reference/packs/reports.md) carries the full structure,
constraints, and standards basis of each.

### Engine outputs — present in every session

These are produced by the engine itself, not by a genre pack:

| Output | The question it answers | When to read it | In the example |
| --- | --- | --- | --- |
| **Falsification report** | What survived adversarial scrutiny, and what was weakened or cut — and why? | Before you act on anything. It is the calibration layer for the whole topic. | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/2026-06-28-falsification-report/) |
| **Research progress** | How did this research unfold, and where is the session now? | To resume a run, audit the process, or see what is still pending. | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/research-progress/) |

### First-class outputs — the harness's own channels

These ship with the core; they are not optional packs. The `report` channel (the
L3 report of record) is realized by the genre reports below; the blog is its
readable projection:

| Output | The question it answers | When to read it | In the example |
| --- | --- | --- | --- |
| **Report of record** (L3 `report` channel) | What is the authoritative, falsification-graded write-up? | When you need the single source of truth — rendered as the genre reports below. | the genre reports |
| **Blog synthesis** (L1 projection) | What is the readable, publishable narrative of what we found? | When you want the story for a general reader or to publish. | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/synthesis-okf-mif-knowledge-spine/) |

### Deliverable genres — the report packs

Each genre re-shapes the *same* surviving findings for a different audience and
convention. **Enabled by default:** `exec-summary`, `briefing`, `academic`,
`engineering`, `trend-analysis`. Everything else is **opt-in**.

| Genre | The question it answers | When to read it | Default | In the example |
| --- | --- | --- | --- | --- |
| **exec-summary** | What's the answer and the recommended action? | A decision-maker who reads to page two — BLUF first, 1–2 pages. | on | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-exec-summary/) |
| **briefing** | What do I need to know before this meeting? | A one-page pre-read or decision memo, read in two minutes. | on | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-briefing/) |
| **academic** | How does this read to a scholarly reviewer? | A peer-review-style paper (APA/IMRaD) with a formal bibliography. | on | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-academic/) |
| **engineering** | What is the build-vs-buy / architecture call? | A practitioner audience — required comparison table, optional diagrams. | on | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-engineering/) |
| **trend-analysis** | Where is this heading, and what should I watch? | Signals, drivers, and 2–4 forward scenarios with a trajectory diagram. | on | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-trend-analysis/) |
| **computing-paper** | How does this read for an ACM/IEEE venue? | A systems paper with Related Work and an explicit Evaluation section. | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-computing-paper/) |
| **market-research-report** | What is the full, disclosed market study? | A complete ESOMAR/ISO 20252-shaped study with sampling and methodology. | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-market-research-report/) |
| **market-sizing** | How big is the opportunity? | A TAM/SAM/SOM estimate with a named methodology and confidence. | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-market-sizing/) |
| **competitive-analysis** | Who competes, and how intense is it? | Porter's 5 Forces and a competitor matrix with trajectory indicators. | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-competitive-analysis/) |
| **competitive-quadrant** | Who leads on vision versus execution? | A two-axis vendor quadrant (Leaders / Challengers / Visionaries / Niche). | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-competitive-quadrant/) |
| **trend-modeling** | What futures are internally consistent when data is scarce? | Qualitative INC/DEC/CONST scenario enumeration with a transition graph. | opt-in | [view](https://modeled-information-format.github.io/research-harness-template/reports/example-okf-mif-knowledge-spine/report-trend-modeling/) |

Beyond these, the harness bundles further **domain genres** — `legal-memo`,
`nist-sp`, `systematic-review`, `sustainability-report`, `humanities-chicago`,
`humanities-mla`, `security-pentest`, `compliance-audit`,
`regulatory-disclosure`, and `clinical-submission` — each reproducing the
structure a particular field expects. All are opt-in; the
[pack reference](../reference/packs/reports.md) documents every one, and
[how to adopt a pack](../how-to/adopt-packs.md) shows how to turn them on.

The takeaway: **the genre changes the shape and the audience, never the
evidence.** Falsified findings are excluded from all of them; weakened and
inconclusive findings are annotated and retained. Whichever report you open in
the OKF + MIF example, you are reading the same gated corpus — the same 31
survivors — dressed for a different reader.

## Findings compound — addressable across topics, current and future

This is the harness's quietest but largest payoff. **A finding is not trapped in
the topic that produced it.** Because every finding is a MIF object with a
stable, global identifier — for example
`urn:mif:concept:harness/example-okf-mif-knowledge-spine:technical-okf-core-data-model` —
it is *addressable from anywhere*: another topic you are researching now, or one
you open a year from now, can point at it, cite it, or build on it directly. The
evidence does not have to be gathered twice.

That turns prior research into a substrate, not an archive:

- **Find it.** The [`search`](../reference/core-skills.md) skill queries the
  whole-corpus index by text or by structured filter (dimension, tags, verdict,
  namespace); [`discover`](../reference/core-skills.md) surfaces clusters, gaps,
  and stale or weakened findings across every topic; [`lab`](../reference/core-skills.md)
  lets you reason across topics interactively rather than one at a time.
- **Link it.** A finding's `relationships[]` and EntityReferences target other
  findings *by URN* — including findings in other topics — so a new topic's claim
  can `derived-from` or `relates-to` evidence already gathered, and the
  [knowledge graph](../reference/core-skills.md) traverses those edges across
  topic boundaries.
- **Trust it.** A reused finding carries its full provenance with it — citations,
  confidence, `gathered_under` goal version, and current verdict — so you inherit
  the calibration *and* can see at a glance if evidence you borrowed has since
  been weakened or falsified by a later gate.
- **Speak one language.** Cross-topic links are *type-aware*, not string-matched,
  because every finding's entity is typed against a shared
  [ontological spine — the concordance](ontological-spine.md), detailed next.

The practical effect: **each topic you research lowers the cost and raises the
grounding of the next.** A future study of, say, agent-memory formats can pull
the OKF + MIF topic's surviving provenance and temporal-modeling findings in as
already-cited, already-gated evidence instead of re-deriving them. The corpus is
a [living knowledge spine](living-corpus.md) that appreciates with every session.

### The concordance — the spine that makes the corpus one graph

Addressing a finding by URN gets you the right object; the **concordance** is what
makes that object *mean the same thing* in the topic you borrow it into. Every
finding's entity is typed against an ontology — an always-on generic core,
optionally layered with domain ontologies via `extends` — and those types
**compose across every topic** into `reports/concordance.json`, the corpus-wide
ontological spine you build and validate with `graph --concordance`. It is the
harness's "world view of knowledge": one validated type vocabulary that all
topics resolve against, rather than a per-topic private dialect.

That is why the spine is load-bearing, not decorative:

- **It makes reuse type-aware.** The OKF, MIF, RDF, and PROV-O entities the
  example topic typed resolve under the *same* ontology a future
  knowledge-representation topic uses — so a cross-topic link connects the same
  concept, not a lookalike string that has to be reconciled by hand.
- **It is enforced fail-closed.** Type resolution is strict
  (`resolve-ontology.sh` / `validate-concordance.sh`): a finding whose entity
  type does not resolve under its declared ontology is a hard failure, so the
  spine cannot quietly drift into incoherence as the corpus grows.
- **It is the substrate the cross-topic tools read.** `graph --concordance`,
  `discover`, and `search` all operate over this spine — it is what lets them
  answer questions *across* the whole corpus instead of one topic at a time.

Without the concordance the corpus would be a pile of silos joined by string
search; with it, the topics are one coherent, **typed** knowledge graph — and
that is precisely what lets a finding gathered today be reused, unambiguously, by
a topic you have not started yet. For the full picture see the
[ontological spine](ontological-spine.md) and the [living corpus](living-corpus.md).
