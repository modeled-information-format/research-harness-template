---
name: start
description: Start a new research session. Ensures a session goal exists, registers the topic, then delegates to the orchestrator agent in full mode.
argument-hint: "[--topic <id>] [--goal <path>] [<research ask>]"
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

Begins a new research session and delegates to the `orchestrator` agent in
`full` mode. The orchestrator is **goal-driven** (SPEC §2, §6b): it consumes a
session goal (`schemas/goal.schema.json`) and loops fan-out → falsify →
synthesize until the goal's `completion_condition.checks` hold or its `bound` is
hit. It does NOT run elicitation — this command's job is to ensure a valid
`GOAL_FILE` exists, register the topic, and spawn the orchestrator.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — the topic id (pattern `^[a-z0-9][a-z0-9-]*$`). If omitted,
  derive from the ask: lowercase, hyphenate, truncate to 40 chars.
- `--goal <path>` — path to an existing validated `goal.json`. If omitted, look
  for `reports/<topic>/goal.json`.
- Remaining text is the raw research ask.

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

If a progress file exists, prior research is present. Ask:

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

## Phase 3: Delegate to the orchestrator

Spawn the `orchestrator` agent in `full` mode with the inputs its
"Inputs (spawn prompt)" contract requires:

```text
Agent(
  subagent_type: "orchestrator",
  name: "orchestrator",
  prompt: """
    You are the research orchestrator for a NEW session.

    MODE: full
    GOAL_FILE: {GOAL_FILE}            — the validated session goal; research toward it
    TOPIC: <user_input>{topic}</user_input>
    TOPIC_SLUG: {TOPIC}
    REPORTS_DIR: {REPORTS_DIR}
    MAX_CONCURRENCY: 3
    QUERY_BUDGET: 6
    CLAIM_BUDGET: 50

    Execute the full goal-driven orchestration per your agent definition:
    Phase 0 (load+validate goal, team, progress) → Phase 1 (fan out
    dimension-analysts across the goal's dimensions[]) → Phase 2 (single
    falsification gate) → Phase 3 (completion check / loop to bound) →
    Phase 4 (synthesize surviving findings, render progress, cleanup).

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
- Next steps: `/status`, `/augment <dimension>`, `/falsify`, `/resume`.
