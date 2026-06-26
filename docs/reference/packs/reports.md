---
diataxis_type: reference
---

# Report packs

Report packs are deliverable-genre templates. Each one declares a document structure,
target audience, altitude, citation style, and required matter. The `report-synthesizer`
skill consumes a genre template, binds surviving findings from the corpus, and the result
renders through any channel.

The core report packs — `academic`, `briefing`, `engineering`, `exec-summary`, and
`trend-analysis` — are enabled by default and require no enable command unless explicitly
disabled. The additional domain and specialized genres below are **opt-in**: disabled by
default and enabled per pack with `scripts/pack-toggle.sh <name> on`. Each pack's header
states its default.

For control-plane mechanics see [Packs and Plugins](../packs-and-plugins.md).

---

## academic

**Version:** 0.3.0 | **Kind:** genre

### Purpose

Produces a peer-review-style academic paper from the surviving findings corpus. The
genre follows academic conventions: structured abstract, methodology section, results
section with citations, discussion, and a formal bibliography.

The citation style is **selectable** — author-date (APA 7th, default) or numbered
(Vancouver/IMRaD/ICMJE) — and an optional APA Method sub-section taxonomy
(Participants / Materials / Procedure / Analysis) can be rendered in APA mode. Editions are
verified live; the IMRaD anchor is a weakened verdict, so conformance is not over-claimed.

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

**Version:** 0.2.1 | **Kind:** genre

### Purpose

Produces a one-page decision brief from the surviving findings corpus. The genre enforces
a hard one-page ceiling: if the content exceeds that limit, it is cut rather than
continued.

`briefing` is **harness-native**: no named domain standard (ISO/NISO/ANSI/APA/etc.)
prescribes a "briefing" format, so unlike the standards-anchored report genres it has no
external standard to conform to and "alignment" does not apply. The nearest named anchors
would be the executive-summary conventions of NIST SP or ESOMAR reports, but adopting
either would turn `briefing` into a variant of `exec-summary` — so it stays deliberately
harness-native.

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

## computing-paper

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces an ACM/IEEE computing conference or journal paper from the surviving findings
corpus. The genre follows ACM/IEEE conventions: abstract, introduction, related work,
approach / system design, an explicit evaluation (experimental setup and results),
discussion, conclusion & future work, and a numbered reference list.

### When to use

Use `computing-paper` when the deliverable is a computing or engineering systems paper
targeting an ACM or IEEE venue. This is distinct from `academic` (APA/IMRaD): choose
`computing-paper` when the work calls for Related Work, a System Design / Approach
section, an explicit Evaluation, and IEEE numbered citations.

### What it provides

- ACM/IEEE section structure: Abstract, Introduction, Related Work, Approach / System
  Design / Method, Evaluation, Discussion, Conclusion & Future Work, References
- IEEE numbered bracket citations (`[1]`) resolving to a numbered reference list
- CCS Concepts (ACM Computing Classification System) and keywords / index terms front
  matter

### Dependencies

None beyond the core engine.

### Benefits

- Enforces the section taxonomy an ACM/IEEE program committee expects, kept separate
  from the academic APA/IMRaD genre
- IEEE numbered citations resolve every claim to a traceable, URL-bearing reference
- Explicit Evaluation section keeps experimental setup and results legible to reviewers

### Enable

```sh
scripts/pack-toggle.sh computing-paper on
```

---

## engineering

**Version:** 0.3.0 | **Kind:** genre

### Purpose

Produces a technical engineering report from the surviving findings corpus. A comparison
table is required. Mermaid architecture diagrams are optional and included when the
findings support a system or component structure worth visualizing.

Optional **ANSI/NISO Z39.18** conformance can be rendered on request — a Report
Documentation Page, a distribution statement / STINFO markings, and Z39.18 back-matter
ordering (with ISO/IEC Directives Part 2 as an international cross-check, verified live).
These are additive and off by default; the standard report is unchanged when they are not
requested.

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

**Version:** 0.3.0 | **Kind:** genre

### Purpose

Produces a 1-2 page decision-oriented executive summary. It can also be **composed into** a
larger report as the leadership-summary section: an ESOMAR-style market-research management
summary, or a PTES-style penetration-test Executive/Leadership Summary expanded with the
PTES sub-elements **Posture**, **Risk Profile**, and **Roadmap**. (ESOMAR is an ethics code,
not a report format — that caveat is carried.) These composable modes are additive and off
by default; standalone behavior is unchanged. Section order is fixed and enforced:

1. **BLUF (Bottom Line Up Front)** — the heading must literally contain the acronym
   "BLUF" for automated checks to locate it. States the answer and recommended action
   before any context.
2. **Key Findings** — 3 to 5 bullets, each a single load-bearing fact with its "so what",
   each tracing to at least one finding's MIF `@id`.
3. **Recommendation** — one bold, specific, actionable directive covering What / Why /
   How / Risk.
4. **Risks & Caveats** — 1 to 3 conditions under which the recommendation fails, plus
   the confidence basis.

The length ceiling is hard: 1-2 pages. It applies to the exec/leadership summary section
itself — standalone, and when that section is embedded in a larger ESOMAR/PTES report — not
to the full composed report a host pack assembles around it. Falsified findings leave zero
trace — they are not mentioned, cited, hedged against, or alluded to anywhere. Internal MIF
finding `@id` handles and `urn:mif:` URNs never appear in the rendered output.

### When to use

Use `exec-summary` when the deliverable targets executives, sponsors, or board members
who need the conclusion and recommended action and will not read past page two.

### What it provides

- Four-section structure with BLUF required as first section
- 3-5 Key Findings bullets with load-bearing facts
- Single actionable Recommendation (What / Why / How / Risk)
- Risks & Caveats section covering failure conditions
- Inline numeric citation markers resolving to a compact footnote list
- Hard 1-2 page ceiling on the summary section (standalone or embedded)
- Optional composable modes: ESOMAR management summary, or PTES Executive/Leadership Summary
  with Posture / Risk Profile / Roadmap sub-elements (additive, off by default)

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

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

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

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

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

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

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

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

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

## humanities-chicago

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces an argumentative humanities essay from the surviving findings corpus in Chicago
Notes-Bibliography style: an Introduction stating a thesis, thematic argument sections
(claim, evidence, interpretation), a Conclusion, numbered footnotes, and a full
Bibliography. There is no Method or Results section.

### When to use

Use `humanities-chicago` when the deliverable is a humanities argument — a literary,
historical, or critical essay — rather than an empirical IMRaD paper. The absence of
Method/Results and the footnote-and-Bibliography citation form are what distinguish it from
the `academic` genre, which targets STEM/social-science empirical writing.

### What it provides

- Argumentative structure (thesis introduction, thematic sections, conclusion)
- Chicago Notes-Bibliography citations: numbered footnotes plus a full Bibliography
- Each footnote shows the human-readable source citation (URL); it resolves internally to a
  MIF finding `@id` for traceability, which is never printed in the output
- Verdict-aware handling (weakened annotated, falsified excluded)

### Dependencies

None beyond the core engine.

### Benefits

- The claim/evidence/interpretation argument sections suit humanities reasoning, which
  argues rather than reports
- Footnote-and-Bibliography form matches how humanities scholars document sources
- The genre carries the weakened-verdict caveat so citation conventions are not
  over-attributed

### Edition currency

Chicago Manual of Style editions evolve (the 18th Edition supersedes the 17th). The genre
instructs the author to verify the current edition live rather than baking an edition
number into output.

### Enable

```sh
scripts/pack-toggle.sh humanities-chicago on
```

---

## humanities-mla

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

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

## security-pentest

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces a dual-audience penetration-test report following the Penetration Testing
Execution Standard (PTES). One document serves two audiences from a single evidence base:
a leadership-facing **Executive Summary** (Background, Posture, Risk Profile, General
Findings, Recommendation Summary, Strategic Roadmap) and an engineer-facing **Technical
Report** (Information Gathering, Vulnerability Assessment, Exploitation, Post-Exploitation,
and a per-finding Risk / Remediation section with severity ratings). The genre is for
authorized engagements only; an authorization and scope statement is required matter.

### When to use

Use `security-pentest` when the deliverable is an authorized penetration-test engagement
report that must brief executives on business risk and equip remediation engineers from the
same findings — an external web-app assessment, an internal network test, or a cloud
infrastructure review.

### What it provides

- Dual-audience structure: a strategic Executive Summary and an operational Technical Report
- Required authorization & scope statement as front matter
- Per-finding severity ratings scored against a current rubric (verify the live CVSS version
  at synthesis time; NIST SP is a separate standards-overlay pack)
- A severity-distribution figure and a per-finding risk/remediation table

### Dependencies

None beyond the core engine.

### Benefits

- One source of truth serves both leadership and remediation engineers, keeping the
  business-risk narrative and the technical evidence consistent
- Audience separation keeps exploit primitives out of the Executive Summary while preserving
  reproducible detail in the Technical Report
- Edition-currency rule on severity scoring avoids baking a stale CVSS edition into the report

### Enable

```sh
scripts/pack-toggle.sh security-pentest on
```

---

## market-research-report

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces a full market research report following the conventional ESOMAR/ISO 20252
structure. Section order is fixed and enforced:

1. **Background & Objectives** — commissioning context, business problem, research
   objectives, and the scope and definitions of the market under study.
2. **Methodology** — research design, sampling (frame, method, size), the instrument,
   and fieldwork (mode, dates, response/completion). The verification gate is stated.
3. **Findings** — the evidence, organized by objective, each claim tracing to a
   finding's MIF `@id` and reporting its verification verdict.
4. **Conclusions & Recommendations** — what the findings mean and the specific,
   traceable recommendations that follow.
5. **Technical Appendix** — full methodology detail (sampling, weighting, instrument,
   fieldwork log), data-quality and limitations notes, and ISO 20252 quality notes.

The report must carry the convention-not-standard caveat: **ESOMAR/ICC is an
ethics/conduct code, not a format mandate.** The structure is conventional practice,
not a codified report standard, and the report must not claim to "conform to the ESOMAR
standard." ISO 20252 is under active revision (AI integration, 2024–2026); any ISO
reference is anchored to "verify the current edition live." Falsified findings are
excluded from the evidence and claims; weakened and inconclusive findings are retained
with annotation, and the Methodology section states this verification policy. Internal
MIF `@id` handles and `urn:mif:` URNs never appear in the rendered output.

### When to use

Use `market-research-report` when the deliverable is a complete market-research study
write-up for clients or insights stakeholders who need a disclosed sampling and
fieldwork basis, a traceable methodology, and actionable recommendations — not a short
summary.

### What it provides

- Five-section structure (Background → Methodology → Findings → Conclusions &
  Recommendations → Technical Appendix) with enforced order
- Explicit sampling and fieldwork disclosure in the Methodology section
- Technical appendix with methodology detail, data-quality notes, and ISO 20252 notes
- Numbered or author-date citations resolving to a source list
- The convention-not-standard caveat required in every rendered report

### Dependencies

None beyond the core engine.

### Benefits

- Enforced section order and required appendix make a complete, defensible study
  structure verifiable without human review
- Mandatory sampling and fieldwork disclosure keeps the evidence basis transparent
- The convention-not-standard caveat prevents the report being mis-sold as conforming
  to a codified ESOMAR standard, and the live-edition anchor keeps ISO 20252 references
  from decaying

### Enable

```sh
scripts/pack-toggle.sh market-research-report on
```

---

## systematic-review

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces a PRISMA 2020 systematic review that makes the evidence-selection process legible
and reproducible end to end. A **PRISMA flow diagram is required** — it reports the count of
records at each stage (identified → screened → excluded with reasons → included) and must
reconcile, so identified minus excluded equals included. The harness's own pipeline maps
onto the PRISMA stages: dimension fan-out is identification, candidate gathering is
screening, the single adversarial falsification gate is eligibility, and synthesis of the
surviving corpus is inclusion; a `falsified` unit is an excluded record carrying its
falsification reason.

Section order:

1. **Title / Abstract (structured)** — background, objectives, eligibility, sources,
   synthesis methods, results, conclusions
2. **Introduction** — rationale and explicit objectives (review question)
3. **Methods** — eligibility criteria, information sources, search strategy, selection
   process, data items, risk-of-bias assessment
4. **Results** — study selection with the PRISMA flow diagram and synthesis of results
5. **Discussion** — limitations and conclusions
6. **Registration & Protocol** — registration record and protocol availability
7. **References** — numbered (Vancouver-style) reference list

### When to use

Use `systematic-review` when the deliverable must document a reproducible evidence-synthesis
process — the eligibility criteria, search, and selection — precisely enough that another
reviewer could repeat it, with every inclusion and exclusion decision auditable.

### What it provides

- Seven-section PRISMA 2020 structure with a structured abstract
- Required PRISMA flow diagram with reconciling stage counts (identified / screened /
  excluded / included)
- A reproducible Methods protocol (eligibility, sources, search, selection, data items,
  risk-of-bias)
- Falsified findings recorded as excluded records with their exclusion reasons
- Numbered (Vancouver-style) citations resolving to a references list

### Dependencies

None beyond the core engine. Mermaid rendering of the flow diagram is optional.

### Benefits

- The required, reconciling flow diagram makes the selection process auditable rather than
  narrated
- Mapping the harness pipeline onto PRISMA stages turns falsification verdicts into
  documented exclusion reasons
- The reproducible Methods protocol forces the eligibility and search to be stated precisely
  enough to repeat

### Enable

```sh
scripts/pack-toggle.sh systematic-review on
```

---

## compliance-audit

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Drafts and models a SOC 2 Type II-shaped controls report so a service organization can
prepare and self-assess its controls narrative ahead of (or independent of) a formal
audit. It reproduces the report **structure** and a tests-of-controls matrix only — it is
**not an attestation, assurance, certification, or audit opinion**, and no licensed CPA
firm is involved. Use it to draft or model a controls report, never to issue one.

Section order:

1. **Independent Service Auditor's Report** — draft placeholder framing scope and period;
   expresses no opinion
2. **Management's Assertion** — the organization's own statement of system and controls,
   tied to finding `@id`s
3. **System Description** — infrastructure, software, people, data, and processes
4. **Trust Services Criteria** — Security always; Availability, Processing Integrity,
   Confidentiality, Privacy when the findings cover them
5. **Tests of Controls & Results** — the matrix: control, test performed, result/exception
6. **Other Information** — supplementary material outside the scope of testing

### When to use

Use `compliance-audit` when the deliverable models a service organization's controls
against the Trust Services Criteria for internal readiness or self-assessment. Do **not**
use it to produce or represent an issued SOC 2 report — that is an attestation engagement
performed by a licensed CPA firm under AICPA standards (SSAE 18), which this harness does
not and cannot perform.

### What it provides

- Six-section SOC 2 Type II-shaped structure
- A required controls / test-results matrix (Control · Test Performed · Result / Exception)
- Explicit in-scope / excluded Trust Services Criteria
- A strongly-stated no-attestation / no-assurance / no-opinion caveat throughout
- Exception reporting (failed or partially-met controls are surfaced, never hidden)

### Dependencies

None beyond the core engine.

### Benefits

- Reproduces a familiar report shape teams can use to drive internal readiness work
- The required matrix forces each control to trace to cited evidence rather than prose
- The no-attestation caveat is load-bearing — it prevents the draft from being mistaken
  for an issued, CPA-attested SOC 2 report

### Enable

```sh
scripts/pack-toggle.sh compliance-audit on
```

## competitive-quadrant

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces a two-axis competitive-quadrant report that ranks vendors in a defined market on
**Completeness of Vision** (x-axis) against **Ability to Execute** (y-axis) and places each
into one of four quadrants. A two-axis quadrant figure is required; every axis score,
strength, and caution must trace to a cited finding.

This genre reproduces a **generic** two-axis competitive-analysis structure. It is **not** a
Gartner Magic Quadrant: "Magic Quadrant" is a Gartner trademark and proprietary methodology,
and the genre is deliberately named `competitive-quadrant`, never `magic-quadrant`.

Section order:

1. **Market Definition / Inclusion Criteria** — the market and the explicit criteria a vendor
   must meet to be included
2. **Two-axis evaluation** — Completeness of Vision against Ability to Execute, with the
   sub-criteria rolled into each axis, every score tied to a finding `@id`
3. **Vendor profiles** — one per vendor, each with an explicit Strengths list and a Cautions
   list, source-attributed
4. **Quadrant placement** — Leaders / Challengers / Visionaries / Niche Players, each vendor
   in exactly one, justified by its two-axis position
5. **Context & Market Overview** — market forces framing the placements
6. **Methodology** — scoring, evidence gathering and verification, limits, and as-of date

### When to use

Use `competitive-quadrant` when the deliverable ranks vendors or offerings in a market on two
evaluation axes and must place them into Leaders / Challengers / Visionaries / Niche Players —
vendor landscape comparisons, buyer shortlists, or platform selection assessments.

### What it provides

- Six-section structure with a required two-axis quadrant figure
- Two named axes (Completeness of Vision, Ability to Execute) with per-vendor scoring
- Per-vendor Strengths / Cautions profiles, each point cited
- Four-quadrant placement (Leaders / Challengers / Visionaries / Niche Players)
- An explicit not-a-Gartner-Magic-Quadrant trademark caveat baked into the genre rules

### Dependencies

None beyond the core engine. Mermaid rendering is optional.

### Benefits

- The required two-axis figure forces a defensible visual placement rather than prose ranking
- Per-vendor Strengths / Cautions pairs make each placement auditable against cited evidence
- The trademark caveat keeps the generic structure clearly distinct from Gartner's proprietary
  Magic Quadrant methodology

### Enable

```sh
scripts/pack-toggle.sh competitive-quadrant on
```

---

## nist-sp

**Version:** 0.2.0 | **Kind:** genre | **Disabled by default (opt-in).**

### Purpose

Produces a NIST Special Publication (SP 800-series) standards/guidance report — a
standards document with front-matter authority, numbered normative sections, defined
terms, references, and appendices. This is the standards-document genre, distinct from an
engagement deliverable such as a penetration-test report: a NIST SP states normative
requirements and control mappings that an engagement report would reference.

Section order:

1. **Authority** — the publication's mandate and the standing of its guidance
2. **Purpose & Scope** — what the publication establishes and its boundary of applicability
3. **Audience** — the intended readers and the roles expected to apply the guidance
4. **Abstract** — a self-contained summary of the problem, guidance, and conclusions
5. **Keywords** — a short controlled list of index terms (no more than ten)
6. **Numbered normative sections** — the body, numbered sequentially (`1.`, `1.1.`,
   `1.1.1.`), each requirement traced to a finding `@id` with explicit normative force
7. **Definitions / Glossary** — every term of art defined once
8. **References** — the numbered reference list
9. **Appendices** — control mappings, control catalogs, and crosswalks

### When to use

Use `nist-sp` when the deliverable is a standards or guidance document that states normative
requirements — a security control baseline, a guidance publication, or a framework
crosswalk that downstream engagement reports will reference.

### What it provides

- NIST SP front matter (Authority, Purpose & Scope, Audience, Abstract, Keywords) in order
- Numbered normative sections (up to four heading levels) with explicit normative force
- A required Definitions/Glossary section for terms of art
- Numbered bracketed `[N]` references carrying each source's MIF `@id` provenance floor
- Appendices for control mappings and crosswalks to external control frameworks

### Dependencies

None beyond the core engine.

### Benefits

- Front-matter authority and scope make the publication's standing and applicability explicit
- Numbered normative sections with consistent normative force (shall / should / may) keep
  requirements unambiguous and individually traceable to evidence
- A required Definitions/Glossary prevents undefined terms of art from carrying normative weight

### Enable

```sh
scripts/pack-toggle.sh nist-sp on
```

## trend-analysis

**Version:** 0.3.0 | **Kind:** genre

### Purpose

Produces a trajectory report tracking how something is changing and projecting forward
under uncertainty. A trajectory or scenario diagram is required — a time-series chart of
the trend and / or a Mermaid state or branch diagram of the scenarios. Every trajectory
claim must be anchored in time; undated trend assertions are not admissible.

This genre is anchored to a **foresight convention, not a codified standard** — no
standards body (ISO/NISO/ANSI) has codified a foresight report format — so the SKILL
discloses the convention rather than claiming standard conformance. An optional **STEEP /
PESTLE environmental scan** and a **Methodology Appendix** (signal/survey sourcing) can be
rendered on request, mirroring IFTF/WEF practice; they are additive and off by default.

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
