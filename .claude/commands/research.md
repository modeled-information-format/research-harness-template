---
name: research
description: Engine-path entry point for a research campaign — wraps ONE Workflow tool call into the vendored research-pipeline.js (mode router + bounded autonomous round loop covering full, augment, pivot, import, and audit modes). Supersedes /start's spawn of the orchestrator subagent for the engine path; does not delete or disable /start.
argument-hint: "[--topic <id>] [--mode full|augment|pivot|import|audit] [--max-rounds <n>] [--focus-hint <text>] [--delta <what changed>] [--container-dir <path>] [--trust-imported-verdicts] [--genres <g1,g2>] [--channels <c1,c2>] [--claim-budget <n>] [--query-budget <n>] [--lenses <n>] [<research ask>]"
allowed-tools:
  - Workflow
  - Bash
  - Read
  - AskUserQuestion
---

# Research

> **Engine path.** This command is a **thin invocation surface** over the
> vendored workflow-of-workflows, `.claude/workflows/research-pipeline.js`
> (Epic #550; see its own header comment and, for the mode-router and
> bounded-round-loop design this command wraps, Decision D-11's first
> forward-improvement item in the workspace research-pipeline architecture
> document — a workspace-level design document, not a file in this repo,
> cited by name rather than linked). It **supersedes `/start`'s spawn of the
> `orchestrator` subagent** as the primary entry point for a research
> campaign — the issue #392 failure class (subagent poll loops,
> filesystem-as-message-bus, self-graded completion) is structurally
> unexpressible in the Workflow runtime's `pipeline()`/`parallel()`/`workflow()`
> primitives (that architecture document's Decision D-1; see
> [engine-workflows.md's migration
> note](../../docs/reference/engine-workflows.md#migration-note-supersedes-starts-orchestrator-spawn-in-place)
> for the in-repo account). **`/start` and `.claude/agents/orchestrator.md`
> are NOT deleted or disabled by this command** — the interactive/legacy
> path remains fully available during migration, per Epic #550's and parent
> Epic #551's explicit non-deletion requirement.
>
> This command carries **no orchestration logic of its own**. Everything
> after argument resolution below is exactly one `Workflow` tool call — the
> mode router, the round loop, budget floors, and completion grading all live
> inside `research-pipeline.js` itself, never re-implemented here.

## Arguments

Parse `$ARGUMENTS`. **Input sanitization**: truncate to 200 characters, strip
backticks and angle brackets.

- `--topic <id>` — the topic id (pattern `^[a-z0-9][a-z0-9-]*$`), matching a
  `harness.config.json` `topics[]` entry. `research-pipeline.js` throws
  immediately (`args.topic is required`) if this is missing, so resolve it
  before the tool call rather than letting the script surface that failure:
  - If omitted, read `harness.config.json` `topics[]`: exactly one topic →
    use it; more than one → **AskUserQuestion** which topic; none
    registered → tell the user to register one first (`/start` or
    `/configure topics`) and stop.
- `--mode <full|augment|pivot|import|audit>` — default `full`. Selects the
  script's mode-router branch:
  - `full` — the bounded autonomous goal loop (goal → [fanout →
    falsify-drain → synthesis → independent completion check]\* →
    audit-driven adaptation → projection → optional deliverables).
  - `augment` — one deepening-decision round. A plan with nothing worth
    deepening is a valid, honest outcome (`deepened: []` plus the judge's
    reasoning), never an error.
  - `pivot` — reshapes the goal from `--delta`, re-gates the stale
    carry-overs, fans out only the gap dimensions, then synthesizes and
    projects.
  - `import` — applies a MIF Container from `--container-dir` through the
    fail-closed import gate, gates whatever needs it, then synthesizes and
    projects.
  - `audit` — runs the six-auditor coverage sweep alone and returns the
    routed backlog; no fan-out, falsify, synthesis, or projection follows.
- `--max-rounds <n>` — `full` mode only. Caps the round loop (script default
  `3`). Passed through as `maxRounds`.
- `--focus-hint <text>` — `augment` mode only. A steer for the deepening
  judge (a dimension name or an unmet-check description). Passed through as
  `focusHint`; omit to let the judge choose on its own.
- `--delta <what changed>` — **required for `--mode pivot`**
  (`research-pipeline.js` throws `pivot mode requires args.delta` without
  it). If `--mode pivot` is given with no delta, ask the user what changed
  rather than invoking the tool with a missing required argument.
- `--container-dir <path>` — **required for `--mode import`**
  (`research-pipeline.js` throws `import mode requires args.containerDir`
  without it). Same handling: if `--mode import` has no `--container-dir`,
  ask for the path (as produced by `/export`) rather than invoking the tool.
- `--trust-imported-verdicts` — `import` mode only. Passed through as
  `trustImportedVerdicts: true`; omit for the default (re-gate every
  imported finding regardless of its foreign verdict).
- `--genres <g1,g2,...>` / `--channels <c1,c2,...>` — `full` mode only.
  Comma-split into string arrays and passed through as `genres`/`channels`
  to request deliverable renders once the run completes; omit for neither.
- `--claim-budget <n>` / `--query-budget <n>` / `--lenses <n>` — optional
  passthroughs to the falsification gate the script drives internally
  (`claimBudget`, `queryBudget`, `lenses`); omit to use the gate's own
  defaults.
- Remaining unflagged text — the raw research ask, **`full` mode only**.
  Passed through as `ask` (an empty string lets the `research-goal` child
  workflow derive the sharpest goal from the topic's existing context).

## Resolve mode + args, then invoke the Workflow tool exactly once

Build the args object for the resolved `MODE`, including only the fields
that mode actually consumes (omit the rest rather than passing empty
placeholders):

```text
Workflow(
  scriptPath: ".claude/workflows/research-pipeline.js",
  args: {
    topic: "{TOPIC}",
    mode: "{MODE}",
    ask: "{ASK}",                                       // full mode
    maxRounds: {MAX_ROUNDS},                             // full mode, default 3
    genres: [{GENRES}],                                  // full mode, optional
    channels: [{CHANNELS}],                              // full mode, optional
    focusHint: "{FOCUS_HINT}",                           // augment mode, optional
    delta: "{DELTA}",                                    // pivot mode, required
    containerDir: "{CONTAINER_DIR}",                     // import mode, required
    trustImportedVerdicts: {TRUST_IMPORTED_VERDICTS},    // import mode, optional
    claimBudget: {CLAIM_BUDGET},                         // optional, any gating mode
    queryBudget: {QUERY_BUDGET},                         // optional, any gating mode
    lenses: {LENSES},                                    // optional, any gating mode
  }
)
```

`harnessDir` and `workflowsDir` are deliberately omitted from the call — the
script's own in-repo defaults (`'.'` and `'.claude/workflows'`, per the
`#552`-precedent adaptation documented in its header comment) already
resolve correctly from this instance's root.

Do not add any fan-out, falsify, synthesis, or projection logic here — the
script owns every one of those phases internally, and re-implementing any
part of them in this command would duplicate control flow the architecture
doc explicitly keeps in one place (D-9: composition is exactly two levels
deep, and `research-pipeline.js` is the one composer). This command's only
job after argument resolution is the single call above.

## Report the result

The tool returns the script's typed result (shape varies by mode — see its
own `return` statements). Report it plainly, without re-narrating the run as
if this command had performed the work itself:

- **`audit`** — `{ backlog, summary, rawItems, uncoveredAngles }`. Show the
  summary and the routed backlog (`action`/`target`/`why`/`priority` per
  entry).
- **`import`** — `{ imported, gate, synthesis, projection }` on success, or
  `{ imported: <failed result> }` if the import gate itself failed — surface
  its `ok: false` stage/reason directly rather than paraphrasing it away.
- **`pivot`** — `{ goalVersion, carried, stale, fanout, synthesis, projection }`.
- **`augment`** — `{ deepened: [], reasoning }` when nothing warranted
  deepening (an honest terminal state, not a failure), or
  `{ deepened: [...], fanout, gate, synthesis, projection }` otherwise.
- **`full`** — `{ goal, done, checks: { met, unmet }, synthesis, projection,
  deliverables }`. State `done` plainly; if `done` is `false`, list the
  `unmet` checks with their `why` — never claim completion the script itself
  did not report.

## Next steps

- `full` mode, `done: false` — `/research --topic <id> --mode augment` (let
  the judge decide what to deepen), or `/research --topic <id>` again (a
  fresh `full` run re-evaluates against the same goal and every persisted
  finding).
- Any mode surfacing thin coverage on a specific check or dimension —
  `/research --topic <id> --mode augment --focus-hint <dimension or check id>`.
- The goal itself needs to change, not just deepen —
  `/research --topic <id> --mode pivot --delta "<what changed>"`.
- `/status`, `/topics`, and the interactive `/start` / `/resume` / `/falsify`
  commands remain fully available — this command adds the non-interactive
  engine path; it does not replace any of them.
