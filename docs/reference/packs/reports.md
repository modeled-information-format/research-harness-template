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

## legal-memo

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a predictive legal memorandum from the surviving findings corpus. The genre
follows the conventional memo structure — Question Presented, Brief Answer, Statement of
Facts, an IRAC Discussion, and a Conclusion — with Bluebook practitioner citations to
authority. It reproduces the *structure and reasoning form* of a legal memo; it is not
legal advice and asserts no legal sufficiency.

### When to use

Use `legal-memo` when the deliverable is an internal analysis that predicts how a question
of law resolves on a set of facts and must show its reasoning issue by issue — the
audience is a supervising attorney or decision-maker who will scrutinize the chain from
facts to governing rule to application.

### What it provides

- Five-section structure in order: Question Presented, Brief Answer, Statement of Facts,
  Discussion, Conclusion
- IRAC sub-structure (Issue, Rule, Application, Conclusion) per issue in the Discussion —
  the genre's distinguishing feature
- Bluebook practitioner citations to authority, each resolving to a MIF finding `@id` + URL
- Verdict-aware handling: weakened/inconclusive authorities annotated, falsified excluded

### Dependencies

None beyond the core engine.

### Benefits

- The IRAC sub-structure forces each issue through rule-then-application reasoning rather
  than a flat narrative, so the prediction is auditable
- Question Presented / Brief Answer up front gives the reader the disposition before the
  analysis, matching how memos are actually read
- Citations to named authority keep every rule statement traceable to its source

### Edition currency

Bluebook citation conventions evolve across editions. The genre instructs the author to
verify the current edition live rather than baking an edition number into output.

### Enable

```sh
scripts/pack-toggle.sh legal-memo on
```

---

## regulatory-disclosure

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces an SEC-style annual disclosure report from the surviving findings corpus,
following Regulation S-K / Form 10-K item order: Business, Risk Factors, Properties &
Legal Proceedings, Selected Financial Data, MD&A, Financial Statements & Supplementary
Data, and Controls & Procedures. The Selected Financial Data heading is always emitted, but
its content is conditional: Reg S-K item requirements evolve, so when the currently effective
rules no longer call for it the section is marked N/A and its highlights fold into MD&A.
It reproduces the disclosure *structure* only.

### When to use

Use `regulatory-disclosure` when the deliverable must present information in the order and
categories an investor or analyst expects from a public-company annual report. It does not
assert 10-K compliance, legal or financial sufficiency, or audit assurance — the
underlying disclosure-landscape evidence is weakened, so the genre reproduces structure,
not conformance.

### What it provides

- Seven-section structure in Reg S-K item order, with MD&A as the analytical core and
  Risk Factors surfaced early (all seven headings always emitted; Selected Financial Data
  marked N/A and folded into MD&A when not currently required)
- Disclosure references to source filings, each resolving to a MIF finding `@id` + URL
- Forward-looking-statement flagging and verdict-aware handling (weakened annotated,
  falsified excluded)

### Dependencies

None beyond the core engine.

### Benefits

- Reg S-K item ordering puts material risk and management analysis where readers of annual
  reports expect them
- The explicit scope caveat prevents over-claiming conformance the evidence does not support
- Inline XBRL tagging is deliberately out of scope — it is an orthogonal serialization that
  ships as a separate `xbrl` channel pack, keeping this genre focused on narrative structure

### Enable

```sh
scripts/pack-toggle.sh regulatory-disclosure on
```

---

## clinical-submission

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a clinical study report from the surviving findings corpus on the ICH E3 CSR
skeleton — Synopsis, Ethics, Investigators/Structure, Objectives, Investigational Plan,
Methods (efficacy & safety), Results, Discussion & Conclusions, Tables/Figures/Appendices —
situated in the CTD five-module frame (M1–M5), where an E3 CSR lives in Module 5.

### When to use

Use `clinical-submission` when the deliverable must present a study in the order a
clinical, regulatory-affairs, or medical reviewer expects. It does not assert clinical
validity, statistical adequacy, or regulatory acceptance — the genre reproduces the
submission structure, not a submittable CSR.

### What it provides

- Nine-section ICH E3 CSR structure with efficacy and safety kept distinct
- CTD five-module framing (E3 CSR placed in Module 5)
- Scientific/regulatory references, each resolving to a MIF finding `@id` + URL
- Verdict-aware handling (weakened annotated, falsified excluded)

### Dependencies

None beyond the core engine.

### Benefits

- ICH E3 ordering and the efficacy/safety split match how clinical reviewers read a CSR
- CTD framing places the report correctly in a submission's module structure
- FDA eCTD v4.0 electronic packaging is deliberately out of scope — it is an orthogonal
  serialization that ships as a separate `ectd` channel pack, keeping this genre focused on
  narrative structure

### Enable

```sh
scripts/pack-toggle.sh clinical-submission on
```

---

## sustainability-report

**Version:** 0.2.0 | **Kind:** genre

### Purpose

Produces a GRI-Standards sustainability/ESG report from the surviving findings corpus:
GRI 1 Foundation, GRI 2 General Disclosures, GRI 3 Material Topics, topic-standard
disclosures across the GRI 200 (economic) / 300 (environmental) / 400 (social) series, and
a GRI content index mapping every disclosure to its location.

### When to use

Use `sustainability-report` when the deliverable must present sustainability information in
the GRI structure for ESG analysts, investors, regulators, or stakeholders. It does not
assert assurance, third-party verification, or full "in accordance with GRI" conformance —
the genre reproduces the GRI structure, not GRI-assured reporting.

### What it provides

- Five-part GRI structure ending in the distinguishing GRI content-index table
- Materiality determination in GRI 3 (how material topics were identified and prioritized)
- Disclosure-indexed references, each resolving to a MIF finding `@id` + URL
- Verdict-aware handling (weakened annotated, falsified excluded); reporting boundary stated

### Dependencies

None beyond the core engine.

### Benefits

- The GRI content index gives readers a single map from every disclosure to its location
  and the evidence behind it
- GRI 3 materiality determination forces an explicit, defensible topic selection rather
  than an arbitrary list
- The explicit scope caveat prevents over-claiming assurance the evidence does not support

### Enable

```sh
scripts/pack-toggle.sh sustainability-report on
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
