---
title: "MIF Container: an instance-scoped export/import manifest format"
description: "Build a Data-Package-style container manifest (schemas/mif-container.schema.json) for lossless topic export/import between research-harness-template instances, correcting Data Package's opt-in integrity and breaking-migration weaknesses; independent of and not blocked by the org-wide MIF Container Profile proposed in MIF#77."
type: adr
category: architecture
tags: [container, export-import, portability, integrity, ontology, digest]
status: accepted
created: 2026-07-10
updated: 2026-07-10
author: zircote
project: research-harness-template
technologies: [JSON Schema, SHA-256, jq, ajv-cli]
audience: [developers, architects]
related: [0011-fail-closed-ontology-completeness-gate.md, 0012-on-demand-ontology-vendoring.md, 0014-compiled-ontology-engine-cli-and-mcp.md, 0016-engine-only-classification.md]
---

# ADR-0017: MIF Container: an instance-scoped export/import manifest format

## Status

accepted

## Context

### Background and Problem Statement

The harness has no way to move a topic -- its findings, citations, ontology
typing, concordance/relationship edges, verification verdicts, tags, and
provenance/session lineage -- between two corpus instances (two clones, two
orgs, a fork) without hand-copying files and hoping nothing referential
breaks (research-harness-template#194). The `mif-corpus-import-export`
research session (60 gated findings, 0 falsified, two augment passes) was
commissioned to close this gap and converged on the OKF/Frictionless Data
Package family (`datapackage.json`, Table Schema, Tabular/Fiscal Data
Package) as the closest real, multi-portal-adopted prior art -- closer than
git bundle, OCI artifacts, or npm's package-lock, though each contributes
individual mechanisms this design borrows. Full research record:
`docs/proposals/mif-container-format/ai-architecture-doc.md`.

Two corroborated weaknesses in Data Package itself must not be copied: its
integrity model is opt-in (an MD5-default, per-resource `hash` field checked
only if the reader opts in; relational `foreignKeys` checked only with
`relations=True` at read time), and its v1-to-v2 migration broke most
reference tooling for months with no compatibility gate.

**Relationship to research-harness-template#194 and MIF#77 -- independent,
not conflicting.** An earlier draft of this proposal (issue #275's original
body) argued this container needed to reconcile with, or wait on, the
MIF-org-wide "MIF Container Profile" proposed in
`modeled-information-format/MIF#77` (a `records[]`/`kind` envelope for
MNEMOS/Charon and other MIF ecosystem tools) before any implementation could
start. That framing was scope creep introduced by the authoring agent, not
an actual constraint: this ADR's container is a
`research-harness-template`-local schema (`schemas/mif-container.schema.json`)
serving one narrow use case -- moving a research-harness *topic* (findings,
documents, corpus metadata) between two harness clones -- independent of
whatever the org-wide MIF Container Profile eventually becomes. Should
MIF#77 land as an accepted MIF Container Profile in the future, adopting it
as this schema's basis is a candidate follow-up ADR at that time, not a
blocker on building this one now.

### Current Limitations

- No supported export path exists today; `scripts/import-corpus.sh` is a
  deprecated, first-clone-only adoption path, not a topic-level
  instance-to-instance flow (#194).
- Ontology dependency is a silent-corruption risk: a target instance lacking
  a finding's bound ontology pack/version has no fail-closed gate today.
- `urn:mif:` id collisions on import have no defined remap/reconciliation
  behavior.
- No round-trip proof exists that an export-then-import-then-export cycle is
  lossless.

## Decision Drivers

### Primary Decision Drivers

1. Enable lossless topic export/import between two MIF corpus instances (the
   commissioning goal, #194).
2. Make integrity and ontology-version-compatibility checks mandatory and
   fail-closed at import, correcting Data Package's two named weaknesses.
3. Support full-topic AND filtered-subset export, with an explicit
   boundary-marker mechanism for any excluded cross-reference -- never a
   silent drop.

### Secondary Decision Drivers

1. Remain extensible to any current or future domain ontology pack without a
   breaking change to the base container reader, reusing the harness's
   existing ontology-pack `extends` mechanism (ADR-0012) rather than
   inventing a second one.
2. No new dependency: `jq`/`ajv-cli`, already required by `scripts/verify.sh`,
   must be sufficient for the reference implementation.

## Considered Options

### Option 1: OKF/Frictionless Data Package family, with corrections (chosen)

**Description:** Model the manifest on `datapackage.json`'s `resources[]`
array (extended with a `mifType` discriminator), Table Schema, and Fiscal
Data Package's additive domain-specialization pattern, but replace Data
Package's opt-in MD5 hash with a mandatory SHA-256 per-resource digest plus
a manifest-level digest, and add a fail-closed ontology-binding
compatibility gate Data Package has no equivalent of.

- **Advantages:** closest real, multi-portal-adopted prior art;
  profile-composition pattern (Tabular Data Package's three MUST
  constraints, Fiscal Data Package's additive fields) maps directly onto the
  harness's existing ontology-pack `extends` layering; no new external
  dependency.
- **Disadvantages:** the corrections (mandatory digest, ontology gate) are
  harness-specific additions with no upstream Data Package precedent to
  lean on for their own validation.
- **Risk Assessment:** technical low (schema + jq/ajv, no new runtime);
  schedule low (M1 scoped to shell/skill path); ecosystem low (no new
  dependency).

### Option 2: git bundle

**Description:** Package a topic's git history slice as a portable git
bundle.

- **Advantages:** full-fidelity, proven portable transfer mechanism; no
  manifest format to design.
- **Disadvantages:** git history granularity does not map onto a "topic"
  (findings span commits, live alongside unrelated topics in the same
  tree); no native ontology-binding or subset-boundary semantics; a git
  bundle is opaque to non-git tooling that might want to validate a
  container without cloning.
- **Risk Assessment:** technical medium (mapping topic boundaries onto
  commit ranges is itself unsolved); schedule medium; ecosystem low.

### Option 3: OCI artifacts

**Description:** Package a topic as an OCI artifact, using OCI's
content-addressable manifest digest and referrers API for cross-reference
handling.

- **Advantages:** self-verifying, content-addressed manifest digest is
  exactly the integrity model this ADR adopts; referrers' dangling-subject
  tolerance is a direct precedent for the boundary-marker mechanism (AD-4
  below).
- **Disadvantages:** requires an OCI registry (or registry-shaped tooling)
  as a transport, a real dependency the harness does not otherwise have;
  the harness needs a mandatory `jq`/`ajv-cli`-only reference
  implementation.
- **Risk Assessment:** technical medium (registry dependency); schedule
  medium; ecosystem medium (new tooling class).

### Option 4: npm package-lock model

**Description:** Model the manifest on `package-lock.json`'s
dependency-tree-with-integrity-hash shape.

- **Advantages:** SRI-enforced, fail-closed integrity check at install time
  is the exact pattern this ADR's digest engine copies.
- **Disadvantages:** package-lock's shape is dependency-resolution-oriented
  (nested version ranges), not export/subset-oriented; no analog for
  ontology-binding compatibility or origin/reconciliation tagging.
- **Risk Assessment:** technical low; schedule low; ecosystem low -- but a
  poor structural fit, contributing only the integrity-check pattern, not
  the overall shape.

## Decision

Option 1: adopt a Data-Package-style manifest (`mif-package.json`, one per
exported unit, validated against a new `schemas/mif-container.schema.json`),
corrected on the two axes the research corroborated as genuine Data Package
weaknesses, and reusing the harness's own `extends` mechanism for
ontology-profile layering rather than inventing a second composition
system. The realized design is recorded as seven accepted sub-decisions
(full rationale and citations:
`docs/proposals/mif-container-format/ai-architecture-doc.md`):

- **AD-1 (packaging):** a container is a manifest plus a directory of the
  resource files it names; an archived form (tar/zip) is an optional
  convenience, not a second format.
- **AD-2 (integrity):** every resource carries a mandatory SHA-256 digest,
  verified by default at import with no opt-in flag; the manifest itself
  carries a top-level digest over all resource digests.
- **AD-3 (identifiers):** the container mints no new identifiers -- every
  packaged finding keeps its existing `urn:mif:concept:<namespace>:<slug>`
  id unchanged; only the export act itself gets a manifest-level
  identifier.
- **AD-4 (subset boundaries):** closure-first, marker-fallback -- a subset
  export first attempts dependency-closure inclusion for any
  referenced-but-out-of-scope target; only when closure is not requested or
  not possible does it emit an explicit `boundaryReferences[]` marker.
  Silent dropping is never permitted.
- **AD-5 (extensibility):** a container's ontology-profile layering reuses
  the harness's existing `extends` chain (ADR-0012) rather than a parallel
  composition system.
- **AD-6 (origin tagging):** every container carries a `sourceInstance`
  field, distinct from each finding's own W3C-PROV provenance; import
  applies a named, per-field-class reconciliation policy (ontology
  typing/tags MAY reconcile; verification verdicts and session lineage stay
  origin-scoped).
- **AD-7 (implementation surface, M1 vs. M2):** M1 builds the reference
  implementation as a Harness-services shell/skill
  (`scripts/mif-container-export.sh`/`-import.sh`, wrapped by an
  `/export`/`/import` command pair), matching the existing
  `search`/`discover`/`lab`/`graph`/`topics` pattern -- not as new
  `mif-rh-cli` subcommands. Nothing in the measured research indicates an
  export/import performance problem analogous to what justified the
  compiled ontology engine (ADR-0014); migrating the manifest-build/verify
  logic into `mif-rh-cli` is a natural M2 if a future scale or
  bulk-migration use case demonstrates a real bottleneck, not a redesign.

The M1 acceptance criteria and the Stories/Tasks these decisions scope are
recorded in `feature-spec.md` in the same directory as the architecture
doc.

## Consequences

### Positive

1. One mandatory, fail-closed integrity check and one fail-closed
   ontology-compatibility gate at import, correcting the two named Data
   Package weaknesses before they can recur here.
2. No new external dependency -- `jq`/`ajv-cli` already required by
   `scripts/verify.sh` are sufficient.
3. Subset export gets an explicit, never-silent boundary-marker contract,
   closing the "silently dropped or rewritten cross-reference" failure
   class.
4. Reuses the harness's proven `extends` ontology-layering mechanism
   instead of adding a second one.

### Negative

1. The manifest schema, digest engine, export-scope resolver, import gate,
   origin-tagging policy, `/export`/`/import` command pair, and NFR
   verification suite are seven new pieces of harness-owned surface area to
   build and maintain (Stories #308/#312/#315/#318/#324/#328/#331).
2. The manifest-level identifier strategy for the export act itself
   (UUIDv5 vs. timestamp+token) is explicitly deferred to the M1 implementer
   (AD-3's open item) -- a small design gap carried forward, not resolved
   here.
3. `MIF#77`'s proposed envelope (`records[]` with a `kind` discriminator)
   is a structurally different shape from this schema's `resources[]` with
   a `mifType` discriminator -- if a future decision adopts `MIF#77` as this
   schema's basis, that is a breaking rewrite of the manifest shape, not an
   additive migration, and should be budgeted as such rather than assumed
   cheap.

### Neutral

1. An archived (tar/zip) packaging form remains optional; the reference
   implementation only needs to validate the loose-directory form.
2. Whether a future MIF-org-wide Container Profile (`MIF#77`) is ever
   adopted as this schema's basis is an open follow-up question this ADR
   takes no position on -- not blocking on it now, per the Context section
   above, is the only claim this ADR makes.

## Decision Outcome

The harness gains a fail-closed, extensible, dependency-free container
format for lossless topic portability, built entirely on mechanisms the
repo already trusts (the ontology `extends` chain, SHA-256 digests, the
existing skill/command pattern) rather than adopting Data Package wholesale
or waiting on an org-wide spec this repo's own need does not depend on.

## Related Decisions

- ADR-0011: the fail-closed ontology-completeness gate this design's
  import-time ontology-binding check extends to a second surface.
- ADR-0012: the on-demand ontology vendoring and `extends` chain AD-5
  reuses directly.
- ADR-0014: the compiled ontology engine whose performance driver AD-7
  explicitly finds absent here, justifying the shell/skill choice for M1.
- ADR-0016: the engine-only classification cutover -- the precedent AD-7
  weighs against for M1's implementation surface.

## More Information

- **Date:** 2026-07-10
- **Source:** `docs/proposals/mif-container-format/ai-architecture-doc.md`
  (full research record, citations, C4 component diagram, NFRs);
  `reports/mif-corpus-import-export/` (60 gated findings, 0 falsified,
  source research session, private instance not vendored into this repo).

## Audit

### 2026-07-10

**Status:** Pending

| Finding | Files | Assessment |
| --- | --- | --- |
| ADR authored per research-harness-template#306, records the MIF#77 independence decision | `docs/adr/0017-mif-container-instance-scoped-export-import-format.md` | compliant |
| Companion feature-spec.md scoping M1 authored alongside | `docs/proposals/mif-container-format/feature-spec.md` | compliant |
| Manifest schema, digest engine, export resolver, import gate, origin tagging, command pair, NFR verification not yet built | Stories #308/#312/#315/#318/#324/#328/#331 | pending |

**Summary:** ADR and feature-spec authored; implementation Stories remain
open, tracked under Epic #275.

**Action Required:** None (implementation tracked separately).
