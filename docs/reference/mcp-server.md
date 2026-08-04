---
id: reference-mcp-server
type: semantic
created: '2026-07-05T10:16:37-04:00'
modified: '2026-07-12T14:26:33.819Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: mif-rh MCP server"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-05T10:16:37-04:00'
  ttl: P6M
  recordedAt: '2026-07-05T10:16:37-04:00'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ae91b6b6-8d5c-4bea-963d-9e4b7907cf09
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Reference: mif-rh MCP server

`mif-rh-mcp` is a stdio MCP server exposing a read-only view of the
`mif-rh` engine's corpus (ADR-0016/ADR-0020/ADR-0015) to Claude Code
sessions: `search`, `suggest_type`, `find_similar`, and `corpus_stats`. It
has no filesystem write access to `reports/` — every candidate it returns
is a hypothesis for a human or agent to confirm through
`/ontology-review --enrich`, never an auto-stamp. For the CLI binary these
tools wrap, see [../engine-cli/](../engine-cli/).

## Registration

`.mcp.json` at the instance root registers `mif-rh` alongside `mif-mcp`
(`mif-docs-plugin`'s own document-tooling server — see
[../dependencies/](../dependencies/) — unrelated to this page's `mif-rh-mcp`,
scoped here for completeness only):

```json
{
  "mcpServers": {
    "mif-rh": {
      "command": "bin/mif-rh-mcp",
      "args": []
    },
    "mif-mcp": {
      "command": "mif-mcp",
      "args": []
    }
  }
}
```

`bin/mif-rh-mcp` is installed by `scripts/fetch-engine.sh` alongside
`bin/mif-rh-cli` (same release, same attestation verification).

## Prerequisite: the search index

`search` and `find_similar` read a SQLite finding index distinct from
`research-index.json`. Build it with:

```bash
bin/mif-rh-cli review --build-index
```

If the index does not exist, or exists with zero indexed findings (a state
left by mis-recording paths like `review --suggest` or
`suggest-type --record`, which create the same database file without
indexing anything), both tools return an `index-not-built` problem — never
an empty result set. Rebuild the index after large review passes.

## Tools

| Tool | Reads | Writes |
| --- | --- | --- |
| `search` | Finding index | none |
| `suggest_type` | Ontology catalog + config, calibration artifact | none |
| `find_similar` | Finding index, calibration artifact | none |
| `corpus_stats` | Every topic's `ontology-map.json` under `reports_dir` | none |

### search

Full-text search over the `mif-rh` finding index.

#### Parameters

| Field | Type | Description |
| --- | --- | --- |
| `query` | string | The full-text query. |
| `limit` | integer, optional | Maximum number of ranked results. Default `10`. |
| `index_path` | string, optional | Path to the search index. Default `reports/_meta/search-index.sqlite`. |

#### Result

Array of:

| Field | Type | Description |
| --- | --- | --- |
| `finding_id` | string | The matched finding's id. |
| `topic` | string | The finding's topic. |
| `snippet` | string | A matching excerpt. |
| `score` | number | Match score. |

### suggest_type

Suggest candidate entity types for a piece of text, ranked by embedding
similarity to a topic's bound ontologies' entity-type embedding documents
(description + aliases + exemplars), each annotated with a confidence tier
under the corpus's calibration artifact. A hypothesis only — never writes
to `reports/`, at any tier.

#### Parameters

| Field | Type | Description |
| --- | --- | --- |
| `text` | string | The text to classify. |
| `topic` | string | The topic whose bound ontologies supply the candidate entity types. |
| `catalog` | string, optional | Path to the ontology catalog. Default `.claude/enabled-packs.json`. |
| `config` | string, optional | Path to the harness config. Default `harness.config.json`. |
| `root` | string, optional | Base directory ontology catalog `source` paths resolve against. Default the current directory. |
| `limit` | integer, optional | Maximum number of ranked candidates. Default `10`. |
| `calibration` | string, optional | Path to the confidence-calibration artifact. Default `reports/_meta/confidence-calibration.json`; when absent, conservative built-in thresholds apply and results carry `calibrated: false`. |

#### Result

Array of `TypeSuggestion`:

| Field | Type | Description |
| --- | --- | --- |
| `entity_type` | string | The candidate entity type's name. |
| `ontology_id` | string | The ontology declaring it. |
| `score` | number | Raw cosine similarity between the query and the type's positive embedding document. |
| `tier` | string | `auto_classify_eligible` \| `flag_for_review` \| `trigger_expansion`. |
| `margin` | number, optional | The top candidate's lead over the second-best candidate. Present only at rank 0 when a rival exists. |
| `calibrated` | boolean | Whether `tier` came from a real calibration run against the embedding model in use, versus built-in uncalibrated defaults. |
| `negative_demoted` | boolean, optional | `true` when this candidate's query similarity to one of its type's curated `negative_examples` met or exceeded its similarity to the positive embedding document, barring it from `auto_classify_eligible` regardless of raw score. Omitted from the result entirely whenever `false` (including every candidate whose type carries no curated `negative_examples`), so absence and `false` are indistinguishable on the wire. A non-reordering gate: `score` and rank are unaffected. |

### find_similar

Find findings similar to a piece of text, across every topic. Each hit
carries a similarity band under the calibrated floors, deliberately not
the classification tier vocabulary — similarity recall is not a
classification decision.

#### Parameters

| Field | Type | Description |
| --- | --- | --- |
| `text` | string | The text to find similar findings for. |
| `limit` | integer, optional | Maximum number of ranked results. Default `10`. |
| `exclude_finding_id` | string, optional | A finding id to exclude from the results (e.g. the finding whose own content is the query). |
| `index_path` | string, optional | Path to the search index. Default `reports/_meta/search-index.sqlite`. |
| `calibration` | string, optional | Path to the confidence-calibration artifact. Default `reports/_meta/confidence-calibration.json`; when absent, conservative built-in thresholds apply and results carry `calibrated: false`. |

#### Result

Array of:

| Field | Type | Description |
| --- | --- | --- |
| `finding_id` | string | The matched finding's id. |
| `topic` | string | The finding's topic. |
| `score` | number | Cosine similarity. |
| `band` | string | `near_duplicate` \| `related` \| `weak`. |
| `calibrated` | boolean | Whether `band`'s floors came from a real calibration run for the embedding model in use. |

### corpus_stats

Aggregate ontology classification coverage across every reviewed topic —
the same aggregate `ontology-review.sh`'s own summary line reports, read
from each topic's already-written `ontology-map.json` rather than a fresh
classification pass.

#### Parameters

| Field | Type | Description |
| --- | --- | --- |
| `reports_dir` | string, optional | Root `reports/` directory. Default `reports`. |

#### Result

| Field | Type | Description |
| --- | --- | --- |
| `topics` | integer | Topics with a readable `ontology-map.json`. |
| `findings` | integer | Total findings across those topics. |
| `stamped` | integer | Findings with a durable (`declared`/`resolved`) type on disk. |
| `discovery` | integer | Findings typed only by a content-pattern guess, never written back. |
| `untyped` | integer | Findings with no entity/ontology at all. |
| `invalid` | integer | Findings that failed resolution or validation. |

A missing or unreadable `reports_dir` root is an explicit error; an
individual topic whose `ontology-map.json` is missing, unreadable, or
unparsable is silently skipped (an unreviewed or mid-write topic is normal
corpus state).

## Error contract

Every tool failure renders as a compact RFC 9457 `application/problem+json`
envelope (matching `mif-cli`/`mif-mcp`'s own convention), never a thrown
protocol error. Failure modes:

| Problem slug | Status | Cause |
| --- | --- | --- |
| `index-not-built` | 404 | `search`/`find_similar` called before `mif-rh-cli review --build-index` has ever run, or against an index with zero findings. Carries a machine-applicable suggested fix naming the exact command to run. |
| `reports-dir-missing` | 404 | `corpus_stats` pointed at a `reports_dir` that does not exist or cannot be read. |
| `delegated` | 500 | An underlying engine or calibration error, forwarded as-is. |

## `reports/_meta/` artifact shapes

Both are derived, per-corpus data, never authored configuration — neither
is committed by the template. Unknown fields are rejected
(`deny_unknown_fields`) on the calibration artifact; a typo'd key fails
loud rather than silently reverting to defaults.

### confidence-calibration.json

Written by `mif-rh-cli calibrate`; read by `suggest-type`, `review --suggest`,
`find_similar`, and `suggest_type`. Defaults to
`<reports-dir>/_meta/confidence-calibration.json`.

| Field | Type | Description |
| --- | --- | --- |
| `embedding_model` | string | The embedding model these thresholds were calibrated for. |
| `tier1_floor` | number | Minimum top-candidate score for auto-classify eligibility. |
| `tier1_margin` | number | Minimum lead the top candidate must hold over the second-best candidate. |
| `tier2_floor` | number | Minimum score for flag-for-review; below it a score is a trigger-expansion miss. |
| `calibrated` | boolean | Whether these values came from a real calibration run, versus built-in uncalibrated defaults. |
| `negatives_active` | boolean | Whether curated `negative_examples` were among the candidates that scored the samples this artifact was swept from. `false` when no pack scoring a swept sample carries negatives, in which case this run's scoring is byte-identical to the pre-negatives engine. Recorded for audit only: `negative-demotion-v1` is a downstream suggestion-time gate applied regardless of this flag, and it does not affect `tier1_floor`/`tier1_margin`/`tier2_floor`, which are computed from pre-demotion raw scores. |
| `calibrated_at` | string, optional | RFC 3339 timestamp of the calibration run. |
| `sample_size` | integer, optional | Labeled samples the calibration run used. |
| `method` | string, optional | Calibration method identifier (e.g. `stamped-quantile-v1`). |
| `expansion.cluster_similarity` | number | Minimum pairwise cosine similarity every pair of members of one expansion cluster must satisfy (mutual, not chained). Default `0.80`. |
| `expansion.min_cluster_size` | integer | Minimum cluster size before it surfaces as an expansion candidate. Default `3`. |
| `expansion.min_distinct_runs` | integer | Minimum number of distinct runs the cluster's members must span. Default `2`. |

Built-in uncalibrated defaults (used when the file is absent):
`tier1_floor: 0.85`, `tier1_margin: 0.05`, `tier2_floor: 0.60`,
`calibrated: false`.

### suggestions/\<topic\>.json

Written by `mif-rh-cli review --suggest`; read and updated by
`/ontology-review --enrich`. One file per topic, defaulting to
`<reports-dir>/_meta/suggestions/<topic>.json`.

#### SuggestionQueue

| Field | Type | Description |
| --- | --- | --- |
| `topic` | string | The topic this queue belongs to. |
| `entries` | array of `SuggestionEntry` | Queue entries, sorted by `finding_id`. |

#### SuggestionEntry

| Field | Type | Description |
| --- | --- | --- |
| `finding_id` | string | The finding's id. |
| `file` | string, optional | The finding's file path exactly as the producing review listed it — absolute or relative to that review's working directory, not normalized. |
| `basis` | string | Why the finding needed a suggestion: its followup basis (`discovery`, `untyped`, `gap`, ...). |
| `run_id` | string | The run that produced or last refreshed this entry. |
| `candidates` | array of `TypeSuggestion` | Ranked, tier-annotated candidates (see `suggest_type`'s result shape above). |
| `status` | string | `pending` until a human/agent confirms or rejects via `/ontology-review --enrich`. Free-form beyond `pending`; any non-pending value is preserved verbatim on upsert. |

Entries are never deleted; a confirmed candidate still goes through the
normal typing edit and resolve re-stamp, never a direct auto-write. The
queue only grows: entries not re-suggested in a `--topic`-scoped run are
kept even when pending.
