---
name: start
description: Start or extend a research session. Full mode (default) ensures a goal exists, registers the topic, and delegates to the orchestrator; --augment [<dimension>] deepens one dimension (or every thin dimension if omitted) and --update re-runs changed dimensions against the existing goal.
argument-hint: "[--topic <id>] [--goal <path>] [--augment [<dimension>]] [--update] [<research ask>]"
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Glob
  - Grep
  - Read
  - Write
---

# Start

Begins a new research session (default) — or **extends** an existing one with
`--augment`/`--update` — and delegates to the `orchestrator` agent in the matching
mode (`full | augment | update`). The orchestrator is **goal-driven** (SPEC §2,
§6b): it consumes a session goal (`schemas/goal.schema.json`) and loops fan-out →
falsify → synthesize until the goal's `completion_condition.checks` hold or its
`bound` is hit. It does NOT run elicitation — this command's job is to ensure a
valid `GOAL_FILE` exists, register the topic, and spawn the orchestrator.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — the topic id (pattern `^[a-z0-9][a-z0-9-]*$`). If omitted,
  derive from the ask: lowercase, hyphenate, truncate to 40 chars.
- `--goal <path>` — path to an existing validated `goal.json`. If omitted, look
  for `reports/<topic>/goal.json`.
- `--augment [<dimension>]` — extend an EXISTING session (orchestrator `augment`
  mode): with a dimension, re-research that single config-declared dimension to add
  more findings; with no dimension, re-research EVERY config-declared dimension. The
  named dimension is honored unconditionally — the harness does not second-guess
  which dimensions "need" it. Gates the new findings and merges. Requires an existing
  goal and prior findings; never authors a goal or overwrites progress.
- `--update` — re-run the dimensions whose inputs changed against the existing goal
  (orchestrator `update` mode). Requires an existing goal.
- Remaining text is the raw research ask (full mode only).

Resolve the **mode** from these flags: `--augment [<dimension>]` → `MODE=augment`
with `DIMENSION=<dimension>` (empty when the dimension is omitted); `--update` →
`MODE=update`; otherwise `MODE=full`. `--augment` and `--update` are mutually
exclusive and operate only on a topic that already has a goal and prior findings —
if either is missing, tell the user to run `/start` (full) first; do NOT author a
goal or fan out all dimensions for them.

## Phase 0: Resolve the session goal

The orchestrator's Phase 0 runs
`ajv validate -s schemas/goal.schema.json -d "$GOAL_FILE"` and stops if the goal
is missing or invalid. So a valid `GOAL_FILE` must exist before delegation.

1. If `--goal <path>` was given, set `GOAL_FILE` to it.
2. Else if `reports/<topic>/goal.json` exists, set `GOAL_FILE` to it.
3. Else there is no goal yet. Tell the user:

   > No session goal found for `<topic>`. Author one first with
   > `/goal-writer <your research ask>`, then re-run `/start --topic <topic>`.

   If a raw ask was supplied, suggest the exact `/goal-writer` invocation. Do NOT
   fabricate a goal — the goal is the session contract.

Validate the resolved goal before proceeding:

```bash
ajv validate --spec=draft2020 --strict=false \
  -s schemas/goal.schema.json -d "$GOAL_FILE"
TOPIC=$(jq -r '.topic // empty' "$GOAL_FILE")
```

If validation fails, report the error and stop. Resolve `TOPIC` from the goal
when present; otherwise use the `--topic`/derived id. Set
`REPORTS_DIR="reports/$TOPIC"`.

## Phase 1: Previous-session detection

```bash
ls "reports/$TOPIC/research-progress.md" 2>/dev/null
```

**In `augment`/`update` mode, skip this prompt** — they always extend the existing
session. If no progress file exists in those modes there is nothing to extend: tell
the user to run `/start` (full) first, and stop.

In `full` mode, if a progress file exists, prior research is present. Ask:

> Previous research found for `<topic>`. Resume it (`/resume`), or start fresh
> (overwrites prior progress)?

If "resume" → stop and tell the user to run `/resume --topic <topic>`. If
"fresh" → proceed (the orchestrator appends to the progress log; the one-round
rule prevents re-falsifying prior findings).

## Phase 2: Register the topic in harness.config.json

`harness.config.json` `topics` is an **array** of `{id, title, namespace,
status}`. Register or update the topic by its `id` (per the Structured Data
Protocol — jq write, then re-validate):

```bash
TITLE=$(jq -r '.goal_statement' "$GOAL_FILE" | cut -c1-80)
jq --arg id "$TOPIC" --arg title "$TITLE" --arg ns "harness/$TOPIC" '
  if any(.topics[]; .id == $id)
  then (.topics[] | select(.id == $id) | .status) = "active"
  else .topics += [{ id: $id, title: $title, namespace: $ns, status: "active" }]
  end' harness.config.json > tmp.$$ && mv tmp.$$ harness.config.json
ajv validate --spec=draft2020 --strict=false \
  -s harness.config.schema.json -d harness.config.json
```

### Phase 2b: Identify and incorporate an ontology (SPEC §8c)

Direct the topic to an appropriate ontology so its findings can be classified and
typed. The vendored core — `mif-generic` (built-in generic types: concept, person,
organization, technology, file) and `mif-base` (scaffolding) — is **always enabled
for every topic**, so findings can always be typed generically. Binding a domain
ontology adds more specific types. The six example data packs under
`packs/ontologies/` are the bindable domain ontologies — inspect their entity types
to match the topic's domain:

```bash
for o in packs/ontologies/*/; do
  id=$(basename "$o")
  echo "$id: $(yq -r '[.entity_types[].name] | join(", ")' "$o$id.ontology.yaml" | cut -c1-100)"
done
```

Match the topic to the best-fitting ontology (e.g. an education topic →
`k12-educational-publishing`; a pasture/farm topic → `regenerative-agriculture`;
software → `software-engineering`). **If the match is ambiguous or none fits, ask
the user** (AskUserQuestion) — offer the top candidates plus "core only" — rather
than guessing. Then **incorporate** the chosen ontology: enable its data pack and
bind it to the topic (jq write, re-validate, then `sync-packs.sh` to catalog it):

```bash
ONTO=<chosen-id>   # omit this whole step to leave the topic core-only
jq --arg o "$ONTO" --arg t "$TOPIC" '
  (.ontologies[] | select(.id == $o) | .enabled) = true
  | (.topics[] | select(.id == $t) | .ontologies) = [$o]' \
  harness.config.json > tmp.$$ && mv tmp.$$ harness.config.json
ajv validate --spec=draft2020 --strict=false -s harness.config.schema.json -d harness.config.json
scripts/sync-packs.sh   # materializes the enabled ontology into the catalog
```

A bound ontology must be `enabled` in `ontologies[]` (only enabled ontologies are
cataloged, and `gate_m12` enforces binding → catalog → registry). Leaving the topic
core-only is valid — its findings simply stay untyped.

## Phase 3: Delegate to the orchestrator

Spawn the `orchestrator` agent in the resolved `{MODE}` with the inputs its
"Inputs (spawn prompt)" contract requires. Pass `DIMENSION` only in `augment` mode
(the single dimension to deepen, or empty to deepen every thin dimension); omit it
otherwise:

```text
Agent(
  subagent_type: "orchestrator",
  name: "orchestrator",
  prompt: """
    You are the research orchestrator for this session ({MODE} mode).

    MODE: {MODE}                      — full | update | augment
    DIMENSION: {DIMENSION}            — augment mode only: the single dimension to deepen
                                        (empty = deepen every config-declared dimension)
    GOAL_FILE: {GOAL_FILE}            — the validated session goal; research toward it
    TOPIC: <user_input>{topic}</user_input>
    TOPIC_SLUG: {TOPIC}
    REPORTS_DIR: {REPORTS_DIR}
    MAX_CONCURRENCY: 3
    QUERY_BUDGET: 6
    CLAIM_BUDGET: 50

    Execute the goal-driven orchestration for this MODE per your agent definition:
    Phase 0 (load+validate goal, progress) → Phase 1 (fan out dimension-analysts —
    full: every goal dimension; update: only changed dimensions; augment: the single
    DIMENSION, or every declared dimension when DIMENSION is empty) → Phase 2 (single
    falsification gate over the new findings) → Phase 3 (completion check / loop to
    bound) → Phase 4 (synthesize surviving findings, render progress, cleanup).

    Follow all protocols in your agent definition.
  """
)
```

Wait for the orchestrator to complete. It handles all user-facing progress
updates and confirmations.

## Error handling

If the orchestrator does not complete:

1. Check for partial findings: `ls reports/<topic>/*.json 2>/dev/null`.
2. If findings exist, the orchestrator made progress — check
   `reports/<topic>/research-progress.md` for the last phase; suggest `/resume`.
3. If none, inform the user: "Research session did not complete. Retry with
   `/start --topic <topic>`."

## Output

After completion:

- Findings as individual MIF units under `reports/<topic>/`.
- Continuity log at `reports/<topic>/research-progress.md`.
- Quarantined (falsified) findings under `reports/<topic>/quarantine/`.
- Next steps: `/status`, `/start --augment [<dimension>]`, `/falsify`, `/resume`.
