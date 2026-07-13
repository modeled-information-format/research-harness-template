---
title: "Content-hashed, append-only goal versioning"
description: "Evolve a session goal by appending immutable content-hashed versions and reusing findings across them, preserving verifiability."
type: adr
category: data
tags: [goal, versioning, content-hash, living-corpus, verifiability]
status: proposed
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [JSON Schema, SHA-256, W3C-PROV]
audience: [developers, architects]
related: [0003-config-declared-research-dimensions.md, 0004-single-adversarial-falsification-gate.md]
---

# ADR-0006: Content-hashed, append-only goal versioning

## Status

Proposed

## Context

### Background and Problem Statement

A research session runs toward a goal (`reports/<topic>/goal.json`,
`schemas/goal.schema.json`) — the harness's one verifiability contract: "did we
answer the question" is a printable fact only because the contract did not move
underneath the run (design spec §2, §6b). Research is not one-shot: scope shifts,
dimensions are added, checks change. The question is how a goal evolves without
destroying verifiability or discarding findings already gathered
(`docs/explanation/living-corpus.md`). That document is an accepted design
proposal not yet fully implemented, so this record is `proposed`.

### Current Limitations

If the goal is mutated in place, the harness can never again prove a past session
met its goal, and the findings already gathered cannot be cleanly reused across
an evolved question.

## Decision Drivers

### Primary Decision Drivers

1. A goal version must be a fixed, checkable snapshot — verifiability cannot move.
2. Identity must be self-verifying and decoupled from commit timing (the harness
   runs against the working tree, so goals are often uncommitted mid-session).

### Secondary Decision Drivers

1. Findings must be reusable across versions, not re-gathered from scratch.
2. Evolution should write little, not rewrite every finding.

## Considered Options

### Option 1: Mutate the goal in place

**Description:** Keep one `goal.json` and edit it over time as scope changes.

- **Advantages:** Trivially simple to implement.
- **Disadvantages:** Destroys the verifiability contract; no past run can be proven to have met its goal.
- **Risk Assessment:** technical low; schedule low; ecosystem high.

### Option 2: Timestamp or git-SHA keyed versions

**Description:** Identify each goal version by a git SHA or wall-clock timestamp.

- **Advantages:** Ordering between versions is obvious.
- **Disadvantages:** A git SHA identifies a commit, not the goal's content, and the harness runs on an often-uncommitted working tree — the key would not match the content actually researched.
- **Risk Assessment:** technical medium; schedule low; ecosystem medium.

### Option 3: Content-hashed append-only lineage

**Description:** Identify each version by `gv-<sha256(goal.json)[:12]>`, retained immutably in a per-topic lineage; reuse findings many-to-many across versions.

- **Advantages:** The hash is self-verifying (recomputing it proves a finding matches that version) and decoupled from commit timing; a human alias and git SHA are kept as provenance, never identity; `provenance.gathered_under` (single, immutable origin) is separated from `goal_versions[]` (the computed membership set), so a finding is produced once and reused across every version it still serves, and only the true gap is re-gathered.
- **Disadvantages:** Membership must be re-derived by a scope-resolution pass rather than hand-authored.
- **Risk Assessment:** technical medium; schedule medium; ecosystem low.

## Decision

Adopt **Option 3: content-hashed append-only lineage.** A goal evolution appends
a new immutable version identified by `gv-<sha256[:12]>`; prior versions are
retained. `/goal-writer --reshape` mints the version and classifies existing
findings (carry / re-verify / gap); `/start --update` runs only the delta.
Membership is a computed projection, and freshness is tracked separately from
membership.

## Consequences

### Positive

1. The goal evolves while every version stays provably checkable.
2. Findings are reused, not re-gathered; only the true gap is gathered.

### Negative

1. The implementation adds lineage, a scope-resolution pass, and freshness
   fields, and open questions remain (membership authority location, reshape
   delta input, freshness model).

### Neutral

1. Archival becomes a rare, safe end-of-life event — a finding leaves only when
   out of scope for every live version, and is archived, never deleted.

## Decision Outcome

Content-hashed append-only versioning lets the goal evolve while preserving the
verifiability that makes "we answered the question" a printable fact, and reuses
findings across versions instead of re-gathering them. Because the living-corpus
model is documented but not yet built, this record remains `proposed` until the
lineage, scope-resolution pass, and freshness fields are implemented.

## Related Decisions

- [ADR-0003: Domain-general, config-declared research dimensions](0003-config-declared-research-dimensions.md)
- [ADR-0004: Single adversarial falsification gate](0004-single-adversarial-falsification-gate.md)

## Links

- `docs/explanation/living-corpus.md`
- `schemas/goal.schema.json`

## More Information

- **Date:** 2026-06-23
- **Source:** `docs/explanation/living-corpus.md`, `schemas/goal.schema.json`

## Audit

### 2026-06-23

**Status:** Pending

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Goal contract schema present | `schemas/goal.schema.json` | compliant |
| Living-corpus model documented | `docs/explanation/living-corpus.md` | compliant |
| Content-hashed lineage implemented | (not yet present) | pending |
| Scope-resolution pass + freshness fields | (not yet present) | pending |

**Summary:** The goal contract and the design model exist, but the lineage, scope-resolution pass, and freshness fields described here are not yet implemented — the source document states the model is a design proposal not yet built.

**Action Required:** None
