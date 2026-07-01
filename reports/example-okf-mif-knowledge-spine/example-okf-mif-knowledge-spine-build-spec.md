---
slug: reports/example-okf-mif-knowledge-spine/example-okf-mif-knowledge-spine-build-spec
version: 1
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-okf-mif-knowledge-spine:build-spec
conceptType: semantic
namespace: harness/example-okf-mif-knowledge-spine
title: "OKF+MIF Knowledge-Spine Build Spec — an AI-ready architecture spec for layering MIF's modeling/provenance/temporal spine on OKF packaging"
created: "2026-06-29T00:00:00Z"
genre: architecture-spec
audience: implementer
status: proposed
mif:
  conformanceLevel: 1
evidence_base: "36 active findings (example-okf-mif-knowledge-spine) — 12 technical, 7 landscape, 9 trajectory, 8 market; 31 survived, 5 weakened, 0 falsified"
provenance:
  "@type": Provenance
  sourceType: system_generated
  confidence: 0.9
  trustLevel: moderate_confidence
citations:
  - "@type": Citation
    citationType: specification
    citationRole: source
    title: "OKF — Open Knowledge Format (Google Cloud), v0.1 core data model"
    url: "https://github.com/google/open-knowledge-format"
  - "@type": Citation
    citationType: specification
    citationRole: source
    title: "MIF — Modeled Information Format, v1.0.0 spec"
    url: "https://mif-spec.dev/"
  - "@type": Citation
    citationType: specification
    citationRole: source
    title: "W3C PROV-O — The Provenance Ontology"
    url: "https://www.w3.org/TR/prov-o/"
tags:
  - architecture-spec
  - ai-ready-spec
  - knowledge-spine
  - okf
  - mif
  - worked-specimen
---

# OKF+MIF Knowledge-Spine Build Spec

This is an AI-ready architecture specification for building a **knowledge spine** that layers
**MIF** (Modeled Information Format) as the modeling, provenance, and temporal layer over **OKF**
(Google Cloud's Open Knowledge Format) as the accessible, git-distributable packaging layer. It is
a **worked specimen** in the `architecture-spec` genre the `ai-spec` channel targets: every design
claim below is grounded in a surviving finding, and the acceptance criteria are drawn from the goal's
completion checks. It is written in the genre it demonstrates.

## 1. Introduction and goals

The build target is the OKF+MIF layering itself: OKF supplies minimalist markdown-YAML packaging an
AI agent can read; MIF supplies the formal ontology, typed relationships, first-class provenance,
and bi-temporal tracking OKF lacks. Quality goals, in priority order: **agent-executable** (a coding
agent builds the layering from this spec), **grounded** (every claim cites a surviving finding or a
named standard), **deterministic**, and **self-demonstrating**.

## 2. Constraints

- OKF stays minimal — untyped links, a single last-modified timestamp, no formal ontology — and is
  not forked. MIF is layered *over* it through a complementary extension seam.
- MIF is the Level-3 substrate: typed entities, PROV-O-compatible provenance, bi-temporal validity.
- Fail-closed: an unresolved type or a broken citation aborts rather than degrading silently.

## 3. Context and scope (C4 system context)

```text
research findings  ─►  OKF packaging (markdown+YAML)  ─►  MIF spine (ontology · provenance · time)  ─►  agent-consumable knowledge
   (MIF substrate)        accessible distribution            typed/attributed/temporal layer
```

In scope: the layering mechanics, the complementary-fields mapping, and the extension seam. Out of
scope: re-specifying OKF or MIF.

## 4. Solution strategy

Layer, do not merge. OKF carries the human/agent-accessible packaging; MIF carries the structural
spine in fields OKF does not define, joined at a documented extension seam. The research settles the
direction: OKF is a minimalist markdown format with untyped links and a single timestamp (landscape:
*OKF — The Minimalist AI-Agent Knowledge Packaging Spec*; *OKF's Untyped Link Mechanism*), and MIF
supplies the typed-relationship, provenance, and temporal advantages OKF lacks (technical: *MIF's
First-Class Provenance Block*; *MIF's Bi-Temporal Tracking and Decay Modeling*; *MIF's Formal
Ontology and EntityReference System*).

## 5. Building-block view (C4 container view)

| Block | Provided by | Responsibility |
| --- | --- | --- |
| Packaging | OKF | Minimalist markdown-YAML, git-distributable, agent-readable |
| Ontology / typing | MIF | Formal entity types + EntityReference structured domain typing |
| Typed relationships | MIF | Structural-core predicates with strength (vs OKF prose links) |
| Provenance | MIF | First-class PROV-O-compatible attribution block |
| Temporal | MIF | Bi-temporal tracking + decay modeling (vs OKF's single timestamp) |

Each block is grounded in a surviving technical finding (*OKF+MIF Layering Mechanics: Complementary
Fields, Conflicts, and the Extension Seam*).

## 6. Runtime view

The layering joins at the extension seam: OKF fields render the accessible surface; MIF fields carry
the spine. The seam maps complementary fields and resolves the few conflicts; no OKF field is
overwritten (*OKF+MIF Layering Mechanics*). MIF's typed relationships and provenance attach to OKF
nodes without altering OKF's markdown shape.

## 7. Decisions and alternatives (Path B)

| Decision | Options | Selection rule | Verdict |
| --- | --- | --- | --- |
| Spine format | OKF+MIF layering · RDF/OWL · schema.org · SKOS · PROV-O alone | If accessibility AND typed-provenance-temporal depth are both required → layer | **OKF+MIF** |
| Packaging | OKF markdown · Frictionless Data Packages · JSON-LD | If git-distributable agent-readable packaging is the goal → OKF | **OKF** |

RDF/OWL is rejected on authoring cost (technical: *RDF/OWL: Full Semantic Rigor, Prohibitive
Authoring Cost*); schema.org and SKOS on missing provenance/typed relationships; Frictionless on
tabular-not-knowledge scope. The Semantic Web's adoption failure is the cautionary map (trajectory:
*The Semantic Web's Adoption Failure*).

## 8. Acceptance criteria (EARS)

Generated from the goal's `completion_condition.checks[]`:

- **AC-1** WHEN the spine is built, THE SYSTEM SHALL carry ≥4 active technical, ≥3 landscape, ≥3
  trajectory, and ≥3 market findings. Verify: per-dimension active-finding counts meet the floors.
- **AC-2** WHEN OKF's minimalism is asserted, THE SYSTEM SHALL ground it in ≥1 surviving finding.
  Verify: a survived/weakened finding establishes OKF's untyped-link, single-timestamp, no-ontology
  minimalism.
- **AC-3** WHEN MIF's advantage is asserted, THE SYSTEM SHALL ground typed relationships +
  first-class provenance + temporal/versioning in ≥1 surviving finding. Verify: a survived finding
  establishes each.
- **AC-4** WHEN a finding ships, THE SYSTEM SHALL validate it against the MIF findings schema.
  Verify: every active finding validates.
- **AC-5** WHEN findings are graded, THE SYSTEM SHALL run the adversarial gate exactly once per
  finding and hold citation integrity. Verify: one gate pass per finding; the citation-integrity
  gate passes.

## 9. Evidence base

The design rests on the topic's 36 active findings (31 survived, 5 weakened): 12 technical (the
layering mechanics, the MIF spine blocks, the OKF comparators), 7 landscape (prior-art comparators),
9 trajectory (adoption signals), 8 market. No design claim is ungrounded.

## 10. Risks and caveats

Reported with the falsification gate's qualifications. OKF is nascent with unproven adoption
(market, **weakened**: *OKF Nascency and Unproven Adoption as Market Risk*); the demand and pricing
signals are indicative, not settled (market, **weakened**: *AI and LLM Workflows Are Driving
Demand*; *Pricing and Business Model Signals*). MIF's typed-relationship predicate set is
corroborated but **weakened** (technical: *MIF's Typed Relationship System*).

## 11. How to reuse as template

Hold the §1–§12 taxonomy fixed and fill: the **build subject** (§1, §3), the **building blocks**
(§5), the **decision forks** (§7), the **evidence base** (§9), and the **acceptance criteria** (§8,
one EARS statement per goal check). A document filling these slots is one the `ai-spec` channel
could have emitted — which is the test that the channel, the genre, and the template are one thing.

## 12. Sources

- [OKF — Open Knowledge Format (Google Cloud)](https://github.com/google/open-knowledge-format)
- [MIF — Modeled Information Format](https://mif-spec.dev/)
- [W3C PROV-O — The Provenance Ontology](https://www.w3.org/TR/prov-o/)
- [arc42 — architecture documentation template](https://arc42.org/overview)
