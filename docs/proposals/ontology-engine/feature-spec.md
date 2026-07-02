---
id: feature-ontology-engine-poc
type: semantic
created: '2026-07-01T00:00:00Z'
modified: '2026-07-01T00:00:00Z'
namespace: spec/feature/ontology-engine
title: Compiled Ontology Engine Proof-of-Concept (CLI + MCP)
tags:
  - feature-spec
  - ontology
  - cli
  - mcp
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-01T00:00:00Z'
  ttl: P6M
  recordedAt: '2026-07-01T00:00:00Z'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  trustLevel: high_confidence
relationships:
  - type: derived-from
    target: /docs/proposals/ontology-engine/prd.md
  - type: depends-on
    target: /docs/proposals/ontology-engine/ai-architecture-doc.md
ontology:
  '@type': OntologyReference
  id: mif-docs
  version: 1.0.0
  uri: https://mif-spec.dev/ontologies/mif-docs
entity:
  name: Compiled Ontology Engine Proof-of-Concept
  entity_type: feature-specification
---

# Compiled Ontology Engine Proof-of-Concept (CLI + MCP)

## Overview

`scripts/ontology-review.sh` and `scripts/resolve-ontology.sh` review and
classify MIF findings against domain ontologies by spawning `yq`, `jq`, and
`ajv` as separate subprocesses per finding — measured at 20+ minutes for a
real 4296-finding corpus. This feature builds a compiled proof-of-concept
engine that reimplements exactly the observable behavior of that pair
(including the `--followup` backlog and STAMPED/DISCOVERY/UNTYPED/INVALID
coverage split from research-harness-template#251), as a CLI (drop-in for
existing callers) and an MCP server (`search`, `suggest_type`, `find_similar`,
`corpus_stats`). Scope is exactly this one pair — not the harness's other
bash scripts (see `docs/adr/0014-compiled-ontology-engine-cli-and-mcp.md` for
why the scope stops here) — and the bash scripts remain the reference
implementation and fallback throughout this proof-of-concept phase.

## Acceptance Criteria

1. When the engine's `review` subcommand runs against a synthetic fixture
   corpus of at least 4296 findings across 36 topics (generated to match the
   scale of the real corpus used for this session's measurement,
   `~/Projects/zircote/research-harness`, since that corpus is a private path
   not vendored into this repo and unreachable by CI or a future
   implementer), it shall complete in under 5 minutes. The real corpus
   remains the out-of-band reference measurement this bound was derived from,
   verified by the author, not a CI-enforceable input.
2. When any of the 144 `scripts/verify.sh` assertions or 41
   `evals/run-evals.sh` evals that currently invoke
   `scripts/ontology-review.sh` or `scripts/resolve-ontology.sh` are
   re-pointed at the engine's CLI with no other change, they shall pass with
   identical outcomes — same exit codes, same stdout table/summary format,
   same `--followup` backlog JSON shape.
3. When an agent calls the `find_similar` MCP tool with a finding's content,
   the engine shall return results ranked by similarity score.
4. When an agent calls the `find_similar` MCP tool with a finding's content,
   the engine shall not restrict results to the querying finding's own topic.
5. When an agent calls the `find_similar` MCP tool with a finding's content,
   the engine shall include each result's topic and `finding_id`.
6. When an agent calls the `suggest_type` MCP tool, the engine shall return
   ranked candidate entity types with similarity scores.
7. When an agent calls the `suggest_type` MCP tool, the engine shall not
   write anything to any finding file — the MCP server process shall have no
   write access to `reports/`.
8. If the engine binary is missing or fails to start, then the existing bash
   scripts shall continue to operate correctly with no change in behavior —
   this proof-of-concept introduces no hard dependency.
9. If two engine invocations are started against the same corpus
   concurrently, then the second invocation shall fail closed with a clear
   "another review is in progress" error rather than proceeding to write.

## Design

- **CLI subcommands** mirror today's flags exactly, so callers change only
  the binary name:
  - `<engine> review [--topic <id>] [--strict] [--reports-dir <p>] [--config <p>] [--catalog <p>] [--followup <path>]`
  - `<engine> resolve <finding.json> [--topic <id>] [--catalog <p>] [--config <p>] [--map <path>]`
- **Index build**: `<engine> review` builds/refreshes a full-text index
  (over each finding's content fields) and a flat embedding store, as a
  derived, gitignored artifact analogous to `ontology-map.json` but instance-
  local and not committed — e.g. `reports/_meta/search-index.sqlite` and
  `reports/_meta/embeddings.bin`. Rebuilding is the same operation as today's
  "rebuild deterministically from disk" pattern (`ontology-review.sh`'s own
  comment), just against a persistent index instead of a JSON file per topic.
- **Lock file**: `<engine> review` acquires an exclusive lock (e.g.
  `reports/_meta/.review.lock`) for the duration of the run and fails closed
  if it cannot acquire it — the exact concurrency gap this session hit by
  accident, running two `ontology-review.sh` processes in parallel and
  corrupting derived `ontology-map.json` files with no lock to prevent it.
- **MCP server** reads the same index the CLI builds:
  - `search(query: string, limit?: number) -> [{finding_id, topic, snippet, score}]`
    — full-text query.
  - `suggest_type(text: string, topic: string, limit?: number) -> [{entity_type, ontology_id, score}]`
    — embedding similarity against each bound ontology's entity-type
    descriptions; a hypothesis for the `/ontology-review --enrich`
    retro-classification step to confirm, never an auto-write.
  - `find_similar(text: string, limit?: number, exclude_finding_id?: string) -> [{finding_id, topic, score}]`
    — embedding similarity across every topic in the corpus, addressing the
    "has this already been found" gap from the PRD.
  - `corpus_stats() -> {topics: N, findings: N, stamped: N, discovery: N, untyped: N, invalid: N}`
    — the same aggregate `ontology-review.sh`'s summary line reports today,
    read from the index instead of a fresh scan.
  - If the index does not exist (fresh clone, engine never run), every MCP
    tool returns a clear `"index not built — run <engine> review first"`
    error, never an empty/silent result that could be misread as "nothing
    found."

## Edge Cases

- **Zero-finding corpus (fresh instance)**: `<engine> review` produces the
  same "0 topics" output the bash script produces today; every MCP tool
  returns an empty result set, not an error.
- **A finding file that fails to parse (invalid JSON)**: the CLI path
  matches today's fail-closed behavior exactly — counted as invalid/gap,
  never silently skipped. The index-build path skips it from the index with
  a logged warning and continues building the rest of the index; it must not
  abort the whole build over one bad file.
- **Concurrent `<engine> review` invocations on the same corpus**: the second
  invocation fails closed on the lock file with a clear error naming the
  in-progress run, rather than racing to write the same index/map files (the
  exact corruption this session caused by accident with the bash scripts,
  which have no such lock).
- **Engine binary missing or crashes on startup**: existing bash-script
  callers (`.claude/commands/`, `.claude/agents/`, `scripts/verify.sh`,
  `evals/run-evals.sh`) continue working unmodified — this proof-of-concept
  phase introduces no hard dependency on the engine existing.
- **`suggest_type`/`find_similar` called before any index exists**: returns
  the "index not built" error described above, not a stale or empty
  false-negative result.
