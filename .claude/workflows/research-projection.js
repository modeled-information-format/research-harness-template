// research-projection.js — atomic step 5 of the research pipeline (projection).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564 precedent.
//
// Vendored from the workspace engine reference (Epic #543, Task #569). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the established
// precedent from research-goal.js/research-fanout.js/research-falsify.js/
// research-synthesis.js). Two things were verified against the CURRENT
// substrate rather than carried forward from the reference unchanged:
//
// SAME-PROCESS synthesisPath CONTRACT — existence-checked, not assumed.
// research-synthesis.js's (#542, #564) synthesisPath hand-off is explicitly
// SAME-PROCESS-ONLY: a bare mktemp FILE outside the repo tree, no cleanup
// trap, no cross-process survival guarantee — its own header states a
// consumer "must read synthesisPath before that process exits" and that
// nothing "guarantees survival across process boundaries." The reference
// research-projection.js takes synthesisPath as a required arg with NO
// staleness/existence check — that gap is NOT carried forward here. A
// Preflight step (folded into the top of the Report phase, not a separate
// meta phase — it is a guard, not a projection stage in its own right) runs
// a cheap haiku existence+non-empty+valid-JSON check on synthesisPath BEFORE
// any Report work starts, and fails CLOSED with a clear, actionable error
// (never a silent empty report) if the file is gone. This module remains
// valid only when composed in the SAME orchestrating process as the
// research-synthesis call that produced synthesisPath (true for
// workflow()-based pipeline composition, e.g. research-pipeline.js's
// `wf('projection', { synthesisPath: syn.synthesisPath })` — see
// research-pipeline.js) — never as a standalone step run later against a
// possibly-vanished tmp file.
//
// GENUINE SUBSTRATE GAP — surfaced and resolved, not carried forward.
// The reference research-projection.js's Report/Index phases reimplement a
// rough approximation of this repo's existing publish-report/readme/graph
// skills via free-form prompts instead of delegating to them. Read against
// the actual shipped SKILL.md files (not guessed from the grounding summary):
//
//   - publish-report/SKILL.md's own Non-negotiables: the report's
//     extensions.harness.verification verdict must NEVER be hand-authored —
//     it must come from a REAL falsification pass via the pipeline
//     synthesize-artifact.sh -> falsify.sh -> render-artifact.sh ->
//     mif-project.sh (-> build-topic-readme.sh, which THIS module's own
//     Index phase owns instead, see below). The reference's Report phase has
//     the sonnet agent write MIF frontmatter/citations/verdict directly from
//     the synthesis and never invokes the falsification gate at all — a
//     CORRECTNESS gap, not a style preference, if carried through unchanged
//     (a hand-authored "verdict" is not a verdict).
//   - readme/SKILL.md wraps scripts/build-topic-readme.sh for the
//     deterministic structural backbone (every count/date/verdict-breakdown/
//     source-total/dimension-rollup/report-table computed from the
//     substrate — never guessed), and is explicit that Key Findings/Purpose
//     are the ONE thing the script cannot do and must be hand-authored on
//     top, synthesis-grade (4-10 bullets synthesizing ACROSS findings, never
//     one-finding-per-bullet restatements) — never a full from-scratch
//     recompute the way the reference's Index phase instructs.
//   - graph/SKILL.md wraps scripts/build-graph.sh (build) +
//     scripts/assert-graph-mif.sh (the MIF-native acceptance gate proving
//     every node/edge traces to a urn:mif: id) — the reference's Index phase
//     only vaguely gestures at "refresh it" without naming a script.
//
//   RESOLUTION (matches the #539-#542 precedent of delegating to scripts/*.sh
//   rather than reimplementing, and the architecture doc's own stated intent
//   to "compose with the harness's existing publish-report/readme/graph
//   skills... rather than duplicating their logic wholesale" — a deviation
//   from the REFERENCE's prompt-only shape, not from the architecture doc):
//   the Report phase below invokes the publish-report script pipeline
//   directly; the Index phase invokes build-topic-readme.sh for the
//   structural backbone (sonnet authors ONLY Key Findings/Purpose on top —
//   moved off haiku by research-harness-template#720, see that phase's own
//   note below) and build-graph.sh + assert-graph-mif.sh for the
//   knowledge-graph refresh.
//
// @id SUPERSESSION IS STRUCTURAL, VERIFIED EMPIRICALLY (not asserted from
// reading render-artifact.sh alone). A fixture run of the actual pipeline —
// synthesize-artifact.sh -> falsify.sh -> render-artifact.sh (twice, same
// topic/slug) -> mif-project.sh, against reports/_meta/sample-session's real
// findings plus evals/fixtures/raw-finding.json+evidence.json — confirmed
// the engine derives the report's @id deterministically from
// namespace+slug (urn:mif:report:<namespace>:<slug>), so re-rendering the
// SAME topic/slug preserves the SAME @id automatically (version increments,
// temporal.validFrom carries forward from the prior render) with no extra
// agent-side "remember the old @id" step required — the Report phase prompt
// below therefore just says "re-render," not "manually preserve @id."
//
// ENGINE REQUIREMENT: synthesize-artifact.sh, render-artifact.sh,
// mif-project.sh, build-graph.sh, and assert-graph-mif.sh all hard-require
// the mif-rh-cli engine (ADR-0016) — scripts/fetch-engine.sh, mif-rh-cli on
// PATH, or MIF_RH_CLI. Known open infra bug #567 (verify.sh's --gates
// ENGINE resolution runs before gate filtering) is orthogonal to this
// module's own runtime behavior — this module never calls verify.sh itself
// (see the Verify phase below, D-10) — and is out of scope for this Task;
// work around it locally with scripts/fetch-engine.sh, never silently.
//
// GENRE SKILL INVOCATION GAP — closed, not carried forward
// (research-harness-template#633). This module previously passed `genre` to
// synthesize-artifact.sh as a plain pass-through argument and never invoked
// any genre's real skill — every genre (`engineering`, `briefing`, …)
// therefore rendered the identical genre-neutral findings-dump body, with
// `genre:` merely stamped into the output metadata: indistinguishable from a
// correctly-genred report by inspection unless you diffed the body against a
// different genre's output. Confirmed against the KNOWN-WORKING mechanism
// (`.claude/agents/report-synthesizer.md`'s Step 2 — "Resolve the genre
// (optional, pack-provided)"), intended to apply every genre's real
// template in the interactive `/start` path: each genre is its own
// individually-toggleable pack entry (`harness.config.json packs[]`, no
// shared "reports" family pack), BUT every one of those pack entries
// sources from the single external `mif-docs` marketplace-ref plugin
// (confirmed: `.claude-plugin/marketplace.json` here declares no
// standalone `<genre>` plugin, and `mif-docs-plugin`'s own marketplace
// declares exactly ONE plugin, name="mif-docs", "one skill per document
// genre") — so the correct invocation is `Skill(mif-docs:<genre>)` (e.g.
// `Skill(mif-docs:engineering)`), NOT `Skill(<genre>:<genre>)`
// (research-harness-template#744; report-synthesizer.md's Step 2 carried the
// identical wrong-namespace guidance and is fixed alongside this file).
// This only happens when that SPECIFIC genre's pack is enabled in
// `harness.config.json packs[]`; otherwise report-synthesizer falls back to
// neutral synthesis and does NOT stamp a genre it didn't earn. The Report
// phase below now mirrors that exact resolution before rendering (see the
// GENRE RESOLUTION step ahead of the pipeline): `genre="general"` (the
// default) or a disabled/absent genre pack renders the neutral script
// pipeline unchanged, under `genreArg="general"`, and reports
// genre="general" honestly; an ENABLED genre pack additionally invokes
// `Skill(mif-docs:<genre>)` (pipeline step 6b) to restructure the rendered
// report's body into that genre's real documented structure — built from
// the same artifact/synthesis claims, never inventing new content, never
// touching the MIF frontmatter/citations/verdict fields the script pipeline
// already established — and re-confirms `mif-project.sh` since the body
// changed. The returned `genreApplied`/`genreSkillInvoked` fields make this
// outcome caller-visible instead of silently cosmetic. `research-deliverables.js` has a comparable
// `GENRES` pass-through gap for its OWN artifact-based channels (confirmed
// while fixing this issue, not yet repro'd end-to-end); that is tracked
// separately as research-harness-template#640, deliberately out of scope
// here.
//
// CONCURRENCY FIX (issue #628) — a topic-scoped lock, not a genre-suffixed
// path. The Report phase's intermediates (${RDIR}/artifact.json,
// report-finding.json, report-finding.falsified.json,
// report.verification.json) are FIXED per-topic paths, not parameterized by
// genre or slug — two concurrent invocations of this module against the
// SAME topic with different genre/slug (exactly the multi-genre pattern
// #626 proposes eliciting up front) previously raced on them with no error
// surfaced: every invocation reported ok:true while one invocation's
// synthesize-artifact.sh clobbered another's artifact.json mid-flight, so
// concurrent renders silently stamped the wrong genre's content into each
// other's reports, and in the reported repro, one invocation's render step
// overwrote the topic's existing canonical report entirely. Genre-suffixing
// these paths the way research-deliverables.js's OWN blog/book intermediates
// already do (`artifact.<genre>.json`, see that module's header) is NOT a
// safe option here: unlike those, ${RDIR}/artifact.json at its fixed name is
// a well-known, unsuffixed file that mif-container-export.sh,
// mif-container-import.sh, and verify.sh's export/import gates all expect
// to find (or round-trip) at that exact path — renaming it per genre would
// silently break container export/import for every topic. The Report phase
// therefore acquires a per-topic lock — `reports/<topic>/.projection-lock`
// — around the whole synthesize-artifact.sh -> render-artifact.sh pipeline,
// via the SAME shared `scripts/lib/container-lock.sh` primitive
// `mif-container-export.sh`/`mif-container-import.sh` already use for their
// own `.container.lock` (mkdir-atomic, stale-lock self-healing, refresh-
// capable — see that file's own header). This is a THIRD, deliberately
// independent lock namespace, mirroring the existing intentional separation
// between `reports/<topic>/.run-lock` (findings-mutation, the orchestrator
// and /falsify) and `reports/<topic>/.container.lock` (export/import) —
// merging any of the three was explicitly out of scope when #375
// established that precedent, and holds here too: a projection run must
// never contend with, or be blocked by, an unrelated findings-mutation run
// or export/import.
//
// BOUNDED SUMMARY CONSTRUCTION (research-harness-template#629). report-finding.json's
// summary field inherits maxLength: 500 from the canonical MIF schema
// (schemas/mif/mif.schema.json) — the same vendored MIF Level 3 constraint the
// falsification-analyst's bounded-summary-qualifier algorithm (#503/#504) already
// respects for a WEAKENED finding's appended qualifier. This module hits the same
// cap from the opposite direction: Report phase step 2 below constructs
// report-finding.json's summary FROM SCRATCH off the artifact's title/sections/
// sources, and a naturally-written summary over a substantial multi-finding
// synthesis can run well past 500 chars (observed 3937 chars against a real topic,
// research-harness-template#629, reported by the pipeline's own problems[] rather
// than caught before the file was written) — there is no qualifier being appended
// here, just a summary being authored, so the fix is a bounded CONSTRUCTION, not a
// bounded APPEND. The algorithm below is the EXACT snippet
// evals/report-finding-summary-cap.sh extracts and exercises (never a hand-copied
// reimplementation that could drift silently) — if this snippet's shape changes,
// that eval's extraction must be updated to match.
//
// ```python
// MAX_SUMMARY_LEN = 500
//
// def bound_summary(summary: str) -> str:
//     """Fit `summary` under the schema's 500-char cap at construction time."""
//     if len(summary) <= MAX_SUMMARY_LEN:
//         return summary
//     return summary[: MAX_SUMMARY_LEN - 1].rstrip() + "…"
//
// assert len(bound_summary(summary)) <= MAX_SUMMARY_LEN
// ```
//
// The Report phase's step-2 prompt below requires the constructing agent to apply
// this EXACT bound to report-finding.json's summary BEFORE writing the file — never
// rely on the Verify phase (or the pipeline's own problems[] surfacing) to catch an
// oversized summary after the fact; that check still runs, as a backstop, not as
// the enforcement mechanism.
//
// WITNESSED PROVENANCE GAP — closed, not carried forward (#632). This
// module's Report phase previously stopped at step 6 (mif-project.sh's L3
// schema re-confirmation), leaving the rendered report's `provenance` block
// whatever `synthesize-artifact.sh`/`render-artifact.sh` asserted from the
// artifact's own content — identical boilerplate
// (sourceType/confidence/trustLevel) across every genre and run, never
// hook-observed. ADR-0018 already names `mif-docs-plugin`'s `mif-provenance`
// skill as the harness's witnessed-provenance authority (ADR-0002 stays the
// schema-conformance authority) and its own "Current Limitations" section
// states plainly that "every provenance block, including in synthesized
// reports, is model-asserted" — this module was the gap. The interactive
// `/start` orchestrator's report-synthesizer.md agent already documents the
// correct fix (its Step 4d) for the non-workflow path; step 7 below applies
// the IDENTICAL pattern here — Skill(mif-docs:mif-provenance) invoked via
// the Skill tool (never a hand-rolled script path into the plugin's install
// cache), declining gracefully (exit 3) when capture is off or the session
// ledger never witnessed this file, never hand-authoring a block to work
// around a decline.
export const meta = {
  name: 'research-projection',
  description: 'Atomic step 5 (projection): project the typed synthesis onto the durable corpus surfaces — the canonical MIF Level-3 report of record (via the publish-report script pipeline, gated by a REAL falsification pass, never a hand-authored verdict), the topic README/knowledge graph (via the readme/graph skills\' deterministic scripts, synthesis-grade Key Findings authored on top) — then verify only what changed',
  whenToUse: 'After a clean synthesis — materializes the tracked, in-repo projections (the report channel is the source of truth; deliverable genres are a separate workflow)',
  phases: [
    { title: 'Report', detail: 'existence-checked synthesisPath (same-process contract) -> genre resolved against harness.config.json packs[] enablement (#633) -> publish-report pipeline: synthesize-artifact.sh -> REAL falsify.sh gate over the report\'s own central claims (never hand-authored) -> render-artifact.sh -> mif-project.sh -> Skill(mif-docs:<genre>) applied + re-confirmed when that genre\'s pack is enabled, else an honest genre="general" (#633, never a claimed-but-unapplied genre) -> Skill(mif-docs:mif-provenance) witnessed-provenance stamp (ADR-0018, #632; declines gracefully when capture is off, never hand-authored as a workaround)', model: 'sonnet' },
    { title: 'Index', detail: 'readme skill\'s build-topic-readme.sh backbone + synthesis-grade Key Findings/Purpose authored on top -> graph skill\'s build-graph.sh + assert-graph-mif.sh; wrapped in try/catch (research-harness-template#720) -> degrades to a null index with a named warning on any throw, never fails the pipeline', model: 'sonnet' },
    { title: 'Verify', detail: 'targeted gates on changed files only (D-10) — never the full verify.sh suite', model: 'haiku' },
  ],
}

// research-harness-template#654: normalize a top-level standalone Workflow-tool
// invocation. `args` arrives as a JSON-encoded STRING when this module is
// invoked directly at the top level (confirmed empirically -- issue #617),
// but as a real in-process object when composed as a nested child via
// research-pipeline.js's wf() helper. research-pipeline.js already guards
// its own external entry point for this; every atomic module is ALSO a
// valid direct entry point and needs the identical guard -- this was #654's
// actual root cause: `args` was a JSON string, so `args.topic` (or any
// other args.* property) silently read `undefined` (a string property
// access, never a thrown error) rather than the real value, and the very
// next `if (!TOPIC) throw` line fired even though the caller's `topic`
// argument was genuinely present in the call.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})

// args: { harnessDir, topic, synthesisPath, slug?: string, genre?: string (default 'general') }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
const SYN = A && A.synthesisPath
if (!TOPIC) throw new Error('research-projection: args.topic is required')
if (!SYN) throw new Error('research-projection: args.synthesisPath is required (run research-synthesis first, in the SAME process — see the same-process contract note in this module\'s header)')
const RDIR = `${H}/reports/${TOPIC}`
const SLUG = (A && A.slug) || TOPIC
const GENRE = (A && A.genre) || 'general'
// GENRE is interpolated into a shell command (the jq --arg g "${GENRE}" lookup
// below) and into a Skill() reference in the Report-phase prompt
// (genreSkillRef = `mif-docs:${GENRE}` — research-harness-template#744). Pack names are constrained by
// harness.config.schema.json's packs[].name pattern (^[a-z][a-z0-9-]*$) — a
// caller composing this workflow programmatically could otherwise pass an
// unconstrained string that produces a malformed prompt or a command/
// skill-reference injection. Validate against that same pattern BEFORE any
// use, and fail closed rather than silently coercing or proceeding.
if (GENRE !== 'general' && !/^[a-z][a-z0-9-]*$/.test(GENRE)) {
  throw new Error(
    `research-projection: args.genre "${GENRE}" does not match the pack-name pattern harness.config.schema.json enforces ` +
      `(^[a-z][a-z0-9-]*$) — refusing to interpolate an unvalidated genre string into a shell command or Skill() reference.`,
  )
}

const PREFLIGHT_SCHEMA = {
  type: 'object',
  properties: {
    exists: { type: 'boolean' },
    reason: { type: 'string', description: 'why exists=false, or a one-word "ok" when true' },
  },
  required: ['exists', 'reason'],
}
const REPORT_SCHEMA = {
  type: 'object',
  properties: {
    reportPath: { type: 'string' },
    frontmatterLevel: { type: ['integer', 'null'], description: 'the report\'s achieved MIF level, read back from the rendered file\'s frontmatter after step 5/6 — null ONLY when verificationVerdict is "falsified" and step 3 stopped the pipeline before render-artifact.sh/mif-project.sh ever ran (research-harness-template#773: never fabricate a level for an artifact that was never rendered)' },
    checksAddressed: { type: 'array', items: { type: 'string' } },
    verificationVerdict: { type: 'string', enum: ['falsified', 'weakened', 'survived', 'inconclusive'] },
    reportId: { type: 'string', description: 'the report\'s own @id, read back from the rendered file\'s frontmatter after step 5/6 — same across a supersession re-run, by construction of render-artifact.sh (see header note); "" ONLY when verificationVerdict is "falsified" and step 3 stopped the pipeline before that render ever happened (research-harness-template#773: never invent an @id for an artifact that was never created)' },
    genreApplied: { type: 'boolean', description: '(#633) true only if step 6b actually invoked Skill(mif-docs:<genre>) and restructured the body per that genre\'s template; false when genre="general" was requested or the requested genre\'s pack was disabled/absent, in which case the report\'s own genre metadata must read "general", never the originally-requested genre' },
    genreSkillInvoked: { type: 'string', description: '(#633/#744) the "mif-docs:<genre>" Skill reference actually invoked at step 6b, or "" when genreApplied is false' },
    provenanceOutcome: { type: 'string', enum: ['stamped', 'declined', 'error', 'not-applicable'], description: 'result of the Skill(mif-docs:mif-provenance) stamp attempt (#632) — "declined" is expected/healthy when capture is off or the session ledger never witnessed this file, never a projection failure; "not-applicable" is the ONLY correct value when step 3\'s verificationVerdict="falsified" stopped the pipeline before step 7 ever ran — never fabricate "stamped"/"declined"/"error" for a report that was quarantined before the stamp attempt' },
    provenanceReason: { type: 'string', description: 'why declined/error (the skill\'s own stated reason), "witnessed" when stamped, or "report quarantined at step 3 (falsified) — step 7 never reached" when provenanceOutcome is "not-applicable"' },
  },
  required: ['reportPath', 'frontmatterLevel', 'checksAddressed', 'verificationVerdict', 'reportId', 'genreApplied', 'genreSkillInvoked', 'provenanceOutcome', 'provenanceReason'],
}
const GENRE_SCHEMA = {
  type: 'object',
  properties: {
    genreArg: { type: 'string', description: '(#633) the genre string to actually pass to synthesize-artifact.sh — "general" unless the requested genre\'s own pack is enabled' },
    genrePackEnabled: { type: 'boolean' },
    genreSkillRef: { type: 'string', description: '(#744) "mif-docs:<genre>" Skill reference to invoke after rendering when genrePackEnabled is true, else ""' },
  },
  required: ['genreArg', 'genrePackEnabled', 'genreSkillRef'],
}
const INDEX_SCHEMA = {
  type: 'object',
  properties: {
    readmePath: { type: 'string' },
    readmeCheckPassed: { type: 'boolean' },
    graphRefreshed: { type: 'boolean' },
    graphAssertPassed: { type: 'boolean' },
    changedFiles: { type: 'array', items: { type: 'string' } },
  },
  required: ['readmePath', 'readmeCheckPassed', 'graphRefreshed', 'graphAssertPassed', 'changedFiles'],
}
const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    lintClean: { type: 'boolean' },
    schemaClean: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'string' } },
  },
  required: ['lintClean', 'schemaClean', 'problems'],
}

phase('Report')

// Same-process contract guard (see header note): a cheap haiku existence +
// non-empty + valid-JSON check on synthesisPath BEFORE any Report work
// starts. Fails CLOSED with a clear, actionable error if the file is gone —
// never a silent empty report, and never proceeding on an unchecked
// required arg the way the reference implementation does.
const preflight = await agent(
  `SAME-PROCESS CONTRACT CHECK. research-synthesis.js's synthesisPath hand-off is explicitly SAME-PROCESS-ONLY (no cleanup trap installed, but also no cross-process survival guarantee — its own header states a consumer must read the file before that process exits). Before this module trusts ${SYN}, verify all three: (1) the file exists (test -f), (2) it is non-empty (test -s), (3) it parses as valid JSON (jq empty). Return exists=true ONLY if all three hold; otherwise exists=false with a one-sentence reason naming which check failed (e.g. "file missing", "empty file", "invalid JSON").`,
  { label: 'projection:preflight', model: 'haiku', effort: 'low', schema: PREFLIGHT_SCHEMA },
)
if (!preflight || !preflight.exists) {
  throw new Error(
    `research-projection: synthesisPath "${SYN}" is not usable (${preflight ? preflight.reason : 'preflight check itself failed'}). ` +
      `The ephemeral-output contract is SAME-PROCESS-ONLY (research-synthesis.js's synthesisPath has no cleanup trap but ` +
      `also no cross-process survival guarantee) — this module must be composed in the SAME process as the research-synthesis ` +
      `call that produced it, invoked before that process exits (e.g. research-pipeline.js's ` +
      `wf('projection', { synthesisPath: syn.synthesisPath }) immediately after wf('synthesis', {})). Re-run research-synthesis ` +
      `and consume its synthesisPath in the same pipeline run — do not retry this module standalone against a stale path.`,
  )
}

// GENRE RESOLUTION (research-harness-template#633): resolve the requested
// genre against harness.config.json packs[] enablement BEFORE any Report
// work starts, mirroring report-synthesizer.md's Step 2 exactly (see header
// note). "general" (the default, no genre requested) needs no lookup — it
// is definitionally the neutral render. Otherwise a disabled/absent pack
// falls back to genreArg="general" honestly rather than silently letting a
// GENRE the pipeline cannot actually apply flow into synthesize-artifact.sh
// and the output frontmatter.
const genreResolution =
  GENRE === 'general'
    ? { genreArg: 'general', genrePackEnabled: false, genreSkillRef: '' }
    : await agent(
        `GENRE ENABLEMENT CHECK (research-harness-template#633 — mirrors report-synthesizer.md's Step 2, never treat a requested genre ` +
          `as automatically applicable). Genre "${GENRE}" was requested for topic ${TOPIC} in harness ${H}. Run: jq -r --arg g "${GENRE}" ` +
          `'.packs[] | select(.name==$g and .enabled) | .name' ${H}/harness.config.json. If it prints "${GENRE}", the pack IS enabled: ` +
          `return genreArg="${GENRE}", genrePackEnabled=true, genreSkillRef="mif-docs:${GENRE}" (research-harness-template#744 — every ` +
          `genre pack sources from the single "mif-docs" plugin, never a standalone "<genre>" plugin). If it prints nothing (pack disabled or ` +
          `absent from packs[] entirely), return genreArg="general", genrePackEnabled=false, genreSkillRef="" — the neutral pipeline ` +
          `renders instead, and the caller must be told this happened (never silently proceed with the requested genre string when no ` +
          `template will actually be applied for it).`,
        { label: 'projection:genre-resolve', model: 'haiku', effort: 'low', schema: GENRE_SCHEMA },
      )
if (!genreResolution) throw new Error('research-projection: genre resolution failed')
if (GENRE !== 'general' && !genreResolution.genrePackEnabled) {
  log(`Genre "${GENRE}" requested but its pack is not enabled — falling back to genreArg="general" honestly (research-harness-template#633); the report will NOT claim genre="${GENRE}" in frontmatter`)
}

const genreStepText = genreResolution.genrePackEnabled
  ? `6b. GENRE SKILL APPLICATION (research-harness-template#633): genre "${GENRE}"'s pack is enabled (resolved above) — invoke ` +
    `Skill(${genreResolution.genreSkillRef}) to restructure ONLY ${RDIR}/${SLUG}.md's BODY content into that genre's actual documented ` +
    `section structure (its own template's required sections — e.g. engineering's mandatory Problem/Context/Options/Trade-offs-table/` +
    `Decision/Implementation-Notes/Consequences, briefing's Headline/What's-New/Why-It-Matters/What's-Next), built from the SAME ` +
    `artifact/synthesis claims steps 1-5 already established — invent no new claims, never touch the MIF frontmatter fields (schema/` +
    `citations/verificationVerdict) steps 1-6 already wrote. Then re-run step 6's mif-project.sh once more, since the body just changed ` +
    `— must still report "projects to a valid MIF L3 finding". Set genreApplied=true, genreSkillInvoked="${genreResolution.genreSkillRef}".\n`
  : `6b. GENRE SKILL APPLICATION (research-harness-template#633): no genre template applies here — either "general" was requested, or ` +
    `"${GENRE}"'s pack is disabled/absent (resolved above), so genreArg="general" was already used at step 1 and the report stays the ` +
    `neutral render. This report's genre metadata must read "general", NOT "${GENRE}" — never let the output claim a genre whose ` +
    `template was never applied (mirrors report-synthesizer.md's own rule). Set genreApplied=false, genreSkillInvoked="".\n`

// research-harness-template#727 (mirrors #720's Index-phase fix): agent()
// surfaces the "completed all real work but never called StructuredOutput"
// non-compliance class as a THROW, not a null return — this is the same
// mixed judgment-plus-pipeline task shape (render/falsify/provenance-stamp,
// not a single-shot mechanical extraction) that made Index vulnerable, and
// this phase runs on the same `sonnet` model. UNLIKE Index, this throw is
// re-thrown rather than degraded to a null report: every downstream field
// (reportPath/reportId/frontmatterLevel/genreApplied/genreSkillInvoked/
// provenanceOutcome/provenanceReason) is read unconditionally both by this
// phase's own `if (!report) throw` a few lines below and by the Index/Verify
// phases and final return further down — inventing a degraded report shape
// here would be a caller-visible-contract decision this issue explicitly
// declines to prescribe, not a safe no-op the way Index's null-index is.
//
// CONCURRENCY GUARD note: the prompt above acquires/releases a per-topic
// `.projection-lock` (see CONCURRENCY GUARD, step 7's release-on-every-exit-
// path instruction). If this throw fires AFTER the subagent's own step 7
// release — the observed #720/#727 failure shape, all real work done, only
// the final StructuredOutput call missing — the lock is already clear. If it
// fires mid-task BEFORE that release, the lock could be left held; this is a
// PRE-EXISTING risk the unguarded throw already carried before this fix, not
// something introduced by it, and scripts/lib/container-lock.sh's
// CONTAINER_LOCK_STALE_MIN (240 min default) self-heals a stuck lock without
// new JS-side cleanup logic. Left as a known, examined, unchanged limitation
// rather than scope-creeping into a rewrite of the lock-acquisition contract.
let report
try {
  report = await agent(
  `Render the CANONICAL MIF Level-3 report of record for topic ${TOPIC} in harness ${H} — the harness's source of truth, held ` +
    `to the same bar as a finding (never exempt from the gate). Follow the publish-report skill's SCRIPT PIPELINE exactly — ` +
    `never hand-author the frontmatter, citations, or verification verdict directly; the verdict in particular must come from ` +
    `a REAL falsification pass, never be asserted.\n` +
    `Input: the typed synthesis at ${SYN} (read it; it is @id-keyed to surviving findings).\n` +
    `CONCURRENCY GUARD (issue #628 — a documented incident, not precautionary): ${RDIR}/artifact.json, report-finding.json, ` +
    `report-finding.falsified.json, and report.verification.json below are SHARED per-topic paths, fixed, never genre- or ` +
    `slug-parameterized (mif-container-export.sh/mif-container-import.sh/verify.sh all expect ${RDIR}/artifact.json at this ` +
    `exact well-known name, so it cannot simply be renamed per genre the way research-deliverables.js's OWN blog/book ` +
    `intermediates already are). A second concurrent research-projection.js invocation against the SAME topic with a ` +
    `different genre/slug (e.g. rendering "engineering" and "exec-summary" reports back to back for one topic) previously ` +
    `raced on these shared files with no error surfaced — every invocation reported ok:true while silently stamping the ` +
    `wrong genre's content into another invocation's report, or overwriting the canonical report entirely. BEFORE step 1, ` +
    `acquire a topic-scoped lock so a second concurrent projection run REFUSES to start rather than racing this one — this ` +
    `is a THIRD, independent lock namespace (reports/<topic>/.projection-lock), deliberately separate from the existing ` +
    `reports/<topic>/.run-lock and reports/<topic>/.container.lock (mirrors the pre-existing intentional separation between ` +
    `those two), so it never contends with the orchestrator's findings-mutation lock or a concurrent /export /import:\n` +
    `bash -c '. "${H}/scripts/lib/container-lock.sh" && container_lock_acquire "${RDIR}/.projection-lock" "projection:${GENRE}"' ` +
    `— capture its exit code and do NOT treat every nonzero exit as contention (research-harness-template#769): ` +
    `container_lock_acquire's own header in scripts/lib/container-lock.sh documents two distinct nonzero codes. rc=3 means ` +
    `another projection run genuinely holds this topic's lock (or this attempt lost the steal race against one) — STOP ` +
    `immediately (do not steal a live lock, do not proceed to step 1) and report failure as LOCK CONTENTION. rc=1 means the ` +
    `mkdir itself failed for an unrelated filesystem reason (e.g. ${RDIR} missing, a read-only filesystem) — STOP immediately ` +
    `here too, but report failure as that underlying FILESYSTEM ERROR (quote container-lock.sh's own stderr message), never ` +
    `as lock contention; no other projection run is necessarily involved. On success (rc=0), hold the lock for the entire ` +
    `remainder of this Report phase and ` +
    `release it exactly once before the phase ends, on EVERY exit path (success at step 7, a falsified verdict at step 3, or ` +
    `any earlier failure) — never leave the topic locked:\n` +
    `bash -c '. "${H}/scripts/lib/container-lock.sh" && container_lock_release "${RDIR}/.projection-lock"'\n` +
    `PIPELINE, IN ORDER (publish-report SKILL.md steps 2-5):\n` +
    `1. bash ${H}/scripts/synthesize-artifact.sh ${RDIR}/findings ${genreResolution.genreArg} ${RDIR}/artifact.json — ` +
    `(genreArg resolved above per the GENRE RESOLUTION step — research-harness-template#633, "general" unless "${GENRE}"'s own pack ` +
    `is enabled) projects the surviving findings into one typed Artifact (schemas/artifact.schema.json). Cross-check its sections ` +
    `against the synthesis at ${SYN} so the artifact's claims trace to what the synthesis actually established.\n` +
    `2. Construct ${RDIR}/report-finding.json — a finding-shaped projection of the artifact's central claims (its citations, ` +
    `NO verification block yet) — a single MIF Concept object (@context/@type/@id/conceptType/namespace/title/content/summary/ ` +
    `citations/provenance/tags/created/modified) built from ${RDIR}/artifact.json's title/sections/sources. Invent no claims ` +
    `beyond what the artifact already states. BOUND THE SUMMARY FIELD (research-harness-template#629, see this module's ` +
    `header note): the schema's summary maxLength is 500 chars, and a naturally-written summary over a substantial ` +
    `multi-finding synthesis can run well past that. Author it naturally, then apply this exact bound before writing the ` +
    `file — if it exceeds 500 characters, truncate to 499 characters (stripping trailing whitespace) and append exactly ` +
    `one U+2026 "…" ellipsis character (not three ASCII periods, not any other marker), never emit a summary over 500 ` +
    `characters, and never rely on the Verify phase below (or the ` +
    `pipeline's own problems[] surfacing) to catch an oversized summary after the fact.\n` +
    `3. Obtain a REAL verdict over that report-finding — the SAME substrate research-falsify.js (#541) writes through, at the ` +
    `same rigor: decompose its central claims, gather INDEPENDENT web evidence (WebSearch/WebFetch only, never prior findings ` +
    `or internal memory) trying to falsify each one, then materialize an evidence fixture keyed by the report-finding's @id ` +
    `(mktemp OUTSIDE the repo tree) and write the verdict through: bash ${H}/scripts/falsify.sh ${RDIR}/report-finding.json ` +
    `<fixture-path> > ${RDIR}/report-finding.falsified.json. A falsified verdict means the report is QUARANTINED and NOT ` +
    `shipped — release the projection lock (see CONCURRENCY GUARD above) FIRST, then report verificationVerdict="falsified" ` +
    `and STOP here, do not proceed to render. In this case neither step 5 (render-artifact.sh) nor step 6 (mif-project.sh) nor ` +
    `step 6b (genre skill application) nor step 7 (provenance stamping) ever runs, so frontmatterLevel and reportId can never ` +
    `be genuinely known (research-harness-template#773) — set frontmatterLevel=null and reportId="" (never fabricate a MIF ` +
    `level or @id for an artifact that was never rendered), genreApplied=false, genreSkillInvoked="", ` +
    `provenanceOutcome="not-applicable", and provenanceReason="report quarantined at step 3 (falsified) — step 7 never ` +
    `reached" — do NOT fabricate a stamped/declined/error outcome, or a genreApplied=true, for a report quarantined before ` +
    `those steps ever ran.\n` +
    `4. jq '.extensions.harness.verification' ${RDIR}/report-finding.falsified.json > ${RDIR}/report.verification.json\n` +
    `5. bash ${H}/scripts/render-artifact.sh ${RDIR}/artifact.json report ${RDIR}/${SLUG}.md ${RDIR}/report.verification.json ` +
    `— write-then-validated; fails closed if it does not project to a valid L3 finding. If a report of record already exists ` +
    `at this path, this IS a supersession re-render, not a fresh create: the engine derives the report's @id deterministically ` +
    `from its namespace+slug, so re-running this exact command with the same topic/slug preserves the SAME @id automatically ` +
    `(version increments, temporal.validFrom carries forward) — do not delete the existing file first, and do not attempt to ` +
    `hand-copy an @id forward yourself.\n` +
    `6. Re-confirm: bash ${H}/scripts/mif-project.sh ${RDIR}/${SLUG}.md — must report "projects to a valid MIF L3 finding".\n` +
    genreStepText +
    `7. Stamp WITNESSED provenance (mif-docs-plugin's mif-provenance skill, ADR-0018) on top of — never instead of — the L3 ` +
    `schema conformance step 6 (and step 6b's re-confirmation, if a genre skill was applied) just confirmed. Invoke it via the ` +
    `Skill tool, namespaced pack:skill exactly like publish-report's ` +
    `own genre skills, never a hand-rolled script path into the plugin's install cache:\n` +
    `   Skill(mif-docs:mif-provenance) — "stamp ${RDIR}/${SLUG}.md"\n` +
    `If capture is disabled (mifProvenance.capture unset or false at every settings scope) or the session ledger has no witnessed ` +
    `touch of this file, stamp DECLINES (exit 3) — this is expected and healthy, not a projection failure to surface as broken; ` +
    `the report's provenance block stays whatever step 2-5 already asserted (model-asserted). Do NOT hand-author a provenance ` +
    `block to work around a decline. On success the block carries hook-observed agent/agentVersion/wasGeneratedBy fields instead ` +
    `of only model-asserted ones; trustLevel stays user_stated (a local, unsigned witness) — never overstate it as anything ` +
    `higher when reporting the outcome. Stamping never trades conformance for provenance: if it would drop the report below the ` +
    `MIF level step 6 confirmed, it declines and leaves the file untouched — if it succeeds, re-run step 6's mif-project.sh once ` +
    `more, since a successful stamp mutates the exact frontmatter step 6 already checked. ` +
    `Then release the projection lock (see CONCURRENCY GUARD above) — this phase is done, success or not.\n` +
    `Return the report path, the achieved MIF level (frontmatterLevel — read back from the rendered file's frontmatter after ` +
    `step 5/6, never invented; null ONLY when verificationVerdict="falsified" stopped you at step 3 before any file was ` +
    `rendered, research-harness-template#773), which goal check ids the report addresses, the verification verdict ` +
    `ACTUALLY WRITTEN by falsify.sh (never hand-authored), the report's own @id (reportId — read it back from the rendered ` +
    `file's frontmatter after step 5/6, not invented; "" ONLY when verificationVerdict="falsified" stopped you at step 3 ` +
    `before that render ever happened, research-harness-template#773), the genre outcome from step 6b (genreApplied/genreSkillInvoked, per step 6b's ` +
    `own instruction above — false/"" when quarantined at step 3 or when no template applied, true/"mif-docs:<genre>" only when ` +
    `Skill(mif-docs:<genre>) was actually invoked), and the provenance stamp outcome from step 7 (provenanceOutcome: ` +
    `"stamped"/"declined"/"error", plus provenanceReason naming why, or "witnessed" when stamped — UNLESS verificationVerdict ` +
    `is "falsified" and step 3 already stopped you before step 7, in which case provenanceOutcome="not-applicable" and ` +
    `provenanceReason="report quarantined at step 3 (falsified) — step 7 never reached", per step 3's own instruction).`,
  { label: 'projection:report', model: 'sonnet', schema: REPORT_SCHEMA },
  )
} catch (err) {
  log(`WARNING: Report phase agent() threw instead of returning (research-harness-template#727 — mirrors the #720 Index-phase failure class: the subagent likely completed its render/falsify/provenance work but failed to call StructuredOutput, possibly after falsely claiming it already had). Report's return shape is NOT degradable the way Index's is (see the comment above this try block) — re-throwing a clearer, #727-tagged error instead of letting the original bubble up unexplained. Underlying error: ${err && err.message ? err.message : err}`)
  throw new Error(`research-projection: Report phase failed (research-harness-template#727 — agent() threw instead of returning; see the WARNING log above for the underlying error and the .projection-lock note on lock state): ${err && err.message ? err.message : err}`)
}
if (!report) throw new Error('research-projection: report rendering failed')
if (report.verificationVerdict === 'falsified') {
  log(`Report quarantined: the falsification gate returned "falsified" over the report's own claims — NOT shipping ${report.reportPath}`)
  return {
    ok: false,
    reason: 'report-falsified',
    reportPath: report.reportPath,
    verificationVerdict: report.verificationVerdict,
    genreRequested: GENRE,
    genreApplied: report.genreApplied,
    genreSkillInvoked: report.genreSkillInvoked,
  }
}

phase('Index')
// research-harness-template#720: the Index phase's own task shape is NOT a
// single-shot mechanical extraction — it wraps authored prose (synthesis-grade
// Key Findings/Purpose) around two script-driven validation gates, the same
// mixed judgment-plus-pipeline shape the Report phase above already runs on
// `sonnet`. Observed in production: a `haiku` run completed every real step
// (README rewritten, both gates re-run and passing, graph rebuilt) and then
// never called StructuredOutput — and when the harness's structured-output-
// enforce nudge fired, it asserted in prose that it HAD already called the
// tool, which it never did. `agent({schema})` surfaces that specific
// non-compliance class as a THROW, not a null return (contrast the
// documented "returns null on death" contract for timeout/exhausted-retry/
// user-skip) — so this call, alone among this file's three agent() calls,
// is wrapped in try/catch: give it the stronger model this task shape
// structurally needs (matching the Report-phase precedent), and if it still
// throws, degrade to a null index rather than let one late-pipeline phase
// discard an entire multi-hour, multi-round run one step from the finish
// line. A caller can still tell "Index degraded entirely" (readmePath null,
// below) apart from "Index ran but one validation gate failed" (readmePath
// set, readmeCheckPassed/graphAssertPassed false) via the existing return
// shape — no new field needed.
let index = null
try {
  index = await agent(
    `Reconcile the derived corpus surfaces for topic ${TOPIC}, harness ${H} — via the readme/graph skills' SCRIPT PIPELINES, ` +
      `never a from-scratch recompute:\n` +
      `1. README structural backbone (readme skill): bash ${H}/scripts/build-topic-readme.sh ${TOPIC} — computes every count, ` +
      `date, verdict breakdown, source total, dimension rollup, and the report/artifact tables from ${RDIR}/findings/*.json + ` +
      `${RDIR}/goal.json (never hand-guessed; stale numbers are defects). Then Read ${RDIR}/README.md (the file this command ` +
      `just wrote — required before editing it) and author ONLY the two sections the script cannot compute: rewrite ` +
      `'## Key Findings' as 4-10 bullets that SYNTHESIZE ACROSS findings — an insight, tension, or converging consensus per ` +
      `bullet, never a one-finding-per-bullet restatement; carry named specifics (standards/tools/products/numbers/dates) drawn ` +
      `from the findings' actual content; respect verdict nuance (weakened findings carry caveats, inconclusive ones are ` +
      `reported open, falsified ones excluded) — then tighten '## Purpose' to 1-2 sentences. Edit ONLY those two sections. ` +
      `Then VALIDATE (the gate, must pass before reporting done): bash ${H}/scripts/build-topic-readme.sh ${TOPIC} --check — a ` +
      `non-zero exit means the README is wrong; fix it, do not ship it.\n` +
      `2. Knowledge graph refresh (graph skill): bash ${H}/scripts/build-graph.sh ${RDIR}/findings ${RDIR}/knowledge-graph.json ` +
      `then bash ${H}/scripts/assert-graph-mif.sh ${RDIR}/knowledge-graph.json — must pass (proves every node/edge traces to a ` +
      `urn:mif: id, MIF-native, never tag-derived).\n` +
      `Return the README path, whether its --check passed, whether the graph rebuilt, whether assert-graph-mif passed, and the ` +
      `full changed-file list.`,
    { label: 'projection:index', model: 'sonnet', schema: INDEX_SCHEMA },
  )
} catch (err) {
  log(`WARNING: Index phase agent() threw instead of returning (research-harness-template#720 — the subagent likely completed its README/graph work but failed to call StructuredOutput, possibly after falsely claiming it already had) — degrading to a null index rather than failing the whole pipeline. Underlying error: ${err && err.message ? err.message : err}`)
  index = null
}
if (index && (!index.readmeCheckPassed || !index.graphAssertPassed)) {
  log(`WARNING: Index phase did not fully validate (readmeCheckPassed=${index.readmeCheckPassed}, graphAssertPassed=${index.graphAssertPassed}) — surfacing rather than silently proceeding`)
} else if (!index) {
  log(`WARNING: Index phase produced no result at all (readmePath=null) — README/graph refresh may not have happened this run; see the research-harness-template#720 note above`)
}

phase('Verify')
const changed = [report.reportPath].concat(index ? index.changedFiles : [])
// research-harness-template#727 (mirrors #720's Index-phase fix): agent()
// can throw instead of returning here too — guard it the same way, but
// DEGRADE to a null verify (matching Index) rather than re-throw (matching
// Report): the final return below already treats a null verify as
// ok:false + problems:['verify agent failed'], the same non-fatal shape
// Index's null-index degradation uses, so this is a safe no-op path, not a
// caller-visible-contract change.
//
// Model stays `haiku` deliberately — this is a DEFAULT-NO-OP decision, not
// an oversight. Verify's task (run markdownlint-cli2/ajv-validate, report
// problems verbatim, do not fix) is a single-shot mechanical check-and-
// report with no authored-prose sub-step, the same shape as this file's own
// `projection:preflight` and `projection:genre-resolve` haiku calls above —
// neither of which has ever shown this failure class in production — and
// NOT the "author 4-10 synthesis bullets" authored-prose shape that #720's
// own analysis pinned as Index's actual failure driver. If production data
// later shows Verify hitting this class at a nontrivial rate despite that
// reasoning, the try/catch below still catches it safely either way — this
// is a latency/cost-vs-robustness tradeoff to revisit then, not a
// correctness gap now.
let verify = null
try {
  verify = await agent(
    `Targeted verification of ONLY these changed files in harness ${H} (never the full verify.sh suite here — D-10): ` +
      `${JSON.stringify(changed)}. Run markdownlint-cli2 (repo config) on the markdown; ajv-validate any touched JSON against ` +
      `its schema under ${H}/schemas/ (knowledge-graph, findings). If reports/<topic>/ontology-map.json is among the ` +
      `changed/touched files, its established, correct shape is a JSON ARRAY of {finding_id, entity_type, resolved_ontology, ` +
      `basis, valid} rows (see scripts/mif-container-import.sh, scripts/build-concordance.sh, scripts/ontology-review.sh, and ` +
      `every existing topic's on-disk ontology-map.json) — there is no schemas/ontology-map.schema.json to ajv-validate it ` +
      `against, so do not flag its array root as wrong or assume it should be an object; only confirm it parses as valid JSON ` +
      `and its root is an array. Report problems verbatim; do not fix anything, and never run this concurrently with ` +
      `scripts/ontology-review.sh (shared temp/catalog state races).`,
    { label: 'projection:verify', model: 'haiku', effort: 'low', schema: VERIFY_SCHEMA },
  )
} catch (err) {
  log(`WARNING: Verify phase agent() threw instead of returning (research-harness-template#727 — mirrors the #720 Index-phase failure class) — degrading to a null verify rather than failing the whole pipeline one step from the finish line. Underlying error: ${err && err.message ? err.message : err}`)
  verify = null
}

return {
  ok: !!(verify && verify.lintClean && verify.schemaClean),
  reportPath: report.reportPath,
  reportId: report.reportId,
  mifLevel: report.frontmatterLevel,
  checksAddressed: report.checksAddressed,
  verificationVerdict: report.verificationVerdict,
  genreRequested: GENRE,
  genreApplied: report.genreApplied,
  genreSkillInvoked: report.genreSkillInvoked,
  provenanceOutcome: report.provenanceOutcome,
  provenanceReason: report.provenanceReason,
  readmePath: index ? index.readmePath : null,
  readmeCheckPassed: index ? index.readmeCheckPassed : false,
  graphRefreshed: index ? index.graphRefreshed : false,
  graphAssertPassed: index ? index.graphAssertPassed : false,
  problems: verify ? verify.problems : ['verify agent failed'],
}
