---
name: graph
description: "Build, refresh, and query the MIF-native knowledge graph — the typed substrate of concepts and entities (all urn:mif: ids) linked by MIF relationships and mentions. Use this skill when the user asks about relationships between findings, what connects two concepts or entities, entity overlap, or wants a visual map. Triggers on 'what connects', 'how are these related', 'show graph', 'knowledge graph', 'visualize research', 'rebuild the graph', 'entity overlap', 'shared between'. With --concordance, the same verbs operate on the corpus-wide ontological spine spanning ALL topics (build/validate/query reports/concordance.json) — triggers on 'concordance', 'across topics', 'whole corpus', 'cross-topic', 'ontological spine', 'world view of knowledge'. The graph is derived from MIF entities and relations, never from tags."
version: 0.3.0
argument-hint: "[--concordance] [--build] [--validate] [--viz] [--stats] [--node <urn:mif:id>] [--between <id1> <id2>] [--kind concept|entity]"
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

Render a standalone, dependency-free HTML view. The HTML is an **ephemeral**
artifact: with no output path it renders to a `mktemp` file **outside** the
project tree and prints the path (`build-graph-viz: wrote <path>`) — report that
path to the user. Never write it into `reports/`, which dirties the tree and
blocks `copier update`.

```bash
bash scripts/build-graph-viz.sh <knowledge-graph.json>   # -> <mktemp-dir>/knowledge-graph.html (reported)
```

Only when the user **explicitly asks to persist** the viz, pass an in-repo
output path as the second argument:

```bash
bash scripts/build-graph-viz.sh <knowledge-graph.json> reports/<topic>/knowledge-graph.html
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

## `--concordance` — query the cross-topic ontological spine (SPEC §8d)

The **concordance** is the corpus-wide counterpart of the per-topic graph: one unified,
ontology-typed graph over **every** topic — concept nodes stamped with their ontology
type + verdict, entities merged across topics by `urn:mif:` @id, falsified flagged (not
excluded). `--concordance` makes every verb below operate on `reports/concordance.json`
instead of a single topic's `knowledge-graph.json`; the node/edge shape is the same, so
`--stats`, `--node`, `--between`, and `--kind` work unchanged (plus the richer
`verdict` / `topics` / `ontology` fields). Two extra verbs are concordance-only:

- **`--concordance --build`** — rebuild the spine over the whole corpus:

  ```bash
  scripts/build-concordance.sh                 # -> reports/concordance.json (all topics)
  ```

- **`--concordance --validate`** — fail-closed ontology conformance (every node
  `entityType` and relationship `type` must be ontology-declared for its topic, with
  `from`/`to` domains satisfied; `gate_m13` enforces this):

  ```bash
  scripts/validate-concordance.sh reports/concordance.json
  ```

- **`--concordance --stats`** (or `--concordance` alone) — corpus-wide rollup,
  including the spine-specific breakdowns by verdict and topic:

  ```bash
  jq '{ nodes:(.nodes|length), edges:(.edges|length),
        by_kind:    [ .nodes|group_by(.kind)[]    | { kind:.[0].kind, count:length } ],
        by_verdict: [ .nodes|map(select(.kind=="concept"))|group_by(.verdict)[]
                      | { verdict:(.[0].verdict//"untyped"), count:length } ],
        by_topic:   [ .nodes|map(.topics[])|group_by(.)[] | { topic:.[0], count:length } ] }' \
    reports/concordance.json
  ```

- **`--concordance --node <urn>` / `--between <id1> <id2>` / `--kind concept|entity`**
  — identical jq to the per-topic verbs above, but against `reports/concordance.json`.
  Because entities are merged by @id, a `--node` neighborhood here spans every topic
  that references it (`.topics`), and `--between` reveals cross-topic links.

### Coverage gaps → suggest `/ontology-review`

The build never stops (untyped findings are valid nodes), but a topic with **no bound
ontology** — or one whose findings carry **domain types nothing declares** — leaves the
spine under-typed. After a `--concordance` build or validate, surface these and point the
user at the remedy; do **not** silently ship an under-typed spine.

- **Untyped concept nodes** (topics that would benefit from a binding) — list the topics
  with any untyped finding:

  ```bash
  jq -r '[ .nodes[] | select(.kind=="concept" and .entityType==null) | .topics[] ] | unique[]' \
    reports/concordance.json
  ```

- **Hard conformance failures** — `--concordance --validate` already fails closed and its
  message **names the topic and the fix** (`… not declared by a bound ontology — fix:
  /ontology-review --topic <id> --enrich`).

For each gap, recommend to the user: **run `/ontology-review --topic <id> --enrich`** to
bind/enrich that topic's ontology, then rebuild with `--concordance --build`. (A core-only
topic whose findings are all generically typed or untyped is *not* a gap — generic typing
is valid; only unresolved **domain** types are.)

If `reports/concordance.json` is missing, build it first (`--concordance --build`). See
`docs/explanation/ontological-spine.md`.
