---
slug: reports/example-okf-mif-knowledge-spine/example-okf-mif-knowledge-spine-feature-build-spec
version: 1
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:report:harness/example-okf-mif-knowledge-spine:feature-build-spec
conceptType: semantic
namespace: harness/example-okf-mif-knowledge-spine
title: "OKF+MIF Extension Seam — feature spec"
created: "2026-06-29T00:00:00Z"
genre: feature-spec
audience: implementer
status: proposed
mif:
  conformanceLevel: 1
evidence_base: "Drawn from the example-okf-mif-knowledge-spine technical dimension (OKF+MIF layering mechanics; OKF v0.1 core data model; MIF formal ontology + EntityReference) — all survived"
tags:
  - feature-spec
  - ai-ready-spec
  - extension-seam
  - okf
  - mif
  - worked-specimen
---

# OKF+MIF Extension Seam — Feature Spec

A worked specimen in the `feature-spec` genre: **one capability** of the OKF+MIF build — the
extension seam that joins MIF's typed spine to OKF packages — authored for a coding agent. It is a
worked example in the genre, grounded in this topic's surviving technical findings.

## Summary

A documented seam where MIF fields (formal ontology, EntityReferences, typed relationships) attach
to an OKF package's nodes without altering OKF's minimalist markdown-YAML shape.

## Motivation / context

OKF's v0.1 core data model is deliberately minimal (*OKF v0.1 Core Data Model*); MIF adds the formal
ontology and EntityReference structured typing OKF lacks (*MIF's Formal Ontology and EntityReference
System*). The seam is the join point that lets the two layer cleanly with complementary fields and
the few conflicts resolved (*OKF+MIF Layering Mechanics*).

## Behaviour

The seam reads an OKF package, attaches MIF typed fields under a namespaced extension key, and emits
a package that an OKF-only consumer still parses and a MIF-aware consumer reads as a typed node.

## Acceptance criteria (EARS)

- **AC-1** WHEN MIF fields are attached, THE SYSTEM SHALL preserve every OKF field unchanged.
  Verify: an OKF-only parser round-trips the package.
- **AC-2** WHEN typing is applied, THE SYSTEM SHALL resolve each node's entity type against a bound
  ontology. Verify: `ontology-review` reports the node typed (0 untyped).
- **AC-3** WHEN the MIF advantage is claimed, THE SYSTEM SHALL ground typed relationships + ontology
  in ≥1 surviving finding. Verify: `thesis_mif_advantage` holds.

## Out of scope

Re-specifying OKF or MIF; the provenance and temporal layers (separate features).

## Sources

- [OKF — Open Knowledge Format (Google Cloud)](https://github.com/google/open-knowledge-format)
- [MIF — Modeled Information Format](https://mif-spec.dev/)
