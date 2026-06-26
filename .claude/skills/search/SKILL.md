---
name: search
description: "Search the MIF research index — find findings by free-text query or by structured filters over the index fields (dimension, tags, namespace, verdict). Use this skill when the user wants to find research findings, look up what is known about a subject, query findings, or asks 'what do I have on X', 'find findings about Y', 'search research for Z', 'what research', 'what findings'. Reads the projected index, not raw tag files."
version: 0.3.0
argument-hint: "<query> [--lex|--sem] [--tag <tag>] [--namespace <ns>] [--dimension <dim>] [--verdict <v>] [--limit <N>]"
allowed-tools: Read, Bash, Grep, Glob
---

# search — query the MIF research index

Find findings across the corpus. Each entry in `research-index.json` is a flat
projection of one MIF finding, carrying exactly:

```json
{ "id": "urn:mif:...", "title": "...", "namespace": "...",
  "dimension": "...", "tags": ["..."], "verdict": "...", "citations": 1 }
```

The index is reproducible from the MIF findings at any time; it is **not** a
tag-derived recomputation. Rebuild it with
`bash scripts/build-index.sh <findings-dir>` if it is missing or stale.

## Backends

- **lexical (`jq`)** — the default and only required backend. Filters and
  free-text matching run with `jq` over the index fields. Always available.
- **semantic (optional)** — if an external semantic-search backend is wired in
  for this clone, it can rank findings by meaning over the same id set, then the
  results are looked up in the index by id. Treat it as an optional accelerator,
  never a dependency: when absent, fall back to lexical `--lex` and say so.

## Arguments

- **Free text** — words matched against `title` + `tags` (lexical by default)
- `--lex` — lexical only (the default; explicit form)
- `--sem` — request the optional semantic backend; fall back to `--lex` if absent
- `--tag <tag>` — findings carrying this tag
- `--namespace <ns>` — scope to one MIF namespace (one topic)
- `--dimension <dim>` — filter by a config-declared dimension
- `--verdict <v>` — filter by verification verdict (e.g. `survived`, `weakened`)
- `--limit <N>` — max results (default: 20)
- No arguments — show an index summary

## Lexical search and filters

Build the `select()` from whichever flags are present, then sort and cap:

```bash
jq --arg q "QUERY" --arg tag "TAG" --arg ns "NS" \
   --arg dim "DIM" --arg v "VERDICT" '
  [ .findings[]
    | select($q == "" or ((.title + " " + (.tags | join(" "))) | ascii_downcase | contains($q | ascii_downcase)))
    | select($tag == "" or (.tags | index($tag)))
    | select($ns  == "" or .namespace == $ns)
    | select($dim == "" or .dimension == $dim)
    | select($v   == "" or .verdict == $v) ]
  | .[0:LIMIT]
' reports/_meta/sample-session/research-index.json
```

Pass `""` for any flag the user did not supply. Point the path at the active
topic's index, or at the sample (`reports/_meta/sample-session/`) when exploring.

## Index summary (no arguments)

```bash
jq '{ count,
  by_dimension: [ .findings | group_by(.dimension)[] | { dimension: .[0].dimension, count: length } ],
  by_verdict:   [ .findings | group_by(.verdict)[]   | { verdict: .[0].verdict, count: length } ],
  namespaces:   [ .findings | map(.namespace) | unique[] ] }' \
  reports/_meta/sample-session/research-index.json
```

## Output format

Present each finding as:

```text
**<title>** (<namespace> / <dimension>)
Verdict: <verdict> | Citations: <citations>
Tags: <tags joined>
id: <id>
```

Group by namespace when results span multiple topics. End with
"Showing N of M findings."

## Handoffs

| Need | Route to |
| --- | --- |
| Coverage gaps, clusters, stale findings | `/discover` |
| Relationships between findings/entities | `/graph` |
| Reason about or stress-test the evidence | `/lab` |
| Adversarial web verification of a claim | `/falsify` |

## Prerequisites

- `research-index.json` for the active corpus. If missing:
  `bash scripts/build-index.sh <findings-dir>`.

## Examples

```text
/search update propagation
/search --tag distribution --verdict survived
/search --dimension technical --namespace harness/example-topic
/search --sem "living template"
/search
```
