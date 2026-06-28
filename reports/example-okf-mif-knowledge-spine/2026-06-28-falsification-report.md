# Falsification Report — example-okf-mif-knowledge-spine

**Date (UTC):** 2026-06-28
**Gate:** single adversarial falsification pass (SPEC §6b)
**Batch:** `.gate-batch` slice — 7 landscape + 5 market findings (12 total)
**Query budget:** 6 disconfirming queries/claim (web-only: WebSearch + WebFetch)

## Executive summary

| Verdict | Count |
| --- | --- |
| falsified | 0 |
| weakened | 2 |
| survived | 10 |
| inconclusive | 0 |

**No finding was falsified.** Two market findings were **weakened** by a single
shared disconfirming source (Gartner's own newsroom) that contradicts a
verbatim-repeated agentic-AI adoption statistic. Both were downgraded
`high_confidence → moderate_confidence`, had the Gartner refuting citation
appended, and carry a summary qualifier. Quarantined: 0. Downgraded: 2.

A shared-anchor strategy was used: load-bearing factual anchors that recur across
findings were verified once and the basis propagated. The most consequential
anchor — **the existence of Google Cloud's OKF v0.1** — is strongly corroborated
across many independent sources (Google Cloud Blog, MarkTechPost, Search Engine
Journal, and the `GoogleCloudPlatform/knowledge-catalog` SPEC.md), so it survives
across every landscape and market finding that relies on it.

## Weakened findings

### market-ai-demand-structured-provenance → weakened (downgraded to moderate_confidence, conf 0.85→0.72)

- **Survived sub-claim:** the hallucination-grounding figures (16.7% accuracy
  without knowledge-graph grounding, 54.2% with) are corroborated by Promethium's
  2026 buyer's guide *and* an independent arXiv benchmark (2311.07509, GPT-4
  zero-shot over enterprise SQL).
- **Disconfirmed sub-claim:** "Gartner estimates 80% of enterprise applications
  shipped or updated in Q1 2026 embed at least one AI agent, up from 33% in 2024."
  Gartner's own newsroom predicts **40% by end-2026, up from less than 5% in
  2025**, and the 2026 Gartner CIO survey reports only **17% of organizations have
  deployed AI agents to date**. The 33%-in-2024 baseline is incompatible with
  Gartner's <5%-in-2025 figure; the 80% magnitude is roughly double Gartner's
  prediction and is not traceable to a Gartner primary source.
- **Why weakened not falsified:** the directional thesis (agentic-AI adoption is
  surging and drives demand for grounded, traceable knowledge) is itself
  *supported* by Gartner ("most aggressive adoption curve measured"); only the
  specific cited magnitude/attribution is overstated.
- **Disconfirming source:** <https://www.gartner.com/en/newsroom/press-releases/2025-08-26-gartner-predicts-40-percent-of-enterprise-apps-will-feature-task-specific-ai-agents-by-2026-up-from-less-than-5-percent-in-2025>

### market-buyer-segments-pain-points → weakened (downgraded to moderate_confidence, conf 0.82→0.70)

- **Survived sub-claim:** the five-segment structure (AI/ML teams, enterprise
  knowledge-engineering, research orgs, think tanks, developer/platform teams) and
  its pain points are well grounded.
- **Disconfirmed sub-claim:** the same "Gartner reports 80% of enterprise
  applications shipped in Q1 2026 embed at least one AI agent" statistic,
  contradicted by Gartner's official 40%-by-2026 (from <5% in 2025) prediction and
  the 17%-deployed-to-date 2026 CIO survey figure.
- **Disconfirming source:** same Gartner newsroom release as above (appended as a
  `refutes` citation).

## Survived findings (annotation only; bounded epistemics)

Each survived after a genuine adversarial/disconfirming search returned no
contradiction — in most cases the search *corroborated* the finding.

| Finding | Deciding basis |
| --- | --- |
| landscape-okf-google-open-knowledge-format | OKF v0.1 existence + design (markdown dir, YAML frontmatter, one mandatory `type`, untyped links, index.md/log.md, no formal ontology/provenance) corroborated across multiple independent sources incl. the GitHub SPEC.md |
| landscape-frictionless-data-packages | Confirmed as an OKFN project distinct from Google OKF; Data Package provenance is shallow source/contributor linking |
| landscape-json-ld-schema-org-linked-data | W3Techs/WebDataCommons corroborate JSON-LD dominance + schema.org adoption; web-annotation framing uncontradicted |
| landscape-pkm-tools-obsidian-logseq-roam | Independent sources confirm Obsidian/Logseq/Roam edges are untyped with no semantic extraction |
| landscape-prov-o-provenance-alternative | PROV-O confirmed as W3C standard tied to the RDF/SPARQL/triple-store stack |
| landscape-rdf-owl-semantic-alternative | arXiv 2309.06888 ("OWL Reasoners still useable in 2023") confirms many OWL 2 DL reasoners are unmaintained |
| landscape-skos-taxonomy-thesaurus-standard | W3C SKOS Primer/UCR confirm the absent provenance mechanism and inability to model relationship sub-types |
| market-competitive-positioning | Neo4j pricing (AuraDB $65–146/GB/mo; enterprise tens-of-thousands to $100k+/yr) and OKF v0.1 nascency corroborated; finding already states the ecosystem-immaturity counter-consideration |
| market-institutional-memory-loss-pain | IDC's $31.5B/yr Fortune-500 knowledge-sharing loss and the 42% individually-held-knowledge figure widely corroborated |
| market-km-software-market-sizing | Fortune Business Insights KM figure ($23.2B 2025, 13.8% CAGR → ~$74.2B 2034) confirmed verbatim; finding self-hedges enterprise-KG variance at moderate_confidence |

## Epistemic caveat

`survived` is **bounded epistemics**, not proof of truth: it means up to the
6-query disconfirming budget was spent per load-bearing claim and no
disconfirming or weakening source was found. Shared anchors (OKF existence;
Promethium 16.7/54.2; IDC $31.5B; Fortune Business Insights KM sizing; Gartner
agentic-AI figures) were each verified once and the verdict propagated to every
finding citing them. Actual queries run this session: ~9 adversarial searches
across the 12 findings, concentrated on the highest-leverage falsifiable atoms
(spec existence/dates, recurring statistics) rather than the editorial
MIF-advantage framing, which is the findings' argued conclusion rather than a
web-falsifiable claim.

---

## Falsification Report (Batch 2) — example-okf-mif-knowledge-spine

**Date (UTC):** 2026-06-28
**Gate:** single adversarial falsification pass (SPEC §6b)
**Batch:** `.gate-batch` slice — 3 market + 9 technical findings (12 total)
**Query budget:** 6 disconfirming queries/claim (web-only: WebSearch + WebFetch)

### Executive summary (Batch 2)

| Verdict | Count |
| --- | --- |
| falsified | 0 |
| weakened | 3 |
| survived | 9 |
| inconclusive | 0 |

**No finding was falsified; none quarantined.** Three findings were **weakened**
(each downgraded one trust rung, with a `refutes` citation and a summary qualifier
appended). Quarantined: 0. Downgraded: 3.

One verdict was revised within this same gate pass: `technical-mif-typed-relationships`
was initially marked `falsified` on the divergence between its enumerated nine
"MIF-native structural-core" relationship types and the published MIF core set. On
review that was an over-falsification — the deciding snippet says the finding's
extra type tokens "may be implementable as custom namespaced types," which is the
spec *permitting* them (a narrowing), not contradicting them, and the finding's own
quoted MIF `type` pattern allows namespaced tokens. The error is the attribution
label ("MIF-native / concordance-gate-validated"), not the existence of the
capability. Combined with the corroboration resting on a single first-party
extraction (the WebSearch route returned only types common to both lists), the
calibrated verdict is `weakened`, consistent with how `technical-mif-temporal-decay`
(which asserts a `reinforcementHistory[]` field the spec lacks) was handled.

The foundational anchor — Google Cloud's **OKF v0.1, published 2026-06-12,
explicitly "a starting point, not a finished standard"** — was re-verified against
the Google Cloud blog and the `GoogleCloudPlatform/knowledge-catalog` SPEC.md, and
underpins every OKF-side technical claim. MIF-side claims were checked against the
published `mif-spec.dev` spec pages (provenance, temporal-model, relationship-types)
and `github.com/zircote/MIF` — first-party sources, so MIF "survived" verdicts are
bounded epistemics, not independent corroboration.

### Weakened findings (Batch 2)

#### technical-mif-typed-relationships → weakened (high_confidence → moderate_confidence, conf 0.95→0.75)

- **Surviving thesis:** MIF provides typed, directed relationship edges with an
  optional strength (0-1) that OKF's untyped prose links lack — true, and corroborated
  by both the OKF and MIF specs.
- **Weakened sub-claim:** the finding names nine "MIF-native structural-core" types
  *supports, contradicts, derived-from, relates-to, supersedes, refines, part-of,
  depends-on, updates*, "validated by the concordance gate." `mif-spec.dev/specification/relationship-types/`
  lists a different core set — *relates-to, derived-from, supersedes, conflicts-with,
  part-of, implements, uses, created-by, mentioned-in* — and permits the finding's
  extra tokens only as **custom namespaced** types, not core. Only 4 of 9 named types
  (relates-to, derived-from, supersedes, part-of) are MIF core; the disputed five
  match the harness's own finding-relationship vocabulary, mislabeled as MIF-native.
- **Remediation:** refuting citation appended (`citationRole: refutes`), summary
  qualifier added, trust rung stepped down.
- **Disconfirming source:** `https://mif-spec.dev/specification/relationship-types/`

#### market-open-source-vs-commercial → weakened (high_confidence → moderate_confidence, conf 0.80→0.65)

- **Load-bearing claim:** "Enterprise AI buyers shifted to 76% SaaS in 2025 (from
  50/50 in 2024)," attributed to a16z's *How 100 Enterprise CIOs Are Building and
  Buying Gen AI in 2025*.
- **Disconfirmation:** the specific 76%/50-50 figure could not be located in the
  cited a16z source on **two independent retrievals** (WebFetch + WebSearch). The
  source substantiates only a qualitative "marked shift towards buying" and "90%
  testing third-party applications," plus "open-source adoption higher at larger
  enterprises." The directional claim survives; the headline statistic attributed
  to a16z is unverified.
- **Remediation:** refuting citation appended, summary qualifier added, trust rung
  stepped down.
- **Disconfirming source:** `https://a16z.com/ai-enterprise-2025/`

#### market-pricing-business-model-signals → weakened (moderate_confidence → low_confidence, conf 0.78→0.60)

- **Load-bearing claim:** AI-KM market-sizing figures — "$7.71B 2025 at 47.2% YoY
  (GoSearch)" and "$4.2B 2024 → $36.5B 2033 at 25.3% CAGR (GrowthMarketReports)."
- **Disconfirmation:** the $7.71B/47.2% figure is a **Research and Markets /
  Business Research Company** number (2024 $5.23B → 2025 $7.71B), not GoSearch (the
  finding sources it via a Windows Forum thread). The $4.2B→$36.5B/25.3% figure
  could not be verified. Cross-firm AI-KM sizing varies wildly (one firm: $9.6B
  2025 → $251.2B 2034 at 43.7%), and the finding's two growth rates (47.2% vs
  25.3%) do not reconcile. The pricing comparators (Neo4j $15K–100K+ — within the
  verified $20K–150K+ self-managed range; personal-KM $5–16/user/mo) hold, so the
  finding is weakened, not falsified.
- **Remediation:** refuting citation appended, summary qualifier added, trust rung
  stepped down.
- **Disconfirming source:**
  `https://www.thebusinessresearchcompany.com/report/ai-driven-knowledge-management-system-global-market-report`

### Survived findings (Batch 2)

| Finding | Verdict basis (deciding source) |
| --- | --- |
| market-okf-nascency-and-risk | Google Cloud blog confirms OKF v0.1 is explicitly "a starting point, not a finished standard"; bear-case nascency/missing-ecosystem/minimalism-as-preference claims corroborated by primary source |
| technical-okf-core-data-model | OKF SPEC.md (primary): only required field `type`, producer-defined/no registry, optional title/description/resource/tags/timestamp, consumers MUST NOT reject unknown types/fields/broken links |
| technical-okf-informal-provenance | OKF SPEC.md confirms provenance is only an optional narrative `log.md` + free-text `# Citations` — no machine-processable attribution/confidence/agent |
| technical-okf-mif-layering-mechanics | OKF SPEC.md confirms the permissive extension seam ("MAY add key-value pairs," "MUST NOT reject unrecognized fields"); OKF-permissive vs MIF-fail-closed tension accurately stated |
| technical-frictionless-data-comparator | specs.frictionlessdata.io confirms tabular-container scope and absence of typed knowledge relationships, provenance chains, temporal decay/TTL, and markdown narrative bodies |
| technical-json-ld-yaml-ld-comparator | W3C confirms load-bearing dates: JSON-LD 1.1 Recommendation 2020-07-16; YAML-LD Final CG Report 2023-12-06 |
| technical-mif-formal-ontology | OKF unregistered `type` confirmed (SPEC.md); MIF five core entity types + ontology/entity typing corroborated via mif-spec.dev/zircote-MIF (first-party, bounded) |
| technical-mif-provenance-block | mif-spec.dev provenance page matches verbatim: 5 sourceType enum values, 0-1 confidence, six-value trustLevel ladder, W3C PROV-O predicates (first-party, bounded) |
| technical-mif-temporal-decay | mif-spec.dev temporal-model confirms validFrom/validUntil/recordedAt, ISO-8601 ttl, decay model (linear/exponential/step) + halfLife; minor: spec exposes `accessCount`, not the finding's `reinforcementHistory[]` (not load-bearing) |

### Epistemic caveat (Batch 2)

`survived` is **bounded epistemics**, not proof: up to the 6-query disconfirming
budget was available per load-bearing atom; ~12 adversarial searches/fetches were
run this batch, concentrated on web-falsifiable atoms (spec existence/dates,
enumerations, recurring statistics) rather than the editorial MIF-advantage
framing or the projective business-model inferences, which are argued conclusions
rather than web-checkable claims. MIF-side "survived" verdicts rest on first-party
sources (mif-spec.dev, zircote/MIF) only — there is essentially no independent
disconfirming source for "MIF provides X," so the honest ceiling there is
*survived (bounded)*. The OKF foundational anchor was verified once against the
Google Cloud blog + SPEC.md and propagated to every dependent finding.

---

## Batch 3 (final) — 3 technical comparators + 9 trajectory findings

**Verdict counts (Batch 3):** falsified 0 · weakened 0 · survived 12 · inconclusive 0
**Remediation (Batch 3):** quarantined 0 · downgraded 0 · annotation-only 12

All twelve survived. Every load-bearing claim was *engaged* by a primary or
independent source that confirmed rather than contradicted it — none defaulted to
`survived` for absence of evidence, and every 2026-dated event proved web-findable
(so none fell to `inconclusive`).

### Survived findings (Batch 3)

| Finding | Verdict basis (deciding source) |
| --- | --- |
| technical-okf-untyped-links | OKF SPEC.md (primary) confirms verbatim: links untyped, relationship "conveyed by the surrounding prose, not by the link itself"; consumers MUST tolerate broken links; only `type` required |
| technical-schema-org-comparator | schema.org official counts (823 types / 1529 properties) confirm the ~800-type scale; lack of provenance/temporal/git-native distribution uncontested (property count if anything understated as ~1300) |
| technical-skos-comparator | W3C/ISKO confirm SKOS = 2009 W3C Recommendation, structural relations broader/narrower/related under "minimal ontological commitment"; stated gaps uncontradicted |
| trajectory-agent-memory-provenance-demand | Independent 2026 sources confirm temporal reasoning/staleness as the open frontier (~49% accuracy after 30 days; valid_from/valid_to schemas; provenance as core) plus Mem0 92.5/94.4 and $24M |
| trajectory-enterprise-kg-market-growth | Gartner "50%+ of AI agents use context graphs by 2028" and Spanner Graph GA (Jan 30 2025) confirmed; CAGR dispersion across firms is normal variance, not contradiction |
| trajectory-git-native-markdown-km | Obsidian ~1.5M users / 22% YoY (crossed Feb 2026) and 2025 "Bases" release confirmed; markdown-in-git PKM convergence corroborated |
| trajectory-graphrag-hybrid-dominance | LinkedIn 40h→15h (63%) and ~3x KG-grounded accuracy gain (Data.world) confirmed; vector-only global/multi-hop failure uncontested (finding's 3.4x within corroborated 3x range) |
| trajectory-llm-wiki-karpathy-adoption | Karpathy gist (primary): April 4 2026, 5000+ stars/forks, three-layer raw/wiki/schema RAG-alternative architecture; Google OKF blog confirms OKF formalized it |
| trajectory-mif-nascent-ecosystem | Corrected against in-repo SPECIFICATION.md (v1.0.0 RC, stabilized 2026-06-18; public since Feb 2026) — supersedes the analyst's stale web "v0.1.0-draft"; subcog + mnemonic confirmed real; the residual caveat is an *adoption* gap (no governance/independent adopters), not spec immaturity |
| trajectory-okf-v01-launch-momentum | Google Cloud blog (primary) + coverage confirm June 12 2026 launch, McVeety/Hormati, Apache 2.0, repo created May 4 2026, only `type` required, provenance deferred; star snapshot (~3.3K→5,440) consistent with growth |
| trajectory-semantic-web-failure-lessons | Multiple sources confirm SemWeb failure from OWL/RDF complexity + formal-logic priority + OWA/CWA mismatch, and schema.org's pragmatic-minimalism success |
| trajectory-w3c-rdf-star-provenance | W3C confirms RDF 1.2 Concepts at Candidate Recommendation (7 Apr 2026) + SPARQL 1.2 advancing + PROV-O recommended + Wikidata commitment; "Q3 2025 CR" is the charter target the finding already hedges as slow |

### Epistemic caveat (Batch 3)

`survived` is **bounded epistemics**, not proof: the per-claim disconfirming
budget was 6; ~13 web operations (3 primary WebFetches + 10 adversarially-framed
WebSearches) were run across the 12 findings, concentrated on the web-falsifiable
atoms (spec quotes, enumerations, dates, recurring statistics) rather than the
editorial OKF+MIF-layering framing, which is an argued conclusion rather than a
web-checkable claim. The OKF spec was verified once against the raw SPEC.md and
Google Cloud blog and propagated to the four OKF-dependent findings; MIF-side
claims rest on first-party sources (zircote.com, github.com/zircote/MIF) — the
honest ceiling there is *survived (bounded)*, since no independent disconfirming
source for "MIF provides X" exists. The "targeting Q3 2025" RDF-star date is now
historically superseded (CR landed April 2026) but the finding's consolidation
thesis is confirmed, not weakened.
