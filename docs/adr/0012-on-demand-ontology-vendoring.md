---
title: "On-demand ontology vendoring from a canonical registry"
description: "Fetch domain ontologies on demand from the canonical ontologies registry, verified fail-closed against a pinned sha256 index, instead of bundling every ontology in every clone; keep base layers committed; offer to author-and-contribute a new ontology when none exists."
type: adr
category: architecture
tags: [ontology, vendoring, supply-chain, fail-closed, registry, on-demand]
status: accepted
created: 2026-06-30
updated: 2026-06-30
author: zircote
project: research-harness-template
technologies: [Bash, jq, yq, sha256]
audience: [developers, architects]
related: [0008-attested-fail-closed-supply-chain.md, 0011-fail-closed-ontology-completeness-gate.md]
---

# ADR-0012: On-demand ontology vendoring from a canonical registry

## Status

Accepted

## Context

### Background and Problem Statement

The harness typed findings against ontology packs that shipped **bundled** —
every domain ontology committed in every clone, kept current by hand. That has
two costs: each clone carries (and must re-sync) ontologies it never binds, and
hand-edits to a vendored copy silently drift it from its canonical definition
(the source of truth is the `ontologies` repo, served at
`https://mif-spec.dev/ontologies/`). The drift is real: a clone's bundled packs
had fallen ~1800 lines behind canonical, and a reviewer once suggested editing a
vendored pack in place — which would have desynced it permanently.

## Decision Drivers

### Primary Decision Drivers

1. PDD-1: Eliminate the drift risk of bundled ontology copies — a clone's
   bundled packs had fallen ~1800 lines behind canonical, and a reviewer once
   suggested editing a vendored pack in place, which would have desynced it
   permanently. The source of truth must be the `ontologies` repo, not a
   per-clone copy.
2. PDD-2: Lean clones — a clone should not carry (and re-sync) domain
   ontologies it never binds to a topic.
3. PDD-3: Supply-chain integrity consistent with ADR-0008 — every downloaded
   ontology artifact must be verified against a pinned sha256 hash fail-closed
   before use, never trusted blind.

### Secondary Decision Drivers

1. SDD-1: When no ontology exists for a domain, the harness should be able to
   author and contribute a draft back upstream, not just consume.
2. SDD-2: Offline/dev/CI environments need a local-directory source option,
   not just HTTP.

## Considered Options

### Option 1: Continue bundling every ontology in every clone (status quo)

Every domain ontology ships committed in every clone, kept current by hand.

**Advantages:** No network dependency; every ontology is available
immediately offline; simplest mental model (nothing to fetch).

**Disadvantages:** Each clone carries (and must re-sync) ontologies it never
binds to a topic; hand-edits to a vendored copy silently drift it from its
canonical definition — already observed in practice (a clone's bundled packs
had fallen ~1800 lines behind canonical, and a reviewer once suggested editing
a vendored copy in place, which would have desynced it permanently).

**Risk Assessment:** Technical — drift accumulates silently with no
verification mechanism; Schedule — zero migration effort; Ecosystem — every
clone re-syncs ontologies it may never use.

### Option 2: On-demand vendoring from the canonical registry, staged rollout (chosen)

Vendor domain ontologies on demand from the canonical registry
(`https://mif-spec.dev/ontologies/`), verified fail-closed against a pinned
sha256 index, while keeping base layers (`mif-base`, `mif-generic`,
`shared-traits`, `engineering-base`) committed since every finding needs them.
The mechanism ships now; flipping the currently-bundled domain packs to a
gitignored on-demand cache is a staged follow-up, since it also requires
re-enriching the bundled example corpus (canonical migrated some entity-type
names; pinned findings must be re-pinned via `/ontology-review --enrich`) and
the registry actually being served.

**Advantages:** Lean clones going forward; vendored copies are verifiable and
drift-proof (sha256-pinned against the canonical index); edits are forced
upstream where the source of truth lives; base layers stay offline-safe with
zero fetch latency; the harness becomes a producer as well as a consumer via
`scripts/author-ontology.sh`, which scaffolds and concierges draft ontologies
upstream when none exists for a domain.

**Disadvantages:** Introduces a new network/registry dependency for binding a
not-yet-present domain ontology (mitigated: base layers and already-vendored
packs work fully offline, and the lock file pins exact content so a missing
network is loud, not silent); adoption is necessarily staged rather than a
single atomic cutover.

**Risk Assessment:** Technical — fail-closed sha256 verification against a
pinned index bounds the new network dependency's risk; Schedule — one
mechanism-first migration, cutover follow-up tracked separately; Ecosystem —
every instance gains a registry dependency for not-yet-vendored domains.

### Option 3: On-demand vendoring, immediate full cutover

Same mechanism as Option 2, but flip every currently-bundled domain pack to a
gitignored on-demand cache immediately, rather than staging the cutover.

**Advantages:** One clean cutover instead of two rollout phases; no interim
period where some domain packs are bundled and others are fetched.

**Disadvantages:** Blocked on prerequisites that were not yet ready: the
bundled example corpus would need re-enrichment first (canonical had migrated
some entity-type names, so pinned findings would need re-pinning via
`/ontology-review --enrich`), and the canonical registry needed to actually be
served. Forcing an immediate cutover on unready prerequisites risked breaking
the bundled example corpus rather than improving on it.

**Risk Assessment:** Technical — the bundled example corpus would break if
cutover forced ahead of re-enrichment; Schedule — blocked on the registry
being served and corpus re-enrichment, an unbounded external dependency;
Ecosystem — a single atomic cutover with no fallback if either prerequisite
slips.

## Decision

Option 2. Vendor **domain** ontologies on demand from the canonical registry,
and keep **base** layers (`mif-base`, `mif-generic`, `shared-traits`,
`engineering-base`) committed (every finding needs them; no fetch latency,
offline-safe).

- The registry publishes `index.json` mapping `id -> {version, file, sha256,
  extends[]}` (`scripts/gen-ontology-index.sh` in the `ontologies` repo).
- `scripts/fetch-ontology.sh <id>` resolves the id's `extends` closure, fetches
  each domain layer not already present, **verifies its sha256 against the index
  fail-closed**, materializes it as `packs/ontologies/<id>/`, and pins the result
  in `ontologies.lock.json`. This reuses the supply-chain stance of ADR-0008
  (verify every downloaded artifact against a pinned hash).
- `scripts/check-ontology-lock.sh` proves every enabled domain ontology matches
  its pinned hash — catching local drift (fixes belong upstream) and missing
  on-demand packs.
- When resolution finds **no** ontology for a domain, the harness is a producer,
  not just a consumer: `scripts/author-ontology.sh <id> <topic>` scaffolds a
  draft ontology from the entity types the topic's findings actually used
  (`reports/<topic>/ontology-map.json`, generic-fallback types first) with
  grounding stubbed, and concierges a draft PR back to the `ontologies` repo.
- Source resolution: `$MIF_ONTOLOGY_SOURCE` / `.ontologies.source` /
  `https://mif-spec.dev/ontologies` (default). A local directory source is read
  for dev/CI/offline; an http source via curl.

## Consequences

### Positive

- Lean clones; vendored copies are verifiable and drift-proof; edits are forced
  upstream where the source of truth lives.
- The harness becomes a producer as well as a consumer of ontologies via the
  author-and-contribute flow.
- Base layers remain offline-safe with zero fetch latency.

### Negative

- A new network/registry dependency for binding a not-yet-present domain
  ontology (mitigated: base layers + already-vendored packs work offline, and the
  lock pins exact content).
- Adoption is staged rather than atomic: the bundled example corpus needs
  re-enrichment (canonical migrated some entity-type names; pinned findings must
  be re-pinned via `/ontology-review --enrich`) before the currently-bundled
  domain packs can flip to a gitignored on-demand cache.

### Neutral

- Existing consumers of the bundled packs (`resolve-ontology.sh`,
  `ontology-review.sh`) are unchanged by this decision; the vendoring mechanism
  sits underneath them.

## Decision Outcome

On-demand vendoring from the canonical registry, verified fail-closed against a
pinned sha256 index, removes the drift risk of hand-maintained bundled copies
while keeping the always-needed base layers committed and offline-safe. The
mechanism ships now; the remaining bundled-to-gitignored cutover for domain
packs is a staged follow-up once the bundled example corpus is re-enriched and
the registry is served.

## Related Decisions

- ADR-0008: the attested, fail-closed supply-chain posture this decision's
  sha256-pinned fetch reuses directly.
- ADR-0011: the fail-closed ontology-completeness gate this vendoring mechanism
  feeds — a topic bound to an ontology that fails to vendor or verify is
  exactly the failure this gate must catch.

## Links

- `scripts/fetch-ontology.sh` — the fetch/verify/pin command this decision specifies.
- `scripts/check-ontology-lock.sh` — the drift-detection command.
- `scripts/author-ontology.sh` — the author-and-contribute-upstream flow.
- `ontologies.lock.json` — the pinned-hash lock file this mechanism maintains (gitignored, instance-derived — generated by `scripts/fetch-ontology.sh`, not a committed repo artifact).

## More Information

- **Date:** 2026-06-30
- **Source:** `scripts/fetch-ontology.sh`, `scripts/check-ontology-lock.sh`, `scripts/author-ontology.sh`, `ontologies.lock.json`

## Audit

### 2026-06-30

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Fetch/verify/pin mechanism implemented and fail-closed | `scripts/fetch-ontology.sh`, `ontologies.lock.json` | compliant |
| Drift-detection command implemented | `scripts/check-ontology-lock.sh` | compliant |
| Author-and-contribute-upstream flow implemented | `scripts/author-ontology.sh` | compliant |

**Summary:** The vendoring mechanism (fetch, verify, pin, drift-check, author-upstream) is implemented and in use. The staged bundled-to-gitignored cutover for domain packs remains a follow-up per this ADR's own Consequences section.

**Action Required:** None (staged cutover tracked separately, not blocking this ADR's own scope).
