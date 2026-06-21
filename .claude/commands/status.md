---
name: status
description: Show the current research session state from the topic's continuity file (research-progress.md) and active finding set.
argument-hint: "[--topic <id>]"
allowed-tools:
  - Bash
  - Glob
  - Read
---

# Status

Reports the current state of a research session by reading its continuity file
(`reports/<topic>/research-progress.md`, the audit log the orchestrator appends
on every phase transition) and counting the active finding set. Read-only.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — which session to report. Required when more than one session
  exists.

## Phase 0: Resolve the session

```bash
ls reports/*/research-progress.md 2>/dev/null
```

- None found → "No research session found. Run `/start` to begin (author a goal
  first with `/goal-writer`)." Stop.
- Exactly one, and no `--topic` → use it.
- Multiple, and no `--topic` → list the topic ids and ask which to report. Do NOT
  pick arbitrarily.

Set `REPORTS_DIR="reports/<topic>"`.

## Phase 1: Read the continuity file

Read `reports/<topic>/research-progress.md`. The orchestrator writes a header
status block (Status, Goal met, Dimensions, Findings Summary, Next Steps) and an
append-only phase log (Session Initialized, Dimensions Complete, Falsification
Gate, Completion Check, Session Complete). Surface the latest header block and
the most recent few phase entries.

## Phase 2: Count the live state

The goal and findings are the ground truth; the progress file is the narrative.
Reconcile them so the user sees the real current numbers:

```bash
# Goal (the session contract)
jq -r '.goal_statement' "$REPORTS_DIR/goal.json" 2>/dev/null
jq -r '.dimensions | join(", ")' "$REPORTS_DIR/goal.json" 2>/dev/null
jq -r '.completion_condition.checks[] | "- " + .id + ": " + .assertion' \
  "$REPORTS_DIR/goal.json" 2>/dev/null

# Active findings = individual MIF units under findings/, excluding quarantine/
ACTIVE=$(ls "$REPORTS_DIR"/findings/*.json 2>/dev/null | wc -l | tr -d ' ')
QUARANTINED=$(ls "$REPORTS_DIR"/quarantine/*.json 2>/dev/null | wc -l | tr -d ' ')

# Per-dimension active counts (read dimension from each finding)
for f in "$REPORTS_DIR"/findings/*.json; do
  [ -e "$f" ] || continue
  jq -r '.extensions.harness.dimension // "unassigned"' "$f" 2>/dev/null
done | sort | uniq -c

# Verdict roll-up over active findings
for f in "$REPORTS_DIR"/findings/*.json; do
  [ -e "$f" ] || continue
  jq -r '.extensions.harness.verification.verdict // "ungraded"' "$f" 2>/dev/null
done | sort | uniq -c

# Topic lifecycle from the config registry (topics is an array, key by .id)
jq -r --arg id "<topic>" '.topics[] | select(.id == $id) | .status' \
  harness.config.json 2>/dev/null
```

## Phase 3: Present

Show a compact status:

- **Topic / status** — id and the `harness.config.json` lifecycle status.
- **Goal** — `goal_statement` and the `completion_condition.checks[]` (the gate
  for "done").
- **Dimensions** — the goal's `dimensions[]` and the active finding count per
  dimension.
- **Findings** — active count, verdict roll-up (survived / weakened /
  inconclusive / ungraded), and quarantined (falsified) count.
- **Last phase** — the most recent phase-log entry from the progress file.
- **Next steps** — `/resume` to continue, `/start --augment <dimension>` to deepen a
  named dimension, `/falsify` to re-run the gate, `/start` for a fresh session.

If `goal.json` is absent, say so plainly — the session has no contract to gate
against; recommend `/goal-writer`.
