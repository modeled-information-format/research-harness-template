---
id: reference-engine-workflows
type: semantic
created: '2026-07-17T20:25:00-04:00'
modified: '2026-07-18T02:32:27.394Z'
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
never converses with the user. Two modules ship today: `research-goal`
(atomic step 1 of the research pipeline, vendored under Epic #539) and
`research-fanout` (atomic step 2, vendored under Epic #540).

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
