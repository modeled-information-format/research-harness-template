---
id: reference-engine-workflows
type: semantic
created: '2026-07-17T20:25:00-04:00'
modified: '2026-07-18T16:10:21.452Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: engine workflows"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-07-17T20:25:00-04:00'
  ttl: P6M
  recordedAt: '2026-07-17T20:25:00-04:00'
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:7b4efc9f-b778-4d49-b1e4-c009adbd178a
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.212
---

# Reference: engine workflows

`.claude/workflows/` holds the harness's Workflow-runtime modules — the
engine-path counterparts to the interactive slash commands in
[commands](commands.md). A workflow module is composed programmatically (by a
research pipeline or an orchestrating session) and returns a typed result; it
never converses with the user. Seven modules ship today: `research-goal`
(atomic step 1 of the research pipeline, vendored under Epic #539),
`research-fanout` (atomic step 2, vendored under Epic #540), `research-falsify`
(atomic step 3, vendored under Epic #541), `research-synthesis` (atomic
step 4, vendored under Epic #542), `research-projection` (atomic step 5,
vendored under Epic #543), `research-deliverables` (atomic step 6,
vendored under Epic #544), and `research-augment` (atomic action A —
deepening decision, vendored under Epic #545).

## Module shape and parse-check

The Workflow runtime strips a module's `export` statement and evaluates the
remaining source as the **body of an async function**, so top-level `await`
and `return` are legal in the file — and a bare `node --check` rejects a
valid module by design. `scripts/check-workflow-syntax.sh` compile-checks
each module through the same async-body wrap (nothing executes);
`verify.sh`'s `gate_workflows` runs it on the required `verify` CI surface,
and `evals/workflow-parse-check.sh` proves the wrap is load-bearing (#552).

## Governing architecture

These modules are vendored from the research-pipeline architecture document
that governs the workspace engine (see its "Atomic action 1 — goal-writing"
section for the container catalog, flowcharts, and design-pattern rationale
— this page documents only the in-repo surface). Two of that document's
shared architectural rules are load-bearing here and inherited unchanged:

- **Typed hand-offs only.** Every `agent()` call carries a JSON Schema the
  runtime enforces; no downstream stage parses prose.
- **Write-validate atomicity.** Any agent writing corpus JSON composes it
  with `jq` and validates it with `ajv` in the same turn — a write is not
  done until it validates. This is the same contract the harness already
  imposes on findings (ADR-0002); the workflow inherits it rather than
  restating it.

## research-goal

Atomic step 1 (goal-writing): turn a raw research ask into a schema-valid,
transcript-verifiable session goal — `reports/<topic>/goal.json`, valid
against `schemas/goal.schema.json` — via prompt chaining with a validation
gate after every link. Source: `.claude/workflows/research-goal.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | A topic id registered in `harness.config.json` `topics[]`. An unregistered topic short-circuits the run (`ok: false`, `reason: topic-not-registered`) before anything is drafted. |
| `ask` | no | `''` | The raw research ask. When empty, the Draft phase derives the sharpest decision-enabling goal from the topic and any existing goal context. |
| `harnessDir` | no | `.` | Path to the harness instance the goal is written into. The in-repo default is the instance root, so a pipeline running inside a clone passes nothing. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Context | haiku (low effort) | Reads `harness.config.json` (is the topic registered? which `dimensions[]` are config-declared?) and summarizes any existing `reports/<topic>/goal.json`, including its `gv-*` version. |
| Draft | sonnet | Follows `.claude/commands/goal-writer.md` as its operating manual. Composes `goal.json` with `jq`, validates it with `ajv` (draft2020 + ajv-formats) against `schemas/goal.schema.json`, and emits the companion `/goal` prose. Re-authoring an existing goal routes through ADR-0006's content-hashed append-only lineage — snapshot the live version to `goals/goal-<gv>.json` via `scripts/goal-version.sh`, then stamp `.version`/`.supersedes`/`.revision` — never an ad hoc snapshot. |
| Gate | haiku (low effort) | Re-runs `ajv`, then a verifiability lint: every `completion_condition.check` must be an end-state fact (not a step) that is transcript-verifiable, and every `dimensions[]` entry must be config-declared. |

### Bounded repair loop

A failing Gate triggers at most **two** repair rounds. Each round is a
sonnet repair (fix only the flagged issues, editing with `jq` and
re-validating with `ajv`; ADR-0006 lineage fields are preserved) followed by
a haiku re-lint. If issues remain after round two, the module returns
`ok: false` with the outstanding issues and the caller decides — the loop
never runs unbounded.

### Returns

A typed result: `{ ok, goalFile, goalProse, dimensions, checks, lintIssues }`
— or `{ ok: false, reason: 'topic-not-registered', context }` from the
Context short-circuit.

### Positioning: /goal-writer stays the interactive path

[`/goal-writer`](commands.md#goal-writer) remains the interactive,
user-facing path for authoring and reshaping goals — it elicits, converses,
and handles `--reshape` in dialogue. `research-goal` is the **engine path**
a pipeline composes: the same contract (the command's manual is the Draft
phase's operating manual; same schema; same ADR-0006 lineage) delivered as
a typed, non-interactive result.

For engine-composed goal authoring, this deterministic prompt chaining —
an `ajv` machine gate plus a verifiability lint after every link, with a
bounded repair loop — **supersedes prompt-discipline gating**, where a
single prompt was trusted to validate its own output. What is superseded is
prompt discipline as the gate, not the command: the interactive
`/goal-writer` path stays.

## research-fanout

Atomic step 2 (research fan-out): parallel evidence-gathering across the
goal's dimensions — each analyst a stateless typed worker emitting
schema-valid MIF finding records into `reports/<topic>/findings/`, run
through a per-dimension validate/repair lane with **no cross-dimension
barrier** (a slow dimension never blocks a fast one), followed by one
cross-corpus relation pass over everything the round produced. Source:
`.claude/workflows/research-fanout.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/goal.json` drives the round. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552 precedent), so a pipeline running inside a clone passes nothing. |
| `dimensions` | no | all goal dimensions | An explicit subset to fan out — the augment/update/pivot-gap entry point. The Plan phase restricts to the subset and notes any requested id absent from the goal. |
| `depth` | no | `standard` | `standard` covers each dimension's principal sub-areas; `deep` researches to saturation (keep searching until new searches surface nothing new and germane). |
| `roundContext` | no | — | What earlier rounds already covered / which checks are unmet; injected verbatim into every analyst brief so a later round does not re-gather round one. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Plan | haiku (low effort) | Reads `reports/<topic>/goal.json`, resolves the dimension set (or the requested subset), and distills the goal statement plus a 2–3 sentence researcher scope brief. No dimensions resolved is a hard failure. |
| Research | sonnet, per dimension | Parallel pipeline lanes, one per dimension. Each analyst does real web research only (`WebSearch`/`WebFetch`, saturation policy set by `depth`) and writes individual finding files under its own dimension pin. |
| Validate | haiku (low effort), per lane | `ajv` (draft2020 + ajv-formats) check of every file the lane wrote against `schemas/findings.schema.json` with the vendored `schemas/mif/` closure registered — plus lane lints: `extensions.harness.dimension` must equal the lane's pin, citations must be non-empty and actually retrieved. |
| Repair | sonnet, per lane, only on invalids | Bounded repair of the lane's invalid files (`jq` edits, re-run `ajv` until clean). Fixes structure, citation objects, and the dimension pin **only** — it never deletes a finding or weakens its claim to make validation pass. |
| Relate | sonnet, once | Cross-corpus pass over all new findings (skipped when the round produced one or none): substantially-duplicate claims are annotated with a typed MIF relationship (relates-to/duplicates semantics) from the newer to the older — never deleted — with every touched file kept `ajv`-valid. |

### Lane contract

Each finding is **one MIF concept object with its own `@id`** — never an
array envelope or a `{dimension, findings: []}` wrapper — written as an
individual JSON file, carrying its dimension pin
(`extensions.harness.dimension`), citations to sources actually retrieved
(never fabricated, never from training data alone), and provenance. The
contract is stated once in the module (its `FINDING_CONTRACT` constant) and
embedded verbatim in every worker brief, so analyst briefs are
self-contained — no dependence on `.claude/agents/dimension-analyst.md`
prose. Write-validate atomicity is inherited unchanged from the
[shared architectural rules](#governing-architecture) (ADR-0002): a write
is not done until it validates.

### Supersession: typed pipeline lanes replace Phase-1 coordination

For engine-composed gathering, the module's typed pipeline lanes
**supersede the orchestrator's Phase-1 coordination style** — filesystem
hand-offs between agents and bounded `Bash` poll loops watching the
findings directory for growth (cf. #10, and the concurrent-writes defect
class of #357). In the lane model every hand-off is a schema-enforced typed
result the runtime delivers to the next stage: there is nothing to poll and
no shared file to race on. What is superseded is the coordination style,
not the substrate — the finding contract (`schemas/`, ADR-0002) is
inherited unchanged, and the orchestrator-driven `/start` loop remains the
interactive research path.

### crossDimensionLeads routing

Every analyst also returns `crossDimensionLeads`: germane evidence it
encountered that belongs to a *different* dimension (or to none). The
analyst records the lead instead of writing a finding outside its pin, and
the module surfaces the collected leads in its return payload as
`{from, lead}` pairs. This is a **forward-looking routing surface**: its
consumers are the coverage-audit workflow (atomic action Z, #549) and the
add-dimensions workflow (atomic action B, #546), neither of which is
vendored yet — the payload documents where homeless evidence goes, not a
live integration. The old engine simply dropped this evidence; the module
guarantees it survives the round for those consumers to pick up.

### Returns

A typed result:
`{ dimensions, findings, perDimension, crossDimensionLeads, related }` —
`findings` is the flat list of validated finding paths, `perDimension`
carries each lane's `{ dimension, written, valid, searches, saturation }`
accounting, `crossDimensionLeads` the `{ from, lead }` pairs above, and
`related` the relation-pass annotation count (0 when the pass was skipped).

## research-falsify

Atomic step 3 (falsification): the single adversarial gate, decomposed —
haiku claim decomposition, 2–4 perspective-diverse sonnet skeptic lenses
(counter-evidence, source-integrity, temporal-validity, and at 4 lenses
scope-integrity; web-only), deterministic verdict-merge arithmetic in code,
opus adjudication only on contested minority-`falsified` patterns, verdict
write through the `falsify.sh` substrate via a code-materialized evidence
fixture, and remediation (quarantine / downgrade / annotate) applied by this
module. Source: `.claude/workflows/research-falsify.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` drives the run. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance (the #552/#556 precedent). |
| `scope` | no | `'all'` | `'all'`, `'dimension:<d>'`, or `{ paths?: string[], ids?: string[] }` for an explicit finding set — the `regate` entry point. |
| `claimBudget` | no | `50` | Findings gated per run. Findings past the budget are **deferred**, never dropped — see Returns. |
| `queryBudget` | no | `6` | Disconfirming queries per claim, per lens. |
| `lenses` | no | `3` | Skeptic lens count, clamped to `2..4`. |
| `regate` | no | `false` | Re-open verification for findings a goal-version pivot/update classified stale. Valid **only** with an explicit `scope.paths`/`scope.ids` — see [Regate](#regate-a-client-side-verification-block-reset) below. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Enumerate | haiku (low effort) | Resolves the working set from `scope`. One-round rule enforced structurally: any finding already carrying `extensions.harness.verification.attempted_at` is excluded before any model call, counted in `skippedAlreadyVerified` — except in `regate` mode, which includes them. A working set past `claimBudget` is sliced; the remainder returns as `deferredIds`, logged, never silently dropped. |
| Gate | mixed, per finding | Decompose (haiku) → parallel skeptic lenses (sonnet, web-only) → `mergeVotes()` (deterministic code) → adjudicate (opus) only if contested → [regate reset](#regate-a-client-side-verification-block-reset) if applicable → materialize an evidence fixture in code → write via `falsify.sh <finding> <fixture>` → apply [remediation](#remediation-is-implemented-in-this-module-not-by-falsifysh) ported from `falsification-analyst.md`. |
| Rollup | — | Tallies verdicts and contested-adjudication counts, logs one summary line. |

### Skeptic lenses and deterministic verdict-merge arithmetic

The four lenses are deliberately **diverse in attack angle**, not redundant
copies of the same prompt: `counter-evidence` (independent disconfirming
search), `source-integrity` (do the finding's own citations exist and say
what it claims?), `temporal-validity` (has a newer primary source superseded
the claim?), `scope-integrity` (does the evidence support the claim's stated
*generality*, not just its narrow core?). `lenses` selects the first *N* of
this fixed list, never a random subset.

Verdict merging is `mergeVotes()` — plain code, not a model call: unanimous
or majority `falsified`/`weakened`/`survived` resolve deterministically; any
minority `falsified` vote is `contested` and escalates to the opus
adjudicator (weighing evidence quality over vote count, never a re-vote); a
non-falsified mixed result with no majority takes the most severe vote on the
`falsified > weakened > inconclusive > survived` ordinal without spending an
adjudication call. This is the same "arithmetic lives in code" rule
`crossDimensionLeads` slicing and the claim-budget deferral above already
follow.

### The fixture-write bridge: `falsify.sh` takes a finding + fixture, never bare verdict args

This is a substrate fact, not a design choice this module made: `falsify.sh`'s
real signature is `falsify.sh <finding.json> [<evidence-fixture.json>]`, where
the fixture is a JSON object keyed by the finding's `@id`
(`{ "<id>": { verdict, basis, disconfirming: [url, ...] } }`) — there is no
form that takes `verdict`/`basis` as bare CLI arguments. The module's Gate
phase therefore **materializes that fixture in code**
(`buildFixtureEntry()`), from the already-computed `mergeVotes()`/adjudication
result and the lenses' own retrieved URLs, then hands the write agent the
exact JSON text to `mktemp` **outside the repo tree** and pass as
`falsify.sh <finding> <fixture>`'s second argument. The write agent's job is
purely mechanical (write this exact content, invoke the script, clean up
the ephemeral fixture) — it never composes or re-derives the verdict itself.
`falsify.sh` (delegating to `mif-rh-cli`'s `HarnessCommand::Falsify`) remains
the one and only verdict writer either way.

### Remediation is implemented in this module, not by `falsify.sh`

Neither `falsify.sh` nor the `mif-rh-cli` engine implements remediation —
confirmed by inspection of `crates/mif-rh/src/harness_falsify.rs` and
`crates/mif-rh-cli/src/main.rs` in `mif-rs`: zero `"quarantine"` hits in
either file. The engine implements only the one-round-guarded verdict write
described above; everything past that write was, before this module,
executed by hand from prose in `.claude/agents/falsification-analyst.md`
Step 7. `research-falsify.js` ports that logic verbatim
(`REMEDIATION_CONTRACT`) and applies it itself, keyed on the verdict
`falsify.sh` just wrote: `falsified` → quarantine (move the finding file out
of the active `findings/` set); `weakened` → downgrade one rung down the
real `provenance.trustLevel` ladder plus a bounded summary qualifier (capped
under the schema's `maxLength: 500`, never raised); `survived`/`inconclusive`
→ annotate only, no file mutation beyond the verification block `falsify.sh`
already wrote. This is a substrate gap this module closes, not a
restatement of what the engine already does.

### Regate: a client-side verification-block reset

The one-round rule has **no engine override**: `already_graded()` in
`harness_falsify.rs` unconditionally short-circuits any finding already
carrying `attempted_at`, and the `mif-rh-cli` `Falsify` command takes exactly
`finding`/`fixture` with no re-verify flag anywhere in the stack — confirmed
by inspection, not assumed from the reference design. When `regate: true` is
passed (only together with an explicit `scope.paths`/`scope.ids`), the Gate
phase clears the stale finding's `extensions.harness.verification` block
itself — via `jq 'del(.extensions.harness.verification)'`, write-then-`mv`,
never edit-in-place — **before** re-invoking `falsify.sh`, so the one-round
check sees a finding with no `attempted_at` and performs a genuine write.
The verdict write itself still routes exclusively through `falsify.sh`;
only the pre-condition it checks is reset outside the engine. A follow-up to
close this gap properly — an explicit `--regate` override in `mif-rh-cli`
itself, so a caller no longer has to pre-mutate the finding file
out-of-band — is filed and tracked as
[`mif-rs#119`](https://github.com/modeled-information-format/mif-rs/issues/119).

### Supersession: mechanism decomposed, epistemics and substrate unchanged

For engine-composed falsification, this module's decomposition — haiku
decomposition, diverse-lens voting, code-arithmetic merge, escalation-only
opus adjudication — **supersedes** the monolithic single-opus-agent
`falsification-analyst` gate in *mechanism only*. Decision D-3 of the
workspace research-pipeline architecture document (the source this module
was vendored from) states the rationale for that decomposition — why diverse
lenses beat redundant copies, why the merge is deterministic code, and why
opus is escalation-only — and is cited here rather than restated; see that
document's "Atomic action 3 — falsification" section. `falsify.sh` remaining
the sole verdict writer (D-3's own closing invariant) is unchanged by any of
this.

What is *not* unchanged is the substrate this vendored module actually runs
against, in exactly the three ways documented above: the architecture
document's own description assumes a bare-CLI-arg verdict write (no fixture
bridge), assumes `falsify.sh` owns remediation (it owns only the write), and
is silent on regate having no engine path at all (it has none). Those three
gaps were verified against `scripts/falsify.sh`, `harness_falsify.rs`, and
`mif-rh-cli` before this module was written, not carried forward from the
source document's assumptions. This section — not the architecture
document — is the authoritative as-built account of what is actually
implementable against today's `mif-rh-cli`; the architecture document
remains the record of the intended design and the decomposition rationale
(D-3), not of this substrate's present limits.

### Returns

A typed result: `{ gated, rollup, verdicts, deferredIds, alreadyVerified }`
— `gated` the count of findings this run actually resolved a verdict for,
`rollup` a `{ verdict: count }` tally, `verdicts` the per-finding
`{ id, dimension, verdict, contested, remediation }` list, `deferredIds` any
`@id`s pushed past `claimBudget` (re-run to continue; nothing silently
dropped), and `alreadyVerified` the one-round-rule skip count from Enumerate.

## research-synthesis

Atomic step 4 (synthesis): an evaluator-optimizer loop over the surviving
corpus. Select (haiku) builds the citable survivor set; Draft (sonnet)
writes a typed, `@id`-keyed synthesis organized around the goal's
`completion_condition.checks[]`; Critique (opus) grades that draft against
the contract and drives a bounded repair loop. Source:
`.claude/workflows/research-synthesis.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` and `goal.json` drive the run. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance (the #552/#556/#560 precedent). |
| `maxRepairRounds` | no | `2` | Upper bound on Critique → Repair → Re-critique cycles. Unresolved issues past the bound are returned, never looped past. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Select | haiku (low effort) | Builds the survivor set from `reports/<topic>/findings/`: every finding whose `extensions.harness.verification.verdict` is `survived`, `weakened`, or `inconclusive` (verdict recorded per finding — a weakened/inconclusive survivor is usable but stays marked). Findings under `reports/<topic>/quarantine/` or `reports/<topic>/archive/` are structurally excluded — `research-falsify.js` already moved every `falsified` finding there, so this phase counts them in `excluded` rather than re-deriving falsified status from the verdict field. Findings carrying no verification block at all are counted separately in `unverified` (ungated, not survivors — logged as a warning) and never silently promoted into the survivor set. Also reads `reports/<topic>/goal.json` for `goal_statement` and `completion_condition.checks[]`. Zero survivors short-circuits with `{ ok: false, reason: 'no-survivors' }`. |
| Draft | sonnet | Writes the typed synthesis: every claim cites the finding `@id`(s) it rests on; a claim resting on a weakened/inconclusive survivor carries that confidence marker explicitly; contradictions between survivors are surfaced as tensions, never silently resolved; each goal check gets a section stating the answer the evidence supports, or that it remains open. The document is written to disk per the [ephemeral-output contract](#ephemeral-output-contract) below, and its path is returned in `synthesisPath`. |
| Critique | opus (high effort) | Reads the file at `synthesisPath` and grades it adversarially against four axes: (1) per-check answer — `yes`/`partially`/`no`, evidence-backed; (2) citation-key integrity — every cited `@id` must be in the closed survivor set Select produced, nothing outside it and nothing uncited; (3) fidelity/overreach — spot-checks claims against the cited finding files, flags any claim going further than its citation supports and any weakened/inconclusive finding used without its confidence marker; (4) tension-burial — flags contradictory survivors merged into one smooth claim instead of surfaced as a tension. `clean: true` only if zero issues **and** no check graded `no`. |

### Bounded repair loop

A dirty Critique triggers at most `maxRepairRounds` (default 2) repair
rounds. Each round is a sonnet repair **in place** at `synthesisPath` —
fixing only what Critique flagged, never a wholesale restructure and never
importing evidence outside the valid survivor set; a check the evidence
genuinely cannot answer stays marked open rather than papered over — followed
by a fresh opus re-critique. If issues remain once the bound is hit, the
module returns `ok: false` with the unresolved `openIssues` and per-check
`checkCoverage` rather than looping further — the same "return the
unresolved report, do not loop past the bound" shape `research-goal`'s Gate
loop and `research-falsify`'s `claimBudget` deferral already use.

### Ephemeral-output contract

No canonical `mktemp`/scratch-path convention existed anywhere in this repo
before this module — CLAUDE.md's "ephemeral artifacts go to `mktemp` outside
the tree" rule was already followed ad hoc by several scripts
(`scripts/build-graph-viz.sh`, `scripts/mif-container-export.sh`,
`research-falsify.js`'s evidence fixture), but each invented its own
shape and none of them hand off a path to a *later, independent* workflow the
way synthesis output must hand off to `research-projection` (#543, not yet
started). `research-synthesis.js` is the first module to need that hand-off,
so it states one explicitly here — a real design decision, not a restatement
of an existing rule — for `research-projection` (and any future consumer) to
read rather than re-derive:

1. **Location.** The Draft phase's agent writes the typed synthesis as a
   single JSON document to a path obtained from a bare `mktemp` (a file, not
   `mktemp -d`), **outside the repo tree**. Nothing derived from a synthesis
   run is ever written under `reports/<topic>/` — that tree holds only
   contract-valid, tracked corpus artifacts (findings, verdicts, the report
   of record), per the [shared architectural rule](#governing-architecture)
   this module inherits unchanged.
2. **Hand-off field.** The absolute path travels back to the caller in the
   top-level `synthesisPath` field of this module's return value — never
   nested, never renamed. A consumer reads `result.synthesisPath` to locate
   the artifact; there is no second location to check.
3. **Lifetime.** The file is **process-ephemeral** and this module does
   **not** delete it — unlike `research-falsify.js`'s evidence fixture,
   which is single-use and cleaned up immediately after `falsify.sh`
   consumes it, the synthesis output's entire purpose is to be read by a
   *later* phase or workflow in the same pipeline run. The path is
   guaranteed valid only for the lifetime of the invoking process/session: a
   caller composing `research-synthesis` → `research-projection` in one
   pipeline run must read `synthesisPath` and act on it before that process
   exits. No cleanup trap is installed here, and nothing guarantees the file
   survives a process boundary.
4. **Shape on disk.** The JSON document is
   `{ sections: [...], findingsUsed, ...synthesis body keyed to check ids and
   finding @ids }` — the structure the Draft phase's agent composes (see the
   module source for the exact prompt). This module does not itself enforce
   a schema on the file's contents beyond what the Critique phase grades;
   citation-key integrity against the closed survivor `@id` set is the
   Critique phase's job, not a file-level schema.

This is the contract a future `research-projection` module (#543) can build
against directly, without re-deriving it from `research-synthesis.js`'s
source: read `result.synthesisPath` from a `research-synthesis` call in the
same process, treat it as a single ephemeral JSON file outside the tree, and
consume it before the process ends.

### Supersession: selection and critique split into independently graded phases

For engine-composed synthesis, this module's decomposition **supersedes**
the `report-synthesizer` (and, for the cross-topic atlas, `corpus-synthesizer`)
agents' front-door role *in mechanism*: those are single monolithic opus
agents that select survivors and draft the synthesis in one undifferentiated
pass, with no independent grading step. `research-synthesis.js` splits
selection (haiku), drafting (sonnet), and critique (opus, against the goal
contract and the closed survivor `@id` set) into separately modeled,
separately graded phases, with a bounded repair loop between drafting and
critique. Decision D-4 and the "Atomic action 4 — synthesis" section of the
workspace research-pipeline architecture document (the source this module
was vendored from) state the evaluator-optimizer rationale for that split —
why an independent evaluator grading against the contract, with the loop-exit
decided by code, replaces a single agent judging its own output — and are
cited here rather than restated.

What is *not* superseded: `report-synthesizer` remains the domain-general
front door to the output pipelines for the interactive path, and
`corpus-synthesizer`'s cross-topic atlas role (spanning every topic,
including what was falsified) is a distinct surface this module does not
touch. Only the *mechanism* by which a single topic's surviving findings
become a graded, typed synthesis changes here — the finding contract, the
verdict/quarantine substrate (ADR-0002, `research-falsify.js`), and the
report-of-record doctrine this synthesis feeds are all inherited unchanged.

### Returns

A typed result:
`{ ok, synthesisPath, sections, findingsUsed, checkCoverage, openIssues, ungatedFindings }`
— `ok` true only once Critique reports `clean`, `synthesisPath` the
[ephemeral-output contract](#ephemeral-output-contract) hand-off, `sections`
and `findingsUsed` carried from the Draft phase, `checkCoverage` the
Critique phase's final per-check `{ checkId, answered, note }` list,
`openIssues` any issues still open after the repair bound (or
`['critic failed']` if Critique itself did not return), and
`ungatedFindings` the Select phase's `unverified` count. A no-survivors
short-circuit instead returns `{ ok: false, reason: 'no-survivors', excluded,
unverified }`.

## research-projection

Atomic step 5 (projection): project the typed synthesis onto the durable
corpus surfaces — the canonical MIF Level-3 report of record, the topic
README/index, and the knowledge graph — then verify only what changed.
Source: `.claude/workflows/research-projection.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` and `goal.json` the report/README/graph are derived from. A missing `topic` throws before any phase runs. |
| `synthesisPath` | yes | — | The ephemeral output path from a `research-synthesis` call — see the [consumption contract](#synthesispath-consumption-contract-same-process-only) below. A missing `synthesisPath` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance (the #552/#556/#560/#564 precedent). |
| `slug` | no | `topic` | The report file's slug (`reports/<topic>/<slug>.md`). |
| `genre` | no | `'general'` | Genre passed through to `synthesize-artifact.sh`. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Report | sonnet | A same-process existence/non-empty/valid-JSON preflight check on `synthesisPath` (folded into the top of this phase, not a separate stage), then the `publish-report` skill's script pipeline: `synthesize-artifact.sh` → a REAL falsification pass over the report's own central claims via `falsify.sh` (never a hand-authored verdict) → `render-artifact.sh` → `mif-project.sh`. A `falsified` verdict quarantines the report — it is not shipped, and the module returns `ok: false` without proceeding to Index. |
| Index | haiku | The `readme` skill's `build-topic-readme.sh` for the computed structural backbone (counts, dates, verdict breakdown, source total, dimension rollup, report/artifact tables — never guessed), with only the Key Findings/Purpose prose hand-authored on top; then the `graph` skill's `build-graph.sh` + `assert-graph-mif.sh` to refresh and re-verify the knowledge graph. |
| Verify | haiku | Targeted gates (markdownlint + `ajv`) on only the files this run actually changed — never the full `verify.sh` suite. See [Decision D-10](#verify-phase-decision-d-10-targeted-gates-only) below. |

### synthesisPath consumption contract (same-process only)

`research-projection` consumes `research-synthesis.js`'s `synthesisPath`
hand-off (documented in that module's own
[ephemeral-output contract](#ephemeral-output-contract)) under the exact same
constraint that contract states: **same-process only**. The path is a bare
`mktemp` file outside the repo tree, with no cleanup trap but also no
cross-process survival guarantee — it is valid only for the lifetime of the
orchestrating process that produced it (e.g. `research-pipeline.js` calling
`wf('projection', { synthesisPath: syn.synthesisPath })` immediately after
`wf('synthesis', {})` in the same run). `research-projection` does not merely
assume the file is still there: its Report phase's first action is a cheap
existence + non-empty + valid-JSON check (`test -f`, `test -s`, `jq empty`)
run **before any report work starts**. If any of the three fails, the module
fails closed with an explicit error naming which check failed (`file
missing`, `empty file`, or `invalid JSON`) rather than proceeding on an
unchecked path or silently emitting an empty report — and the error message
states directly that the fix is to re-run `research-synthesis` and consume
its `synthesisPath` in the same process, not to retry `research-projection`
standalone against a now-stale path.

### Skill composition: orchestrates the existing pipeline, does not reimplement it

`research-projection.js` is an **orchestrator** over the harness's existing
`publish-report`, `readme`, and `graph` skills — it delegates to their
underlying scripts and never re-derives or supersedes their logic:

- **Report phase** invokes the `publish-report` skill's own script pipeline
  exactly as that skill's `SKILL.md` documents it: `synthesize-artifact.sh` →
  `falsify.sh` (the same falsification substrate `research-falsify.js`
  writes verdicts through) → `render-artifact.sh` → `mif-project.sh`. The
  module never authors the report's frontmatter, citations, or verification
  verdict directly — `publish-report`'s own non-negotiable is that the
  verdict must come from a real falsification pass, never be hand-authored,
  and this module does not weaken that rule to save an agent call.
- **Index phase** invokes the `readme` skill's `build-topic-readme.sh` for
  the structural backbone and the `graph` skill's `build-graph.sh` +
  `assert-graph-mif.sh` for the knowledge-graph refresh. The one thing
  `build-topic-readme.sh` cannot compute — synthesis-grade Key
  Findings/Purpose prose — is hand-authored by the haiku phase on top of the
  script's output, per the `readme` skill's own documented division of
  labor; every count, date, and table stays script-computed.

This module composes those three skills' scripts programmatically instead of
reimplementing an approximation of their logic in free-form prompts — the
same "compose with the harness's existing skills rather than duplicating
their logic wholesale" resolution the workspace research-pipeline
architecture document states as its intent for this workflow, and the same
delegate-to-`scripts/*.sh` precedent `research-goal`/`research-fanout`/
`research-falsify`/`research-synthesis` already established for their own
substrates.

### Verify phase: Decision D-10, targeted gates only

The Verify phase's targeted-only scope is not an implementation shortcut —
it is Decision D-10 of the workspace research-pipeline architecture document
governing this engine (see that document's "Atomic action 5 — projection"
section): projection/deliverable stages lint and schema-check only the files
they touched, and `verify.sh`'s full gate array plus `ontology-review.sh`
remain instance/CI responsibilities the workflow never invokes itself. Cited
here rather than restated; see the source document for the full rationale.
This module additionally never runs alongside `ontology-review.sh` (shared
temp/catalog state races, per this repo's own `CLAUDE.md`).

### Supersession-in-place: re-rendering preserves the report's `@id`

A `research-projection` run against a topic/slug that already has a report of
record is a **supersession re-render**, not a fresh create: `render-artifact.sh`
derives the report's `@id` deterministically from its namespace and slug
(`urn:mif:report:<namespace>:<slug>`), so re-running the identical pipeline for
the same topic/slug preserves the **same `@id`** automatically — the version
field increments and `temporal.validFrom` carries forward from the prior
render. No agent-side "remember the old `@id`" step exists or is needed; the
module never deletes the existing file first and never hand-copies an `@id`
forward. This is a durable identity contract other tooling (indexing,
cross-references, the knowledge graph's own node ids) may rely on — a report's
`@id` does not change across re-renders of the same topic/slug.

### Returns

A typed result:
`{ ok, reportPath, reportId, mifLevel, checksAddressed, verificationVerdict, readmePath, readmeCheckPassed, graphRefreshed, graphAssertPassed, problems }`
— `ok` true only once the Verify phase reports both `lintClean` and
`schemaClean`, `reportPath`/`reportId` the rendered report's path and
supersession-stable `@id`, `mifLevel` the achieved MIF frontmatter level,
`checksAddressed` the goal check ids the report speaks to,
`verificationVerdict` the verdict `falsify.sh` actually wrote (never
hand-authored), `readmePath`/`readmeCheckPassed`/`graphRefreshed`/
`graphAssertPassed` the Index phase's script-gate results, and `problems` the
Verify phase's targeted-gate findings. A report-falsification short-circuit
instead returns `{ ok: false, reason: 'report-falsified', reportPath,
verificationVerdict: 'falsified' }` before the Index phase ever runs.

## research-deliverables

Atomic step 6 (deliverable genres): routing workflow covering **both** real
rendering mechanisms the substrate actually has — artifact-based genre
renders (blog/book, via the same `synthesize-artifact.sh` →
`render-artifact.sh` pipeline the `publish-blog`/`book:book-author` skills
use) and source-direct channel packs (pdf, jats, xbrl, ectd, notebooklm,
github-discuss, github-issues — each built directly from findings, never
from a rendered artifact). Source:
`.claude/workflows/research-deliverables.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` the deliverables render from. A missing `topic` throws before any phase runs. |
| `synthesisPath` | yes | — | The ephemeral output path from a `research-synthesis` call — same same-process-only contract as `research-projection`'s (see [above](#synthesispath-consumption-contract-same-process-only)). Consulted only by artifact-based (mechanism 1) rows, for the synthesis-only evidence cross-check; source-direct (mechanism 2) rows never read it, by design (see the [mechanism boundary](#two-disjoint-rendering-mechanisms-and-why-a-third-is-out-of-scope) below). A missing `synthesisPath` throws before any phase runs regardless, since Route can't yet know which rows will need it. |
| `harnessDir` | no | `.` | Path to the harness instance (the #552/#556/#560/#564/#569 precedent). |
| `genres` | no | `[]` | Requested genre packs (e.g. `['academic','engineering']`); empty renders one neutral (`genre="general"`) artifact-based deliverable per requested artifact-based channel. |
| `channels` | no | `['blog']` | Requested channels — may mix artifact-based (`blog`, `book`) and source-direct (`pdf`, `jats`, `xbrl`, `ectd`, `notebooklm`, `github-discuss`, `github-issues`) channels in one call. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Route | haiku | A same-process preflight on `synthesisPath` (verbatim from `research-projection`'s guard), then classifies every requested genre×channel pair against `harness.config.json` `packs[]` and `.claude/settings.local.json`'s native `enabledPlugins` (`"<pack>@research-harness"` key shape — never a bare pack-name lookup) into a mechanism-tagged render plan. Every pair that cannot be served lands in `unavailable[]` with a reason naming the mechanism and exactly what is missing. |
| Render | sonnet | Mechanism 1 (artifact-based): `synthesize-artifact.sh` → synthesis-only cross-check against `synthesisPath` → `render-artifact.sh`. Mechanism 2 (source-direct): `Skill(<pack>:<pack>)` invoked directly against the findings dir, `synthesisPath` never consulted. |
| Check | haiku | Per-artifact validation — markdownlint where the output is Markdown, the citation-leak gate (no internal research identifiers in published prose) regardless of format, and ≥1 primary-source citation. A dirty artifact is fixed in place without touching claim content. |

### Two disjoint rendering mechanisms, and why a third is out of scope

Genre (**what** the document is) and channel (**how** it renders) are
**orthogonal axes** — a request names both independently, and Route resolves
every requested pair on its own, never assuming a genre's availability says
anything about a channel's, or vice versa. Resolving a pair is not one
uniform enablement check, though: the real substrate backing these axes is
**two disjoint rendering mechanisms**, verified directly against the actual
`scripts/`/`SKILL.md` files (not assumed from prose). This module's own
header documents the resolved dual-mechanism design decision in full;
summarized here for the reference reader:

- **Mechanism 1 — artifact-based** (channels `blog`/`book` only; `report` is
  excluded — that channel is `research-projection`'s canonical L3 job, not
  this module's). A genre pack (`kind: "genre"` in `harness.config.json`
  `packs[]`) feeds `synthesize-artifact.sh` → `render-artifact.sh`, the
  identical pipeline `publish-blog`/`book:book-author`'s own `SKILL.md`s
  document. `blog` itself needs no pack (core, always-on); `book` is an
  optional **channel pack** and must itself be enabled, on top of any
  requested genre pack. The Render phase delegates to those two scripts
  rather than free-form-authoring the content itself — the same
  script-delegation-over-reimplementation precedent `research-projection.js`
  established for its own Report phase (#569); cited here, not restated.
- **Mechanism 2 — source-direct channel packs** (`pdf`, `jats`, `xbrl`,
  `ectd`, `notebooklm`, `github-discuss`, `github-issues`): each is built
  "directly FROM THE SOURCES... NEVER from a rendered report" per its own
  `SKILL.md`/`plugin.json` (confirmed individually, and by
  `docs/reference/packs/channels.md`'s own provenance/citation-grounding
  audit) — invoked as its own Skill directly against the findings dir, with
  no genre axis at all.
- **Explicitly out of scope, not folded into either**: `diataxis`
  (per-finding page generation via its own script, an entirely different
  shape) and `ai-spec` (consumes a disjoint genre family —
  `ai-architecture-doc`/`kiro-*`/`feature-spec` — that never renders through
  blog/book). Requesting either surfaces in `unavailable[]` naming this
  explicitly, never silently mapped onto mechanism 1 or 2.

Every requested pair that cannot be served this way — a disabled pack, a
genre pack whose sole consuming channel is `ai-spec`, a methodology pack
mistaken for a genre template, an unrecognized channel, or one of the two
out-of-scope channels above — lands in `unavailable[]` with a reason that
names **which of the two mechanisms** the request was classified into (or
that it is a third-mechanism/architectural-boundary case) and exactly what
is missing; nothing is ever silently dropped.

The synthesis-only evidence rule (a deliverable's claims must trace to what
`research-synthesis` already established, never fresh raw-finding content)
applies **only** to mechanism 1 — mechanism 2's packs are non-negotiably
built the opposite way (`synthesize-artifact.sh` never runs for them, and
`synthesisPath` is deliberately never read for their rows).

### Supersession: a dual-mechanism substrate where the architecture doc describes one

Cited rather than restated: the workspace research-pipeline architecture
document's "Atomic action 6 — deliverable genres" section (the source this
module was vendored from) states the routing intent — genre and channel as
orthogonal axes, requested pairs resolved against "what is actually enabled
(harness packs, mif-docs suite skills as fallback template source)",
`unavailable[]` for anything that cannot be served — and that framing is
unchanged here.

What the architecture document's account does **not** capture is that "what
is actually enabled" is not one uniform check: today's real substrate is
bifurcated into the two disjoint mechanisms documented above, each with its
own template-source shape, its own relationship (or lack of one) to the
synthesis-only evidence rule, and its own `unavailable[]` reason vocabulary.
The architecture document's own "recommended scope" for this module was
narrower still — artifact-based rendering only, per this module's own
vendoring header — and the epic owner explicitly chose the larger,
dual-mechanism scope actually implemented here rather than the narrower one
the source document suggested. This section — not the architecture
document — is the authoritative as-built account of which mechanisms this
module actually covers and how; the architecture document remains the
record of the intended routing design and the orthogonal-axes rationale.

### Returns

A typed result: `{ ok, artifacts, unavailable }` — `artifacts[]` one entry
per successfully rendered deliverable (`path`, `genre`, `channel`,
`mechanism`, `citations`, `clean`), `unavailable[]` every requested pair that
could not be served with its distinguishing reason, and `ok` true iff at
least one deliverable rendered. An empty `plan[]` (nothing servable) returns
`{ ok: false, artifacts: [], unavailable }` before the Render phase ever
runs.

## research-augment

Atomic action A (augment): a pure **decision** workflow — haiku Assess
computes the per-dimension coverage/verdict/staleness matrix, then sonnet
Decide judges which dimensions to deepen, with stated reasoning, rejected
alternatives, and named target checks. It gathers nothing itself: the
orchestrator (#550, not yet vendored) is what feeds its `deepen[]` plan to
`research-fanout` (gathering) and `research-falsify` (the gate). Source:
`.claude/workflows/research-augment.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/goal.json` and `reports/<topic>/findings/` drive the assessment. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552/#556/#560/#564/#569/#573 precedent), so a pipeline running inside a clone passes nothing. |
| `focusHint` | no | — | User steer (e.g. a dimension id or unmet check ids). Decide honors it unless it contradicts the evidence — and says so explicitly when it does. |
| `checkCoverage` | no | — | A `research-synthesis` per-check grade list, when a synthesis round just ran. Folded into Decide's reasoning when supplied; the module runs standalone without it. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Assess | haiku (low effort) | Computes the per-dimension matrix (`findings`, `survived`, `weakened`, `falsified`, `inconclusive`, `ungated`, `oldestFindingDate`) plus the goal's `goal_statement` and `completion_condition.checks[]`, read verbatim. |
| Decide | sonnet | Judges which dimensions (at most 3) to deepen, in what depth, with stated reasoning and named target checks — or that nothing warrants deepening. |

### Assess is discover-delegated, not a re-derivation

The count/verdict portion of Assess's matrix is **delegated to the harness's
own `discover` skill** (`.claude/skills/discover/SKILL.md`): its
coverage-gaps pipeline already groups findings by dimension over
`research-index.json`, and its stale-findings pipeline already filters by
that same index's top-level `.verdict` field — the module composes both into one
`jq` pipeline over that same index rather than having an agent re-derive the
counts by reading and eyeballing raw finding files. This is the same class of
"delegate to a real, existing mechanism instead of reimplementing it via a
free-form prompt" gap Epics #543/#544 (`research-projection`/
`research-deliverables`) found and fixed for their own script-delegated
phases — cited here rather than restated; see `research-augment.js`'s own
vendoring header and Task #578 for the confirmed-gap writeup. The one piece `research-index.json`
genuinely cannot supply — it carries no timestamp, exactly as `discover`'s
own README notes for its age-based staleness signal — is
`oldestFindingDate`: that is real incremental logic layered on top, read
from the raw finding files' `created` and `extensions.harness.dimension`
fields, the same way `discover`'s own age-based staleness pipeline does it.

### Decide-phase priority order

Deepening signals are judged in a fixed priority: **unmet-check-impact >
attrition > thinness > staleness**. A check graded `no`/`partially` whose
evidence would come from a given dimension outranks everything else; high
falsification attrition (falsified+weakened dominating survived) is treated
as a **distinct sourcing-strategy signal** — the dimension's angle of attack
needs to change, not just get more volume — and is never folded into plain
thinness. A dimension already saturated with survivors is a reject
(diminishing returns), reported in `rejected[]` with its reason.

### The empty-plan outcome is valid, not an error

If Decide finds nothing worth deepening, it returns an empty `deepen[]` with
`reasoning` stating why — evidence may simply not exist yet for a check, or
every dimension may already be well-covered. This is a normal, non-error
return, never surfaced as a failure the caller must handle specially.

### Supersession: decides in place of the orchestrator's `augment` mode flag

For engine-composed deepening, `research-augment` **supersedes** the old
engine's `augment` orchestrator-mode flag — Decision D-7 of the workspace
research-pipeline architecture document (the source this module was
vendored from) states the rationale: steering decisions (augment among them)
become standalone, independently invocable, testable workflows with typed
outputs, instead of being folded into orchestrator mode flags with no
engine integration of their own. Cited here rather than restated; see that
document's "D-7 — Steering decisions are first-class atomic workflows"
section and its "Atomic action A — augment" section for the fuller design
rationale and flowchart.

What is *not* superseded: this module only **decides** — it never gathers
or gates. The orchestrator (#550, not yet vendored) remains the piece that
composes `research-augment`'s `deepen[]` plan into actual `research-fanout`
(gathering) and `research-falsify` (gate) calls; until it lands,
`research-augment` is confirmed safe to invoke standalone (no
live-orchestrator-context dependency), consuming an optional `checkCoverage`/
`focusHint` when a caller has them.

### Returns

A typed result: `{ deepen, rejected, reasoning, matrix }` — `deepen[]` the
accepted `{ dimension, depth, rationale, targetChecks }` entries (at most 3),
`rejected[]` the `{ dimension, why }` pairs Decide declined, `reasoning` its
overall explanation (populated even when `deepen[]` is empty), and `matrix`
the per-dimension coverage data Assess computed.
