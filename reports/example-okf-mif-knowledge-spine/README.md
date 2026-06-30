# Example: OKF+MIF as a foundational research knowledge spine

**Research ID:** example-okf-mif-knowledge-spine
**Created:** 2026-06-28 | **Updated:** 2026-06-30
**Findings:** 36 (survived 31, weakened 5) | **Sources:** 84 unique URLs
**Falsification:** 2026-06-28 — survived 31, weakened 5 ([report](2026-06-28-falsification-report.md))
**Status:** archived

---

## Purpose

Decide whether MIF should serve as the modeling, provenance, and temporal spine beneath OKF's accessible, git-distributable packaging layer for a foundational research knowledge spine — testing that layering on four axes: technical feasibility, differentiation from prior art, adoption trajectory, and market reality.

## Dimensions

- **landscape** — Comparable prior art, alternatives, and competing approaches.
- **market** — Market analysis for an OKF+MIF knowledge spine: demand drivers, buyer segments, competitive positioning, and sizing.
- **technical** — Technical feasibility, architecture, and implementation evidence.
- **trajectory** — Direction of travel: adoption, standards, and momentum signals.

## Key Findings

- **Technically feasible by design, with one resolvable tension.** OKF v0.1 requires consumers to preserve unknown frontmatter keys, giving MIF a non-breaking extension seam for its typed relationships, PROV-O-compatible provenance, bi-temporal/decay, and ontology fields; the one real friction — OKF's permissive consumer model vs. MIF's fail-closed validation — resolves by validating at an ingestion-time enrichment pass, and MIF→OKF degradation is lossless (types fall back to annotated prose links).
- **Differentiation is structural, not cosmetic.** Every prior art sits elsewhere on the depth-vs-accessibility curve: RDF/OWL, SKOS, PROV-O, JSON-LD/schema.org, and Frictionless Data deliver semantics only at Semantic-Web toolchain cost, while Obsidian/Logseq/Roam deliver the markdown surface but with untyped links and no provenance. OKF+MIF uniquely fills the "structured but accessible" cell — PROV-O semantics at plain-JSON authoring cost, no triple store.
- **The strongest tailwind is the failure of schema-less RAG.** Graph-grounded retrieval scores 56.2% vs 16.7% ungrounded (3.4x) and 90%+ where pure vector scores 0%, and provenance plus temporal validity are the documented hard problems of agent memory (Mem0's temporal abstraction degrades to 49% at 10M tokens). Demand for exactly MIF's typed-relationship-plus-provenance layer is being created right now.
- **Adoption momentum is asymmetric — but the asymmetry is distribution, not maturity.** MIF is the older, already-stabilized spec (v1.0.0 Released, public since early 2026), predating OKF v0.1 (launched 12 June 2026 with Google weight and 5,440 GitHub stars) by ~four months. What MIF lacks is OKF's distribution: two single-author reference implementations (subcog, mnemonic), no governance body, no independent adopters yet. The favorable trajectory is real but conditional on OKF seeding the practitioner base MIF's stabilized semantic layer would enrich.
- **The market pain is large and survived the gate; the OKF+MIF-specific bet is not yet proven.** Institutional-memory loss runs ~$31.5B/year at Fortune 500s, knowledge-graph grounding lifts LLM answer accuracy from 16.7% to 54.2%, and the combined KM + enterprise-KG TAM exceeds ~$25B in 2025 — but demand for structured formats in general does not transfer automatically to OKF+MIF, and the disconfirming finding (OKF 16 days old with no ecosystem; minimalism possibly being the buyer preference rather than a gap) survived at full strength.
- **Five findings were weakened, not falsified — discount the specific numbers, keep the theses.** Four market findings carry overstated or unverified statistics (the Gartner "80% AI-agent adoption by Q1 2026" should read 40% by end-2026 from <5%; the a16z "76% SaaS" figure is unverified; AI-KM sizing figures do not reconcile), and one technical finding mislabels "nine MIF-native core relationship types" when only four (relates-to, derived-from, supersedes, part-of) are spec-core. Each capability claim holds; each disputed number travels with its caveat.
- **Net guidance: build now, stage the scale-up.** Building the layering is low-regret (MIF attaches to OKF's existing seam and degrades back to prose if wound down); lead with a trivially cheap Level-1 entry to avoid the Semantic Web's "too much ceremony" failure; and gate further investment on OKF demonstrating independent, non-Google ecosystem traction and on evidence that adopters actually want the heavier semantic layer.

## Reports

| Type | Title |
| --- | --- |
| Executive Summary | [Executive Summary: Should MIF Be the Spine Beneath OKF for a Research Knowledge Spine?](report-exec-summary.md) |
| Briefing Report | [Decision Briefing: OKF+MIF as a Foundational Research Knowledge Spine](report-briefing.md) |
| Synthesis | [Should MIF be the spine and OKF the packaging for a research knowledge layer?](synthesis-okf-mif-knowledge-spine.md) |
| Market Research Report | [Market Research Report: An OKF+MIF Knowledge-Spine Offering](report-market-research-report.md) |
| Market Sizing | [Market Sizing: The Structured Knowledge-Spine (OKF+MIF) Opportunity](report-market-sizing.md) |
| Competitive Analysis | [Competitive Analysis: OKF+MIF vs Knowledge-Representation Prior Art](report-competitive-analysis.md) |
| Competitive Quadrant | [Competitive Quadrant: Structured-vs-Accessible Knowledge Formats](report-competitive-quadrant.md) |
| Trend Analysis | [Trend Analysis: Adoption & Standards Momentum for an OKF+MIF Spine](report-trend-analysis.md) |
| Trend Modeling | [Trend Modeling: Trajectories & Scenarios for OKF+MIF Knowledge Persistence](report-trend-modeling.md) |
| Engineering Report | [Engineering Report: Feasibility of Layering MIF over OKF (Extension Seam, Conflicts, Round-Trip)](report-engineering.md) |
| Academic Paper | [Layering MIF Provenance and Temporal Semantics over the Open Knowledge Format: A Feasibility and Differentiation Study](report-academic.md) |
| Computing Paper | [Toward a Layered Knowledge Spine: MIF Provenance/Temporal Semantics over OKF Markdown Packaging](report-computing-paper.md) |
| Falsification Report | [Falsification Report — example-okf-mif-knowledge-spine](2026-06-28-falsification-report.md) |
| Research Progress | [Research Progress: Example: OKF+MIF as a foundational research knowledge spine](research-progress.md) |
| Document | [MIF Provenance Layer over OKF — Kiro spec (requirements → design → tasks)](example-okf-mif-knowledge-spine-kiro-build-spec.md) |
| Document | [OKF+MIF Extension Seam — feature spec](example-okf-mif-knowledge-spine-feature-build-spec.md) |
| Document | [OKF+MIF Knowledge-Spine Build Spec — an AI-ready architecture spec for layering MIF's modeling/provenance/temporal spine on OKF packaging](example-okf-mif-knowledge-spine-build-spec.md) |

## Findings by Dimension

| Dimension | Findings |
| --- | --- |
| technical | 12 |
| trajectory | 9 |
| market | 8 |
| landscape | 7 |

## Tags

`accuracy` `actor-attribution` `adjacent-markets` `adoption` `adoption-failure` `agentic-ai` `ai-agent` `ai-agents` `ai-demand` `ai-ml-teams` `architecture` `attribution` `bi-temporal` `business-model` `buyer-preference` `buyer-segments` `citations` `commercial` `comparator` `comparison` `competitive-positioning` `complexity` `confidence` `confluence` `context-graphs` `controlled-vocabulary` `counter-evidence` `data-distribution` `data-model` `data-package` `dataset-packaging` `decay` `demand` `ecosystem` `enterprise` `enterprise-knowledge-graph` `enterprise-licensing` `entity-typing` `extension-seam` `fair-data` `formal-typing` `format-adoption` `frictionless-data` `gap-analysis` `gartner` `git-distributable` `git-native` `github` `google-cloud` `graph` `graphrag` `hallucination` `headwind` `hybrid-architecture` `informal` `institutional-memory` `integration` `interoperability` `json-descriptor` `json-ld` `karpathy` `knowledge-graph` `knowledge-loss` `knowledge-management` `knowledge-organization` `knowledge-packaging` `knowledge-representation` `landscape` `launch` `layering` `lessons` `linked-data` `llm` `llm-wiki` `log-md` `logseq` `markdown` `market` `market-growth` `market-risk` `market-sizing` `memory` `memory-format` `microsoft` `mif` `mif-advantage` `minimalism` `modeled-information-format` `momentum` `nascent` `neo4j` `notion` `obsidian` `okf` `okf-nascency` `okfn` `ontology` `open-core` `open-knowledge-format` `open-knowledge-foundation` `open-source` `owl` `pain-points` `pattern` `personal-knowledge-management` `pkm` `pricing` `prior-art` `production` `prov-o` `provenance` `rag` `rdf` `rdf-1-2` `rdf-star` `relationships` `research` `risk` `roam-research` `round-trip` `saas` `schema-enforcement` `schema-org` `second-brain` `semantic-web` `semantics` `skos` `sparql` `specification` `staleness` `standards` `stardog` `structured-data` `tabular-data` `tam-sam-som` `taxonomy` `technical` `temporal` `temporal-validity` `temporal-versioning` `thesaurus` `think-tank` `trajectory` `ttl` `typed-relationships` `untyped-links` `v0-1` `vector-search` `w3c` `w3c-prov-o` `web-annotation` `web-vocabulary` `wiki-links` `yaml-frontmatter` `yaml-ld`
