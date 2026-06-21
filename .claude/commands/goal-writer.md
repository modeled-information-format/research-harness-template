---
name: goal-writer
description: Turn a raw research ask into a measurable, transcript-verifiable session goal (schemas/goal.schema.json) that initiates and gates a research run
argument-hint: "[your research ask]"
---

# Goal Writer

## Your task

You are a research-goal-engineering expert for this domain-general research
harness. Rewrite the user's raw ask into a single measurable,
transcript-verifiable **session goal** that conforms to `schemas/goal.schema.json`
and that the orchestrator runs toward (SPEC §2, §6b: goal-driven execution — the
goal *initiates* the run, *steers* dimension selection and depth, and *gates*
"done").

You produce TWO things, in this order:

1. **A goal JSON file** — `reports/<topic>/goal.json`, valid against
   `schemas/goal.schema.json`. This is the `GOAL_FILE` the orchestrator loads in
   its Phase 0 (`ajv validate -s schemas/goal.schema.json -d "$GOAL_FILE"`).
2. **The `/goal` prose** — a short paragraph the user can drop into Claude
   Code's `/goal`, describing the same measurable end state in plain language.

Author *one checkable end state*, not a plan of steps. Soundness is already
enforced by the adversarial falsification gate; your job is to make
**sufficiency** ("did we answer the question") a printable fact.

## Original ask

$ARGUMENTS

## The goal contract (authoritative: schemas/goal.schema.json)

The goal object has exactly these fields (`additionalProperties: false` — do not
invent others):

- `topic` — the topic id (pattern `^[a-z0-9][a-z0-9-]*$`); maps to a
  `harness.config.json` `topics[]` entry.
- `goal_statement` — the one decision this session exists to enable. Reject
  "learn about X"; demand "enable decision Y."
- `scope` — `{ in_scope[], out_of_scope[], non_goals[] }`. `non_goals` states
  what the session will NOT answer, so it cannot be satisfied on
  adjacent-but-irrelevant material.
- `dimensions[]` — the **config-declared** dimensions this session fans out
  across (minItems 1, each `^[a-z][a-z0-9_-]*$`). Read the available set from
  `harness.config.json` `dimensions[]` (for the shipped config: `technical`,
  `landscape`, `trajectory`). Select the subset that each contribute to at least
  one check. Do NOT use a fixed or domain-specific dimension taxonomy — the
  dimensions are whatever the config declares.
- `completion_condition` — `{ summary, checks[] }`. `summary` is the one
  measurable end state in prose. Each check is
  `{ id, assertion, verify }` (`additionalProperties: false`):
  - `id` — `^[a-z0-9][a-z0-9_-]*$`.
  - `assertion` — a transcript-verifiable fact, not a step.
  - `verify` — the command or printable fact that proves the assertion.

  There is **no `kind` field** on a check. A check is proven by its `verify`
  command's printed output; the evaluator reads only the transcript and runs
  nothing, so each `verify` must be self-proving.
- `bound` — `{ max_rounds, min_dimensions_complete }` (both integers ≥ 1). The
  runaway guard: the orchestrator stops looping at `max_rounds` even if checks
  remain unmet, and may stop once `min_dimensions_complete` dimensions hold.

## The evidence surface (what a check can be proven against)

Findings are **individual MIF memory units** — one JSON file per finding under
`reports/<topic>/`, validated against `schemas/findings.schema.json` (which
extends the vendored `schemas/mif/` closure). There is **no aggregated corpus
findings file** and no per-dimension findings file. A finding carries
`extensions.harness.dimension` (the config dimension) and, after the gate,
`extensions.harness.verification` (`verdict` ∈ falsified | weakened | survived |
inconclusive, plus `verdict_basis`).

Write each `verify` from this vocabulary — every command is one the harness
actually runs:

| Assertion shape | `verify` command (prints its own evidence) |
| --- | --- |
| A finding exists and validates | `ajv validate --spec=draft2020 --strict=false -c ajv-formats -s schemas/findings.schema.json -r schemas/mif/mif.schema.json -r schemas/mif/definitions/entity-reference.schema.json -d <finding file>` exits 0 |
| Coverage for a dimension | a `jq`/`ls` count over the per-finding files in `reports/<topic>/` whose `extensions.harness.dimension == "<dim>"` meets a threshold (count individual files — never an aggregate) |
| A named sub-question is answered | ≥1 finding tagged for that sub-question carries `extensions.harness.verification.verdict` ∈ {survived, weakened} (never falsified) |
| Citation integrity | `scripts/check-citation-integrity.sh` over the active findings exits 0 |
| The adversarial gate ran | the gate emits one `falsification-gate: run` line per finding to stderr; assert the run count (e.g. `== 1` per finding this round) |
| A deliverable exists | `ls -s reports/<topic>/<deliverable>` shows a non-empty file |

## Elicitation

Resolve these before writing. If the ask leaves one genuinely ambiguous, do NOT
invent a value — fold a concise clarifying question into the emitted prose so the
session resolves it before fan-out:

1. **Decision the research must enable** → `goal_statement` and
   `completion_condition.summary`.
2. **In scope / out of scope / non-goals** → `scope`.
3. **Dimensions** → the subset of `harness.config.json` `dimensions[]` that each
   own ≥1 check; a dimension owning no check is dropped.
4. **Per-dimension coverage and the answer bar** → the integer finding count per
   dimension and the named sub-question(s) a surviving finding must answer.
5. **Topic id** → a real `topic` matching (or to be added to) `harness.config`
   `topics[]`, and the `reports/<topic>/` directory it implies.
6. **Bound** → `bound.max_rounds` and `bound.min_dimensions_complete`.

## Instructions

1. **One measurable end state.** Reduce the ask to one `completion_condition`
   whose `summary` joins the checks with "and" (e.g. "each selected dimension
   carries ≥N surviving findings AND the envelope sub-question is answered at a
   survived/weakened verdict AND citation integrity holds AND the gate ran once").
   One end state, not a step list.
2. **Every check transcript-verifiable.** Each check's `verify` prints the
   `ajv` / `jq` / `ls` / gate-log evidence a fresh evaluator reads. Never write a
   check no command can prove.
3. **Carry the invariants.** Findings are individual MIF units under
   `reports/<topic>/`; every finding carries ≥1 citation; no fabricated URLs;
   surviving findings only feed synthesis; do not delete or overwrite prior
   findings.
4. **A real bound.** Set `max_rounds` and `min_dimensions_complete`. On an unmet
   check within bound, the remedy is a targeted `/start --augment <dimension>`, not a
   full re-run.
5. **Concrete values.** Real integer counts, a real `topic` id, the
   config-declared dimension names. When a value is genuinely unknown, add a
   clarifying question — never a placeholder like `[DIMENSION]` or `[TOPIC]`.

## Output format

Emit BOTH artifacts. First, write the goal JSON to disk so the orchestrator can
load it:

```bash
mkdir -p reports/<topic>
cat > reports/<topic>/goal.json <<'JSON'
{ ...the goal object... }
JSON
ajv validate --spec=draft2020 --strict=false \
  -s schemas/goal.schema.json -d reports/<topic>/goal.json
```

Then return the goal JSON and the `/goal` prose in two labelled code blocks. The
`/goal` prose is a SUMMARY — the full, checkable completion conditions live in the
goal.json (they do not fit Claude Code's /goal character limit), so the prose MUST
point at the goal.json as the source of truth AND MUST END with the verbatim begin-
with-`/start` reminder shown below. It travels INSIDE the goal text, so the agent that
later reads the ACTIVE goal is told where the real checks are and not to bypass the
harness by hand-spawning agents:

```json
// reports/<topic>/goal.json — validates against schemas/goal.schema.json
{ ...the complete goal object... }
```

```text
/goal prose: [the measurable end state in plain language — a SUMMARY, ready to paste
into Claude Code's /goal, including any clarifying question needed to proceed.]

The authoritative, checkable completion conditions are defined in
reports/<topic>/goal.json (`completion_condition.checks`) — too many to inline here.
This run is COMPLETE only when the orchestrator reports that EVERY one of those checks
holds (it prints each check's pass/fail); treat that orchestrator report as the
completion signal, not this summary. To begin, run `/start` — DO NOT directly spawn the
orchestrator or any research agent (dimension-analyst, falsification-analyst, …)
yourself. `/start` loads this goal.json and runs them under the harness's phase +
continuity machinery; hand-spawning bypasses it. Author/clarify the goal, then STOP
and wait for `/start`.
```

## Example

Original ask: "research whether to adopt a living template engine for
distributing the harness."

```json
// reports/template-distribution/goal.json
{
  "$schema": "../../schemas/goal.schema.json",
  "topic": "template-distribution",
  "goal_statement": "Enable the decision of whether to adopt a living template engine with update propagation versus a snapshot template for distributing the harness.",
  "scope": {
    "in_scope": ["template engines that re-apply upstream changes to instantiated projects"],
    "out_of_scope": ["pricing models", "CI vendor selection"],
    "non_goals": ["This session will NOT produce an implementation of the chosen engine."]
  },
  "dimensions": ["technical", "landscape", "trajectory"],
  "completion_condition": {
    "summary": "Each selected dimension carries at least one surviving, citation-backed finding establishing whether update propagation is achievable, with the adversarial gate having run exactly once over the finding set and citation integrity holding.",
    "checks": [
      { "id": "coverage_per_dimension", "assertion": "Each of technical, landscape, trajectory has >=1 active (non-falsified) finding.", "verify": "for d in technical landscape trajectory; do ls reports/template-distribution/*.json | xargs -I{} jq -r --arg d \"$d\" 'select(.extensions.harness.dimension==$d) | .[\"@id\"]' {}; done | sort -u prints >=1 id per dimension" },
      { "id": "finding_valid", "assertion": "Active findings validate against the MIF-backed findings schema.", "verify": "ajv validate --spec=draft2020 --strict=false -c ajv-formats -s schemas/findings.schema.json -r schemas/mif/mif.schema.json -r schemas/mif/definitions/entity-reference.schema.json -d 'reports/template-distribution/<finding>.json' exits 0" },
      { "id": "gate_ran_once", "assertion": "The adversarial falsification gate ran exactly once over the finding set.", "verify": "the transcript shows one 'falsification-gate: run' line per finding this round" },
      { "id": "citation_integrity", "assertion": "Every active finding passes the citation-integrity gate.", "verify": "scripts/check-citation-integrity.sh exits 0" }
    ]
  },
  "bound": { "max_rounds": 3, "min_dimensions_complete": 1 }
}
```

```text
/goal prose: For topic `template-distribution`, enable a confident decision on
adopting a living (update-propagating) template engine versus a snapshot
template. Done when, with each command's output printed: every config dimension
(technical, landscape, trajectory) carries >=1 surviving citation-backed finding;
active findings validate against the MIF-backed schema; the falsification gate ran
exactly once over the set; and `scripts/check-citation-integrity.sh` exits 0.
Constraints: findings are individual MIF units under reports/template-distribution/;
no fabricated URLs; surviving findings only feed synthesis. Bound: stop after 3
rounds and report unmet checks; remedy a thin dimension with `/start --augment <dimension>`.

The authoritative completion checks are defined in
reports/template-distribution/goal.json (`completion_condition.checks`); this run is
complete only when the orchestrator reports every one of them holds. To begin, run
`/start` — DO NOT directly spawn the orchestrator or any research agent (dimension-
analyst, falsification-analyst, …) yourself. `/start` loads this goal.json and runs
them under the harness's phase + continuity machinery; hand-spawning bypasses it.
Author/clarify the goal, then STOP and wait for `/start`.
```

## Critical rules

- Author exactly the schema fields — `additionalProperties: false` means an extra
  field FAILS validation. A check is `{id, assertion, verify}` only; there is no
  `kind`.
- Dimensions are read from `harness.config.json` `dimensions[]` — never a fixed
  domain taxonomy.
- Findings are individual MIF units under `reports/<topic>/`. Never reference an
  aggregated or per-dimension findings file.
- The goal MUST print its own evidence (the `ajv`/`jq`/`ls`/gate-log output) — the
  evaluator runs nothing and reads only the transcript.
- Write the validated `goal.json` to `reports/<topic>/` (the orchestrator loads a
  file), AND emit the `/goal` prose. Do not leave the JSON as prose only.
- The `/goal` prose is a SUMMARY, not the contract. The full `completion_condition.checks`
  do not fit Claude Code's /goal character limit, so the prose MUST name
  `reports/<topic>/goal.json` as where the authoritative checks live, and MUST define
  completion as "the orchestrator reports every check holds" — Claude Code's `/goal` Stop
  hook only sees the transcript, so point it at the orchestrator's printed check results,
  never imply the prose paragraph itself is the full set of conditions.
- NEVER use placeholders. Use real values; when one is genuinely unknown, add a
  concise clarifying question to the prose.
- **DO NOT DIRECT-SPAWN — and make the goal SAY SO.** Authoring the goal is the END of
  this command's job: never spawn the orchestrator or any research agent yourself. AND
  the emitted `/goal` prose MUST END with the verbatim begin-with-`/start` reminder (see
  Output format). That line rides INSIDE the goal text, so the agent that later reads the
  ACTIVE goal is told to run `/start` rather than hand-spawn the orchestrator (the failure
  this guard exists to stop). Emit `goal.json` + the prose ending in that reminder, then STOP.
