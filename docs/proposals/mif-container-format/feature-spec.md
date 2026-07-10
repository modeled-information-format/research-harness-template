---
id: feature-mif-container-m1
type: semantic
created: '2026-07-10T00:00:00Z'
modified: '2026-07-10T00:00:00Z'
namespace: spec/feature/mif-container-format
title: 'MIF Container M1: manifest, digest, and export/import (shell/skill path)'
tags:
  - feature-spec
  - container
  - export-import
  - ontology
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-10T00:00:00Z'
  ttl: P6M
  recordedAt: '2026-07-10T00:00:00Z'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  trustLevel: high_confidence
relationships:
  - type: derived-from
    target: /docs/proposals/mif-container-format/ai-architecture-doc.md
  - type: depends-on
    target: /docs/adr/0017-mif-container-instance-scoped-export-import-format.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: MIF Container M1
  entity_type: feature-specification
---

# MIF Container M1: manifest, digest, and export/import (shell/skill path)

## Overview

ADR-0017 decided to build a Data-Package-style container manifest
(`mif-package.json`, validated against a new
`schemas/mif-container.schema.json`) for lossless topic export/import
between `research-harness-template` instances (research-harness-template#194),
scoped to this repo alone and independent of the org-wide MIF Container
Profile proposal (`modeled-information-format/MIF#77`). This feature spec
scopes **M1**: the full shell/skill-path reference implementation of the
Stories under Epic #275 -- #308, #312, #315, #318, #324, #328, and #331 --
manifest schema, digest engine, export-scope resolver, import gate,
origin/reconciliation tagging, and the `/export`/`/import` command pair,
verified against a real topic. **M2** (Story #334, evaluating migration of
the manifest
build/verify logic into `mif-rh-cli` subcommands) is explicitly out of
scope for M1 and requires a demonstrated performance bottleneck to trigger,
per ADR-0017's AD-7.

## Acceptance Criteria

1. WHEN a container is built from any finding set, THE SYSTEM SHALL compute
   its manifest-level digest over the sorted, canonicalized list of
   per-resource digests.
2. WHEN two containers are independently built from identical inputs, THE
   SYSTEM SHALL produce a byte-identical manifest digest for both
   (determinism).
3. WHEN a container is imported, THE SYSTEM SHALL verify every contained
   resource's digest against its manifest entry BEFORE writing it to
   `reports/<topic>/`, and SHALL reject the ENTIRE import on any single
   mismatch -- never a partial, resource-by-resource opportunistic check.
4. WHEN a container declares an ontology binding (pack id + version) for a
   contained finding, THE SYSTEM SHALL reject import if the destination
   corpus's cataloged version is not identical or an explicitly-declared
   compatible successor -- never a silent best-effort re-typing.
5. WHEN a container is imported into a corpus that already holds some of its
   findings (matched by stable `@id`), THE SYSTEM SHALL upsert-by-`@id` and
   SHALL NOT create a duplicate finding file.
6. WHEN a subset/incremental container contains a `relationships[]` or
   `ontology-map.json` edge whose target is excluded from the bundle, THE
   SYSTEM SHALL emit an explicit `boundaryReferences[]` entry naming the
   excluded target rather than dropping or silently rewriting the edge.
7. IF a subset export's excluded reference target IS reachable within the
   requested export scope via dependency closure, THEN THE SYSTEM SHALL
   include it directly and SHALL NOT mark it as a boundary reference.
8. WHEN a container is built for a topic bound to N domain ontology packs,
   THE SYSTEM SHALL remain structurally readable (schema-valid,
   digest-verifiable) by a container reader that has loaded ONLY the base
   `mif-generic`/`mif-base` profile, with every domain-specific field
   appearing as an optional, additively-typed extension.
9. IF the container tool encounters a manifest whose declared `profile`
   version it does not recognize, THEN THE SYSTEM SHALL fail closed with a
   named "unrecognized container profile" error rather than
   attempting best-effort parsing.
10. WHEN a user runs `/export <topic> [--subset <selector>]`, THE SYSTEM
    SHALL produce a `mif-package.json` manifest plus its named resource
    files under a single output directory, and SHALL NOT modify
    `reports/<topic>/`.
11. WHEN a user runs `/import <path> [--dry-run]`, THE SYSTEM SHALL execute
    the full fail-closed import gate in order (schema validation, digest
    verification, ontology-binding compatibility, idempotent upsert-by-`@id`,
    deterministic rebuild of the graph/README/concordance), and IF
    `--dry-run` is set, THE SYSTEM SHALL report the outcome without writing
    to `reports/`.
12. WHEN an export or import run is already in progress against a target
    topic, THE SYSTEM SHALL fail closed on a second concurrent invocation
    with a clear "another export/import is in progress" error, rather than
    racing to write the same manifest or `reports/<topic>/` files.

## Design

- **Manifest schema** (`schemas/mif-container.schema.json`, Story #308) --
  `resources[]` entries with a `mifType` discriminator, path, ontology
  type, and mandatory digest (#309); ontology-binding declarations naming
  pack id and version (#310); an export-scope descriptor (`full` |
  `incremental` | `subset`) and `sourceInstance` tag (#311).
- **Digest engine** (Story #312) -- SHA-256 over each resource's canonical
  bytes plus a manifest-level digest over the sorted resource-digest list
  (ADR-0017 AD-2).
- **Export-scope resolver** (Story #315) -- walks `relationships[]` and
  `ontology-map.json` edges; closure-first inclusion, marker-fallback for
  genuinely out-of-scope targets (ADR-0017 AD-4).
- **Import gate** (Story #318) -- strict, ordered, fail-closed sequence:
  schema validation -> digest verification -> ontology-binding
  compatibility -> idempotent upsert-by-`@id` -> trigger the existing
  deterministic rebuilders (`scripts/build-graph.sh`,
  `scripts/build-topic-readme.sh`, concordance rebuild).
- **Origin/reconciliation tagging** (Story #324) -- `sourceInstance` field
  per container, separate from each finding's W3C-PROV provenance;
  per-field-class reconciliation policy at import (ADR-0017 AD-6); any
  candidate concordance `sameAs` merge surfaces as a proposal requiring
  confirmation, never an automatic write.
- **Command pair** (Story #328) -- `/export`/`/import` commands delegating
  to new `scripts/mif-container-export.sh` / `-import.sh`, matching how
  `/falsify` delegates to `falsification-analyst` and the existing
  `search`/`discover`/`lab`/`graph`/`topics` skill pattern. Reference
  implementation uses only `jq`/`ajv-cli` (already required by
  `scripts/verify.sh`) -- no new dependency.
- **NFR verification** (Story #331) -- a round-trip eval (export -> import
  into a fresh instance -> export again) proving the manifest digest is
  byte-identical across the cycle, run against a real topic, not only a
  synthetic fixture.
- **Component view:** see the C4 Level 3 diagram and full building-block
  rationale in `ai-architecture-doc.md` in this directory.

## Edge Cases

- **Digest mismatch on any single resource**: the entire import is
  rejected -- no partial write, matching AC 3. The error names the
  mismatched resource path, not just "import failed."
- **Ontology pack/version not cataloged on the destination instance**: import
  fails closed the same way `resolve-ontology.sh`'s existing `extends`
  resolution already fails closed today (ADR-0011) -- this is existing
  behavior to invoke, not new behavior to build.
- **Subset export reference excluded at either `relationships[]` or
  `ontology-map.json` level**: both edge sources must be walked before
  finalizing a subset manifest; a boundary marker omitted at either level
  reproduces the exact silent-drop failure ADR-0017 AD-4 exists to prevent.
- **Concurrent export or import against the same topic**: the second
  invocation fails closed on a lock file (e.g.
  `reports/<topic>/.container.lock`) with a clear "another export/import is
  in progress" error, mirroring the ontology engine's own lock-file gap
  fix (`docs/proposals/ontology-engine/feature-spec.md`) and this repo's
  standing convention of never running write-path scripts concurrently.
- **Zero-finding topic exported**: produces a manifest with an empty
  `resources[]` array and a defined (not null) manifest-level digest over
  the empty set -- not an error.
- **Manifest `profile` version unrecognized by the importing instance**:
  fails closed per AC 9, naming the unrecognized version, never attempting
  best-effort parsing of an unknown shape.
- **Import target already holds a finding with the same `@id`**: upserts in
  place per AC 5; the pre-existing file's content is replaced only if the
  incoming digest differs, and the operation is safely re-runnable.
