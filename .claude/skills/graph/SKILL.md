---
name: graph
description: "Build, refresh, and query the MIF-native knowledge graph — the typed substrate of concepts and entities (all urn:mif: ids) linked by MIF relationships and mentions. Use this skill when the user asks about relationships between findings, what connects two concepts or entities, entity overlap, or wants a visual map. Triggers on 'what connects', 'how are these related', 'show graph', 'knowledge graph', 'visualize research', 'rebuild the graph', 'entity overlap', 'shared between'. The graph is derived from MIF entities and relations, never from tags."
version: 1.0.0
argument-hint: "[--build] [--viz] [--stats] [--node <urn:mif:id>] [--between <id1> <id2>] [--kind concept|entity]"
allowed-tools: Read, Bash, Grep, Glob
---

# graph — the MIF-native knowledge graph

The knowledge graph maps the corpus as a typed substrate. It is built **from the
MIF findings**, not from tag co-occurrence:

- **Nodes** — one `concept` node per finding (`@id`) and one `entity` node per
  referenced MIF `EntityReference` (`entities[].entity.@id`), deduplicated.
  Every node id is a `urn:mif:` identifier.
- **Edges** — typed MIF `relationships[]` (e.g. `supports`, `contradicts`,
  `derived-from`) carried as `via: "relationship"`, plus `mentions` edges from a
  finding to each entity it references, carried as `via: "entity"`.

There is no separate tag-derived recompute path. The acceptance gate
(`scripts/assert-graph-mif.sh`) proves every node and edge traces to a `urn:mif:`
id and that the graph uses relationship/entity edges, not bare tag strings.

## Build and refresh

```bash
bash scripts/build-graph.sh <findings-dir>          # -> knowledge-graph.json
bash scripts/assert-graph-mif.sh <knowledge-graph.json>   # prove MIF-native
```

The build is a pure projection of the MIF findings — safe to re-run any time a
finding is added or changed.

## Visualization

Render a standalone, dependency-free HTML view:

```bash
bash scripts/build-graph-viz.sh <knowledge-graph.json>   # -> knowledge-graph.html
```

## Querying

The graph is small enough to load whole with `jq`. Use the sample at
`reports/_meta/sample-session/knowledge-graph.json` when exploring.

### `--stats` (or no arguments)

```bash
jq '{ nodes: (.nodes | length), edges: (.edges | length),
  by_kind: [ .nodes | group_by(.kind)[] | { kind: .[0].kind, count: length } ],
  by_edge_type: [ .edges | group_by(.type)[] | { type: .[0].type, count: length } ] }' \
  reports/_meta/sample-session/knowledge-graph.json
```

Also report the most-connected nodes (by degree).

### `--node <urn:mif:id>`

All edges where the node is source or target — its neighborhood:

```bash
jq --arg n "NODE_ID" '
  { node: $n,
    out: [ .edges[] | select(.source == $n) | { type, target, via } ],
    in:  [ .edges[] | select(.target == $n) | { type, source: .source, via } ] }' \
  reports/_meta/sample-session/knowledge-graph.json
```

### `--between <id1> <id2>`

What links two nodes: direct typed edges either way, and shared neighbors
(entities both findings mention, or concepts both relate to):

```bash
jq --arg a "ID1" --arg b "ID2" '
  { direct: [ .edges[] | select((.source==$a and .target==$b) or (.source==$b and .target==$a)) ],
    shared: ( [ .edges[] | select(.source==$a) | .target ]
              - ([ .edges[] | select(.source==$a) | .target ] - [ .edges[] | select(.source==$b) | .target ]) ) }' \
  reports/_meta/sample-session/knowledge-graph.json
```

### `--kind concept|entity`

List all nodes of that kind with their degree.

### Natural-language questions

Parse the question for concept titles or entity names, match them to node
`label`s, look up the ids, and traverse. Answer conversationally, resolving each
concept node back to its finding for context.

## Prerequisites

- `knowledge-graph.json` for the corpus. If missing:
  `bash scripts/build-graph.sh <findings-dir>`.

## Examples

```text
/graph --stats
/graph --build reports/_meta/sample-session/findings
/graph --node urn:mif:entity:technology:copier
/graph --between urn:mif:concept:harness:kg-copier-0001 urn:mif:concept:harness:kg-distribution-0003
/graph --kind entity
/graph --viz
```
