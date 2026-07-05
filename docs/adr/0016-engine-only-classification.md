---
title: "Engine-only classification: hard cutover to mif-rh"
description: "resolve-ontology.sh and ontology-review.sh become thin wrappers that hard-require the attested mif-rh-cli engine binary; the bash classification implementations are retired, with provisioning via an attested fetch script, PATH, or an explicit override."
type: adr
category: architecture
tags: [ontology, classification, engine, cutover, attestation, provisioning, fail-closed]
status: accepted
created: 2026-07-05
updated: 2026-07-05
author: zircote
project: research-harness-template
technologies: [Rust, Bash, GitHub Attestations]
audience: [developers, architects, operators]
related: [0011-fail-closed-ontology-completeness-gate.md, 0014-compiled-ontology-engine-cli-and-mcp.md, 0015-confidence-tier-consumption-and-scored-suggestion-routing.md]
---

# ADR-0016: Engine-only classification: hard cutover to mif-rh

## Status

accepted

## Context

### Background and Problem Statement

The harness has carried two implementations of topical ontology
classification: the original bash pipeline inside `resolve-ontology.sh`
(288 lines) and `ontology-review.sh` (188 lines), and the compiled
`mif-rh` engine (ADR-0014) that reimplements both commands in Rust.
Since the engine landed, its equivalence has been proven continuously:
mif-rs CI runs a fail-closed parity suite against a pinned checkout of
this repository (13 library-level cases plus 10 binary-level cases
covering exit codes, the record line, the coverage table byte layout,
strict mode, and followup ordering), and the M2 benchmark measured
about 2,155 findings per second against a 4,354-finding corpus where
the bash pipeline needed minutes. Maintaining two implementations of
one contract invites drift the parity suite can only catch after the
fact, and every bash change re-risks the exact class of bug the engine
port fixed.

### Current Limitations

- Two implementations of one normative behavior, one of them tested
  only indirectly.
- The bash pipeline needs yq, jq, and ajv at matching versions on every
  machine; the engine needs one static binary.
- Classification throughput on real corpora is minutes in bash against
  seconds in the engine, which discourages full-corpus review passes.

## Decision Drivers

### Primary Decision Drivers

- PDD-1: One implementation of the classification contract; the parity
  suite becomes a regression net for the engine, not a bridge between
  two moving targets.
- PDD-2: Supply-chain integrity: WHEN the harness obtains an engine
  binary, the system SHALL verify its build provenance fail-closed
  before installing it (attested download, or an explicit operator
  override).
- PDD-3: Loud failure: WHEN the engine is absent or older than the
  pinned minimum, classification scripts SHALL fail with a message
  naming the remedy, never fall back to a silently different code path.

### Secondary Decision Drivers

- SDD-1: Operator ergonomics: one command installs a verified binary.
- SDD-2: Developer ergonomics: a source build is usable without ceremony.

## Considered Options

### Option 1: Engine with bash fallback

Keep the bash implementations; delegate when the binary is present.

Risk Assessment: Technical — the fallback path decays silently since
CI would exercise only one side per run; Schedule — lowest immediate
effort; Ecosystem — two dependency stacks indefinitely.

### Option 2: Engine-only, hard required (chosen)

Scripts become thin wrappers that locate a version-gated engine binary
and exec it; the bash classification bodies are deleted. Provisioning
is layered: an explicit `MIF_RH_CLI` override, then PATH, then a
repo-local `bin/mif-rh-cli` installed by `scripts/fetch-engine.sh`,
which downloads the pinned release and verifies its attestation
fail-closed before installing.

Risk Assessment: Technical — a hard runtime dependency on a released
binary, mitigated by three provisioning paths and a version gate;
Schedule — one migration; Ecosystem — CI and instances must install
the engine once.

### Option 3: Retire the scripts, call the engine directly everywhere

Delete the wrappers too and update every caller.

Risk Assessment: Technical — breaks the stable script interface that
commands, agents, evals, and downstream instances reference; Ecosystem
— a coordinated rename across every consumer for no behavioral gain.

## Decision

Option 2. `resolve-ontology.sh` and `ontology-review.sh` keep their
names, flags, and documented contracts, and delegate to the engine
through a shared resolver (`scripts/lib/engine.sh`) that hard-requires
`mif-rh-cli` at or above the pinned minimum version. Provisioning
order: `MIF_RH_CLI` override, PATH, then `bin/mif-rh-cli` from
`scripts/fetch-engine.sh` (attested download, fail-closed
verification). CI installs the engine with the same fetch script the
runbook gives operators.

## Consequences

### Positive

- One classification implementation, continuously parity-proven at the
  binary level before this cutover and regression-tested after it.
- Full-corpus review drops from minutes to seconds, making strict
  gates cheap enough to run habitually.
- The yq/jq/ajv dependency surface for classification disappears.

### Negative

- Classification requires a released engine binary; air-gapped or
  unsupported-platform environments must build from source and point
  `MIF_RH_CLI` at the result.
- A regression in a released engine affects consumers until a patched
  release ships; the version gate plus attested provisioning is the
  containment.

### Neutral

- The wrappers remain the stable interface; callers are unchanged.
- The ADR-0011 fail-closed gate semantics are identical; the engine
  implements the same contract the bash did.

## Decision Outcome

Classification behavior is unchanged by construction (binary-level
parity enforced in mif-rs CI at a pinned SHA of this repository), while
the implementation count drops to one, provisioned only through
attestation-verified channels or explicit operator intent.

## Related Decisions

- ADR-0011: the fail-closed completeness gate the engine preserves.
- ADR-0014: the engine's original packaging and CLI/MCP decision.
- ADR-0015: the confidence-tier surfaces that already require the
  engine binary; this ADR aligns the deterministic path with them.

## Links

- mif-rs parity suites: `crates/mif-rh/tests/parity.rs`,
  `crates/mif-rh-cli/tests/bin_parity.rs`
- Engine releases: modeled-information-format/mif-rs (v0.3.1 and later)

## More Information

The retired bash implementations remain in git history (this commit's
parent) should forensic comparison ever be needed.

## Audit

- 2026-07-05: Pending — cutover PR staged with the wrapper rewrite,
  fetch script, CI installation, and eval updates.
- 2026-07-05: Accepted — cutover merged to `main` (PR #265); the MCP
  server wiring landed alongside it (PR #266).
