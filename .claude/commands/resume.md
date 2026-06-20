---
name: resume
description: Resume a research session from its continuity file, re-spawning the orchestrator against the existing goal to drive remaining checks to completion.
argument-hint: "[--topic <id>]"
allowed-tools:
  - Agent
  - AskUserQuestion
  - Bash
  - Glob
  - Read
---

# Resume

Continues an existing research session (SPEC §6b continuity). The orchestrator
appends to `reports/<topic>/research-progress.md` on every phase transition and
findings persist as individual MIF units, so a session can always be picked back
up. Resume reads that continuity file, then re-spawns the `orchestrator` against
the existing `goal.json` to drive any unmet `completion_condition.checks` to
completion.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — which session to resume. Required when more than one exists.

## Phase 0: Locate the session

```bash
ls reports/*/research-progress.md 2>/dev/null
```

- None → "No research session to resume. Run `/start` to begin." Stop.
- One, no `--topic` → use it.
- Multiple, no `--topic` → list topic ids and ask which to resume. Do NOT pick
  arbitrarily.

Set `TOPIC=<topic>`, `REPORTS_DIR="reports/$TOPIC"`, `GOAL_FILE="$REPORTS_DIR/goal.json"`.

## Phase 1: Read continuity and re-validate the goal

1. Read `reports/<topic>/research-progress.md`. Identify the last phase entry
   (Session Initialized / Dimensions Complete / Falsification Gate / Completion
   Check / Session Complete) and any recorded **unmet checks**.

2. Re-validate the goal (the orchestrator requires a valid `GOAL_FILE`):

   ```bash
   ajv validate --spec=draft2020 --strict=false \
     -s schemas/goal.schema.json -d "$GOAL_FILE"
   ```

   If `goal.json` is missing, stop: "No session goal for `<topic>`; author one
   with `/goal-writer` and `/start` fresh." If the last entry is
   **Session Complete** and all checks held, tell the user the session is already
   done (suggest `/status`, `/augment`, `/falsify`) and ask whether to resume
   anyway.

3. **Reconcile remaining work from disk (authoritative).** Derive the structured
   checkpoint and the exact remaining-work plan — this never re-counts a completed
   finding, so resume never re-runs research/falsification it already paid for:

   ```bash
   scripts/reconcile-session.sh "$REPORTS_DIR"   # writes $REPORTS_DIR/state.json, prints the plan
   ```

   `reports/<topic>/state.json` records, per finding, `{id, dimension, valid,
   attempted_at, verdict}`; per dimension `{total, done}`; per check
   `{check, passed}`. A finding is **done** iff it is schema-valid (validity
   requires a falsification verdict). The printed plan lists only dimensions with
   `done < total` and failing checks. If the plan is `nothing to do`, the session
   is already complete — tell the user and do NOT re-spawn.

   **If `reconcile-session.sh` exits non-zero, STOP.** It fails safe: a non-zero
   exit means the ajv toolchain/environment is broken, not that work remains.
   Report the broken environment and do NOT re-spawn — never treat a reconcile
   failure as "everything remaining" (that would re-run the entire paid session).

4. Summarize for the user before re-spawning: topic, goal statement, last phase,
   the reconcile plan (which dimensions still need work), active vs quarantined
   finding counts, and which checks remain unmet.

## Phase 2: Re-spawn the orchestrator

The orchestrator has modes `full | update | augment` — there is no dedicated
resume mode. Re-spawn in `full` against the existing `GOAL_FILE` and
`REPORTS_DIR`: the orchestrator loads the goal, re-evaluates
`completion_condition.checks` against the persisted findings, and loops only the
thin dimensions. The progress log appends (it is never overwritten) and the
one-round rule blocks re-falsifying findings that already carry a verdict, so a
re-spawn safely continues rather than restarting.

```text
Agent(
  subagent_type: "orchestrator",
  name: "orchestrator",
  prompt: """
    You are the research orchestrator RESUMING an existing session.

    MODE: full
    GOAL_FILE: {GOAL_FILE}            — the validated session goal; research toward it
    TOPIC: <user_input>{topic}</user_input>
    TOPIC_SLUG: {TOPIC}
    REPORTS_DIR: {REPORTS_DIR}        — existing findings live here; do NOT overwrite them
    MAX_CONCURRENCY: 3
    QUERY_BUDGET: 6
    CLAIM_BUDGET: 50

    Existing findings, a state.json checkpoint, and an append-only
    research-progress.md are already in REPORTS_DIR. Continue, do not restart:
    - FIRST run `scripts/reconcile-session.sh "$REPORTS_DIR"` and read state.json:
      it is the authoritative remaining-work plan derived from disk.
    - Re-fan-out (Phase 1) ONLY dimensions whose state.json `dimensions[d]` has
      `done < total` (or that an unmet check names). A dimension with done==total
      is COMPLETE — never re-run it (re-running burns research/falsification budget).
    - In Phase 3, evaluate completion_condition.checks against the findings already
      on disk before fanning out.
    - The one-round rule applies: never re-falsify a finding that already carries
      extensions.harness.verification.attempted_at.
    - Append to research-progress.md; never overwrite the phase log.

    Follow all protocols in your agent definition.
  """
)
```

Wait for completion.

## Error handling

If the orchestrator does not complete, the persisted findings and the appended
progress log are intact — resume is idempotent. Re-run `/resume --topic <topic>`,
or inspect `reports/<topic>/research-progress.md` directly.

## Output

- Updated `reports/<topic>/research-progress.md` with the continued phase log.
- Refreshed active finding set under `reports/<topic>/`.
- Next steps: `/status`, `/augment <dimension>`, `/falsify`.
