---
name: topics
description: "List the registered research topics from the harness manifest, each with its MIF namespace and a finding/verdict rollup from the index. Use this skill when the user asks 'what topics do I have', 'list topics', 'show the registry', 'what am I researching', 'topic status', or wants an overview of the corpus by topic. Reads harness.config.json topics[] over the MIF substrate."
version: 1.0.0
argument-hint: "[-t <query>] [--status <status>]"
allowed-tools: Read, Bash, Grep, Glob
---

# topics — the research registry

List the topics declared in the harness manifest and roll up what the corpus
holds for each. The registry is `harness.config.json` `topics[]`; each topic
declares an `id`, `title`, MIF `namespace`, and `status`. The per-topic
finding/verdict counts come from the projected index — the same MIF substrate
the other services read.

## Arguments

- No arguments — list every topic with its rollup
- `-t <query>` — resolve a single topic by id, title substring, or namespace and
  print its entry; if nothing matches, reply exactly `Topic "<query>" not found`
  and show the full table
- `--status <status>` — filter to topics with the given status (e.g. `active`)

## Listing

Read the manifest registry:

```bash
jq '.topics[] | { id, title, namespace, status }' harness.config.json
```

Roll up each topic's findings from the index, joined on `namespace`:

```bash
jq -n \
  --slurpfile cfg harness.config.json \
  --slurpfile idx reports/_meta/sample-session/research-index.json '
  ($idx[0].findings | group_by(.namespace)
     | map({ key: .[0].namespace,
             value: { findings: length,
                      verdicts: (group_by(.verdict)
                        | map({ (.[0].verdict // "none"): length }) | add) } })
     | from_entries) as $roll
  | $cfg[0].topics
  | map(. + { rollup: ($roll[.namespace] // { findings: 0, verdicts: {} }) }) '
```

A topic with zero findings is a declared-but-unstarted topic — surface it as
such and suggest `/start <topic>`.

## Output format

Present a table:

```text
| Topic | Namespace | Status | Findings | Verdicts |
| --- | --- | --- | --- | --- |
| Example research topic | harness/example-topic | active | 3 | survived: 3 |
```

End with a one-line summary: "N topics, M with findings."

## Prerequisites

- `harness.config.json` with a `topics[]` registry.
- `research-index.json` for the rollup. If missing:
  `bash scripts/build-index.sh <findings-dir>`. A missing index is not fatal —
  list topics from the manifest and report findings as unknown.

## Examples

```text
/topics
/topics -t example
/topics --status active
```
