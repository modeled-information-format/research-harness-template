---
name: lab
description: "Open an interactive exploration session over the research corpus — traverse MIF relationships from a seed concept or entity, develop and stress-test hypotheses against the finding set, and reason across topics. Use this skill whenever the user wants to discuss, explore, or riff on their research rather than just retrieve it: 'explore topic X', 'what does my research suggest about Y', 'develop a hypothesis about Z', 'interrogate the findings on W', 'think through this with my research', 'brainstorm from the corpus'."
version: 0.1.1
argument-hint: "[--seed <urn:mif:id>] [--hypothesis \"<claim>\"] [--interrogate] [--namespace <ns>]"
allowed-tools: Read, Bash, Grep, Glob, Skill
---

# lab — explore and reason over the corpus

A thinking partner grounded in the MIF substrate. Where `/search` retrieves and
`/discover` audits, this skill *reasons*: it walks the MIF-native graph from a
seed, grounds a conversation in findings, and helps form and test hypotheses.

It stays inside the corpus: it never invents findings, and it treats every
finding as a **pointer to a primary source**, not as ground truth. When a claim
matters, recommend re-reading the cited source.

## Data

A finding is a MIF concept at `reports/<topic>/findings/*.json`: `@id`, `title`,
`content`, `tags`, `entities[]`, typed `relationships[]`, `citations[]`, and
`extensions.harness` (dimension, verification verdict). The graph
(`knowledge-graph.json`) is the navigable index of those concepts and their
edges. Use the sample at `reports/_meta/sample-session/` when exploring.

## Modes

Default is open exploration. The flags are postures, not silos.

- `--seed <id>` — start from a concept/entity and traverse its relationships
- `--hypothesis "<claim>"` — develop and stress-test a falsifiable claim
- `--interrogate` — invert the burden: hunt the corpus's weak points
- `--namespace <ns>` — scope reasoning to one topic

## Traversal from a seed

Walk outward from a seed `urn:mif:` id along the graph's typed edges — one hop
gives the seed's direct neighborhood (supports, contradicts, derived-from,
mentions):

```bash
jq --arg seed "SEED_ID" '
  { seed: $seed,
    out: [ .edges[] | select(.source == $seed) | { type, target, strength, via } ],
    in:  [ .edges[] | select(.target == $seed) | { type, source: .source, via } ] }' \
  reports/_meta/sample-session/knowledge-graph.json
```

Follow `supports`/`derived-from` chains to build the case for an idea, and
`contradicts` edges to find the tension. Resolve each target id back to its
finding (title, content, citations) before discussing it.

## Hypothesis mode

Run the pipeline: **Orient → Surface → Form → Corroborate → Disconfirm → Weigh
→ Gaps**. The non-negotiable step is **Disconfirm**: before any verdict, check
for `contradicts` edges, findings whose `extensions.harness.verification.verdict`
is `weakened`/`falsified`/`quarantined`, and low-trust provenance. A hypothesis
never tested against the disconfirming evidence is incomplete.

Verdict is exactly one of: `supported` | `contested` | `unsupported` |
`untestable-with-corpus`. Cite every supporting finding by `@id` and its source
`citations[].url`. Quarantined or falsified material may appear **only** as
disconfirming evidence, never as support.

## Interrogation mode

The whole job is finding what is weak. Surface, in order: findings with a
non-`survived` verdict (name each by id), `contradicts` edges, low-confidence
provenance (`provenance.confidence`), citations that are not externally
resolvable, and aging `created` dates. Produce a ledger of supporting vs
disconfirming findings; weak/falsified ids go only in the disconfirming column.

## Evidence discipline

- **Findings are pointers, not authorities** — cite the `@id` and the source URL.
- **Disconfirming material stays disconfirming** — a falsified or quarantined
  finding is never cited as support.
- **Non-`survived` verdicts are tripwires** — surface them whenever an affected
  finding enters the conversation.
- **Say "the corpus doesn't cover this"** when it doesn't — gaps are findings
  too; hand them to `/discover --gaps` or `/start --augment`.

## Handoffs

| Conversation surfaces | Hand off to |
| --- | --- |
| A pure retrieval need | `/search <query>` |
| A coverage gap or thin dimension | `/discover --gaps` or `/start --augment <dimension> --topic <topic>` |
| A relationship/visualization question | `/graph` |
| A claim needing adversarial web verification | `/falsify` |
| An idea worth becoming new research | `/start` |

## Prerequisites

- The corpus findings dir, `research-index.json`, and `knowledge-graph.json`.
  If the graph is missing: `bash scripts/build-graph.sh <findings-dir>`.

## Examples

```text
/lab --namespace harness/example-topic
/lab --seed urn:mif:concept:harness:kg-copier-0001
/lab --hypothesis "A living template beats a one-time snapshot"
/lab --interrogate
```
