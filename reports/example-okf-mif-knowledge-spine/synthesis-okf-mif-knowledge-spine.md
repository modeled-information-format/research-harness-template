---
slug: reports/example-okf-mif-knowledge-spine/synthesis-okf-mif-knowledge-spine
version: 1
"@context": "https://mif-spec.dev/context/v1.jsonld"
"@type": "Concept"
"@id": "urn:mif:blog:harness/example-okf-mif-knowledge-spine:synthesis"
conceptType: synthesis
genre: blog
channel: blog
mifLevel: 1
mifExempt: true
created: 2026-06-28
topic: example-okf-mif-knowledge-spine
surviving_findings: 36
verdict_breakdown: { survived: 31, weakened: 5, falsified: 0 }
---

# Should MIF be the spine and OKF the packaging for a research knowledge layer?

*A decision synthesis over 36 falsification-gated findings (31 survived, 5 weakened, 0 falsified) spanning four dimensions: technical feasibility, landscape differentiation, adoption trajectory, and market.*

> **Traceability.** Bracketed tokens such as `[technical-okf-core-data-model]` are
> finding `@id` slugs under
> `urn:mif:concept:harness/example-okf-mif-knowledge-spine:`. Every claim below
> traces to the named finding(s); load-bearing external numbers also carry their
> primary-source URL. Findings marked **(weakened)** carry a specific corrected or
> unverified claim, called out where it matters.

## Executive summary

The commissioned question is whether **MIF** (Modeled Information Format) should
serve as the modeling, provenance, and temporal **spine**, layered under **OKF**
(Google Cloud's Open Knowledge Format) as the accessible, git-distributable
**packaging** layer, for a foundational research knowledge spine. The decision
turns on four sub-questions: is the layering technically feasible, is it
differentiated from prior art, is it on a favorable adoption trajectory, and is it
addressed to a real market.

The evidence answers the first two with confidence and the second two with a
genuine two-sidedness that the decision must respect.

- **Technically feasible — yes, by design.** OKF v0.1's conformance model is
  deliberately extensible: consumers must preserve unknown frontmatter keys and
  must not reject documents with unrecognized fields. That extension seam is the
  exact place MIF's typed relationships, first-class provenance, bi-temporal, and
  ontology fields attach without breaking OKF conformance
  [technical-okf-mif-layering-mechanics]. The two specs are complementary at the
  field level, with one real architectural tension (OKF's permissive consumer vs.
  MIF's fail-closed validation) that resolves cleanly by validating at an
  ingestion/enrichment boundary, not at authoring time.
- **Differentiated — yes, on a defensible axis.** Every prior-art alternative
  occupies a different point on the same trade-off curve: RDF/OWL, SKOS, PROV-O,
  JSON-LD/schema.org, and Frictionless Data each deliver part of the semantic
  picture but at Semantic-Web toolchain cost, while PKM tools (Obsidian, Logseq,
  Roam) deliver the accessible markdown surface but with untyped links and no
  provenance. OKF+MIF is the "structured but accessible" cell that none of them
  fill [market-competitive-positioning, landscape-rdf-owl-semantic-alternative,
  landscape-prov-o-provenance-alternative].
- **Trajectory — favorable tailwinds, but asymmetric momentum.** The strongest
  structural tailwind is the 2024–2025 shift from pure-vector RAG to hybrid
  graph+vector retrieval, which creates direct demand for typed, provenance-bearing
  knowledge [trajectory-graphrag-hybrid-dominance]. OKF arrives with Google weight
  and early stars; MIF arrives as the older, already-stabilized spec (v1.0.0, public
  since early 2026) with a sound thesis but no independent community yet
  [trajectory-okf-v01-launch-momentum, trajectory-mif-nascent-ecosystem].
- **Market — real demand, unproven for this specific combination.** The
  knowledge-management and enterprise-knowledge-graph markets are large and growing,
  and institutional-memory loss is a well-quantified pain
  [market-km-software-market-sizing, market-institutional-memory-loss-pain]. But
  demand for *structured knowledge formats in general* does not automatically
  transfer to demand for *OKF+MIF specifically*, and a credible disconfirming case
  exists [market-okf-nascency-and-risk].

The net reading: the architecture is sound and the differentiation is real; the
risk is entirely about timing and adoption, not about technical merit. The
recommended posture is a **staged bet** — build the layering now against OKF's
extension seam, but gate further investment on OKF demonstrating independent
ecosystem traction rather than assuming it.

## Technical feasibility

**OKF is deliberately minimal, and that minimalism is the substrate, not a defect.**
OKF v0.1 (Google Cloud, published 12 June 2026) represents knowledge as a directory
of markdown files with YAML frontmatter. The only required field per concept is
`type`, an unregistered producer-defined string; recommended fields are `title`,
`description`, `resource`, `tags`, and a single `timestamp` (last meaningful
change). Two reserved files, `index.md` and `log.md`, carry hierarchy and an
informal change history [technical-okf-core-data-model]. Three structural gaps
follow directly from this minimalism:

- **Untyped links.** Cross-concept links are standard markdown hyperlinks; the spec
  states relationship semantics live "through surrounding prose," and consumers
  must tolerate broken links. A graph processor knows A links to B but cannot tell
  whether that edge means derivation, dependency, or contradiction without reading
  the prose [technical-okf-untyped-links].
- **Informal provenance.** Origin and change history are handled by `log.md` (a
  human-readable, date-grouped narrative) and a `#Citations` markdown section —
  neither machine-processable, neither carrying confidence, agent identity, or a
  structured citation role [technical-okf-informal-provenance].
- **A single timestamp.** OKF records only last-modified; it cannot express when a
  claim became or stopped being true [technical-okf-core-data-model].

**MIF supplies exactly the layers OKF defers.**

- **Typed relationships.** MIF carries a `relationships[]` array of typed, directed
  edges between concepts, each with an optional numeric `strength` (0.0–1.0) and
  extensible metadata — the queryable semantic graph that OKF's prose links cannot
  natively support [technical-mif-typed-relationships] **(weakened)**. *Correction
  carried from the gate:* the finding labels nine "structural-core" relationship
  types, but per `mif-spec.dev/specification/relationship-types` only four of those
  named (`relates-to`, `derived-from`, `supersedes`, `part-of`) are MIF spec-core;
  the other five are the research harness's own finding vocabulary, admissible only
  as namespaced custom types. The *capability* claim — typed directed edges with
  strength that OKF lacks — holds; the specific enumeration of "nine MIF-native
  core types" does not.
- **First-class provenance.** MIF's `provenance` object is a structured,
  W3C PROV-O-compatible block on every concept: a `sourceType` enum
  (`user_explicit`, `agent_inferred`, `external_import`, `system_generated`,
  `user_implicit`), a numeric `confidence` (0–1), a `trustLevel` tier, agent
  identity, and optional `wasGeneratedBy`/`wasAttributedTo`/`wasDerivedFrom`
  properties — encoding the *epistemic status* of a claim, not just its edit time
  [technical-mif-provenance-block].
- **Bi-temporal and decay modeling.** MIF separates valid time
  (`validFrom`/`validUntil`) from transaction time (`recordedAt`), and adds a
  `ttl` plus a `decay` sub-object (model, half-life, current strength,
  last-reinforced) so a consumer can automatically flag staleness — none of which
  OKF's single timestamp can express [technical-mif-temporal-decay].
- **Formal ontology.** MIF's `ontology` reference plus `entity` block formally type
  each concept against a versioned ontology (a generic core of five types —
  concept, person, organization, technology, file — extensible by domain packs).
  OKF's free-form `type` string becomes a *hint* for MIF ontology matching during
  enrichment [technical-mif-formal-ontology].

**The layering mechanics are concrete and the one real tension is resolvable.**
Because OKF mandates that consumers preserve unknown keys, an OKF-compliant bundle
can carry MIF fields as extended frontmatter (or companion JSON) without breaking
conformance. The field-by-field complement is direct: OKF `type` → MIF
`entity.entity_type` + `ontology.id`; OKF `timestamp` → MIF bi-temporal fields;
OKF `resource` → MIF `citations[].url`; OKF `log.md` → MIF `provenance` +
reinforcement history; OKF untyped links → MIF typed `relationships[]`. The
architectural tension is that OKF's consumer model is permissive ("tolerate broken
links, unknown types") while MIF's harness is fail-closed (an unresolvable type is
a hard failure). The resolution is to keep OKF permissive for authoring and
distribution and apply MIF validation at an ingestion-time enrichment pass — lossy
in the OKF→MIF direction (type inference) but lossless in MIF→OKF (types degrade
gracefully to annotated prose links) [technical-okf-mif-layering-mechanics].

**Verdict on feasibility:** strongly supported. Eight technical findings, all
*survived* except the relationship-enumeration detail, establish that the layering
is not just possible but architecturally intended by OKF's extension design.

## Landscape differentiation

Every serious prior art occupies a different point on the same two-axis map —
*semantic depth* versus *authoring accessibility* — and OKF+MIF is differentiated
precisely by sitting where no incumbent does.

| Prior art | What it delivers | What it lacks for a knowledge spine | Finding(s) |
| --- | --- | --- | --- |
| RDF / OWL | Complete typed semantics, formal ontology, inference | Prohibitive authoring/tooling cost (Turtle, SPARQL, triple stores; many OWL reasoners unmaintained) | [landscape-rdf-owl-semantic-alternative] |
| SKOS | Thesaurus hierarchy (broader/narrower/related) as linked data | Only three predicates; no provenance, no narrative body; RDF toolchain required | [landscape-skos-taxonomy-thesaurus-standard, technical-skos-comparator] |
| PROV-O | The provenance standard MIF is modeled on | Provenance slice only; needs full RDF stack to author/query | [landscape-prov-o-provenance-alternative] |
| JSON-LD / schema.org | Web-scale typed entities (schema.org on ~45% of top sites) | Serialization/vocabulary for web annotation, not a knowledge-management lifecycle; no native provenance or temporal verdicts | [landscape-json-ld-schema-org-linked-data, technical-json-ld-yaml-ld-comparator, technical-schema-org-comparator] |
| Frictionless Data | Git-native packaging of *tabular* data with shallow lineage | Datasets not knowledge concepts; no typed relationships, no decay, no markdown body | [landscape-frictionless-data-packages, technical-frictionless-data-comparator] |
| PKM tools (Obsidian, Logseq, Roam) | Accessible markdown + wiki links; the closest prior art to OKF | Untyped links, no formal ontology, no provenance, author-focused rather than interoperable | [landscape-pkm-tools-obsidian-logseq-roam] |

Two structural observations make the differentiation defensible rather than
cosmetic. First, the Semantic Web stack (RDF/OWL/SKOS/PROV-O) solves *semantic
completeness* but not *adoption friction*; OKF+MIF preserves the markdown authoring
surface those standards sacrifice while remaining semantically compatible with them
— MIF's provenance is explicitly PROV-O-grounded and expressible as plain JSON, so
it delivers PROV-O semantics "at JSON authoring cost" without a triple store
[landscape-rdf-owl-semantic-alternative, landscape-prov-o-provenance-alternative].
Second, the PKM tools prove the demand for the accessible surface but expose the
exact gap MIF fills: typed links, provenance, and temporal validity that "these
tools deliberately avoid" [landscape-pkm-tools-obsidian-logseq-roam].

OKF itself is the keystone of the landscape: Google Cloud explicitly designed it as
a *format, not a platform* — minimally opinionated, producer/consumer independent,
git-distributable — and its deliberate omissions (no ontology, no provenance, no
typed links, no temporal model beyond `timestamp`) are "not defects, they are the
spec's stated minimalism," which is what makes it an ideal packaging layer for MIF
[landscape-okf-google-open-knowledge-format].

**Verdict on differentiation:** strongly supported, all seven landscape findings
*survived*. The combination is genuinely the "structured but accessible" cell:
more semantically rich than KM wikis, more open and git-native than proprietary
graph databases [market-competitive-positioning].

## Adoption trajectory

The trajectory evidence is the most consequential for the decision because it cuts
both ways. The tailwinds are real and several; the cautions are equally concrete.

**Tailwinds.**

- **The hybrid graph+vector shift is the strongest structural tailwind.** Pure
  vector RAG demonstrably fails on multi-hop and global-synthesis queries (0%
  accuracy on schema-bound queries); graph-grounded retrieval reaches 90%+ where
  vector-only scores 0%, and an LLM grounded with a knowledge graph scores 56.2%
  versus 16.7% ungrounded — a 3.4x improvement. The mid-2025 practitioner consensus
  converged on "Vector plus Graph," and the demand for typed relationships and
  provenance is driven by the *failure* of schema-less storage
  [trajectory-graphrag-hybrid-dominance].
- **The practitioner community already converged on OKF's packaging bet.** Andrej
  Karpathy's 4 April 2026 "LLM wiki" gist (5,000+ stars and forks) established
  git-native, LLM-maintained markdown as the default for context persistence, and
  Google explicitly named it as the pattern OKF formalizes
  [trajectory-llm-wiki-karpathy-adoption]. Git-native markdown KM is mainstream:
  Obsidian alone has 1.5M+ users growing ~22% year over year, with AI integration
  now the dominant adoption driver [trajectory-git-native-markdown-km].
- **Enterprise knowledge graphs are entering the mainstream.** The segment shows
  21–36% CAGR across analyst firms, and Gartner places knowledge graphs on the
  Slope of Enlightenment, forecasting that 50%+ of AI agent systems will use
  context graphs by 2028 (decision traces, temporal validity, and policy layers —
  the same capabilities MIF adds) [trajectory-enterprise-kg-market-growth].
- **Provenance and temporal validity are the documented hard problems in agent
  memory.** Mem0 (48k+ stars, $24M funded) tops recall benchmarks (92.5 LoCoMo /
  94.4 LongMemEval) yet temporal abstraction degrades to 64% at 1M tokens and 49%
  at 10M; the biggest 2025–2026 benchmark gains were in temporal reasoning
  (+29.6 points). MIF's provenance and temporal model map directly onto these open
  problems [trajectory-agent-memory-provenance-demand].
- **The standards layer is consolidating, not fragmenting.** W3C RDF 1.2 / RDF-star
  (WG established 2022, Candidate Recommendation targeted Q3 2025) is closing the
  provenance/statement-qualification gap, and PROV-O remains the recommended
  provenance ontology — so MIF's decision to build on PROV-O is well-positioned as
  these trajectories converge [trajectory-w3c-rdf-star-provenance].
- **OKF launched with real early attention.** The
  `GoogleCloudPlatform/knowledge-catalog` repo reached 5,440 stars and 416 forks
  within weeks, under Apache 2.0, with reference implementations and Google's own
  Knowledge Catalog already ingesting OKF [trajectory-okf-v01-launch-momentum].

**Cautions (carried into Risks below).**

- **The Semantic Web is both a map and a headwind.** It failed at mass adoption
  over two decades through complexity, misaligned incentives, and logic-first
  priorities; Schema.org succeeded by being minimal and immediately useful. The
  lesson for OKF+MIF is that layered, opt-in complexity beats mandatory
  completeness — and the risk is that MIF's provenance/ontology layer is perceived
  as "Semantic Web complexity repackaged" by practitioners who already rejected RDF
  [trajectory-semantic-web-failure-lessons].
- **MIF's momentum is asymmetric to OKF's — but the asymmetry is distribution, not
  maturity.** MIF has been public since February 2026 and reached v1.0.0 (Release
  Candidate, stabilized 2026-06-18), with two reference implementations (subcog,
  mnemonic) — so it is the *older and more stabilized* specification, predating OKF
  v0.1 (June 2026) by roughly four months. What it lacks relative to OKF is
  distribution: no large independent adopter base, no formal governance body, and no
  published adoption metrics. The gap it fills is real, but the network effects that
  make a format a de facto standard have not yet materialized — an adoption gap, not
  a version-maturity gap [trajectory-mif-nascent-ecosystem].

**Verdict on trajectory:** favorable but conditional. All nine trajectory findings
*survived*. The favorable scenario is explicit in the evidence — OKF's adoption
creates the practitioner base that hits the typed-relationship and provenance walls
OKF defers, and those users become the most motivated MIF adopters. The unfavorable
scenario is equally explicit: OKF's minimalism becomes a ceiling and demand for the
heavier layer never develops [trajectory-mif-nascent-ecosystem].

## Market opportunity

**The addressable market is large and the underlying pain is well-quantified.**
The KM software market is ~$23B in 2025 at 13–18% CAGR; the more directly
comparable enterprise-knowledge-graph market is ~$0.9–2.9B in 2025 at 20–33% CAGR.
Together they frame a TAM north of $25B in 2025, with a SAM (organizations actively
seeking open, format-neutral, git-distributable knowledge infrastructure) estimated
at roughly 8–12% of the KM market, ~$2–3.3B [market-km-software-market-sizing].
*Read these with the analyst-variance caveat the finding itself states:* enterprise
KG figures vary 2–3x across firms by definition, and the SAM/SOM figures are
analyst inference, not measured.

The pain that funds this market is concrete and *survived* the gate cleanly:
institutional knowledge loss costs Fortune 500 companies ~$31.5B/year, the average
US enterprise loses ~$4.5M/year to information silos, and 42% of institutional
knowledge resides solely with individual employees — failure modes that provenance,
temporal versioning, and typed relationships directly address
[market-institutional-memory-loss-pain]. The AI-grounding pain is similarly solid:
LLMs answer complex enterprise queries correctly only 16.7% of the time without
knowledge-graph grounding, rising to 54.2% with it — a figure corroborated across
the corpus [market-ai-demand-structured-provenance].

**Competitive positioning is clear.** OKF+MIF sits between personal/team KM tools
(Notion at $10–16/user/month, Obsidian commercial at $50/user/year, Roam at
$15/month — none with typed relationships, formal ontology, or first-class
provenance) and enterprise KG platforms (Neo4j Enterprise at $15K–100K+/year,
plus ~1 FTE per 50–100 entity types of semantic-governance cost — high barrier,
not git-native). The differentiators are git-native distribution, progressive
enrichment, agent-readability without an SDK, and zero vendor lock-in
[market-competitive-positioning].

**Buyer segments and business model.** Five buyer segments carry documented pains:
AI/ML teams (LLM grounding), enterprise knowledge-engineering teams (semantic
layers across 5+ fragmented platforms), research organizations (FAIR
provenance/citation), think tanks (institutional memory), and developer/platform
teams (replacing abandoned wikis) [market-buyer-segments-pain-points]
**(weakened)**. The open-format segment is real and distinct — developer teams,
research/academic organizations under FAIR funder mandates, and privacy-sensitive
regulated enterprises all prefer open, git-native, self-hostable formats
[market-open-source-vs-commercial] **(weakened)**. The natural business model,
calibrated against adjacent markets, is open-core: a free MIT-licensed format and
CLI, a commercial enterprise tier (hosted sync, provenance audit, SSO, compliance),
and a usage-priced platform/API tier — mirroring Neo4j (open Community + commercial
Enterprise) and Obsidian (free personal + paid commercial + paid sync)
[market-pricing-business-model-signals] **(weakened)**.

*Corrections carried from the gate on the weakened market findings (do not treat
these as established facts):*

- The "Gartner: 80% of enterprise applications embed an AI agent by Q1 2026, up
  from 33% in 2024" statistic in [market-ai-demand-structured-provenance] and
  [market-buyer-segments-pain-points] is **overstated**. Gartner's actual
  prediction is **40% of enterprise apps with task-specific AI agents by
  end-2026, up from <5% in 2025**, and its 2026 CIO survey shows only ~17% of
  organizations have deployed AI agents to date
  (<https://www.gartner.com/en/newsroom/press-releases/2025-08-26-gartner-predicts-40-percent-of-enterprise-apps-will-feature-task-specific-ai-agents-by-2026-up-from-less-than-5-percent-in-2025>).
  The directional surge in agent adoption is real; the magnitude is not as cited.
- The "76% SaaS in 2025, up from 50/50 in 2024" a16z figure in
  [market-open-source-vs-commercial] **could not be located in the source** on
  re-retrieval; the source supports only a qualitative "marked shift toward
  buying." Treat the build-vs-buy shift as directional, not as a hard percentage.
- The AI-KM sizing figures in [market-pricing-business-model-signals] ("$7.71B at
  47.2% YoY"; "$4.2B → $36.5B at 25.3% CAGR") are **misattributed and do not
  reconcile** with each other or with cross-firm estimates. Lean on the pricing
  *comparators* (Neo4j, personal-KM tiers), which hold, not on the AI-KM
  growth-rate numbers.

**Verdict on market:** a real and growing market with solid, survived pain
signals, but the headline AI-adoption and AI-KM-sizing statistics in the weakened
findings must be discounted. The market case for *structured knowledge
infrastructure* is well-founded; the case for *OKF+MIF specifically* depends on the
adoption questions in the next section.

## Risks and caveats

**The strongest disconfirming finding survived the gate and must be weighed at full
strength.** OKF was 16 days old at research time, with zero enterprise adoption
record, no producer libraries, no consumer integrations with major agent frameworks
(LangChain, LlamaIndex, AutoGen, crewAI), and no governance tooling. Three risks
compound [market-okf-nascency-and-risk]:

1. **Format-adoption is historically slow and contested.** Semantic Web,
   Frictionless Data, Open Annotation, and Schema.org all achieved only partial
   penetration; Google's backing is significant but not determinative (Google Buzz,
   Wave, and + all failed despite Google's resources). OKF's value rests on network
   effects, which require critical mass before they materialize.
2. **Minimalism may be the buyer preference, not a gap.** Obsidian's success (plain
   markdown, untyped links, no schema) shows minimalism is itself a differentiator
   for a large segment. If the market that wants OKF-style formatting wants it
   *because* it is minimal — actively repelled by schema enforcement and provenance
   overhead — then MIF's layer misreads buyer preference. This is the central
   strategic risk, and it is reinforced by the trajectory finding's "minimalism as
   ceiling" scenario [trajectory-mif-nascent-ecosystem].
3. **SaaS competitive pressure.** The broader KM market is trending toward buying
   over building, and well-funded AI-native incumbents (Notion AI, Microsoft
   Copilot for SharePoint/Confluence, Glean, GoSearch) are expanding into the same
   segments with enterprise SSO, compliance certifications, and sales forces that an
   open-format project lacks. A format-first offering competes on merit before
   ecosystem depth — a slower path to value capture [market-competitive-positioning].

**The Semantic Web's failure is a live headwind**, not just history: practitioners
burned by RDF/OWL adoption costs carry skepticism toward any new format that smells
like ontological modeling, and MIF's PROV-O/JSON-LD/ontology vocabulary is exactly
what could trigger that reflex. Keeping the conformance ladder visible and the entry
cost genuinely low is the critical adoption challenge
[trajectory-semantic-web-failure-lessons].

**MIF's adoption gap is a risk independent of OKF's.** MIF's specification is
stabilized (v1.0.0, public since early 2026), but two reference implementations by a
single author, no governance body, and no independent adopters mean MIF's
*adoption* — not its spec maturity — is potential-in-progress, not realized
[trajectory-mif-nascent-ecosystem].

**Epistemic caveats on the weakened findings** (already detailed under Market):
four of the five weakened findings are market findings whose *theses survive* but
whose *headline statistics* were corrected or could not be verified at the gate
(Gartner agent-adoption magnitude; a16z 76% SaaS; AI-KM sizing). The fifth
[technical-mif-typed-relationships] is a technical finding whose *capability* claim
survives but whose enumeration of "nine MIF-native core relationship types" is
mislabeled (only four are spec-core). None of these falsifies its dimension; all of
them mean specific numbers and lists in this synthesis should be cited with their
caveat attached.

## Decision guidance

**The decision is not "is the architecture sound" — it is — but "is the timing
right and is the adoption bet acceptable."**

The four sub-questions resolve as:

| Sub-question | Resolution | Confidence |
| --- | --- | --- |
| Technically feasible? | Yes — OKF's extension seam is designed for exactly this; field-level complement is direct; the one tension resolves at an enrichment boundary | High (8 findings, all survived bar one detail) |
| Differentiated from prior art? | Yes — uniquely occupies the "structured + accessible" cell; PROV-O semantics at JSON cost | High (7 landscape findings, all survived) |
| Favorable trajectory? | Conditionally — strong hybrid-RAG/agent-memory/git-markdown tailwinds, but OKF/MIF momentum is asymmetric and unproven | Medium (9 findings survived; two are explicit cautions) |
| Real market? | Yes for structured knowledge infrastructure; unproven for OKF+MIF specifically | Medium (pain signals survived; some sizing/adoption stats weakened) |

**What the decision turns on.** The single strongest argument *for* proceeding is
that the structural demand for typed, provenance-bearing knowledge is being created
right now by the failure of schema-less RAG and the documented hard problems of
agent memory — and OKF+MIF is positioned precisely at that demand
[trajectory-graphrag-hybrid-dominance, trajectory-agent-memory-provenance-demand].
The single strongest argument *against* is that OKF is too new to know whether it
clears the network-effects threshold, and its minimalism may be the actual buyer
preference rather than a gap to be filled [market-okf-nascency-and-risk].

**Recommended posture: a staged, low-regret bet.**

1. **Build the layering now.** Feasibility and differentiation are settled, and the
   work is genuinely low-regret because MIF attaches to OKF's *existing* extension
   seam rather than forking it — MIF fields degrade gracefully back to OKF prose if
   the bet is wound down [technical-okf-mif-layering-mechanics]. Position MIF as the
   enrichment layer OKF users reach for when they hit the typed-relationship and
   provenance walls, not as a precondition for using OKF.
2. **Lead with the accessible entry point.** Apply the Schema.org lesson directly:
   make Level-1 conformance trivially cheap and the full provenance/ontology ladder
   strictly opt-in, so MIF is never perceived as "RDF again"
   [trajectory-semantic-web-failure-lessons].
3. **Gate further investment on independent OKF traction.** The disconfirming
   finding is decisive here: do not scale commitment on Google's launch weight
   alone. Concrete go/no-go signals are OKF producer libraries and agent-framework
   integrations appearing *outside Google*, and evidence that OKF adopters actively
   want a heavier semantic layer rather than preferring minimalism
   [market-okf-nascency-and-risk, trajectory-mif-nascent-ecosystem].
4. **Pursue the open-core model only after format traction.** The
   open-source-core + commercial-enterprise-tier path is the right shape, but it is
   a slower route than SaaS; sequence it behind demonstrated developer/research
   adoption rather than ahead of it [market-pricing-business-model-signals,
   market-open-source-vs-commercial].

**Bottom line.** The evidence supports building OKF+MIF as a technically sound,
genuinely differentiated knowledge spine, while treating it as an adoption bet whose
escalation is conditioned on OKF proving independent ecosystem momentum. Proceed to
build; stage the scale-up; watch the disconfirming signals as carefully as the
bullish ones.

## Provenance and method

This synthesis covers all 36 active findings of the
`example-okf-mif-knowledge-spine` session: 12 technical, 7 landscape, 9 trajectory,
8 market. Each passed the single adversarial falsification gate exactly once;
31 *survived* and 5 were *weakened* (none *falsified*). Weakened findings are used
for the texture they add but every disputed claim they carry is corrected or
flagged at lower confidence at the point of use, per the gate's verdict basis.
Every assertion above traces to a named finding `@id` slug, and load-bearing
external figures additionally carry their primary-source URL on the originating
finding's citation list.
