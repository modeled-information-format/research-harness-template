---
slug: reports/example-okf-mif-knowledge-spine/example-okf-mif-knowledge-spine-kiro-build-spec
version: 1
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-okf-mif-knowledge-spine:kiro-build-spec
conceptType: semantic
namespace: harness/example-okf-mif-knowledge-spine
title: "MIF Provenance Layer over OKF — Kiro spec (requirements → design → tasks)"
created: "2026-06-29T00:00:00Z"
genre: kiro-spec
audience: implementer
status: proposed
mif:
  conformanceLevel: 1
evidence_base: "Drawn from the example-okf-mif-knowledge-spine technical dimension (MIF's first-class provenance block; OKF's informal log.md/citations provenance; the OKF+MIF extension seam) — all survived"
tags:
  - kiro-spec
  - ai-ready-spec
  - provenance
  - okf
  - mif
  - worked-specimen
---

# MIF Provenance Layer over OKF — Kiro Spec

A worked specimen in the `kiro-spec` genre: one **feature** of the OKF+MIF build — adding MIF's
first-class provenance to OKF packages — decomposed as requirements → design → tasks for a coding
agent. It is a worked example in the genre, grounded in this topic's surviving technical findings.

## 1. Requirements

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

## 2. Design

The MIF provenance block is a sibling object at the extension seam: OKF's `log.md`/citation prose
maps to MIF `provenance` (`sourceType`, `wasDerivedFrom`, `wasAttributedTo`, `generation_time`),
PROV-O-compatible (*MIF's First-Class Provenance Block*). The seam writes MIF fields only; no OKF
field is overwritten (*OKF+MIF Layering Mechanics*). Every design claim above carries its grounding
finding.

## 3. Tasks

1. Map OKF `log.md` + citation conventions to the MIF `provenance` fields (grounds AC-1).
2. Implement the seam writer: attach the provenance block, never mutate OKF fields (grounds AC-3).
3. Validate each packaged node against the MIF findings schema (grounds AC-1).
4. Add a round-trip check: an OKF-only reader parses the package unchanged (grounds AC-3).

## Sources

- [MIF — Modeled Information Format](https://mif-spec.dev/)
- [OKF — Open Knowledge Format (Google Cloud)](https://github.com/google/open-knowledge-format)
- [W3C PROV-O](https://www.w3.org/TR/prov-o/)
