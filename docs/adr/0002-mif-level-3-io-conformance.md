---
title: "MIF Level-3 I/O conformance as the harness substrate"
description: "Bind every artifact crossing the project boundary to MIF Level-3, with harness-local lifecycle state in a non-forking extension."
type: adr
category: data
tags: [mif, conformance, schema, provenance, knowledge-graph]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [MIF, JSON Schema, W3C-PROV, ajv]
audience: [developers, architects]
related: [0004-single-adversarial-falsification-gate.md, 0007-report-channel-canonical-blog-mif-exempt.md]
---

# ADR-0002: MIF Level-3 I/O conformance as the harness substrate

## Status

Accepted

## Context

### Background and Problem Statement

The harness needs one authoritative interchange format so that every artifact
crossing the project boundary — findings, the knowledge graph, citations,
provenance, reports, ingested sources — is machine-validated against a single
contract (`docs/explanation/mif-io-conformance.md`,
`docs/explanation/architecture.md` §6c). The question is which format binds these
artifacts, and at what conformance level.

### Current Limitations

The prior system suffered schema drift: findings, the knowledge graph, citations,
and provenance each used ad-hoc shapes that had to be reconciled by hand, and the
graph was derived from tags rather than being first-class.

## Decision Drivers

### Primary Decision Drivers

1. One machine-validated contract for findings, graph, citations, and provenance.
2. Reports and ingested sources, not just findings, must be held to the contract.

### Secondary Decision Drivers

1. The knowledge graph should be first-class, not derived from tags.
2. Harness lifecycle state (falsification, quarantine, lineage) must be carried
   without forking the base format.

## Considered Options

### Option 1: Bespoke per-artifact JSON schemas

**Description:** Define a tailored JSON schema for each artifact type independently, as the prior system did.

- **Advantages:** Maximally tailored to each artifact's exact needs.
- **Disadvantages:** Reproduces the schema drift this template exists to eliminate, and the graph stays tag-derived.
- **Risk Assessment:** technical medium; schedule low; ecosystem high.

### Option 2: MIF Level-1 (identity only)

**Description:** Adopt MIF but require only Level-1 frontmatter concept identity, without enforcing provenance or a citation closure.

- **Advantages:** Cheap — only frontmatter identity is required of each artifact.
- **Disadvantages:** Does not bind provenance or a citation closure, so findings could ship without verifiable evidence.
- **Risk Assessment:** technical low; schedule low; ecosystem medium.

### Option 3: MIF Level-3 with a harness extension

**Description:** Require MIF Level-3 (provenance + citations + entities + extensions) validated against the vendored `schemas/mif/` closure, with harness-only patterns under `extensions.harness`.

- **Advantages:** Every finding is a MIF memory unit validated against the vendored closure; the graph is MIF entities and typed relationships; citations are MIF Citation objects; provenance is the W3C-PROV block; harness-local concerns close the gap locally rather than forking MIF.
- **Disadvantages:** The vendored MIF closure must be tracked and updated.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 3: MIF Level-3 with a harness extension.** `harness.config.json`
sets `mifConformanceLevel: 3`. A finding is an individual MIF memory unit
validated against the vendored `schemas/mif/` closure; reports
(`reports/<topic>/<slug>.md`) are MIF L3 held to the same bar as a finding; and
ingested sources are wrapped as validated MIF source-envelopes.
`schemas/findings.schema.json` `$ref`s the real vendored MIF schema and only
adds harness-local concerns under `extensions.harness`, never overriding MIF
(§8b).

## Consequences

### Positive

1. Schema drift collapses into one machine-validated contract.
2. The knowledge graph becomes first-class instead of tag-derived.

### Negative

1. Vendoring the MIF closure adds an upstream-tracking obligation (originally
   recorded in `schemas/mif/VENDOR.lock`; that seed-time provenance file was
   retired by #223, superseded by on-demand vendoring per ADR-0012).

### Neutral

1. The L3 floor binds the whole I/O surface, not findings alone, which raises the
   bar uniformly for reports and ingested sources.

## Decision Outcome

A single authoritative format makes findings, the graph, citations, and
provenance one validated contract, with harness lifecycle state added locally
rather than by forking MIF. The upstream-tracking cost is now contained by
on-demand vendoring from the canonical registry (ADR-0012).

## Related Decisions

- [ADR-0004: Single adversarial falsification gate](0004-single-adversarial-falsification-gate.md)
- [ADR-0007: Canonical report channel; blog MIF-exempt](0007-report-channel-canonical-blog-mif-exempt.md)

## Links

- `docs/explanation/mif-io-conformance.md`
- `schemas/findings.schema.json`
- `harness.config.json`

## More Information

- **Date:** 2026-06-23
- **Source:** `docs/explanation/mif-io-conformance.md`, `schemas/findings.schema.json`, `harness.config.json`

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Conformance level declared | `harness.config.json` (`mifConformanceLevel: 3`) | compliant |
| Findings schema refs vendored MIF | `schemas/findings.schema.json` | compliant |
| Vendored MIF closure present | `schemas/mif/`, `schemas/mif/VENDOR.lock` | compliant |

**Summary:** The L3 conformance level is declared, the findings schema references the vendored MIF closure, and the closure is vendored under `schemas/mif/`.

**Action Required:** None

### 2026-06-30

**Status:** Compliant

| Finding | Files | Assessment |
| --- | --- | --- |
| Conformance level declared | `harness.config.json` (`mifConformanceLevel: 3`) | compliant |
| Findings schema refs vendored MIF | `schemas/findings.schema.json` | compliant |
| Vendored MIF closure present | `schemas/mif/` | compliant |

**Summary:** The seed-time `schemas/mif/VENDOR.lock` provenance file was retired (#223): on-demand vendoring from the canonical registry (ADR-0012, pinned in `ontologies.lock.json` via `scripts/check-ontology-lock.sh`) supersedes it. The vendored MIF closure remains under `schemas/mif/`; `gate_m12` still validates it and every registry ontology against the contract.

**Action Required:** None
