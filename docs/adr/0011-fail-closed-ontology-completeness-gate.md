---
title: "Fail-closed ontology-completeness gate before synthesis"
description: "Block synthesis until every shippable finding resolves to a valid ontology type, and auto-reconcile the cross-topic concordance every run, so the ontological spine is current and complete before a deliverable ships."
type: adr
category: architecture
tags: [ontology, synthesis, fail-closed, concordance, gate]
status: accepted
created: 2026-06-29
updated: 2026-06-29
author: zircote
project: research-harness-template
technologies: [Bash, jq, ajv, JSON Schema]
audience: [developers, architects]
related: [0003-config-declared-research-dimensions.md, 0004-single-adversarial-falsification-gate.md, 0010-change-driven-component-versioning.md]
---

# ADR-0011: Fail-closed ontology-completeness gate before synthesis

## Status

Accepted

## Context

### Background and Problem Statement

The ontological spine — a cross-topic, ontology-typed, verdict-aware
`concordance` — is the harness's distinguishing advantage: it is the corpus's
answer to "what does the corpus know" (`docs/explanation/ontological-spine.md`).
Per-finding ontology resolution already runs in orchestrator Phase 1
(`scripts/resolve-ontology.sh` writes `reports/<topic>/ontology-map.json`), but
the spine was never reconciled into the research→synthesis loop, and nothing
verified that a finding was actually typed before it shipped.

The load-bearing defect is a **vacuous pass**. `scripts/validate-concordance.sh`
filters its node checks with `select(.entityType != null and (.external != true))`
(validate-concordance.sh:139). A concept node for an *untyped* finding is stamped
`entityType: null` by `scripts/build-concordance.sh`
(`entity_type // .entity.entity_type // null`, build-concordance.sh:47). An
untyped shippable finding therefore passes concordance validation by being
skipped — the conformance validator structurally cannot see the gap. Meanwhile
`.claude/agents/orchestrator.md` Phase 4 ran membership reconciliation and spawned
the `report-synthesizer` directly, never building or validating the concordance
and never checking that surviving claims were typed.

### Current Limitations

- Untyped, unresolved, or mis-typed shippable claims could reach the deliverable
  with no gate refusing them.
- The cross-topic concordance was built only on demand (`/graph --concordance`,
  `/ontology-review`); between runs the spine drifted stale, and in a fresh corpus
  `reports/concordance.json` did not exist at all.
- Synthesis had no guarantee the corpus was ontologically complete or current.

## Decision Drivers

### Primary Decision Drivers

1. Every shippable claim must be ontology-typed before it is synthesized
   (the spine is only an advantage if it is complete).
2. The cross-topic spine must be reconciled automatically on every run, not by
   hand.
3. The posture must be fail-closed (block), consistent with the harness's
   fail-closed supply-chain and conformance ethos — not advisory warning.

### Secondary Decision Drivers

1. Reuse the existing deterministic engine (`resolve-ontology.sh` /
   `ontology-review.sh` / `build-concordance.sh` / `validate-concordance.sh`)
   rather than add a parallel mechanism.
2. Preserve `reconcile-session.sh` byte-determinism (no wall-clock in `state.json`).
3. Do not add a second adversarial gate (ADR-0004 keeps falsification the single
   adversarial step).
4. Per-topic isolation: one topic's typing defect must not strand another topic's
   synthesis.

## Considered Options

### Option 1: Keep manual `/ontology-review` and warn at synthesis

**Description:** Leave concordance building manual; emit a provenance warning when
a finding is untyped but synthesize anyway.

- **Advantages:** Least disruptive; never stops a run.
- **Disadvantages:** Not fail-closed — untyped claims still ship; the spine keeps
  drifting stale; the warning is easily ignored.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

### Option 2: Reuse `ontology-review.sh --strict` as the gate

**Description:** Run the existing strict mode as the pre-synthesis block.

- **Advantages:** No new script.
- **Disadvantages:** `--strict` fails on *any* invalid finding including
  **falsified** ones (which are excluded from synthesis anyway), and it has no
  verdict scoping — it cannot express "block only shippable (survived|weakened)
  findings, and treat `basis==untyped` (which is `valid:true`) as blocking."
- **Risk Assessment:** technical medium; schedule low; ecosystem low.

### Option 3 (chosen): Thin per-topic typing gate + auto build/validate concordance

**Description:** A new deterministic `scripts/check-shippable-typing.sh` hard-blocks
synthesis when a shippable finding is untyped/unresolved/invalid; the orchestrator
then builds and validates the concordance every run, recording its status.
Concordance non-conformance is surfaced as a NOTE (per-topic isolation), the typing
gate is the authoritative shippable-output block.

- **Advantages:** Fail-closed exactly where it must be; verdict-scoped; reuses the
  existing build/validate scripts; closes the vacuous-pass gap the validator can't see.
- **Disadvantages:** Introduces a new run-stopping failure mode (mitigated below).
- **Risk Assessment:** technical low; schedule low; ecosystem low.

### Option 4: Make concordance non-conformance a global hard block too

**Description:** Also fail the whole run when `validate-concordance.sh` reports any
violation.

- **Advantages:** Strongest global guarantee.
- **Disadvantages:** The concordance merges entities across topics by `@id`, so a
  domain violation is not cleanly attributable to one topic — a violation seeded by
  topic X could strand topic Y's synthesis. Deferred.
- **Risk Assessment:** technical medium; schedule medium; ecosystem low.

## Decision

Block synthesis with a thin, deterministic, per-topic typing gate, and
auto-reconcile the cross-topic spine on every run.

`scripts/check-shippable-typing.sh` blocks (exit 1) iff a finding whose
`extensions.harness.verification.verdict` is `survived` or `weakened` has an
`ontology-map.json` record that is missing, `valid==false`, or
`basis ∈ {untyped, unresolved}`. Falsified/quarantined/inconclusive findings never
block. A missing map fails closed (exit 3) — typing cannot be proven vacuously.

`.claude/agents/orchestrator.md` Phase 4 gains one step before the synthesizer
spawn: refresh the lock, rebuild this topic's `ontology-map.json`
(`ontology-review.sh --topic`), run the typing gate, and — on pass — build
(`build-concordance.sh`) and validate (`validate-concordance.sh`) the spine, write
`reports/concordance-status.json`, and project the status into `state.json` via
`reconcile-session.sh`. On a block, the orchestrator writes the
`reports/<topic>/.synthesis-withheld` sentinel, records the reason, releases the
lock, and stops; `.claude/commands/resume.md` reads the sentinel as the remaining
work and re-enters Phase 4 after the operator runs
`/ontology-review --topic <id> --enrich`. The orchestrator clears the sentinel on a
clean synthesis, so the loop converges. `schemas/session-state.schema.json` carries
an optional `concordance` block; `scripts/verify.sh` `gate_m24` proves the gate
blocks an untyped survivor, ignores a falsified one, passes a typed corpus, and is
wired before the synthesizer spawn.

**Why this is not a second adversarial gate (ADR-0004):** the falsification gate is
adversarial and probabilistic — it forms a *new* judgment about whether a claim
holds. The typing gate is deterministic conformance over verdicts that were *already
decided*; it forms no new judgment and only refuses to *ship* a survivor that is not
ontology-typed. ADR-0004's single-adversarial-gate invariant stands.

## Consequences

### Positive

1. No untyped, unresolved, or mis-typed claim ships; the spine is complete before
   synthesis.
2. `reports/concordance.json` is reconciled and validated every run; its status is
   recorded in `concordance-status.json` and `state.json`.
3. The vacuous-pass gap the conformance validator cannot see is closed by a gate
   that targets exactly it.

### Negative

1. A run can now stop before synthesis — a new failure mode. Mitigated by the
   `.synthesis-withheld` sentinel and the `/ontology-review --enrich` → `/resume`
   convergence loop, both of which name the exact remediation.

### Neutral

1. `reconcile-session.sh` now reads one level up (`reports/concordance{,-status}.json`)
   for corpus status — a deliberate, existence-guarded exception to its
   purely-per-topic contract; determinism is preserved (the wall-clock lives only in
   the sidecar).

## Decision Outcome

Shippable claims are guaranteed ontology-typed and the spine is guaranteed current
before any deliverable is produced, at the cost of one recoverable stop whose
remediation is explicit and automated through `/resume`.

## Related Decisions

- 0003-config-declared-research-dimensions.md
- 0004-single-adversarial-falsification-gate.md
- 0010-change-driven-component-versioning.md

## More Information

- **Date:** 2026-06-29
- **Source:** `scripts/check-shippable-typing.sh`, `.claude/agents/orchestrator.md`, `scripts/validate-concordance.sh`

## Audit

### 2026-06-29

**Status:** Pending

| Finding | Files | Assessment |
| --- | --- | --- |
| Gate blocks untyped shippable findings, ignores falsified | `scripts/check-shippable-typing.sh`, `scripts/verify.sh` | pending |
| Concordance built + validated before synthesis | `.claude/agents/orchestrator.md` | pending |

**Summary:** Fail-closed ontology-completeness gate and auto-reconciled spine wired into Phase 4.

**Action Required:** None
