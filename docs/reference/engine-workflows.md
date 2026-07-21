---
id: reference-engine-workflows
type: semantic
created: '2026-07-17T20:25:00-04:00'
modified: '2026-07-21T01:08:27.808Z'
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
  agent: claude-code/claude-fable-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:6cffe5d9-0ff6-4850-a402-01fd4a85a0d9
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.216
---

# Reference: engine workflows

`.claude/workflows/` holds the harness's Workflow-runtime modules — the
engine-path counterparts to the interactive slash commands in
[commands](commands.md). A workflow module is composed programmatically (by a
research pipeline or an orchestrating session) and returns a typed result; it
never converses with the user. Twelve modules ship today: `research-goal`
(atomic step 1 of the research pipeline, vendored under Epic #539),
`research-fanout` (atomic step 2, vendored under Epic #540), `research-falsify`
(atomic step 3, vendored under Epic #541), `research-synthesis` (atomic
step 4, vendored under Epic #542), `research-projection` (atomic step 5,
vendored under Epic #543), `research-deliverables` (atomic step 6,
vendored under Epic #544), `research-augment` (atomic action A —
deepening decision, vendored under Epic #545), `research-add-dimensions`
(atomic action B — widen the dimension set, vendored under Epic #546),
`research-pivot` (atomic action C — pivot research focus, vendored under
Epic #547), `research-import` (atomic action D — include pre-existing
findings, vendored under Epic #548), `research-coverage-audit`
(atomic action Z — corpus audit, vendored under Epic #549), and
`research-pipeline` (the workflow-of-workflows orchestrator — mode router
plus bounded round loop, vendored under Epic #550).

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

A typed result:
`{ ok, goalFile, goalProse, dimensions, checks, deliverables, lintIssues }`
— or `{ ok: false, reason: 'topic-not-registered', context }` from the
Context short-circuit. `deliverables` (research-harness-template#626) is
whatever the Draft phase actually left on `goal.json`'s optional
`deliverables` field — this module never elicits it itself (that is
`/goal-writer`'s own interactive-path job, via `AskUserQuestion` — see
[Positioning](#positioning-goal-writer-stays-the-interactive-path) below): a
`--reshape` re-author preserves an existing `deliverables` block verbatim,
and a fresh author leaves it `undefined`. See
[research-pipeline](#research-pipeline)'s Project/Deliver phases for how a
populated `deliverables.genres`/`.channels` is consumed downstream.

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

**Deliverable-genre elicitation (research-harness-template#626) stays
interactive-only, by the same reasoning.** `/goal-writer` elicits the
optional `deliverables.genres`/`.channels` field via `AskUserQuestion`,
sourced from the instance's real enabled genre packs
(`harness.config.json` `packs[]`), with the full `mif-docs-plugin` genre
catalog offered as a fallback set when nothing enabled fits. `research-goal`
**cannot** ask this question — a Workflow-runtime engine call has no
mechanism to pause for user input — so it never tries: its Draft prompt
carries an explicit carve-out to either preserve an existing `deliverables`
block verbatim (`--reshape`) or leave the field absent (fresh author), and
nothing else. A session run through the engine path with no prior
`deliverables` therefore still defaults to the single genre-neutral
canonical report — the pre-#626 behavior — exactly as before; only the
interactive `/goal-writer` path can turn that into a real, elicited choice.

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
`{from, lead}` pairs. This is a **routing surface** with two named
consumers: the coverage-audit workflow (atomic action Z, #549, not yet
vendored) and the add-dimensions workflow
([atomic action B, `research-add-dimensions`](#research-add-dimensions),
vendored under Epic #546). The latter's `leads` arg consumes this payload
directly — no longer forward-looking, a live integration — while the
former still only has a documented destination, not a consumer. The old
engine simply dropped this evidence; the module guarantees it survives the
round for both consumers to pick up.

### Returns

A typed result:
`{ dimensions, findings, perDimension, crossDimensionLeads, related, repaired }`
— `findings` is the flat list of validated finding paths, `perDimension`
carries each lane's `{ dimension, written, valid, repaired, searches, saturation }`
accounting, `crossDimensionLeads` the `{ from, lead }` pairs above, `related`
the relation-pass annotation count (0 when the pass was skipped), and the
top-level `repaired` the round's total defect count: how many findings
arrived schema-invalid or citation-defective and needed the Repair phase
before they validated (0 when every finding was clean on first write). This
is the disclosure surface [research-harness-template#623](https://github.com/modeled-information-format/research-harness-template/issues/623)
added: `research-pipeline`'s independent completion check threads this
number into its own prompt so a `finding_valid`/`citation_integrity`-shaped
check can never be graded `met` from the post-repair corpus state without
disclosing that repair happened — see
[The full-mode round loop](#the-full-mode-round-loop) below.

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
| `runDate` | required once a finding needs gating | — | A stamped ISO-8601 timestamp supplied by the caller from OUTSIDE the Workflow runtime. `new Date()`/`Date.now()` throw if called from inside this script's own body ("breaks resume") — this is the fix for [research-harness-template#618](https://github.com/modeled-information-format/research-harness-template/issues/618), where the crash was total (every finding needing gating, every real run). A working set of zero legitimately never touches this and needs nothing supplied. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Enumerate | haiku (low effort) | Resolves the working set from `scope`. One-round rule enforced structurally: any finding already carrying `extensions.harness.verification.attempted_at` is excluded before any model call, its `@id` itemized in `skippedAlreadyVerifiedIds` — except in `regate` mode, which includes them and leaves `skippedAlreadyVerifiedIds` empty. The same agent turn also returns `allFindingIds`: EVERY on-disk `@id` under `findings/`, derived mechanically via `find … \| sort`, never re-derived from the same reasoning that produced the working set. `reconcileEnumeration()` (deterministic code, [research-harness-template#625](https://github.com/modeled-information-format/research-harness-template/issues/625)) then — only for `scope: 'all'`, the one scope whose working set is meant to span the whole corpus — checks every `allFindingIds` entry is covered by `workingSet ∪ skippedAlreadyVerifiedIds`; a gap triggers one named retry naming the missing id(s), and a gap that survives the retry throws loudly rather than silently gating a partial working set (the exact failure #625 reported: `scope:'all'` enumerated 18 of 19 on-disk findings with nothing to catch the drop). Under a narrower scope (`dimension:*`, or an explicit `paths`/`ids` set including `regate`) the working set is a deliberate subset, so this reconciliation is skipped — `allFindingIds` is scope-independent and would otherwise falsely flag every out-of-scope finding. Separately, in `regate` mode a deterministic guard fails loudly (naming the offending id(s)) if enumeration nonetheless returns a non-empty `skippedAlreadyVerifiedIds` — regate's contract is that it stays empty (already-attempted findings must be re-opened, not skipped), and this is enforced in code rather than trusted from the enumeration agent's own compliance with that prompt wording. A working set past `claimBudget` is sliced; the remainder returns as `deferredIds`, logged, never silently dropped. |
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
| `genre` | no | `'general'` | The requested genre. Resolved against `harness.config.json` `packs[]` enablement before rendering (#633): only an ENABLED genre pack's real `Skill(<genre>:<genre>)` template is actually applied to the rendered report body; `'general'` or a disabled/absent genre pack renders the neutral script pipeline honestly under `genreArg="general"` — the report's own genre metadata never claims a genre whose template was not actually applied. See [Genre resolution](#genre-resolution-skillgenregenre-applied-only-when-enabled-633) below. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Report | sonnet | A same-process existence/non-empty/valid-JSON preflight check on `synthesisPath` (folded into the top of this phase, not a separate stage), then genre resolution against `harness.config.json` `packs[]` enablement (#633), then the `publish-report` skill's script pipeline: `synthesize-artifact.sh` → a REAL falsification pass over the report's own central claims via `falsify.sh` (never a hand-authored verdict) → `render-artifact.sh` → `mif-project.sh` → `Skill(<genre>:<genre>)` applied + re-confirmed only when that genre's pack is enabled. A `falsified` verdict quarantines the report — it is not shipped, and the module returns `ok: false` without proceeding to Index. |
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

### Genre resolution: `Skill(<genre>:<genre>)` applied only when enabled (#633)

Before this fix, `genre` flowed straight into `synthesize-artifact.sh` as
pass-through metadata — the deterministic script is genre-neutral by design,
so every requested genre rendered the identical findings-dump body with only
the frontmatter `genre:` field differing from a neutral render, indistinguishable
from a correctly-genred report without diffing bodies across two genres. The Report phase now resolves the requested genre **before**
rendering, mirroring `.claude/agents/report-synthesizer.md`'s own Step 2
("Resolve the genre (optional, pack-provided)") — the known-working
mechanism for the interactive `/start` path:

- `genre="general"` (the default) needs no lookup: it is definitionally the
  neutral render, `genreArg="general"`.
- Otherwise, an enablement check (`jq` over `harness.config.json packs[]`)
  determines whether the SPECIFIC requested genre's own pack is enabled —
  each genre ships as its own individually-toggleable pack, never a shared
  "reports" family pack. An **enabled** pack resolves `genreArg=<genre>` and
  a `genreSkillRef="<genre>:<genre>"`; after the script pipeline renders the
  neutral body, the Report phase invokes `Skill(<genre>:<genre>)` to
  restructure that body per the genre's real documented template (e.g.
  `engineering`'s mandatory Trade-offs comparison table, `briefing`'s
  Headline/What's New/Why It Matters/What's Next), built from the same
  artifact/synthesis claims already established — inventing nothing new,
  never touching the MIF frontmatter/citations/verdict fields the script
  pipeline already wrote — then re-confirms `mif-project.sh` since the body
  changed.
- A **disabled or absent** pack falls back to `genreArg="general"` instead
  of the originally-requested genre — the neutral pipeline renders, exactly
  as if no genre had been requested, and the report's own genre metadata
  reads `"general"`, never the unearned requested genre (mirrors
  `report-synthesizer.md`'s own rule that frontmatter must only claim a
  genre whose template was really applied).

The Report phase's returned `genreApplied` (boolean) and `genreSkillInvoked`
(the `"<genre>:<genre>"` reference, or `""`) make this outcome caller-visible
instead of silently cosmetic — see [Returns](#returns) below. A falsified
verdict (step 3) quarantines the report before either the genre resolution's
skill-application step or the provenance stamp ever runs:
`genreApplied=false`, `genreSkillInvoked=""`.
`research-deliverables.js` has a comparable `genres` pass-through gap for its
own artifact-based channels, tracked separately as
research-harness-template#640 — deliberately out of scope for this fix.

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
`{ ok, reportPath, reportId, mifLevel, checksAddressed, verificationVerdict, genreRequested, genreApplied, genreSkillInvoked, provenanceOutcome, provenanceReason, readmePath, readmeCheckPassed, graphRefreshed, graphAssertPassed, problems }`
— `ok` true only once the Verify phase reports both `lintClean` and
`schemaClean`, `reportPath`/`reportId` the rendered report's path and
supersession-stable `@id`, `mifLevel` the achieved MIF frontmatter level,
`checksAddressed` the goal check ids the report speaks to,
`verificationVerdict` the verdict `falsify.sh` actually wrote (never
hand-authored), `genreRequested` the raw `genre` arg as passed in,
`genreApplied`/`genreSkillInvoked` the genre resolution's outcome (#633 —
`true`/`"<genre>:<genre>"` only when that genre's pack was enabled and its
skill actually invoked; `false`/`""` for `"general"`, a disabled/absent
pack, or a falsified report), `provenanceOutcome`/`provenanceReason` the
`Skill(mif-docs:mif-provenance)` stamp attempt's outcome (#632 —
`"stamped"`/`"declined"`/`"error"`/`"not-applicable"`),
`readmePath`/`readmeCheckPassed`/`graphRefreshed`/`graphAssertPassed` the
Index phase's script-gate results, and `problems` the Verify phase's
targeted-gate findings. A report-falsification short-circuit instead returns
`{ ok: false, reason: 'report-falsified', reportPath, verificationVerdict:
'falsified', genreRequested, genreApplied: false, genreSkillInvoked: '' }`
before the Index phase ever runs.

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
| `channels` | no | `['blog']` | Requested channels — may mix artifact-based (`blog`, `book`) and source-direct (`pdf`, `jats`, `xbrl`, `ectd`, `notebooklm`, `github-discuss`, `github-issues`) channels in one call. The `['blog']` default applies ONLY when `channels` is absent/not an array (`Array.isArray` check, research-harness-template#626) — an explicit `channels: []` is honored as a real "render zero channels" answer, never silently coerced back to the default. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Route | haiku | A same-process preflight on `synthesisPath` (verbatim from `research-projection`'s guard), then classifies every requested genre×channel pair against `harness.config.json` `packs[]` and `.claude/settings.local.json`'s native `enabledPlugins` (`"<pack>@research-harness"` key shape — never a bare pack-name lookup) into a mechanism-tagged render plan. Every pair that cannot be served lands in `unavailable[]` with a reason naming the mechanism and exactly what is missing. |
| Render | sonnet | Mechanism 1 (artifact-based): `synthesize-artifact.sh` → synthesis-only cross-check against `synthesisPath` → `render-artifact.sh` → `Skill(<genre>:<genre>)` applied to the rendered body whenever genre≠`"general"` (#640 — that genre's pack enablement was already confirmed by Route, so no re-check is needed here) → `Skill(mif-docs:mif-provenance)` witnessed-provenance stamp (#632). Mechanism 2 (source-direct): `Skill(<pack>:<pack>)` invoked directly against the findings dir, `synthesisPath` never consulted, no genre axis (`genreApplied` always `false`), provenance stamp explicitly `not-applicable`. |
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

### Genre resolution: `Skill(<genre>:<genre>)` applied only when enabled (#640)

Before this fix, mechanism 1's Render step passed the resolved genre straight
into `synthesize-artifact.sh`/`render-artifact.sh` as pass-through metadata
and never invoked any genre's real template — every requested genre rendered
the identical neutral body, indistinguishable from a correctly-genred
deliverable without diffing bodies across two genres (the same defect class
`research-projection.js`'s [genre resolution](#genre-resolution-skillgenregenre-applied-only-when-enabled-633)
closed for the report channel, #633). This module already runs a dedicated
Route phase that resolves genre×channel servability — including pack
enablement — **before** Render ever starts, so unlike #633's fix, Render does
not need its own separate enablement re-check: any artifact-based row
reaching Render with a genre other than `"general"` already had that genre's
own pack confirmed enabled by Route.

- `genre="general"` renders the neutral body from `synthesize-artifact.sh` →
  `render-artifact.sh` unchanged — no skill invocation, `genreApplied=false`.
- Any other genre invokes `Skill(<genre>:<genre>)` (a new Render step,
  inserted between `render-artifact.sh` and the `#632` provenance stamp) to
  restructure the rendered body per that genre's real documented template —
  built from the same artifact claims already established, never inventing
  new content, never touching the citation/References section
  `render-artifact.sh` already wrote — then reports `genreApplied=true` and
  `genreSkillInvoked="<genre>:<genre>"`.
- Mechanism 2 (source-direct channel packs) has no genre axis at all — every
  row reports `genreApplied=false`, `genreSkillInvoked=""` regardless of
  whether a genre was requested alongside it (matching the existing
  "genre does not apply, ignore it" handling for these channels).

A caller-supplied genre string is validated against the same
`^[a-z][a-z0-9-]*$` pack-name pattern `harness.config.schema.json` enforces
before it is interpolated into either a shell command argument or a `Skill()`
reference (mirrors #633's own injection guard) — the module throws rather
than silently proceeding with an unvalidated string in either position.

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

A typed result: `{ ok, artifacts, unavailable }` — `artifacts[]` one entry per
successfully rendered deliverable (`path`, `genre`, `channel`, `mechanism`,
`citations`, `clean`, `genreApplied`, `genreSkillInvoked`, `provenanceOutcome`,
`provenanceReason`), `unavailable[]` every requested pair that could not be
served with its distinguishing reason, and `ok` true iff at least one
deliverable rendered. `genreApplied`/`genreSkillInvoked` are the genre
resolution's outcome (#640 — `true`/`"<genre>:<genre>"` only for a
mechanism-1 row whose genre was not `"general"`; `false`/`""` for a
`"general"` render or any mechanism-2 row). `provenanceOutcome`/
`provenanceReason` are the `Skill(mif-docs:mif-provenance)` stamp attempt's
outcome (#632 — `"stamped"`/`"declined"`/`"error"` for mechanism-1 rows,
`"not-applicable"` for mechanism-2 rows). An empty `plan[]` (nothing
servable) returns `{ ok: false, artifacts: [], unavailable }` before the
Render phase ever runs.

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

## research-add-dimensions

Atomic action B (add dimensions): widen the dimension set. Generator-critic
prompt chaining ending in a lineage event — sonnet Propose derives candidate
new dimensions from the goal, corpus leads, and user hints; sonnet Prune
attacks each candidate on overlap/scope/decision-relevance; Amend wires the
survivors into `harness.config.json` `dimensions[]` and mints a new goal
version. Source: `.claude/workflows/research-add-dimensions.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/goal.json` and `harness.config.json` `dimensions[]` the run reads and amends. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552/#556/#560/#564/#569/#573/#578 precedent), so a pipeline running inside a clone passes nothing. |
| `hints` | no | — | User-suggested dimensions or themes. Propose evaluates them against the goal and the existing dimension set rather than rubber-stamping them. |
| `leads` | no | — | `{from, lead}` pairs — `research-fanout`'s [`crossDimensionLeads`](#crossdimensionleads-routing) output: evidence a prior fan-out round could not house under any declared dimension. This is the strongest signal a dimension is missing; Propose treats it as first-class input alongside `hints`. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Propose | sonnet | Reads `reports/<topic>/goal.json` and `harness.config.json` `dimensions[]`, then derives at most 4 candidate dimensions — each a schema-legal id, a one-sentence description matching the config's dimension style, the evidence that no existing dimension can house it, and a methodology note. Zero candidates is a valid, non-error return. |
| Prune | sonnet | Skeptic pass over every candidate: overlap (is it really a subset/restatement of an existing dimension?), scope (does the goal's `out_of_scope`/`non_goals` exclude it?), decision-relevance (would findings on this axis change the goal's decision, or merely be interesting?). Rejects on any hit, with the specific reason; approves only what survives all three. |
| Amend | sonnet | Two ordered steps: (1) patches `harness.config.json` `dimensions[]` with each approved candidate's `{id, description}` (no `methodologyNote` field — that is goal-authoring context only) and validates against `harness.config.schema.json` with `ajv`; (2) mints the new goal version — see [Goal-version delegation](#goal-version-delegation-scriptsgoal-versionsh-not-a-freehand-hash) below. |

### Zero-candidate and all-rejected outcomes are valid, not errors

Propose returning no candidates, or Prune rejecting every candidate it was
given, are both normal, non-error short-circuits —
`{ added: [], rejected: [...or []], goalVersion: null }` — never a failure
the caller must handle specially. The current dimension set already holding
the evidence is an expected, even common, outcome of running this workflow;
the module returns early rather than forcing an Amend pass with nothing
approved. This is the same "an empty/no-op plan is a legitimate answer, never
surfaced as a failure" shape `research-augment`'s
[empty-plan outcome](#the-empty-plan-outcome-is-valid-not-an-error) already
established for its own Decide phase.

### Goal-version delegation: `scripts/goal-version.sh`, not a freehand hash

This is the as-built account of a confirmed gap, not a restatement of the
reference design: `research-add-dimensions.js`'s own vendoring header
records that the reference implementation's Amend phase instructs its agent
to compute the `gv-` content hash **freehand** — a prose description of the
algorithm (sha256 first-12-hex over the goal with `version`/`supersedes`/
`revision` stripped, keys sorted) for the agent to re-derive itself, rather
than invoking the script this repo already ships for exactly that purpose.
This is the same class of "delegate to a real, existing mechanism instead of
reimplementing it via a free-form prompt" gap Epics #543/#544/#545
(`research-projection`/`research-deliverables`/`research-augment`) found and
fixed for their own script- and skill-delegated phases — cited here rather
than restated.

The fix wires Amend to the same snapshot-then-mint idiom already established
for goal evolution (`.claude/commands/goal-writer.md`'s update flow;
`research-goal.js`'s own re-authoring branch): snapshot the live goal to
`reports/<topic>/goals/goal-<OLD>.json` **before** editing, apply the
dimension-widening delta, then mint `OLD`/`NEW` by actually running
`bash scripts/goal-version.sh reports/<topic>/goal.json` — once before the
edit, once after — and stamp `.version`/`.supersedes`/`.revision` with `jq`.
The agent returns the version it read back from the amended `goal.json`
after minting, never a value it would have computed itself. This is a
deliberate deviation from the reference implementation's own Amend-phase
text, not carried forward as-is.

### Goal lineage: ADR-0006 (`proposed`, not yet `accepted`)

The immutability rule Amend's goal-minting step enforces — a goal is fixed
per version, and widening the dimension set is an append to that version's
lineage, never an in-place edit of the live `goal.json` — is
[ADR-0006: Content-hashed, append-only goal versioning](../adr/0006-content-hashed-append-only-goal-versioning.md).
Cited here rather than restated; see that record for the content-hash
scheme, the `supersedes`/`revision` fields, and the findings-reuse
rationale. ADR-0006's own status is **`proposed`**, not `accepted` — it
records a design this module (and `research-goal`'s re-authoring branch)
already implements against, but the record itself has not been promoted to
accepted, and nothing in this Epic changes that status. `supersedes` points
at the prior version's real id, never `null` — this module only ever runs
against an already-existing `goal.json` (the Propose phase reads it as its
own precondition), so `OLD` is always the `gv-` id
`scripts/goal-version.sh` computes over that live content.
(`schemas/goal.schema.json`'s `null` case covers a topic's genuinely first
goal, before any content exists to hash — out of scope for an add-dimensions
call, which widens an existing goal.)

### Propose's homeless-evidence inputs and Prune's attack surface are carried from the reference unchanged

Unlike the Amend-phase goal-version delegation above, the Propose phase's
`hints`/`leads` inputs and the Prune phase's three-attack skeptic pass
(overlap/scope/decision-relevance) are carried forward from the reference
design largely as specified — a candidate surviving Prune must be justified
as something existing dimensions genuinely cannot house, never merely
"related but distinct."

### Supersession: widening becomes a standalone typed workflow, not folded into `/goal-writer --reshape`

For engine-composed dimension-widening, `research-add-dimensions`
**supersedes** `/goal-writer --reshape`'s role for the widen-only case —
Decision D-7 of the workspace research-pipeline architecture document (the
source this module was vendored from) states the rationale: before this
module, widening the dimension set had command support only
(`/goal-writer --reshape`, a conversational path) with no engine
integration, and the `crossDimensionLeads` homeless-evidence payload
(`research-fanout`, #540) had no consumption path at all. Cited here rather
than restated; see that document's "D-7 — Steering decisions are first-class
atomic workflows" section and its "Atomic action B — add dimensions" section
for the fuller generator-critic rationale and flowchart.

What is *not* superseded: `/goal-writer --reshape` remains the interactive
path for an actual goal *reshape* (a changed question — atomic action C,
[`research-pivot`](#research-pivot), vendored under Epic #547 — see that
section below for its own supersession relationship with
`/goal-writer --reshape`) and for any conversational dimension change a
user drives directly; this module is the engine-composed widen-only path,
invoked with an explicit `hints`/`leads` payload rather than a dialogue
turn. Its `fanoutPlan` output hands the newly-added dimensions to
`research-fanout` for the very next round — the same "typed hand-off, no
filesystem coordination" contract every other module on this page already
follows.

### Returns

A typed result: `{ added, rejected, goalVersion, supersedes, fanoutPlan }` —
plus the early-return shape `{ added: [], rejected: [], goalVersion: null }`
from either short-circuit above — `added` the approved dimension ids
actually wired into `harness.config.json` and the new goal version,
`rejected` the Prune phase's `{ id, why }` pairs, `goalVersion` the `gv-` id
`scripts/goal-version.sh` computed over the new goal content, `supersedes`
the prior version's real id (never `null` once Amend runs — this module
only widens an already-existing goal, so `OLD` is always a real `gv-` id),
and `fanoutPlan` a `{ dimensions, depth: 'standard' }` hint for the
orchestrator to fan out only the newly-added dimensions next round.

## research-pivot

Atomic action C (pivot research focus): the question itself changes.
Sonnet Reshape mints a new goal version in the append-only `gv-` lineage
from a required `delta` (snapshot, delta applied, content-hash identity,
`supersedes`, `revision`); parallel haiku Classify batches grade every
existing finding against the NEW goal as carry / stale / out-of-scope —
findings are gathered once and reused across goal versions, classification
never deletes; sonnet Plan computes `gapDimensions` (which dimensions the
carried corpus cannot answer the new checks from) and `reverifyIds` (the
stale re-gate list). Source: `.claude/workflows/research-pivot.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/goal.json` the run reshapes and whose `reports/<topic>/findings/` the Classify phase grades. A missing `topic` throws before any phase runs. |
| `delta` | yes | — | What changed and why. A pivot without a stated delta throws before Reshape runs — see [Delta-required refusal](#delta-required-refusal-and-out-of-scope-findings-kept-unused-are-both-non-error) below. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552/#556/#560/#564/#569/#573/#578/#582 precedent), so a pipeline running inside a clone passes nothing. |
| `batchSize` | no | `15` | Findings graded per Classify batch. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Reshape | sonnet | `reports/<topic>/goal.json` must already exist — pivot **evolves** an existing goal, it never authors one fresh; if it is missing, the phase stops and reports that `/goal-writer` must run first (an explicit precondition this phase states in its own prompt, not carried from another module). Applies the delta to `goal_statement`/`scope`/`dimensions`/`completion_condition`, then mints the new version — see [Goal-version delegation](#goal-version-delegation-scriptsgoal-versionsh-not-a-freehand-hash-a-third-time) below. Returns the new `goalVersion`/`supersedes` (both read back from `goal.json` after minting, never a self-computed value), the new/dropped dimension ids, the new check ids, and the new `goal_statement`. |
| Classify — List | haiku (low effort) | Lists the `@id` of every finding under `reports/<topic>/findings/` (quarantine/archive siblings excluded). |
| Classify — grade | haiku, parallel batches of `batchSize` | Grades every listed finding against the NEW goal version as `carry` (in the new scope, evidence still current), `stale` (in scope, but its verification predates what the delta changed, or its evidence is time-sensitive and old — needs **re-gating**, not re-gathering), or `out-of-scope` (the new scope/`non_goals` exclude it — it stays on disk, simply unused by this version). Classification never deletes a finding file, regardless of class. |
| Plan | sonnet | Reads the carried/stale id lists, the new checks, and the new/dropped dimensions; decides `gapDimensions` — always including the brand-new dimensions, plus any existing dimension whose carried evidence cannot answer the new checks — and returns `reverifyIds` (the stale list) plus a rationale. |

### Delta-required refusal and out-of-scope-findings-kept-unused are both non-error

A pivot call with no `delta` throws before Reshape runs
(`research-pivot: args.delta is required — a pivot without a stated delta
is not a pivot`) — a hard precondition, not a soft default to an empty
delta, since a pivot with no stated change is a contradiction in terms, not
a degenerate case to tolerate. Separately, and explicitly **not** an error
path: findings the Classify phase grades `out-of-scope` are never deleted,
moved, or quarantined — they stay on disk under `reports/<topic>/findings/`,
simply unreferenced by the new goal version's evidence pool. This mirrors,
for the findings a goal version's evidence draws from, the same append-only,
nothing-discarded posture ADR-0006 already imposes on the goal document
itself.

### The falsify regate hookup: `reverifyIds` feeds `research-falsify` directly, no adapter

This is stated as a **verified fact**, not an assumed interface — both
modules' real signatures were read before writing this section, not carried
forward from the reference design's prose. `research-pivot`'s `reverifyIds`
is a plain array of finding `@id` strings (the Plan phase's stale list).
[`research-falsify`](#research-falsify)'s `scope` argument accepts exactly
`'all' | 'dimension:<d>' | { paths?: string[], ids?: string[] }`, and its
`regate: true` flag is gated to require that explicit `paths`/`ids` scope —
it throws on `'all'`/`'dimension:*'` (see falsify's
[Regate section](#regate-a-client-side-verification-block-reset)).
`reverifyIds` already **is** that `ids[]` array, so the orchestrator hookup
is a direct pass-through with zero translation:

```js
research-falsify({ ..., scope: { ids: pivotResult.reverifyIds }, regate: true })
```

No adapter, wrapper, or field-renaming sits between pivot's output shape and
falsify's scope-argument shape — this is the one intended way stale
findings get re-gated after a pivot; they are never re-gathered.

### Goal-version delegation: `scripts/goal-version.sh`, not a freehand hash (a third time)

This is the as-built account of a confirmed gap, not a restatement of the
reference design: `research-pivot.js`'s own vendoring header records that
the reference implementation's Reshape phase instructs its agent to
compute the `gv-` content hash **freehand** — a prose description of the
algorithm for the agent to re-derive itself, rather than invoking the
script this repo already ships for exactly that purpose. This is the same
class of "delegate to a real, existing mechanism instead of reimplementing
it via a free-form prompt" gap Epics #543/#544/#545/#546
(`research-projection`/`research-deliverables`/`research-augment`/
`research-add-dimensions`) found and fixed for their own script-, skill-,
and goal-version-delegated phases — cited here rather than restated.

The fix wires Reshape to the same snapshot-then-mint idiom already
established for goal evolution (`.claude/commands/goal-writer.md`'s
`--reshape` flow; `research-add-dimensions.js`'s own Amend phase): snapshot
the live goal to `reports/<topic>/goals/goal-<OLD>.json` **before** editing,
apply the stated delta, then mint `OLD`/`NEW` by actually running
`bash scripts/goal-version.sh reports/<topic>/goal.json` — once before the
edit, once after — and stamp `.version`/`.supersedes`/`.revision` with `jq`.
The agent returns the version it read back from the amended `goal.json`
after minting, never a value it would have computed itself. This is a
deliberate deviation from the reference implementation's own Reshape-phase
text, not carried forward as-is.

`research-pivot` is the **third** module in this codebase to invoke
`scripts/goal-version.sh` for `gv-` minting — after `research-goal.js`'s
re-authoring branch (whose own vendoring header already routes through it,
confirmed by inspection — it was written this way from the start and never
carried the freehand-hash gap the other two did) and
`research-add-dimensions.js`'s Amend phase (the confirmed-gap fix Epic #546
made, closing the exact same freehand-hash gap this section fixes for
Reshape). `scripts/goal-version.sh` itself has delegated to the canonical
`mif-rh-cli` engine mechanism since the Category-B cutover
(research-harness-template#276, Story #298) — this module's own vendoring
header cites that history, not restated in full here. Precision worth
stating explicitly: `research-falsify`'s
regate-reset is the complementary **consumer** side of this same ADR-0006
lineage event — it re-opens verification for findings a goal-version pivot
already classified stale (see falsify's
[Regate section](#regate-a-client-side-verification-block-reset)) — but it
does not itself mint a `gv-` version and never calls
`scripts/goal-version.sh`; confirmed by inspection of
`research-falsify.js`, which contains no `goal-version.sh` invocation
anywhere in its source. Minting a lineage version and reacting to one
having been minted are two distinct roles, not the same delegation counted
twice.

### Goal lineage: ADR-0006 (`proposed`, not yet `accepted`)

The immutability rule Reshape's goal-minting step enforces — a goal is
fixed per version, and a pivot is an append to that version's lineage,
never an in-place edit of the live `goal.json` — is
[ADR-0006: Content-hashed, append-only goal versioning](../adr/0006-content-hashed-append-only-goal-versioning.md).
Cited here rather than restated; see that record for the content-hash
scheme, the `supersedes`/`revision` fields, and the findings-reuse
rationale. ADR-0006's own status is **`proposed`**, not `accepted`,
verified fresh against `docs/adr/0006-content-hashed-append-only-goal-versioning.md`'s
frontmatter at documentation time (unchanged from the `proposed` status
Task #583 recorded for the same record) — it records a design this module
(and `research-goal`'s re-authoring branch, and `research-add-dimensions`'
Amend phase) already implements against, but the record itself has not been
promoted to accepted, and nothing in this Epic changes that status.
`supersedes` is never `null` here — Reshape only ever runs against an
already-existing `goal.json` (its own first precondition check), so `OLD`
is always a real `gv-` id `scripts/goal-version.sh` computes over that live
content. (`schemas/goal.schema.json`'s `null` case covers a topic's
genuinely first goal, before any content exists to hash — out of scope for
a pivot call, which reshapes an already-existing goal.)

### Cross-reference: the workspace architecture document's design rationale

The fuller design rationale and the
`Reshape → List → Classify(batches of 15) → Plan` flowchart this module was
vendored from live in the workspace research-pipeline architecture
document's "Atomic action C — pivot research focus" section — cited here
rather than restated; see that document for the mermaid flow and the
container catalog this module implements against.

That document's own description of the version-minting step is the
abstracted `content-hash`/`gv-hash identity` shorthand shown in its
flowchart — it does not itself specify a computation mechanism, so there is
no literal contradiction between it and this module. Where this vendored
module's real delegation differs is one level down, against the **upstream
reference implementation's actual Reshape-phase prompt text** (recorded in
`research-pivot.js`'s own vendoring header, not in the architecture
document): that reference text instructs a **freehand, prose-derived** hash
computation, which this module deliberately replaces with the concrete
`scripts/goal-version.sh` delegation described above — see
[Goal-version delegation](#goal-version-delegation-scriptsgoal-versionsh-not-a-freehand-hash-a-third-time).

### Supersession: the actual reshape case, not the widen-only case

`research-add-dimensions` (Epic #546) supersedes `/goal-writer --reshape`
only for the widen-only case (adding dimensions with no other change to the
goal). `research-pivot` is the engine-composed counterpart for the case
`research-add-dimensions`' own docs left open: an actual reshape — a
changed question, dropped/reweighted dimensions, a revised decision. For
engine-composed pivots, this module's classify-then-plan chain supersedes
running `/goal-writer --reshape` and then hand-driving re-verification
decisions in conversation; what is *not* superseded is the command itself,
which remains the interactive path for a user-driven reshape or for any
reshape outside a pipeline's typed composition.

### Returns

A typed result:
`{ goalVersion, supersedes, goalStatement, carry, stale, outOfScope, gapDimensions, reverifyIds, rationale }`
— `goalVersion`/`supersedes` the new/old `gv-` ids `scripts/goal-version.sh`
computed, `goalStatement` the reshaped goal's new statement, `carry`/`stale`/
`outOfScope` the Classify phase's three finding-id buckets, `gapDimensions`
the dimensions the next fan-out round should target (falling back to just
the new dimensions if Plan fails), `reverifyIds` the stale-list handed
straight to `research-falsify`'s `scope.ids`/`regate: true` (falling back to
the `stale` bucket itself if Plan fails), and `rationale` Plan's stated
reasoning (or a defaulted-fallback note if the Plan agent failed).

## research-import

Atomic action D (include pre-existing findings): bring an external MIF
Container (or a loose pre-existing finding set) into the topic through the
fail-closed import gate. Haiku DryRun runs the mechanical gate
(`scripts/mif-container-import.sh --dry-run`) against manifest schema,
digests, and ontology-binding compatibility — any failure rejects with
nothing written; sonnet Review then judges what that mechanical gate cannot
see (same-`@id`-different-content collisions, provenance coherence, scope
fit against the topic's goal) — a genuine NO-GO is possible even after
DryRun passes; haiku Apply runs the real import (fail-closed, no partial
writes) and enumerates what landed: imported `@id`s, which carry a foreign
verification verdict, and which are wholly unverified. Source:
`.claude/workflows/research-import.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` receives the import and whose `goal.json` Review checks scope fit against. A missing `topic` throws before any phase runs. |
| `containerDir` | yes | — | Directory holding `mif-package.json` and the container's resources, as produced by `/export`. A missing `containerDir` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552/#556/#560/#564/#569/#573/#578/#582/#586 precedent), so a pipeline running inside a clone passes nothing. |
| `trustImportedVerdicts` | no | `false` | When `false` (the default), every foreign-verdict finding is queued for re-gating alongside the wholly-unverified set — imported evidence is never exempt from gating by default. When `true`, only the wholly-unverified subset queues; findings the source instance already verified are trusted as-is. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| DryRun | haiku (low effort) | Runs `bash scripts/mif-container-import.sh "<containerDir>" "<topic>" --dry-run` and reports its ordered validation results verbatim (manifest schema, per-resource + manifest-level digests, ontology-binding compatibility against this instance's cataloged packs — ADR-0017). The topic must already be registered; if the gate says otherwise, `passed` is `false`. A `passed: false` result short-circuits with `{ ok: false, stage: 'dry-run', detail }` — nothing is written. |
| Review | sonnet | Judges the three things the mechanical gate cannot: (1) `@id` collisions — container resource ids already present under the topic's `findings/` (the gate itself is idempotent, but a silent same-id overwrite of *different* content is a no-go); (2) provenance plausibility — does the manifest's origin metadata cohere with its actual contents; (3) scope fit — sampled container findings against the topic's `goal.json` scope, since a container that is mostly out-of-scope is worth rejecting before it dilutes the corpus. `proceed: false` (with `reasons`) short-circuits with `{ ok: false, stage: 'review', detail }` before anything is applied. |
| Apply | haiku | Runs `bash scripts/mif-container-import.sh "<containerDir>" "<topic>"` (no `--dry-run`) — a failure at any step rejects the whole import, never a partial hand-written fallback. Enumerates every `@id` that landed under the topic's `findings/`, partitioned into which carry a **foreign** `extensions.harness.verification.attempted_at` (a verdict already minted by the source instance — a placeholder verification block with no `attempted_at` still counts as unverified) and which have no `attempted_at` set at all. Reports only — it never edits a verification block itself. |

### Confirmed clean delegation — no reimplementation gap, unlike #543–#547's vendor Tasks

This is a **verified clean pass**, stated explicitly rather than left implicit: unlike every other module vendored in this Epic chain — Epics #543, #544, #545, #546, and #547's vendor Tasks each found and fixed a real freehand-reimplementation gap in their own reference source (a script or skill the reference prompt told an agent to re-derive by hand instead of invoking) — `research-import.js` has **no analogous gap**. Read line by line against the actual reference source before vendoring: the DryRun phase's prompt runs exactly `scripts/mif-container-import.sh ... --dry-run` and reports the gate's own ordered results; the Apply phase runs the identical script without `--dry-run`. Neither phase's prompt describes or
re-derives any manifest/digest/ontology-binding logic freehand anywhere in
the module — the entire mechanical validation surface is delegated to the
real `scripts/mif-container-import.sh` (Stories #318–#328's fail-closed,
ordered, no-partial-write design, confirmed present and matching its own
header comment).

The delegation bar was held especially high here because this is the *one*
workflow in the whole chain that ingests **untrusted external input** —
another harness instance's export container, not this instance's own
research output. The fail-closed gate's integrity depends entirely on zero
freehand duplication of its manifest/digest/ontology-binding checks: a
prompt that re-derived even one of those checks by hand would be an
untrusted-input validation path with no script backing it, exactly the
class of gap the other four modules' Tasks in this Epic had to close for
their own (lower-stakes, same-instance) delegated surfaces.

ADR-0017 ([MIF Container: an instance-scoped export/import manifest
format](../adr/0017-mif-container-instance-scoped-export-import-format.md))
governs the container format `mif-container-import.sh` validates against.
Its status, verified fresh against the record's own frontmatter at
documentation time rather than inherited from another module's assumption
— #546's and #547's docs Tasks each recorded their own cited ADR
(ADR-0006) as `proposed`, not yet `accepted`, at their own documentation
time — is **`accepted`**.

### The falsify regate hookup: `needsGating` feeds `research-falsify` directly, with a `regate: true` nuance beyond #547's

This is stated as a **verified fact**, not an assumed interface — both
modules' real signatures were read before writing this section. `needsGating`
is a plain array of finding `@id` strings, and
[`research-falsify`](#research-falsify)'s `scope` argument accepts exactly
`'all' | 'dimension:<d>' | { paths?: string[], ids?: string[] }`. `needsGating`
already **is** that `ids[]` array, so — as with #547's `reverifyIds` hookup —
the orchestrator composes it with zero adapter:

```js
research-falsify({ ..., scope: { ids: importResult.needsGating }, regate: true })
```

`research-import` is the **second** module whose gating output feeds
`research-falsify`'s `scope` argument via `{ ids }` this way, after
`research-pivot`'s `reverifyIds` — see [pivot's own regate-hookup
section](#the-falsify-regate-hookup-reverifyids-feeds-research-falsify-directly-no-adapter)
for the precedent, cited here rather than restated.

The one real difference between the two hookups is *why* `regate: true` is
needed. Pivot's `reverifyIds` always needs it — every id in that list is
stale-by-definition (a goal-version pivot classified it so), so its prior
verification block is this instance's own, just outdated. Import's
`needsGating` needs it for a different, instance-external reason: when
`trustImportedVerdicts` is `false` (the default), `needsGating` also
includes `withForeignVerdicts` ids, and those already carry a **foreign**
`extensions.harness.verification.attempted_at` block — written by the
*source* instance, not this one. Without `regate: true`, `research-falsify`'s
one-round rule would silently skip every one of them at Enumerate (that
phase excludes anything already carrying `attempted_at`, foreign or not,
before any model call — see [research-falsify](#research-falsify)'s own
Enumerate phase). `research-falsify`'s existing client-side [regate-reset
step](#regate-a-client-side-verification-block-reset) — the same mechanism
`research-pivot`'s hookup already uses, not a separate "import-reset"
mechanism — clears whatever verification block is present, foreign or
stale, before re-invoking `falsify.sh`, so either source of a pre-existing
`attempted_at` is handled identically once `regate: true` is passed.

Passing `regate: true` is safe and idempotent even for the plain
`unverified` members of `needsGating` — findings that carry no prior
verification block at all, foreign or otherwise. The regate-reset step's
`jq 'del(.extensions.harness.verification)'` is a no-op on a finding with
no such block to delete, so the orchestrator hookup above passes
`regate: true` unconditionally for the whole `needsGating` array rather
than branching on which subset actually needs it.

### Cross-reference: the workspace architecture document's design rationale

The fuller design rationale for this module — the fail-closed-gates
chaining pattern, the never-exempt-from-gating posture, and the
`DryRun → Review → Apply` flowchart this module was vendored from — lives
in the workspace research-pipeline architecture document's "Atomic action
D — include pre-existing findings" section, cited here rather than
restated; see that document for the mermaid flow and the container catalog
this module implements against.

### Returns

A typed result: `{ ok, imported, needsGating, trustedForeignVerdicts, collisionsChecked }`
— `imported` the Apply phase's full `importedIds` list, `needsGating` the
`unverified` set (plus `withForeignVerdicts` unless `trustImportedVerdicts`
is `true`) handed straight to `research-falsify`'s `scope.ids`/`regate: true`
per the hookup above, `trustedForeignVerdicts` the `withForeignVerdicts` ids
excluded from gating when `trustImportedVerdicts` is `true` (else empty),
and `collisionsChecked` the Review phase's `@id`-collision list. Any
short-circuit instead returns `{ ok: false, stage: 'dry-run' | 'review' | 'apply', detail }`
with the failing phase's own result attached — nothing is imported and
nothing is queued for gating.

## research-coverage-audit

Atomic action Z (corpus audit): a multi-modal sweep, not a decision or a
gate. Six parallel **blind** auditors each probe the topic's corpus a
different way; a sonnet completeness critic asks what no auditor covered
and spot-checks its top suspicions; a sonnet prioritizer merges both sets
into a single **routed** backlog — every item names which workflow fixes
it. Source: `.claude/workflows/research-coverage-audit.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic whose `reports/<topic>/findings/` (plus `quarantine/`/`archive/` siblings), `goal.json`, and `knowledge-graph.json` (if present) the sweep reads. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance. The in-repo default is the instance root (the #552/#556/#560/#564/#569/#573/#578/#582/#586/#590 precedent), so a pipeline running inside a clone passes nothing. |
| `leads` | no | — | Accumulated `{ from, lead }` pairs — the same `crossDimensionLeads` shape `research-fanout` emits and `research-add-dimensions` consumes (see that module's [Args](#research-add-dimensions)). Folded into the `homeless-leads` auditor's brief when supplied; the sweep runs standalone without it. |
| `checkCoverage` | no | — | A `research-synthesis` per-check grade list. Folded into the `check-traceability` auditor's brief when supplied. |

### The six blind auditors

Each auditor sees only the corpus and its own modality brief — never the
other five auditors' output — so the panel's coverage is a genuine sweep,
not five agents converging on the same signal.

| Auditor | Model | Probes |
| --- | --- | --- |
| `thin-dimensions` | haiku | Per-dimension finding counts weighed against how many of the goal's `completion_condition.checks[]` each dimension is supposed to carry. |
| `staleness` | haiku | Verdict-based staleness (anything not `survived`) and age-based staleness (oldest `created` dates), plus time-sensitive claims a recent event could have superseded. |
| `quarantine-review` | haiku | The quarantine ledger: what sits there, why, and whether any falsification basis has plausibly expired. |
| `graph-orphans` | haiku | Graph connectivity: findings with no relationship edge, single-edge concepts/entities, and suspiciously absent relationship types. |
| `check-traceability` | sonnet | For each goal completion check, which surviving finding `@id`s actually bear on it — flags checks resting on zero/one finding or all-weakened evidence. |
| `homeless-leads` | sonnet | Leads that fit no declared dimension, plus findings whose dimension pin looks like a force-fit — the raw signal for `research-add-dimensions`. |

### Phases

| Phase | Model | What it does |
| --- | --- | --- |
| Sweep | haiku ×4, sonnet ×2 (parallel) | Runs all six auditors above concurrently via `parallel()`; each returns a schema-valid `{ modality, items[] }` (an empty `items[]` is a valid "verified genuinely nothing" result, not a failure). |
| Critique | sonnet | Given every auditor's items, asks what modality nobody ran (citation rot? contradiction density? ontology-pin drift? concordance drift across topics?) and spot-checks its top 2 suspicions against the real corpus, reporting only what it actually finds. |
| Prioritize | sonnet | Merges the sweep's items with the critic's `extraItems`, deduplicates same-action-and-target entries, and ranks by unmet-check impact, then severity, then cost — emitting the routed backlog. |

### Per-auditor discover-skill cross-reference — not a blanket subsumption

The epic's own framing — that this module "subsumes much of the `discover`
skill's audit role" — is accurate for only part of the panel, not the
whole thing. `discover` ([`.claude/skills/discover/SKILL.md`](../../.claude/skills/discover/SKILL.md))
only ever **reports**; it never routes a finding to the workflow that fixes
it. Stated per auditor rather than as one blanket claim:

| Auditor | Relationship to `discover` |
| --- | --- |
| `thin-dimensions` | Substantive overlap: delegates its count computation to the same `jq` pipeline `discover --gaps` uses, adapted from `harness.config.json`'s corpus-wide taxonomy to this topic's own `goal.json` `dimensions[]`. The auditor's own judgment (weighing counts against how many completion checks a dimension carries) is layered on top — `discover --gaps` itself has no notion of checks. |
| `staleness` | Substantive overlap: delegates both signals verbatim to `discover --stale`'s two pipelines (the index's verdict filter; the raw finding files' `created`-date extraction). The auditor's own judgment (recent-event awareness — a claim can be stale even when young) is layered on top. |
| `graph-orphans` | Related, not identical: both are graph-derived, but `graph-orphans` runs the **inverse** of `discover --clusters` — it flags nodes with *no* (or one) edge, where `--clusters` groups nodes that *share* edges. Do not read this as the same signal run twice. |
| `quarantine-review` | No `discover` equivalent — net-new. `discover` has no quarantine-ledger analysis at all. |
| `check-traceability` | No `discover` equivalent — net-new. `discover` has no concept of a goal completion check. |
| `homeless-leads` | No `discover` equivalent — net-new. `discover`'s coverage-gaps output is corpus-wide-taxonomy-relative; it does not surface evidence that fits no dimension at all, nor force-fit pins. |

The completeness critic and the prioritizer/routing layer have no
`discover` equivalent either — they are net-new capability the corpus never
had before this module, on top of the two auditors that genuinely overlap
`discover`'s existing reporting.

This module's own vendoring header describes the delegation the same way
`research-augment.js`'s "[Assess is discover-delegated, not a
re-derivation](#assess-is-discover-delegated-not-a-re-derivation)" section
does — a documentation-level citation of shared method (the same `jq`
pipelines, invoked from a prompt), not a live runtime call to the `discover`
skill. Neither module invokes `discover` at runtime (confirmed by reading
both `.js` sources in full: `discover` is a `SKILL.md`, not a script either
module's code calls); both describe the relationship consistently rather
than implying one has a more literal delegation than the other.

### The routed backlog: `target` is a routing signal, not a directly-forwardable arg

The prioritizer's backlog entries are `{ action, target, why, priority }`,
where `action` is one of `augment | add-dimensions | falsify | import |
projection | manual`. `target` names *what* the item is about (a dimension
id, finding `@id`, check id, or file) — it does not, by itself, assemble
into the named workflow's own args shape:

| Routes to | That workflow's args | Gap a consumer must close |
| --- | --- | --- |
| `augment` | [`research-augment`](#research-augment): `{ harnessDir, topic, focusHint?, checkCoverage? }` | `focusHint` accepts free text ("a dimension or unmet check ids"), so `target` maps here directly. |
| `add-dimensions` | [`research-add-dimensions`](#research-add-dimensions): `{ harnessDir, topic, hints?: string[], leads? }` | `hints` is an array; a bare `target` string needs wrapping (`[target]`). |
| `falsify` | [`research-falsify`](#research-falsify): `{ harnessDir, topic, scope?: 'all' \| 'dimension:<d>' \| { paths?, ids? } }` | `scope` is a tagged union — none of which is a bare string; the consumer must construct one of these shapes from what `target` actually references. |
| `import` | [`research-import`](#research-import): `{ harnessDir, topic, containerDir: string }` | `containerDir` is required and names a real exported MIF package directory (as `/export` produces). A corpus audit cannot manufacture one — a `target` routed here means "go obtain an external export," not a ready arg. |
| `projection` | [`research-projection`](#research-projection): `{ harnessDir, topic, synthesisPath, slug?, genre? }` | `synthesisPath` is a same-process-only ephemeral handle from a preceding `research-synthesis` call. An audit run standalone has none — a `target` routed here means "re-run synthesis, then projection," not a direct call. |
| `manual` | — (no workflow) | Needs a human decision; the backlog item's `why` says what decision. |

Per the architecture document's own flowchart (cited below), the
orchestrator's `mode: audit` returns this backlog as a **report** — it does
not auto-dispatch any of the five workflows itself. Closing the gaps above
is deliberately left to a future consumer (most likely #550, the
not-yet-vendored orchestrator), not silently assumed away by this module.

### Cross-reference: the workspace architecture document's design rationale

The fuller design rationale for this module — the six-auditor blind-panel
design, the completeness critic, and the prioritizer/routing flowchart this
module was vendored from — lives in the workspace research-pipeline
architecture document's "Atomic action Z — corpus audit" section, cited
here rather than restated; see that document for the mermaid flow and the
orchestrator's `mode: audit` composition.

### Returns

A typed result: `{ backlog, summary, rawItems, uncoveredAngles }` —
`backlog` the prioritizer's ranked, routed entries (see the routing table
above), `summary` its 3-sentence recap (or a raw-items fallback note if the
prioritizer itself fails), `rawItems` every auditor item plus the critic's
`extraItems` before merge/dedup/ranking, and `uncoveredAngles` the critic's
list of modalities no auditor ran.

## research-pipeline

The workflow-of-workflows: a deterministic mode router plus a bounded
autonomous round loop, composing all eleven sibling modules above via
`workflow()`. This is the **only** module in the set that composes — every
other module on this page bottoms out in `agent()`/`parallel()` calls, never
in a nested `workflow()` call of its own (re-confirmed by grepping all eleven
siblings for `workflow(` at implementation time: zero real composition
calls). The platform's one-level `workflow()` nesting rule means the eleven
atomic modules only ever *return* plans or results for this script to act
on — they never invoke a child workflow themselves. Source:
`.claude/workflows/research-pipeline.js`.

### Args

| Arg | Required | Default | Description |
| --- | --- | --- | --- |
| `topic` | yes | — | Topic the run operates against. A missing `topic` throws before any phase runs. |
| `harnessDir` | no | `.` | Path to the harness instance (the #552-precedent in-repo default every sibling module already uses). |
| `mode` | no | `'full'` | `'full' \| 'augment' \| 'pivot' \| 'import' \| 'audit' \| 'deliverables'` — selects the mode-router branch; see [Mode router](#mode-router) below. An unrecognized mode string throws (`unknown mode '<mode>'`) rather than silently falling through to `full`. |
| `ask` | no | `''` | `full` mode: the raw research ask passed to the `research-goal` child workflow. An empty string lets that workflow derive the sharpest goal from the topic's existing context. |
| `maxRounds` | no | `3` | `full` mode: caps the round loop. |
| `genres` / `channels` | no (required for `deliverables` mode, at least one) | — | `full` mode: `genres` now also drives the **Project phase**'s per-genre canonical-report loop (research-harness-template#650), taking priority over the goal's own elicited `deliverables.genres` when both are present — see [Project phase: per-genre canonical reports](#project-phase-per-genre-canonical-reports-research-harness-template626) below. `channels` (and `genres` when the Deliver phase actually runs) drives the **Deliver phase**: an explicit `Array.isArray` arg here always wins outright; when omitted, the Deliver phase falls back to that same field on the goal's own `deliverables` (`goal.deliverables.genres`/`.channels`, elicited by `/goal-writer`). The Deliver phase is channel-gated, not genre-gated (research-harness-template#650): it fires only when a channel was actually requested (CLI `--channels` or the goal's `deliverables.channels`) — genres alone, with no channel requested anywhere, route only through the Project phase and never touch the Deliver phase / blog fallback. `deliverables` mode: at least one of the two is required — the script throws `deliverables mode requires args.genres or args.channels` if both are omitted. |
| `focusHint` | no | — | `augment` mode: a steer for the deepening judge, passed straight through to `research-augment`. |
| `delta` | yes for `pivot` | — | `pivot` mode: what changed. The script throws `pivot mode requires args.delta` if omitted. |
| `containerDir` | yes for `import` | — | `import` mode: the MIF Container directory (as `/export` produces). The script throws `import mode requires args.containerDir` if omitted. |
| `trustImportedVerdicts` | no | `false` | `import` mode: passed through to `research-import` unchanged. |
| `claimBudget` / `queryBudget` / `lenses` | no | — | Passed through to every internal `research-falsify` call (`falsifyAll()`'s drain loop and the `pivot` regate call). |
| `workflowsDir` | no | `.claude/workflows` | Where the sibling atomic modules live; `wf(name, …)` resolves each child as `${workflowsDir}/research-<name>.js`. |
| `runDate` | required except `audit`/`deliverables` modes | — | A stamped ISO-8601 timestamp from THIS SCRIPT'S OWN CALLER (the `/research` command's own `date` invocation, run before it calls the `Workflow` tool) — this script cannot compute one itself (`new Date()`/`Date.now()` throw inside a Workflow-runtime script's own body; [#618](https://github.com/modeled-information-format/research-harness-template/issues/618)). Forwarded unvalidated to every `wf(...)` child call; only `research-falsify` consumes it, and only once a finding actually needs gating — `audit` mode never gates anything and `deliverables` mode never calls `research-falsify`, so neither needs it supplied. |

### Mode router

`phase('Route')` is a sequence of independent early-return `if (MODE === ...)`
branches — six branches share this one entry point, each a different, shorter
composition of the same atomic modules the `full` round loop also uses. A
`mode` string outside this set throws `unknown mode '<mode>'` before any
branch runs (research-harness-template#624).

| Mode | Composition |
| --- | --- |
| `audit` | `research-coverage-audit` alone → returns the routed backlog report. No fan-out, falsify, synthesis, or projection follows. |
| `import` | `research-import` → (if `needsGating` is non-empty) a falsify drain over `scope: 'all'` → `research-synthesis` → `research-projection`. An import-gate failure (`!imp.ok`) short-circuits before any gating runs. |
| `pivot` | `research-pivot` → a regate falsify call scoped to `pivot.reverifyIds` (`regate: true`) → (if `gapDimensions` is non-empty and the budget floor hasn't been hit) `research-fanout` over just the gap dimensions plus a falsify drain → `research-synthesis` → `research-projection`. |
| `augment` | `research-augment` → an empty `deepen[]` returns `{ deepened: [], reasoning }` immediately (an honest, non-error terminal state) → a budget below the floor returns `{ deepened: [], planned, reasoning, budgetFloor: true }` before the fanout dispatch (research-harness-template#685 — the same `budgetLow()` guard `pivot` and the full-mode round loop always had; nothing ran, so the corpus is unchanged and synthesis/projection are skipped too, unlike `pivot`'s under-floor path, whose regate pass may already have changed verdicts on disk) → otherwise `research-fanout` over the deepen plan's dimensions plus a falsify drain → `research-synthesis` → `research-projection`. |
| `deliverables` | (research-harness-template#624) `research-synthesis` alone (no fan-out, no falsify — reuses the survivor corpus already on disk) → `research-deliverables` fed that fresh `synthesisPath` plus `genres`/`channels`. Requires at least one of `genres`/`channels`, or the script throws before either child runs. Deliberately never calls `research-projection` — the report of record is untouched by this mode. A `synthesis.ok === false` result (e.g. no surviving findings) short-circuits to `{ deliverables: null }` before `research-deliverables` is invoked. |
| `full` | The bounded autonomous goal loop — see [The full-mode round loop](#the-full-mode-round-loop) below. |

### The full-mode round loop

`full` mode first runs `research-goal` (a `goal.ok === false` result
short-circuits the whole call with `{ stage: 'goal', failed: true }`), then
loops `r = 1..maxRounds`, breaking early the moment `done` is set:

1. **Budget floor check.** `budgetLow()` (remaining token budget under the
   60 000-token floor) stops the loop *before* opening a new round, logging
   the stop reason — a code comparison, not a prompt-enforced discipline
   (Decision D-5, cited below).
2. **Fanout.** `research-fanout` over the round's current `dims`/`depth`/
   `roundContext`; any `crossDimensionLeads` accumulate across rounds for the
   audit/add-dimensions steps later.
3. **Falsify drain.** `falsifyAll()` repeat-calls `research-falsify` with
   `scope: 'all'` until `deferredIds` is empty, the budget floor trips, or a
   hard safety cap of 5 drain iterations is reached (whichever comes first)
   — the same bounded-drain shape [research-falsify](#research-falsify)'s
   own `claimBudget` deferral already documents, plus the iteration cap as
   a belt-and-suspenders bound against a pathological non-terminating
   backlog.
4. **Synthesis.** `research-synthesis` over the surviving corpus.
5. **Independent completion check.** A dedicated sonnet evaluator — never the
   agent that did the round's work — reads `goal.json`, runs each
   `completion_condition.check`'s own `verify` command where one exists (or
   grades the assertion strictly against current corpus state otherwise),
   and returns `{ met, unmet, boundHit }`. `done` is set **only** by
   `unmet.length === 0` from this evaluator's typed output — never by round
   activity, and never by the script's own narrative (Decision D-4, cited
   below). A missing/failed evaluator call stops the loop conservatively
   rather than assuming success. **Repair disclosure**
   ([research-harness-template#623](https://github.com/modeled-information-format/research-harness-template/issues/623)):
   `research-fanout`'s own validate/repair lane can mutate schema-invalid or
   citation-defective findings in place before this evaluator ever runs, so
   grading only "does the corpus currently validate" would make a
   heavily-repaired round indistinguishable from a clean one. The round's
   `fan.repaired` count (see [research-fanout's Returns](#research-fanout))
   is threaded into the evaluator's own prompt every round — repair-then-
   revalidate at authoring time is never by itself a reason to fail a
   check, but a check about finding schema or citation validity (e.g.
   `finding_valid`, `citation_integrity`) may not be graded `met` without
   disclosing that repair count in its evidence. The running total also
   accumulates into the final report's `repaired` field (see Returns
   below), independent of what the evaluator does with the disclosure.
6. **Adapt.** If checks remain unmet, the goal's own bound hasn't been hit,
   and rounds remain, `research-coverage-audit` runs (fed the accumulated
   leads and the last synthesis's `checkCoverage`) and its top-3-priority
   backlog items decide the next round's shape: a backlog wanting
   `add-dimensions` runs `research-add-dimensions` and, if it actually added
   anything, the next round researches only the new dimensions; otherwise
   `research-augment` (steered by the unmet checks) either returns a deepen
   plan the next round targets, or an empty plan — which **stops the loop
   with the judge's own stated reasoning logged**, a real code path (not
   merely documented behavior) matching the
   [empty-plan outcome](#the-empty-plan-outcome-is-valid-not-an-error)
   `research-augment` itself already treats as a valid, non-error result.

Once the loop exits (by `done`, a bound/floor stop, or exhausting
`maxRounds`), the Project phase runs `research-projection` against the last
synthesis's `synthesisPath` (skipped if no synthesis ever completed) — see
[Project phase: per-genre canonical reports](#project-phase-per-genre-canonical-reports-research-harness-template626)
immediately below — then the Deliver phase runs `research-deliverables` only
if a **channel** was actually requested (CLI `--channels` or the goal's own
`deliverables.channels`; research-harness-template#650 — genres alone no
longer trigger this phase, see below).

### Project phase: per-genre canonical reports (research-harness-template#626)

Before #626, this phase called `research-projection` exactly once,
unconditionally at `genre="general"` — the sole canonical report a session
ever produced, regardless of what the goal or caller actually wanted. The
Project phase now loops `research-projection` once per entry in whichever
genre source is actually present: an explicit CLI `args.genres` wins
outright (research-harness-template#650); absent that, the goal's own
elicited `deliverables.genres` (the field `research-goal`'s Draft phase
preserves-or-leaves-absent, elicited by `/goal-writer` — see
[research-goal's Returns](#research-goal)); **defaulting to `['general']`
unchanged when neither source is present** — the pre-#626 single-report
behavior is exactly the `['general']`-default case, not a special path.
`#650` closed a real gap here: the non-interactive `/research` engine path
(no `/goal-writer` step) can never populate `goal.deliverables` at all, so
before this fix a genre-only `/research --genres ...` invocation always fell
through to the `['general']` default here, while its CLI genres were
consumed solely by the Deliver phase below — see that phase's note for what
that produced.

Each iteration passes its own `genre` and a genre-suffixed `slug`:
`genre="general"` keeps the original bare `reports/<topic>/<topic>.md` slug
(back-compat, unsuffixed); every other requested genre renders
`reports/<topic>/<topic>.<genre>.md`, so two or more requested genres never
collide on one canonical-report path (`research-projection`'s own genre
resolution then decides, per #633, whether that genre's real
`Skill(<genre>:<genre>)` template actually applies, or the pack is
disabled/absent and it falls back to an honest `genre="general"` render at
that same genre-suffixed slug).

The Deliver phase's `genres`/`channels` axis resolves independently (CLI
still wins there too, else the goal's own fields), but as of #650 it is
**channel-gated, not genre-gated**: it fires only when a channel was
actually requested (CLI `--channels` or the goal's `deliverables.channels`),
never on genres alone. Before #650, a genre-only request (no channel
requested anywhere) still fired this phase, forwarding `channels: undefined`
into `research-deliverables.js`, whose own `CHANNELS` default (`['blog']`)
then silently rendered an unrequested blog/ deliverable instead of nothing
— the exact defect #650 reported and fixed. The two phases still answer
different questions: Project renders the canonical MIF Level-3 report(s) of
record (the harness's own source of truth); Deliver renders optional
published artifacts (blog/book/pdf/…) from the same synthesis, and now only
when actually asked for. A caller that wants, say, an `engineering`
canonical report AND a `blog` published artifact declares `deliverables: {
genres: ["engineering"], channels: ["blog"] }` on the goal (or passes the
equivalent CLI `--genres engineering --channels blog`) — the Project phase
renders the `engineering` report, and the Deliver phase renders the `blog`
artifact from the same `engineering` genre.

### Returns

Every mode returns a typed result tagged with `mode`; shape varies by branch
— `audit`: `{ mode, backlog, summary, rawItems, uncoveredAngles }` (the
`research-coverage-audit` result spread with `mode`); `import`:
`{ mode, imported, gate, synthesis, projection }` on success, or
`{ mode, imported: <failed result> }` if the import gate itself failed;
`pivot`: `{ mode, goalVersion, carried, stale, fanout, synthesis, projection }`;
`augment`: `{ mode, deepened: [], reasoning }` when nothing warranted
deepening, or `{ mode, deepened, fanout, gate, synthesis, projection }`
otherwise; `deliverables`: `{ mode, synthesis, deliverables }`, where
`deliverables` is `null` when the fresh synthesis itself came back
`ok: false` (e.g. no surviving findings) — no `projection` field, since this
mode never calls `research-projection`; `full`:
`{ mode, goal: { file, dimensions }, done, checks: { met, unmet } | null, synthesis, repaired, projection, projections, deliverables }`
— `repaired` is the run's accumulated repair total across every round (see
the repair-disclosure note in step 5 above; #623). `projections`
(research-harness-template#626) is the Project phase's full per-genre
result list, `{ genre, slug, result }` per entry, one per
`goal.deliverables.genres` entry (`['general']` when the goal declared
none — see [Project phase](#project-phase-per-genre-canonical-reports-research-harness-template626)
above); `projection` is kept for back-compat as a single value — the
`'general'` entry's result when one was rendered, else the first requested
genre's result, `null` only when the Project phase never ran at all (no
synthesis ever completed).
A `full`-mode goal-stage failure instead returns
`{ mode, stage: 'goal', failed: true, detail }` before the round loop ever
starts.

### The `/research` command: the engine's new entry point

[`/research`](commands.md#research) (Epic #550, Task #600) is the thin
slash-command invocation surface over this module — exactly one `Workflow`
tool call per invocation, with no orchestration logic of its own. It resolves
`--topic`/`--mode` and the mode-specific args documented in this module's own
Args table above (asking the user rather than invoking the tool when a
required arg
like `--delta`/`--container-dir` is missing), makes the single call, and
reports the typed result plainly per mode — never re-narrating the run as if
the command had performed the work itself. `/research` is this engine's new
entry point; see [commands.md](commands.md#research) for its full argument
reference.

### Migration note: supersedes `/start`'s orchestrator spawn, in place

**What this module structurally removes.** The old engine's `/start` command
spawns `.claude/agents/orchestrator.md` as a subagent that fans out nameless
background workers and must babysit them with `Bash` poll loops — ending its
turn mid-wait permanently abandons that work, since a subagent gets no
completion notification it can act on after its own turn ends. This is not
hypothetical: it reproduced twice in one real session
([issue #392](https://github.com/modeled-information-format/research-harness-template/issues/392)),
once in the orchestrator's Phase 1 fan-out wait and once in its Phase 2
falsification-gate loop. `research-pipeline.js` removes this failure class
*structurally*, not by prompt discipline layered on top of the same shape:
every sequencing, waiting, and reaping decision above — the round loop, the
falsify drain, the mode router — is owned by the deterministic Workflow
runtime (`workflow()`/`agent()`/`parallel()`), so no agent is ever
responsible for supervising another agent's lifecycle, and there is no
background spawn for a turn boundary to abandon. This is Decision D-1 of the
workspace research-pipeline architecture document (the source this module
and its ten siblings were vendored from — a workspace-level design document,
not a file in this repo, so it is cited by name here rather than linked, the
same as every other Decision-Log citation on this page) — cited here rather
than restated; see that document's Decision Log for the full
context/decision/consequences write-up, and its "The orchestrator —
`research-pipeline.js`" Level-3 section (cited throughout this page's
per-module sections above) for the mode-router and round-loop design this
page documents as built.

**Superseded in place, not deleted.** Consistent with parent Epic #551's own
acceptance criterion ("every supersession is documented in place, nothing
silently deleted"): `.claude/agents/orchestrator.md` and the `/start`,
`/resume`, and `/falsify` commands that spawn or drive it are **untouched**
by this vendor and remain fully available as the interactive, legacy
research path. Nothing about this migration disables, deprecates, or removes
them — `/research` is a new, additional entry point, not a replacement that
breaks the old one. A reader landing on `.claude/agents/orchestrator.md`
finds a cross-link back to this section (see that file's own header note);
a reader landing here finds the reverse pointer in this paragraph.
