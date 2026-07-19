---
name: research
description: Dynamic-workflow alternative to /start for full-, augment-, and update-mode research sessions (ADR-0020). Elicits/authors the session goal inline (goal-writer's methodology, not a separate step) in full mode, registers the topic, then invokes the research.js Workflow instead of spawning the orchestrator subagent. Session resume stays on /resume; the orchestrator remains the fallback path.
argument-hint: "[--topic <id>] [--genres <g1,g2,...>] [--augment [<dimension>]] [--update] [<research ask>]"
allowed-tools:
  - AskUserQuestion
  - Bash
  - Glob
  - Grep
  - Read
  - Skill
  - Workflow
  - Write
---

# Research (dynamic-workflow path)

The **dynamic-path alternative to `/start`** (ADR-0020): drives a full-, augment-,
or update-mode research session through `.claude/workflows/research.js` —
deterministic JS orchestration
(`pipeline`/`parallel`, awaited `agent()` calls) — instead of the `orchestrator`
subagent's poll-loop-and-reap coordination. Both paths preserve every harness
invariant identically (MIF findings, the single falsification gate, ontology typing
gate, goal versioning, knowledge graph/index/concordance). This command is also
this path's **goal-writer**: it elicits/authors the session goal itself, inline,
rather than requiring a separate `/goal-writer` step first.

**Full, augment, and update modes are all supported here** (research-harness#21),
matching `research.js`'s mode support (issues #19, #20). Session **resume** stays
on `/resume` (orchestrator-driven) either way — a workflow run's own resume
mechanic is `resumeFromRunId` on the underlying `Workflow` call, not a harness
concept surfaced by this command. The orchestrator path (`/start
--augment`/`/start --update`) remains available as a fallback; nothing here
removes it.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — the topic id (pattern `^[a-z0-9][a-z0-9-]*$`). If omitted,
  derive from the ask: lowercase, hyphenate, truncate to 40 chars.
- `--genres <g1,g2,...>` — comma-separated deliverable genres to render in addition
  to the always-on canonical report (e.g. `academic,engineering`). Genres are
  pre-filtered against enabled packs **inside the workflow itself** — an unknown or
  disabled genre is logged and skipped there, not rejected here. Omit for a neutral
  synthesis with no extra genre artifacts.
- `--augment [<dimension>]` — extend an EXISTING session (`research.js` `augment`
  mode, issue #20): with a dimension, re-research that single dimension to add more
  findings; with no dimension, re-research EVERY goal dimension. The named
  dimension is honored unconditionally — the harness does not second-guess which
  dimensions "need" it. Requires an existing goal and prior findings; never authors
  a goal. Mirrors `start.md`'s `--augment` flag exactly.
- `--update` — refresh the session against the existing (possibly reshaped) goal
  (`research.js` `update` mode, issue #19). **Membership-aware** (SPEC §11): reuses
  every in-scope, still-fresh finding as-is, re-verifies only the stale ones, and
  fans out only the gap dimensions (plus any tag-gap dimensions a goal reshape
  added new tagged sub-questions to) — it does NOT re-research everything. Requires
  an existing goal. Mirrors `start.md`'s `--update` flag exactly.
- Remaining text is the raw research ask (full mode only).

Resolve the **mode** from these flags exactly as `start.md` does: `--augment
[<dimension>]` → `MODE=augment` with `DIMENSION=<dimension>` (empty when the
dimension is omitted); `--update` → `MODE=update`; otherwise `MODE=full`.
`--augment` and `--update` are mutually exclusive and operate only on a topic that
already has a goal and prior findings — if either is missing, tell the user to run
`/research` (full) first; do NOT author a goal or fan out all dimensions for them.

## Phase 0: Resolve or author the session goal

**Full mode**: unlike `/start`, this command does not require a pre-existing goal —
it authors one inline when needed, reusing `goal-writer`'s methodology directly
(never hand-rolled):

1. If `reports/<topic>/goal.json` already exists and validates
   (`ajv validate --spec=draft2020 --strict=false -c ajv-formats -s schemas/goal.schema.json -d reports/<topic>/goal.json`),
   **reuse it as-is** — do not re-author or reshape it. (`--reshape` semantics for
   this path are a follow-up, not v1; if the goal needs to change, tell the user to
   run `/goal-writer --reshape` then `/research --update`.)
2. Otherwise, author a new one following `goal-writer.md`'s Elicitation and
   Instructions sections in full:
   - Resolve, asking the user (`AskUserQuestion`) rather than inventing a value for
     anything genuinely ambiguous: the decision the research must enable
     (`goal_statement` / `completion_condition.summary`), in/out of scope and
     non-goals, the subset of `harness.config.json` `dimensions[]` each owning ≥1
     check, the per-dimension finding-count bar and sub-question(s) a surviving
     finding must answer, the topic id, and `bound.max_rounds` /
     `bound.min_dimensions_complete`.
   - Author one measurable `completion_condition` (checks joined by "and", never a
     step list). Every check's `verify` must be transcript-verifiable
     (`ajv`/`jq`/`ls`/gate-log evidence). Match check shape to claim: a
     `verdict ∈ {survived, weakened}` check only for an externally web-falsifiable
     claim; a disk assertion for an internal-design/corpus-structure requirement — a
     verdict check over an internally-decided claim can only ever return
     `inconclusive` and is a flaw in the goal, not a research gap.
   - Write `reports/<topic>/goal.json`, then validate it with the same `ajv`
     invocation as above. Do not proceed past a validation failure.

**Augment/update mode**: the goal must already exist. Validate
`reports/<topic>/goal.json` with the same `ajv` invocation above and stop with an
error if it is missing or invalid — do NOT author or reshape a goal in these
modes. Also require `reports/<topic>/research-progress.md` to exist (there must be
a prior session to extend or refresh); if it does not, tell the user:

> No previous research session found for `<topic>`. Run `/research --topic
> <topic> <research ask>` (full mode) first, then `/research --augment` /
> `/research --update` to extend or refresh it.

and stop.

## Phase 1: Register the topic

Same recipe as `/start` Phase 2 (topic derivation → `AskUserQuestion` to confirm the
derived title → `topics[]` upsert → re-validate against
`harness.config.schema.json`) — reused verbatim, not re-derived here. See
`.claude/commands/start.md` Phase 2 for the exact `jq`/`ajv` invocations. In
augment/update mode the topic is already registered from the prior full-mode run;
this upsert is idempotent (it only flips `status` to `active` if the id already
matches) and is safe to run unconditionally in every mode.

## Phase 1b: Ontology binding (optional, SPEC §8c)

Same recipe as `/start` Phase 2b — inspect `packs/ontologies/*` entity types,
match the topic's domain, ask the user if ambiguous or no fit, then bind
(`ontologies[].enabled`, `topics[].ontologies`, `sync-packs.sh`) or leave
core-only. See `.claude/commands/start.md` Phase 2b for the exact invocations.

## Phase 2: Assemble args and invoke the Workflow

```bash
GV=$(bash scripts/goal-version.sh "reports/$TOPIC/goal.json")
RUN_DATE=$(date -u +%Y-%m-%d)
```

Genres: pass through the raw `--genres` list unfiltered — the workflow's own
Synthesize phase filters against enabled packs and logs any skip; this command
does not duplicate that check. Channels: `["report", "blog"]` by default (blog is
still gated on `outputs[]` having `blog` enabled, resolved inside the workflow) —
narrow to `["report"]` only if the user explicitly asked to skip blog.

`mode`/`dimension` mirror the flag resolution above: pass `mode: "{MODE}"` always;
pass `dimension: "{DIMENSION}"` only when `MODE` is `augment` and a dimension was
named (omit the field entirely otherwise — `research.js` rejects a non-empty
`dimension` under any other mode).

```text
Workflow(
  name: "research",
  args: {
    topic: "{TOPIC}",
    goalFile: "reports/{TOPIC}/goal.json",
    mode: "{MODE}",
    dimension: "{DIMENSION}",
    genres: [{comma-separated --genres, or []}],
    channels: ["report", "blog"],
    queryBudget: 6,
    claimBudget: 50,
    batch: 12,
    runDate: "{RUN_DATE}"
  }
)
```

The `args` value must be passed as a real JSON object in the `Workflow` tool call,
not a JSON-encoded string (the workflow script itself defensively guards against
receiving a string anyway — see `.claude/workflows/research.js`'s `args` parsing —
but pass a real object regardless).

`Workflow` runs in the background and returns a task id immediately. **The same
anti-narration rule as issue #490 applies here**: after launching, output ONLY a
bare factual acknowledgment — what was launched (topic, mode, genres if any) and
that you'll report when it completes. No editorializing about expected duration or
effort, no reassurance framing.

## Monitoring a running session

Unlike the orchestrator path, there is no poll-and-reap ambiguity to manage: every
`agent()` call inside the workflow is awaited by construction, so there is no
"is it actually still alive" question the way there is for a backgrounded
`Agent()` spawn. The `Workflow` tool's own progress UI (`/workflows`) and the
completion `<task-notification>` are the authoritative signals — do not
additionally poll `reports/<topic>/findings/` file counts the way `/start`'s
monitoring section instructs; that guidance is specific to the orchestrator's
silent-fan-out failure mode and does not apply here.

## Error handling

If the workflow returns `{status: "blocked", ...}`: report the `reason` verbatim
(`engine_missing`, `goal_invalid`, `lock_held`, or — augment mode only —
`unknown_dimension`, meaning the named `--augment <dimension>` is not one of the
goal's dimensions) and stop — do not retry automatically or steal the lock.

If it returns `{status: "partial", ...}`: real progress was made (findings exist,
possibly gated) but synthesis may have been withheld (check `unmetChecks` and
whether `.synthesis-withheld` is present under `reports/<topic>/`). Point the user
at `/ontology-review --topic <topic> --enrich` if typing was the blocker, or
`/research --augment [<dimension>]` (or `/start --augment`) for a thin dimension —
the workflow itself does not resume mid-run; a fresh `/research` (or `/start`)
invocation re-enters from Prepare and the one-round rule protects already-gated
findings from re-grading.

**If the run was interrupted externally (`TaskStop`, a session crash, or
similar) rather than exiting through its own control flow: manual recovery is
required.** Confirmed empirically (2026-07-17) — the workflow's `finally`
cleanup does NOT reliably run when the task is torn down from outside (a
host-level `TaskStop` mid-Gate left both the run-lock and `.gate-active` open,
with the in-flight batch's findings still ungated). Before retrying:

```bash
bash scripts/run-lock.sh release "reports/<topic>"
rm -f "reports/<topic>/.gate-active"
```

Then re-run `/research` (or `/start`) — the one-round rule protects any
finding that had already been gated before the interruption; only genuinely
ungated findings are re-considered. This is the same class of risk the
orchestrator path already carries under an external kill (neither can run its
own cleanup code once the process is gone) — the workflow path narrows the
*normal-exit* zombie/lock-leak surface that motivated it (ADR-0020), it does
not eliminate the *external-interruption* case.

## Output

Identical shape to `/start`'s output: findings as individual MIF units under
`reports/<topic>/`, continuity log at `reports/<topic>/research-progress.md`,
quarantined findings under `reports/<topic>/quarantine/`, the canonical report plus
any requested genre artifacts and the blog projection. Next steps: `/status`,
`/research --augment [<dimension>]` / `/research --update` (or the orchestrator
equivalents `/start --augment [<dimension>]` / `/start --update`) to extend or
refresh the session, `/falsify`, `/synthesize-corpus`.
