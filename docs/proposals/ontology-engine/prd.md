---
id: prd-ontology-engine
type: semantic
created: '2026-07-01T00:00:00Z'
modified: '2026-07-01T00:00:00Z'
namespace: proposals/ontology-engine
title: 'PRD: Compiled Ontology Engine Proof-of-Concept'
tags:
  - prd
  - ontology
  - performance
  - search
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-01T00:00:00Z'
  ttl: P6M
  recordedAt: '2026-07-01T00:00:00Z'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  trustLevel: high_confidence
  wasDerivedFrom:
    '@id': urn:mif:concept:research-harness-template:pr-251-ontology-discovery-followup
    '@type': prov:Entity
citations:
  - '@type': Citation
    citationType: dataset
    citationRole: supports
    title: 'Measured full-corpus ontology-review.sh run, 4296 findings, 36 topics'
    url: 'https://github.com/zircote/research-harness'
    date: '2026-07-01'
relationships:
  - type: realized-by
    target: /docs/proposals/ontology-engine/feature-spec.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: Compiled Ontology Engine Proof-of-Concept
  entity_type: product-requirements
---

# PRD: Compiled Ontology Engine Proof-of-Concept

## Problem Statement

The research-harness-template's ontology subsystem — `scripts/resolve-ontology.sh`
and `scripts/ontology-review.sh`, which review and classify MIF findings against
domain ontologies — is a collage of bash scripts that spawn `yq`, `jq`, and `ajv`
as separate subprocesses **per finding**. Measured directly this session: a
full-corpus `ontology-review.sh` run against a real 4296-finding, 36-topic corpus
(`~/Projects/zircote/research-harness`) took over 20 minutes. This is a
process-spawn cost, not an algorithmic one, and it scales with corpus size with no
ceiling — every instantiated harness's corpus only grows, so this gets worse, not
better, over time.

The subsystem's only cross-topic query surface today is `reports/concordance.json`
(built by `scripts/build-concordance.sh`, summarized by
`scripts/synthesize-corpus.sh`'s atlas): a **static**, point-in-time snapshot. An
agent authoring a new finding has no way to ask "has anything like this already
been found, in any topic?" before writing it — so redundant research across
topics is invisible until a human happens to notice it by reading the corpus.

The subsystem's fallback classifier (a regex `content_pattern` matcher in
`resolve-ontology.sh`, used when a finding carries no `entity` block) is a blunt
instrument: it either matches ambiguously (refuses to classify) or not at all,
with no notion of "similar to" a known type. Until this session's fix
(research-harness-template#251), its guesses were also silently miscounted as
"typed" in coverage reports, masking real gaps — measured at 63 of 4296 findings
corpus-wide (`~/Projects/zircote/research-harness`, direct scan during this
session, not from PR #251's own body), concentrated as high as 16 of 26 findings
(62%) in one individual topic (`backstage-internal-developer-portal`), genuinely
unstamped on disk. The template's own bundled example topic showed the same
pattern at smaller scale: 15 of 36 findings discovery-only (the figure PR #251
itself cites).

## Goals & Success Metrics

- Full-corpus `ontology-review` completes in under 5 minutes against the same
  4296-finding real corpus that currently takes 20+ minutes — at least a 4x
  speedup.
- Zero regressions: all 144 `scripts/verify.sh` assertions and 41
  `evals/run-evals.sh` evals that currently exercise
  `resolve-ontology.sh`/`ontology-review.sh` pass identically when re-pointed at
  the new engine's CLI.
- A genuinely new capability, not just speed: an agent can query "find findings
  similar to X, across every topic" and get a ranked result in interactive time
  (sub-second to low-single-digit seconds) — a capability that does not exist
  today at any speed, on any corpus size.

## Users / Personas

- **Harness maintainers/contributors** — engineers who maintain
  `research-harness-template` itself and must keep its CI gates (`verify.sh`,
  `evals/run-evals.sh`) fast and green as the template evolves.
- **Instance operators** — engineers who instantiate their own research corpus
  from the template (e.g. a corpus the size of `~/Projects/zircote/research-harness`)
  and run `ontology-review`/`/ontology-review` locally or in their own CI as their
  corpus grows into the thousands of findings.
- **Claude Code agents operating inside an instantiated corpus** — the
  dimension-analyst / report-synthesizer / `/ontology-review --enrich` agents
  that author and retro-classify findings, and would benefit from a live
  "has this been found before" query before writing new research.

## Requirements

1. WHEN `ontology-review` (or its engine equivalent) runs against a 4296-finding
   corpus, THE SYSTEM SHALL complete within 5 minutes.
2. WHEN the existing `scripts/verify.sh` and `evals/run-evals.sh` suites are run
   against the new engine's CLI in place of the bash scripts, THE SYSTEM SHALL
   produce identical pass/fail outcomes for every assertion/eval covering the
   ontology-review/resolve-ontology pair.
3. WHEN an agent queries the engine for findings similar to a given piece of
   text, THE SYSTEM SHALL return a ranked list of candidate findings (with their
   topic, `finding_id`, and a similarity score) across every topic in the corpus,
   not just the current topic.
4. IF the new engine cannot be built or is unavailable, THEN THE SYSTEM SHALL
   continue to operate correctly on the existing bash scripts with no forced
   migration — the proof-of-concept SHALL NOT become a hard dependency until it
   has proven itself against requirements 1 and 2.
5. WHILE the proof-of-concept phase is active, THE SYSTEM SHALL keep the bash
   scripts as the reference implementation for every ontology-review/
   resolve-ontology behavior the new engine claims to replicate.

## Scope & Non-Goals

- **In scope**: a compiled engine covering exactly the `ontology-review.sh` /
  `resolve-ontology.sh` pair (including the `--followup` backlog from PR #251),
  exposed as both a CLI (drop-in for existing callers) and an MCP server
  (similarity search, type suggestion, corpus stats).
- **Non-goals**:
  - Rewriting any of the harness's other ~18 bash scripts (concordance,
    synthesis, session reconciliation, packs, etc.). See ADR-0014 for the
    explicit rejection of a big-bang rewrite.
  - Retiring the bash scripts during this phase — they remain the fallback and
    reference implementation until the engine has proven equal test coverage.
  - Changing the fail-closed deterministic gate contract (ADR-0011) in any way
    — the engine must reproduce it exactly, not relax or reinterpret it.
  - Building a general-purpose vector database or external search service —
    the index is a derived, rebuildable, zero-external-service artifact (see
    ADR-0014, SDD-2).

This PRD elaborates on the decision already recorded in
`docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md`; it does not re-litigate
the options considered there (status quo, big-bang rewrite, MCP-only) — that
comparison belongs to the ADR. This PRD's job is problem framing, success
metrics, and non-goals for the scoped proof-of-concept phase ADR-0014
authorizes proposing.

## Milestones

- **M1 — Parity proof**: the compiled engine's CLI reproduces
  `resolve-ontology.sh`/`ontology-review.sh` behavior exactly enough that all
  144 `verify.sh` assertions and 41 evals pass unchanged against it.
- **M2 — Performance proof**: the same engine, run against the real
  4296-finding corpus, completes full-corpus review in under 5 minutes.
- **M3 — Search proof**: the MCP server's similarity-search tool returns
  correct, ranked cross-topic results for a held-out set of known-similar
  finding pairs.
- **M4 — Generalization decision**: a follow-up decision (out of scope for this
  PRD and for ADR-0014) on whether to extend the engine to the harness's other
  bash scripts, made only after M1-M3 are measured.

## Open Questions

- Should the engine ship inside the template repo itself (a new build-time
  dependency for contributors who touch this subsystem), or as a separate,
  optionally-vendored tool an instance can adopt independently? This affects
  how the template's "no compiled build step" posture is scoped.
- What is the actual corpus-size distribution across real instantiated
  harnesses? The 4296-finding corpus used for measurement here is one data
  point; success metrics may need revisiting against a smaller or larger
  reference corpus once more instances exist.
- How long should the bash reference implementation be kept in parallel with
  the engine before retirement is even considered — is there a concrete
  test-coverage-equality bar that triggers that conversation, or is it a
  judgment call each time?
