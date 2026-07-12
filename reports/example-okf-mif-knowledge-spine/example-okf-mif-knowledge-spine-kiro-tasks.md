---
slug: reports/example-okf-mif-knowledge-spine/example-okf-mif-knowledge-spine-kiro-tasks
version: 1
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-okf-mif-knowledge-spine:kiro-tasks
conceptType: semantic
namespace: harness/example-okf-mif-knowledge-spine
title: "MIF Provenance Layer over OKF — Kiro Tasks"
created: "2026-07-12T16:11:16Z"
modified: '2026-07-12T16:12:04.625Z'
genre: kiro-tasks
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
  - kiro-tasks
  - ai-ready-spec
  - provenance
  - okf
  - mif
  - worked-specimen
---

# MIF Provenance Layer over OKF — Kiro Tasks

A worked specimen in the `kiro-tasks` genre: the task breakdown for one **feature** of the OKF+MIF
build — adding MIF's first-class provenance to OKF packages — grounded in this topic's surviving
technical findings. Split out from a single combined `kiro-spec` document
(research-harness-template#409/#432 retired the bundled `kiro-spec` pack in favor of three
independently selectable `mif-docs-plugin` genres: `kiro-requirements`, `kiro-design`,
`kiro-tasks`; see the sibling `-kiro-requirements.md`/`-kiro-design.md` files for the rest of this
feature's spec).

## Tasks

1. Map OKF `log.md` + citation conventions to the MIF `provenance` fields (grounds AC-1).
2. Implement the seam writer: attach the provenance block, never mutate OKF fields (grounds AC-3).
3. Validate each packaged node against the MIF findings schema (grounds AC-1).
4. Add a round-trip check: an OKF-only reader parses the package unchanged (grounds AC-3).

## Sources

- [MIF — Modeled Information Format](https://mif-spec.dev/)
- [OKF — Open Knowledge Format (Google Cloud)](https://github.com/google/open-knowledge-format)
- [W3C PROV-O](https://www.w3.org/TR/prov-o/)
