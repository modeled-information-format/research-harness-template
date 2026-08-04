---
title: "Confidence-tier consumption and scored-suggestion routing"
description: "Consume the MIF confidence-tiered entity-type classification via a scored suggestion queue and tier-3 miss store under reports/_meta, feeding /ontology-review --enrich and author-ontology.sh — never the deterministic fail-closed gate path."
type: adr
category: architecture
tags: [ontology, classification, confidence-tiers, embeddings, suggestion-queue, calibration, fail-closed]
status: accepted
created: 2026-07-04
updated: 2026-07-04
author: zircote
project: research-harness-template
technologies: [Rust, Bash, jq, JSON Schema, SQLite]
audience: [developers, architects]
related: [0011-fail-closed-ontology-completeness-gate.md, 0012-on-demand-ontology-vendoring.md, 0014-compiled-ontology-engine-cli-and-mcp.md]
---

# ADR-0015: Confidence-tier consumption and scored-suggestion routing

## Status

Accepted

## Context

### Background and Problem Statement

The MIF specification adopted confidence-tiered entity-type classification
(MIF ADR-020, "Confidence-Tiered Entity-Type Classification as a MIF Ontology Capability"): the ontology
schema (1.1.0) gives every entity type three optional classifier-facing
fields — `aliases`, `exemplars`, and `negative_examples` — and defines a
two-threshold, three-tier decision policy over embedding-similarity scores:
**tier 1** `auto_classify_eligible` (above the upper threshold, with an
additional margin gate over the runner-up candidate), **tier 2**
`flag_for_review` (between the thresholds), and **tier 3**
`trigger_expansion` (below the lower threshold — no cataloged type fits,
which is a signal about the ontology, not the finding).

The compiled ontology engine this harness already proved out (ADR-0014:
`mif-rh` / `mif-rh-cli` / `mif-rh-mcp` in `modeled-information-format/mif-rs`)
implements the capability end to end: `mif-ontology` carries the schema-1.1.0
model, and the engine exposes three consuming surfaces:

- **`mif-rh-cli review --suggest`** writes tier-annotated suggestion queues
  to `reports/_meta/suggestions/<topic>.json`. Each entry is
  `{finding_id, file?, basis, run_id, candidates: [{entity_type, ontology_id,
  score, tier, margin?, calibrated}], status}`; `status` starts `"pending"`,
  and non-`pending` statuses are preserved across re-runs — confirming or
  rejecting an entry is the human/agent step, never the engine's.
- **`mif-rh-cli calibrate`** derives `reports/_meta/confidence-calibration.json`
  (method `stamped-quantile-v1`) from the instance's own stamped findings.
- **`mif-rh-cli expansion-candidates [--out clusters.json]`** clusters
  recorded tier-3 misses (mutual similarity, a minimum cluster size counted
  in DISTINCT findings, a minimum number of distinct runs) and emits
  `{clusters: [{size, runs, members: [{finding_id, topic, content, run_id}]}],
  misses_considered, expansion}`.

This ADR records the routing decision the harness must now make: where do
scored suggestions and tier-3 misses land in this repository, and which
harness surfaces consume them? The grounding research is the
`ontology-semantic-classification-scoring` session (39 findings, 0 falsified)
and its draft report "Confidence-Threshold Classification as a MIF Ontology
Capability" — this ADR is that draft's "Path to Adoption" hop 2 (spec → engine
→ **harness consumption**).

### Current Limitations

The harness's only existing not-durably-typed worklist is the `--followup`
backlog (`scripts/ontology-review.sh --followup`, extended by ADR-0014's
engine): `reports/_meta/ontology-followup.json`. It cannot carry the new
capability's output, for three code-grounded reasons:

1. **`FollowupEntry` carries exactly one unscored `entity_type`** (the
   discovery guess, when one exists). A scored suggestion is a ranked LIST of
   candidates, each with `score`, `tier`, `margin`, and calibration
   provenance — flattening that to one unscored string discards precisely the
   information the capability exists to produce.
2. **The backlog is atomically rebuilt on every review run.** That is correct
   for a point-in-time worklist, but structurally wrong for anything that
   must accumulate across runs: confirmed/rejected review statuses and
   recorded tier-3 misses (whose whole value is cross-run recurrence) would
   be erased on the next review.
3. **Embeddings must never enter the deterministic review path.** The
   `--followup` backlog is written by the same deterministic review pass
   whose outputs feed ADR-0011's fail-closed shippable-typing gate. Routing
   embedding-derived scores through that artifact would put a
   model-dependent, non-deterministic signal inside the gate's input surface.

## Decision Drivers

### Primary Decision Drivers

1. Scored, tiered suggestions must reach a reviewer with their scores, tiers,
   and margins intact, and review verdicts (confirmed/rejected) must survive
   re-runs.
2. Tier-3 misses must accumulate across runs so recurring uncataloged
   concepts become visible as ontology-expansion candidates.
3. The deterministic fail-closed path (ADR-0011's gate, `verify.sh`'s
   ontology gates) must remain byte-deterministic and embedding-free.

### Secondary Decision Drivers

1. Consume through surfaces the harness already has — `/ontology-review
   --enrich` for per-finding typing, `scripts/author-ontology.sh` for
   drafting new ontology material — rather than inventing parallel ones.
2. Calibration thresholds are per-instance, recalibratable artifact data,
   never constants baked into code or committed to the template.

## Considered Options

### Option 1 (2a): Reuse the `--followup` backlog and `author-ontology.sh` inputs as-is

**Description:** Extend `FollowupEntry` with the scored candidate list, and
have tier-3 misses ride along in the same backlog; `author-ontology.sh` keeps
mining only `ontology-map.json`.

- **Advantages:** No new artifact family; one worklist file to know about.
- **Disadvantages:** All three limitations above: the entry shape flattens
  scored lists, the atomic rebuild erases review statuses and cross-run miss
  accumulation, and the backlog sits on the deterministic review path that
  ADR-0011's gate consumes — embedding scores would leak into the gate's
  input surface.
- **Risk Assessment:** technical high (gate contamination, data loss on
  rebuild); schedule low; ecosystem medium.

### Option 2 (2b, chosen): Purpose-built scored queue + miss store, feeding the existing surfaces

**Description:** The engine writes purpose-built derived artifacts —
`reports/_meta/suggestions/<topic>.json` (scored, tiered, status-carrying
suggestion queues) and the recorded tier-3 miss store behind
`expansion-candidates` — and the harness's EXISTING surfaces consume them:
`/ontology-review --enrich` reads the suggestion queue as its Phase 2
worklist input, and `scripts/author-ontology.sh --from-clusters` mines the
expansion-candidates cluster JSON into draft entity-type scaffolds. Recorded
as "**2b-routing, 2a-pipeline**": new routing artifacts, existing consuming
pipeline.

- **Advantages:** Preserves scores/tiers/margins end to end; statuses and
  misses persist across runs; the deterministic gate path never touches an
  embedding-derived value; reviewers and authors keep the workflows they
  already know.
- **Disadvantages:** One more derived artifact family under `reports/_meta`;
  `/ontology-review --enrich` learns one new input file.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

### Option 3: No consumption

**Description:** The engine's capability exists but the harness ignores it;
typing continues from the unscored followup backlog alone.

- **Advantages:** Zero change to this repository.
- **Disadvantages:** Forfeits the measured value of the capability (scored
  review prioritization, recurrence-based expansion candidates) that the
  grounding research session established; the engine surfaces would exist
  with no documented consumer.
- **Risk Assessment:** technical low; schedule low; ecosystem medium (the
  Path-to-Adoption chain dead-ends at hop 2).

## Decision

Adopt **Option 2** — "2b-routing, 2a-pipeline": purpose-built scored
suggestion queues and a tier-3 miss store as the routing artifacts, consumed
by the harness's existing surfaces.

- `reports/_meta/suggestions/<topic>.json` (written by `mif-rh-cli review
  --suggest`) is the scored review queue. `/ontology-review --enrich` reads
  it alongside the followup backlog: pending entries' scored candidates are
  reviewed, and each entry's `status` is set to `confirmed` or `rejected` —
  entries are never deleted. A confirmed candidate still goes through the
  normal typing edit (stamp the finding's `entity` block) and resolve
  re-stamp; it is never auto-written.
- `mif-rh-cli expansion-candidates --out <clusters.json>` emits recurring
  tier-3 miss clusters; `scripts/author-ontology.sh --from-clusters
  <clusters.json>` mines them into draft entity-type scaffolds through the
  script's existing output/scaffolding path (the default `ontology-map.json`
  mining mode is untouched).
- **Calibration artifact contract:** `reports/_meta/confidence-calibration.json`
  is derived by `mif-rh-cli calibrate` from the instance's own stamped
  findings (method `stamped-quantile-v1`). The two tier thresholds and the
  tier-1 margin are recalibratable artifact data read from this file — never
  constants in code, never committed by the template (an instance may commit
  its own if it chooses; the template treats it as derived, per-instance
  data, like `ontology-map.json`).

**The ADR-0011 invariant, stated explicitly:** a suggestion at ANY tier —
including tier 1 `auto_classify_eligible` — is a hypothesis, not a stamp.
Nothing in this decision bypasses the fail-closed stamped-vs-discovery
distinction: `check-shippable-typing.sh` continues to block synthesis on any
shippable finding without a durable, valid `entity` stamp, exactly as before,
and no surface introduced or extended here ever auto-writes an
`entity_type` to a finding. "Eligible" names a confidence band, not a write
authorization.

## Consequences

### Positive

1. Scored review UX: `/ontology-review --enrich` works a ranked, tiered,
   calibrated queue instead of an unscored guess list, and its verdicts
   persist.
2. Cross-run recurrence: tier-3 misses accumulate, so a concept the ontology
   repeatedly fails to catalog becomes a visible, clustered expansion
   candidate with cited member findings.

### Negative

1. One more derived artifact family lives under `reports/_meta`
   (`suggestions/<topic>.json`, `confidence-calibration.json`, and any
   exported clusters file), and `/ontology-review --enrich` learns one new
   input file.

### Neutral

1. Calibration is per-instance derived data, never committed by the
   template — instances with different corpora legitimately derive different
   thresholds.

## Decision Outcome

The harness consumes the MIF confidence-tier capability with full fidelity
(scores, tiers, margins, statuses, recurrence) while the deterministic
fail-closed spine of ADR-0011 remains untouched: embedding-derived data flows
only through the new derived artifacts into human/agent review surfaces, and
every durable typing decision still lands as a normal stamped `entity` block
that the existing gates verify.

## Related Decisions

- [ADR-0011: Fail-closed ontology-completeness gate](../0011-fail-closed-ontology-completeness-gate/) — the invariant this decision preserves: suggestions are hypotheses; the stamped-vs-discovery gate is never bypassed.
- [ADR-0012: On-demand ontology vendoring](../0012-on-demand-ontology-vendoring/) — expansion candidates drafted via `author-ontology.sh --from-clusters` still contribute upstream through the vendoring/registry flow.
- [ADR-0014: Compiled ontology engine as a scoped CLI+MCP proof-of-concept](../0014-compiled-ontology-engine-cli-and-mcp/) — the engine whose `review --suggest` / `calibrate` / `expansion-candidates` surfaces this decision routes.

## Links

- `schemas/mif/ontology.schema.json` — re-seeded at 1.1.0 with `aliases`/`exemplars`/`negative_examples`.
- `scripts/author-ontology.sh` — the expansion-candidate authoring flow this decision's suggestion queue feeds.
- `.claude/commands/ontology-review.md` — the `--enrich` consuming surface.

## More Information

- **Date:** 2026-07-04
- **Source:** `schemas/mif/ontology.schema.json` (re-seeded at 1.1.0 with `aliases`/`exemplars`/`negative_examples`), `scripts/author-ontology.sh`, `.claude/commands/ontology-review.md`
- MIF ADR-020 "Confidence-Tiered Entity-Type Classification as a MIF Ontology Capability" (the spec-side decision this consumes).
- The `ontology-semantic-classification-scoring` research session (39 findings, 0 falsified) and its draft "Confidence-Threshold Classification as a MIF Ontology Capability" — this ADR is that draft's "Path to Adoption" hop 2.

## Audit

### 2026-07-04

**Status:** Pending

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Ontology contract re-seeded from MIF at schema 1.1.0 (`aliases`/`exemplars`/`negative_examples`) | `schemas/mif/ontology.schema.json`, `schemas/mif/ontology.context.jsonld` | compliant — byte-identical to the MIF source |
| `--from-clusters` alternate input mode added; default mode untouched | `scripts/author-ontology.sh` | compliant |
| `/ontology-review --enrich` documents the suggestion queue as a Phase 2 input; statuses set, never deleted; no auto-write | `.claude/commands/ontology-review.md`, `docs/reference/commands.md` | compliant |
| Engine-side surfaces (`review --suggest`, `calibrate`, `expansion-candidates`) | `mif-rh-cli` (`modeled-information-format/mif-rs`) | implemented engine-side; consumed here as documented contracts |

**Summary:** Routing decision recorded ("2b-routing, 2a-pipeline") and the
harness-side consumption surfaces documented/implemented; the fail-closed
gate path is unchanged.

**Action Required:** None
