---
title: "Compiled ontology engine as a scoped CLI+MCP proof-of-concept"
description: "Prove out a compiled replacement for the ontology-review/resolve-ontology bash pair — as both a CLI and an MCP server backed by a search index — before deciding whether to generalize it across the harness's other bash/jq scripts."
type: adr
category: architecture
tags: [ontology, cli, mcp, performance, search-index, engine, proof-of-concept]
status: proposed
created: 2026-07-01
updated: 2026-07-01
author: zircote
project: research-harness-template
technologies: [Bash, jq, yq, ajv, Go, Rust, SQLite, MCP]
audience: [developers, architects]
related: [0001-four-layer-single-repository-architecture.md, 0011-fail-closed-ontology-completeness-gate.md, 0012-on-demand-ontology-vendoring.md]
---

# ADR-0014: Compiled ontology engine as a scoped CLI+MCP proof-of-concept

## Status

Proposed

## Context

### Background and Problem Statement

The harness's ontology subsystem (`scripts/resolve-ontology.sh`,
`scripts/ontology-review.sh`, and their callers) is a collage of bash scripts
that shell out to `jq`, `yq`, and `ajv` as separate subprocesses **per
finding**. This has held up well at the scale the template ships with — the
bundled example topic (36 findings) reviews in seconds — but a real production
corpus exposes the cost directly: a full-corpus `ontology-review.sh` run
against `~/Projects/zircote/research-harness` (4296 findings across 36 topics)
took over 20 minutes and was still running, one topic at a time, when checked
at the 20-minute mark (topic 17 of 36). That is a process-spawn cost problem —
three external tool invocations per finding, thousands of findings — not an
algorithmic one.

Separately, the harness's only cross-topic query surface today is
`reports/concordance.json` (built by `scripts/build-concordance.sh` and
summarized by `scripts/synthesize-corpus.sh`'s atlas): a **static** snapshot,
regenerated on demand, not a live index. There is no way for an agent
authoring a new finding to ask "has anything like this already been found, in
any topic?" before writing it. Redundant research across topics is invisible
until a human happens to notice it.

This same subsystem was also the site of a real correctness bug fixed earlier
in this session (research-harness-template#251,
`feat/ontology-discovery-followup`): `resolve-ontology.sh`'s content-pattern
discovery fallback — a regex classifier that fires when a finding has no
`entity` block — let its guesses silently count as "typed" in
`ontology-review.sh`'s coverage report, masking real corpus-wide gaps.
Measured: 15 of 36 findings in the template's own bundled example topic, and
63 of 4296 in the real corpus, were discovery-only (guessed, never durably
stamped) before the fix. That fix is orthogonal to this ADR — it is a
reporting/gating correctness change, not an architecture change — but its root
cause (a regex classifier standing in for real classification) is exactly the
kind of thing a proper engine with semantic matching could do better.

### Current Limitations

- **Runtime scales badly with corpus size.** Subprocess-spawn overhead is paid
  per finding, per tool (`yq`, `jq`, `ajv`), with no in-memory reuse across
  findings within one run.
- **No live search or recall.** `concordance.json` is a point-in-time
  computed artifact; querying it requires knowing to rebuild and re-parse it,
  and it has no similarity/ranking notion at all — only exact structural
  fields (`entityType`, topic, verdict).
- **The discovery classifier is a blunt instrument.** Regex `content_pattern`
  matching (see `docs/adr/0011-fail-closed-ontology-completeness-gate.md`'s
  sibling mechanism in `resolve-ontology.sh`) either matches ambiguously
  (refuses to classify) or not at all; it cannot express "this finding is
  *similar to* a known type" the way an embedding-based classifier can.
- **The value the current approach already delivers is real** and must not be
  lost: zero-toolchain-install (every dependency is a common CLI tool already
  required by `verify.sh`), full line-by-line auditability by any contributor,
  git-diffable behavior, and alignment with this template's own stated
  design philosophy (no `make`/`npm`/`pyproject` build step — "scripts are
  invoked directly"). Any replacement must not regress the 144 `verify.sh`
  gates and 41 `evals/run-evals.sh` evals currently passing against this
  subsystem.

## Decision Drivers

### Primary Decision Drivers

- **PDD-1**: The engine MUST reduce full-corpus `ontology-review` wall-clock
  time from its current measured 20+ minutes (4296 findings) to a
  low-single-digit-minutes-or-better bound, without changing the deterministic
  fail-closed contract callers depend on.
  (EARS: WHEN `ontology-review` runs against a 4296-finding corpus, THE SYSTEM
  SHALL complete within 5 minutes.)
- **PDD-2**: The engine MUST NOT regress any of the 144 `scripts/verify.sh`
  assertions or 41 `evals/run-evals.sh` evals that currently exercise
  `resolve-ontology.sh` / `ontology-review.sh`, when those assertions are
  re-run against the new engine's CLI.
  (EARS: WHEN the existing verify.sh/run-evals.sh suites are run against the
  compiled engine's CLI in place of the bash scripts, THE SYSTEM SHALL produce
  identical pass/fail outcomes.)
- **PDD-3**: The proof-of-concept MUST be scoped to the ontology-review /
  resolve-ontology pair only — not a rewrite of the harness's other ~18
  bash scripts — so the bet is small and reversible.
  (EARS: IF the proof-of-concept's measured results do not justify
  generalizing, THEN the harness SHALL be able to continue operating on the
  existing bash scripts for every other subsystem with no forced migration.)

### Secondary Decision Drivers

- **SDD-1**: Agents SHOULD be able to query "has anything like this finding
  already been found, in any topic?" before authoring new research, to reduce
  invisible redundant work.
- **SDD-2**: Any search/classification index MUST be a derived, rebuildable
  artifact (like `ontology-map.json` today) — never a committed binary blob,
  and never a required external service at gate time.
- **SDD-3**: The deterministic CI/gate path MUST remain runnable headless,
  with no live agent/LLM session in the loop, matching the harness's
  four-layer split (`docs/explanation/architecture.md`) between the
  deterministic engine and the agent enrichment layer.

## Considered Options

### Option 1: Status quo — keep bash + jq/yq/ajv as-is

**Description**: No engineering investment; the current scripts continue
unchanged.

**Advantages**:

- Zero effort, zero new toolchain, zero risk of regressing the 144
  `verify.sh` assertions / 41 evals that pass today.
- Preserves full line-by-line auditability of the ontology subsystem by any
  contributor with no compiled-language literacy required.

**Disadvantages**:

- CI/gate runtime keeps scaling linearly with corpus size; already measured
  at 20+ minutes on a real 4296-finding corpus, with no ceiling.
- No cross-topic recall is ever built (SDD-1) without a larger investment
  later anyway, so this option defers the eventual cost rather than avoiding
  it.

**Risk Assessment:**

- *Technical Risk*: High and compounding — this template's own vendored
  example corpus is small enough to never surface the problem in
  template-level testing, so regressions here are invisible until an
  instance grows.
- *Schedule Risk*: None (no work).
- *Ecosystem Risk*: Defers rather than avoids the eventual cost of building
  cross-topic recall.

### Option 2: Big-bang rewrite of all ~20 scripts

**Description**: Replace every bash script in the
ontology/reports/concordance/synthesis subsystem with a single compiled
engine (Go or Rust) + CLI + MCP server + search index, in one project.

**Advantages**:

- Every subsystem gets PDD-1's runtime benefit and SDD-1's cross-topic
  recall at once, with no interim period of two coexisting implementations
  (bash + compiled) anywhere in the harness, unlike Option 3's explicit
  coexistence risk.
- One coherent engine design across the whole ontology/reports/concordance/
  synthesis subsystem, instead of a patchwork of separately-scoped
  migrations decided one at a time over an unknown number of future ADRs.

**Disadvantages**:

- Much larger surface to get right in one pass, including the fail-closed
  contracts of `check-shippable-typing.sh`, `reconcile-session.sh`,
  `build-concordance.sh`, `validate-concordance.sh`, and
  `synthesize-corpus.sh`, each with their own eval coverage today.
- Long time-to-first-value; nothing ships until the whole subsystem is
  reimplemented and re-proven against all existing gates — PDD-1 and PDD-2
  are not measurable until the entire rewrite is done, unlike Option 3 which
  measures them after one bounded pair.

**Risk Assessment:**

- *Technical Risk*: High — a much larger surface to get right in one pass,
  spanning every fail-closed contract in the subsystem at once.
- *Schedule Risk*: High — long time-to-first-value; nothing ships until the
  whole subsystem is reimplemented and re-proven.
- *Ecosystem Risk*: Contradicts this repo's own "Surgical Changes" convention
  (`CLAUDE.md`) — a large, all-at-once replacement is the shape of change
  this project's own conventions actively discourage.

### Option 3: Scoped proof-of-concept on ontology-review/resolve-ontology only

Build the compiled engine for **only** the ontology-review/resolve-ontology
pair — the one subsystem with a measured, quantified problem (PDD-1) — exposed
as both a CLI (a drop-in replacement callable from the same places the bash
scripts are called today) and an MCP server (`search`, `suggest_type`,
`find_similar`, `corpus_stats` tools) backed by a SQLite FTS5 full-text index
plus a flat embedding store for semantic similarity. Both index choices are
zero-external-service and rebuildable-as-derived-artifact, matching SDD-2.
Prove gate-parity (PDD-2) and measure the actual speedup (PDD-1) before any
decision to generalize.

**Advantages**:

- Directly targets the one subsystem with a measured, quantified problem
  (PDD-1), with a bounded, well-defined test/eval surface (144 assertions,
  41 evals) to prove parity against.
- Small, reversible bet: the rest of the harness's ~18 other scripts are
  entirely unaffected during the proof phase, matching this repo's
  "Surgical Changes" and change-driven versioning conventions.
- Opens genuine cross-topic recall (SDD-1) via the MCP server, which no
  other option delivers without also solving PDD-1.

**Disadvantages**:

- Two implementations of the same logic (bash reference, compiled
  proof-of-concept) coexist during the proof phase and must not silently
  drift from each other.
- Introduces a compiled-language toolchain dependency for this one
  subsystem, where none existed before.

**Risk Assessment:**

- *Technical Risk*: Moderate — the coexistence risk above; mitigated by
  keeping the bash version as the reference implementation and source of
  truth for eval fixtures until the compiled version has equal test
  coverage, only then retiring it.
- *Schedule Risk*: Low — small, bounded scope with an existing, well-defined
  test/eval surface to prove parity against.
- *Ecosystem Risk*: Low — matches this repo's own "Surgical Changes" and
  change-driven versioning conventions; the rest of the harness's scripts
  are entirely unaffected during the proof phase.

### Option 4: MCP-only, no CLI, no compiled deterministic core

**Description**: Expose semantic search/classification only as MCP tools for
agent-time use; leave every deterministic bash gate untouched.

**Advantages**:

- Fast to ship; no compiled toolchain required at all.
- Gives agents a semantic-search convenience immediately, without touching
  any existing gate.

**Disadvantages**:

- Does not address PDD-1 at all — the measured 20-minute CI/gate cost is
  untouched, since it lives entirely in the deterministic path this option
  leaves alone.
- Architecturally mismatched: MCP tools require a live agent session and
  cannot run inside `verify.sh` or a CI job at all (SDD-3).

**Risk Assessment:**

- *Technical Risk*: Moderate, independent of the driver mismatch — an
  MCP-only server still carries a real embedding-model dependency choice
  (same as Option 3's), plus a genuine index-staleness risk unique to this
  option: with no CLI `review` step to force a rebuild, nothing re-indexes
  the corpus as findings change unless the MCP server itself watches
  `reports/` for changes, adding file-watching complexity this option's
  simplicity was supposed to avoid.
- *Schedule Risk*: Low to ship an initial version, but does not address
  PDD-1 at all — the measured 20-minute CI/gate cost is untouched, since it
  lives entirely in the deterministic path this option leaves alone.
- *Ecosystem Risk*: High — the harness's four-layer design (`ADR-0001`)
  requires the deterministic harness-services layer (where
  `resolve-ontology.sh`/`ontology-review.sh` live) to run headless; an
  MCP-only approach cannot be that layer, so this option can only ever be an
  agent-time convenience layered on top of Option 1's unresolved cost, never
  a replacement for it.

## Decision

Adopt **Option 3**: a scoped proof-of-concept compiled engine for the
ontology-review/resolve-ontology pair only, exposed as both a CLI and an MCP
server, backed by a SQLite FTS5 index and a flat embedding store.

Implementation specifics for the proof-of-concept phase:

- The engine reimplements exactly the behavior of `resolve-ontology.sh` and
  `ontology-review.sh` (including the `--followup` backlog from
  research-harness-template#251) as a library, with a CLI frontend that is a
  drop-in replacement for the existing bash entry points (same flags, same
  exit codes, same stdout table/summary format) and an MCP server frontend
  exposing `search`, `suggest_type`, `find_similar`, and `corpus_stats` as
  tools.
- Language choice (Go vs. Rust) and index technology are implementation
  details for the accompanying feature-spec and architecture doc, not this
  decision — this ADR fixes the *shape* (scoped CLI+MCP engine, not a
  big-bang rewrite, not MCP-only), not the *stack*.
- Success is measured, not assumed: PDD-1 and PDD-2 are the acceptance bar
  for the proof-of-concept. A follow-up decision on whether/how to generalize
  to the rest of the harness's scripts is explicitly out of scope for this
  ADR and is gated on those measurements.

## Consequences

### Positive

- Directly measured problem (20+ minute corpus-wide reviews) gets a bounded,
  scoped fix instead of an indefinite deferral or an oversized rewrite.
- Opens a real cross-topic recall capability (SDD-1) that the static
  `concordance.json` snapshot cannot provide, without requiring a live agent
  session for the deterministic gate path.
- Small, reversible bet: if the proof-of-concept underperforms or proves not
  worth the added toolchain (a compiled language now required for this one
  subsystem), the rest of the harness is entirely unaffected and the bash
  scripts remain the fallback.

### Negative

- A compiled toolchain (Go or Rust) becomes a build-time dependency for this
  one subsystem, breaking — for this subsystem only — the template's current
  "no compiled build step" posture. This is a real cost this ADR accepts
  deliberately, scoped to one subsystem, not the whole harness.
- Two implementations of the same logic exist during the proof phase (bash
  reference + compiled proof-of-concept); until the compiled version reaches
  equal test coverage, changes to the ontology contract must be made in both
  places or risk drift.
- The MCP server surface (`search`, `suggest_type`, `find_similar`,
  `corpus_stats`) is new agent-facing behavior that needs its own usage
  guidance so agents don't over-trust a similarity match as a stamped fact —
  `suggest_type`'s output is a hypothesis to confirm, exactly like the
  existing `basis: "discovery"` guess it's meant to improve on.

### Neutral

- The choice of Go vs. Rust, and the exact index technology, are deferred to
  the accompanying feature-spec/architecture doc — this decision does not
  fix them.
- No existing bash script outside the ontology-review/resolve-ontology pair
  is touched by this decision.

## Decision Outcome

The scoped proof-of-concept meets PDD-1 and PDD-2 if, when measured:
full-corpus `ontology-review` against the same 4296-finding real corpus
completes within the 5-minute bound, and the 144 `verify.sh` assertions /
41 `evals/run-evals.sh` evals covering this pair pass unchanged when pointed
at the new engine's CLI. Mitigation for the coexistence risk (two
implementations): the bash scripts remain canonical and un-retired until
the compiled engine has demonstrated equal behavior against the full existing
test/eval surface, not merely a subset.

## Related Decisions

- [ADR-0001: Four-layer single-repository architecture](0001-four-layer-single-repository-architecture.md) — this decision lives inside the "harness services" layer; the deterministic-engine-vs-agent-layer split this ADR relies on (Option 4's rejection) is that same boundary.
- [ADR-0011: Fail-closed ontology-completeness gate](0011-fail-closed-ontology-completeness-gate.md) — the compiled engine must not regress this gate's fail-closed contract.
- [ADR-0012: On-demand ontology vendoring](0012-on-demand-ontology-vendoring.md) — same ontology subsystem; the compiled engine must continue to honor vendored/pinned ontology packs the same way `resolve-ontology.sh` does today.

## Links

- research-harness-template#251 (`feat/ontology-discovery-followup`) — the correctness fix in this same subsystem that motivated closer inspection of it.
- `docs/explanation/architecture.md` — the four-layer architecture this decision must fit inside.

## More Information

The accompanying `docs/proposals/ontology-engine/` document set (PRD,
feature-spec, and architecture doc) covers the concrete scope, success
metrics, and technical design of the proof-of-concept this ADR authorizes
proposing.

## Audit

### 2026-07-01

**Status:** Pending

**Findings:**

| Finding | Files | Lines | Assessment |
| --- | --- | --- | --- |
| ADR drafted from measured session findings | - | - | pending review |

**Summary:** ADR drafted from this session's measured findings (a 20+ minute
corpus-wide `ontology-review.sh` scan against a real 4296-finding corpus, and
15/36 discovery-only findings in the template's own bundled example topic)
and the ideation discussion of a CLI+MCP engine.

**Action Required:** zircote to review and change `status` to `accepted` (or
open a follow-up ADR to reject/amend) before the accompanying feature-spec's
scope is treated as authorized work.
