---
name: discover
description: "Discover gaps, clusters, and stale findings across the research corpus — dimensions with thin coverage, concepts and entities that co-occur through graph edges, and findings that are aging or carry a weakened/quarantined verdict. Use this skill when the user asks 'where are my gaps', 'what's stale', 'what clusters exist', 'research coverage', 'what am I missing', 'audit the corpus', 'what needs updating', 'coverage matrix', 'stale findings'."
version: 1.0.0
argument-hint: "[--gaps] [--clusters] [--stale] [--all]"
allowed-tools: Read, Bash, Grep, Glob
---

# discover — gaps, clusters, and stale findings

Audit the corpus for actionable structure. All three analyses derive from the
MIF substrate — the projected index and the MIF-native graph — never from
tag-co-occurrence recomputation.

Data sources:

- `research-index.json` — flat per-finding projection (id, title, namespace,
  dimension, tags, verdict, citations).
- `knowledge-graph.json` — MIF concept/entity nodes and typed `relationships[]`
  - `mentions` edges (all `urn:mif:` ids).
- `harness.config.json` — the authoritative, config-declared `dimensions[]`.

## Arguments

- `--gaps` — dimensions with few or zero findings (against the config taxonomy)
- `--clusters` — concepts/entities that co-occur via graph edges
- `--stale` — findings that are aging or carry a weakened/quarantined verdict
- `--all` — all three (default when no flag is given)

## Coverage gaps

The dimension taxonomy is **config-declared**, never fixed. Read it from
`harness.config.json`, then count index findings per dimension; a dimension with
no (or very few) findings is a gap.

```bash
jq -n \
  --slurpfile cfg harness.config.json \
  --slurpfile idx reports/_meta/sample-session/research-index.json '
  ($idx[0].findings | group_by(.dimension)
     | map({ (.[0].dimension // "unassigned"): length }) | add) as $counts
  | $cfg[0].dimensions
  | map({ dimension: .id, findings: ($counts[.id] // 0), description })'
```

Present as a table; flag any dimension at 0, or far below the corpus mean, and
recommend `/augment <dimension> <topic>` to fill it.

## Clusters

A cluster is a set of findings tied together through the graph — they share a
referenced entity (`mentions` edges to the same `urn:mif:entity:` id) or sit on
a chain of typed relationship edges. Group by shared entity first:

```bash
jq '[ .edges[] | select(.via == "entity")
      | { entity: .target, finding: .source } ]
    | group_by(.entity)
    | map(select(length > 1)
          | { entity: .[0].entity, findings: map(.finding), size: length })
    | sort_by(-.size)' \
  reports/_meta/sample-session/knowledge-graph.json
```

Name each cluster from its shared entity's node `label`. Highlight clusters that
bridge findings of different dimensions — those are the cross-cutting themes.

## Stale findings

Staleness has two independent signals; report both.

1. **Verdict-based (from the index).** Any finding whose `verdict` is `weakened`,
   `falsified`, or `quarantined` is epistemically stale regardless of age:

   ```bash
   jq '[ .findings[] | select(.verdict != "survived" and .verdict != null) ]' \
     reports/_meta/sample-session/research-index.json
   ```

2. **Age-based (from the MIF findings, not the index).** The index carries no
   timestamp; `created` and MIF temporal/decay metadata live in the finding
   files. Read the findings dir to flag old or low-temporal-strength findings:

   ```bash
   jq -r '[ .["@id"], (.created // "n/a") ] | @tsv' \
     reports/_meta/sample-session/findings/*.json | sort -k2
   ```

   Flag the oldest `created` dates (and any decayed temporal strength) for
   re-validation.

Present each stale finding with its id, title, the reason flagged, and a
recommendation: `/update <topic>` to refresh, or `/falsify` to re-test.

## Output format

For `--all`, three headed sections — Coverage gaps, Clusters, Stale findings —
then a one-line summary: "N gaps, M clusters, P stale findings."

## Prerequisites

- `research-index.json` and `knowledge-graph.json` for the corpus, plus the
  findings dir. If missing:
  `bash scripts/build-index.sh <findings-dir> && bash scripts/build-graph.sh <findings-dir>`.

## Examples

```text
/discover
/discover --gaps
/discover --stale
/discover --clusters
```
