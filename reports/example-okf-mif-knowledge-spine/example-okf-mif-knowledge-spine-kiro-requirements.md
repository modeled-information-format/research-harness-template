---
slug: reports/example-okf-mif-knowledge-spine/example-okf-mif-knowledge-spine-kiro-requirements
version: 1
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-okf-mif-knowledge-spine:kiro-requirements
conceptType: semantic
namespace: harness/example-okf-mif-knowledge-spine
title: "MIF Provenance Layer over OKF — Kiro Requirements"
created: "2026-07-12T16:11:16Z"
modified: '2026-07-12T16:11:39.923Z'
genre: kiro-requirements
audience: implementer
status: proposed
mif:
  conformanceLevel: 1
evidence_base: "Drawn from the example-okf-mif-knowledge-spine technical dimension (MIF's first-class provenance block; OKF's informal log.md/citations provenance; the OKF+MIF extension seam) — all survived"
temporal:
  "@type": TemporalMetadata
  validFrom: "2026-07-12T16:11:16Z"
  ttl: P6M
  recordedAt: "2026-07-12T16:11:16Z"
provenance:
  '@type': Provenance
  sourceType: system_generated
  confidence: 0.9
  trustLevel: user_stated
  wasDerivedFrom:
    '@id': urn:mif:report:harness/example-okf-mif-knowledge-spine:kiro-build-spec
    '@type': prov:Entity
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ae91b6b6-8d5c-4bea-963d-9e4b7907cf09
    '@type': prov:Activity
  agentVersion: 2.1.207
tags:
  - kiro-requirements
  - ai-ready-spec
  - provenance
  - okf
  - mif
  - worked-specimen
---

# MIF Provenance Layer over OKF — Kiro Requirements

A worked specimen in the `kiro-requirements` genre: the requirements phase of one **feature** of
the OKF+MIF build — adding MIF's first-class provenance to OKF packages — grounded in this topic's
surviving technical findings. Split out from a single combined `kiro-spec` document
(research-harness-template#409/#432 retired the bundled `kiro-spec` pack in favor of three
independently selectable `mif-docs-plugin` genres: `kiro-requirements`, `kiro-design`,
`kiro-tasks`; see the sibling `-kiro-design.md`/`-kiro-tasks.md` files for the rest of this
feature's spec).

## Requirements

The feature replaces OKF's informal, prose-only provenance (`log.md` notes and inline citations —
*OKF's Informal Provenance Model*) with MIF's first-class, PROV-O-compatible attribution block
(*MIF's First-Class Provenance Block*), attached at the OKF+MIF extension seam (*OKF+MIF Layering
Mechanics*) without altering OKF's markdown shape.

**Acceptance criteria (EARS)** — from the goal's completion checks:

- **AC-1** WHEN a knowledge node is packaged, THE SYSTEM SHALL attach a MIF provenance block
  (source, derivation, attribution, time) alongside the OKF fields. Verify: the node validates
  against the MIF findings schema (`finding_valid`).
- **AC-2** WHEN provenance is asserted, THE SYSTEM SHALL ground the typed-provenance advantage in
  ≥1 surviving finding. Verify: `thesis_mif_advantage` holds.
- **AC-3** WHEN the layer is applied, THE SYSTEM SHALL leave OKF's existing fields unchanged.
  Verify: an OKF-only reader still parses the package.

## Sources

- [MIF — Modeled Information Format](https://mif-spec.dev/)
- [OKF — Open Knowledge Format (Google Cloud)](https://github.com/google/open-knowledge-format)
- [W3C PROV-O](https://www.w3.org/TR/prov-o/)
