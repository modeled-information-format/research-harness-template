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
//   structural backbone (haiku authors ONLY Key Findings/Purpose on top) and
//   build-graph.sh + assert-graph-mif.sh for the knowledge-graph refresh.
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
export const meta = {
  name: 'research-projection',
  description: 'Atomic step 5 (projection): project the typed synthesis onto the durable corpus surfaces — the canonical MIF Level-3 report of record (via the publish-report script pipeline, gated by a REAL falsification pass, never a hand-authored verdict), the topic README/knowledge graph (via the readme/graph skills\' deterministic scripts, synthesis-grade Key Findings authored on top) — then verify only what changed',
  whenToUse: 'After a clean synthesis — materializes the tracked, in-repo projections (the report channel is the source of truth; deliverable genres are a separate workflow)',
  phases: [
    { title: 'Report', detail: 'existence-checked synthesisPath (same-process contract) -> publish-report pipeline: synthesize-artifact.sh -> REAL falsify.sh gate over the report\'s own central claims (never hand-authored) -> render-artifact.sh -> mif-project.sh', model: 'sonnet' },
    { title: 'Index', detail: 'readme skill\'s build-topic-readme.sh backbone + synthesis-grade Key Findings/Purpose authored on top -> graph skill\'s build-graph.sh + assert-graph-mif.sh', model: 'haiku' },
    { title: 'Verify', detail: 'targeted gates on changed files only (D-10) — never the full verify.sh suite', model: 'haiku' },
  ],
}

// args: { harnessDir, topic, synthesisPath, slug?: string, genre?: string (default 'general') }
const H = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
const SYN = args && args.synthesisPath
if (!TOPIC) throw new Error('research-projection: args.topic is required')
if (!SYN) throw new Error('research-projection: args.synthesisPath is required (run research-synthesis first, in the SAME process — see the same-process contract note in this module\'s header)')
const RDIR = `${H}/reports/${TOPIC}`
const SLUG = (args && args.slug) || TOPIC
const GENRE = (args && args.genre) || 'general'

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
    frontmatterLevel: { type: 'integer' },
    checksAddressed: { type: 'array', items: { type: 'string' } },
    verificationVerdict: { type: 'string', enum: ['falsified', 'weakened', 'survived', 'inconclusive'] },
    reportId: { type: 'string', description: 'the report\'s own @id — same across a supersession re-run, by construction of render-artifact.sh (see header note)' },
  },
  required: ['reportPath', 'frontmatterLevel', 'checksAddressed', 'verificationVerdict', 'reportId'],
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

const report = await agent(
  `Render the CANONICAL MIF Level-3 report of record for topic ${TOPIC} in harness ${H} — the harness's source of truth, held ` +
    `to the same bar as a finding (never exempt from the gate). Follow the publish-report skill's SCRIPT PIPELINE exactly — ` +
    `never hand-author the frontmatter, citations, or verification verdict directly; the verdict in particular must come from ` +
    `a REAL falsification pass, never be asserted.\n` +
    `Input: the typed synthesis at ${SYN} (read it; it is @id-keyed to surviving findings).\n` +
    `PIPELINE, IN ORDER (publish-report SKILL.md steps 2-5):\n` +
    `1. bash ${H}/scripts/synthesize-artifact.sh ${RDIR}/findings ${GENRE} ${RDIR}/artifact.json — projects the surviving ` +
    `findings into one typed Artifact (schemas/artifact.schema.json). Cross-check its sections against the synthesis at ${SYN} ` +
    `so the artifact's claims trace to what the synthesis actually established.\n` +
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
    `shipped — report verificationVerdict="falsified" and STOP here, do not proceed to render.\n` +
    `4. jq '.extensions.harness.verification' ${RDIR}/report-finding.falsified.json > ${RDIR}/report.verification.json\n` +
    `5. bash ${H}/scripts/render-artifact.sh ${RDIR}/artifact.json report ${RDIR}/${SLUG}.md ${RDIR}/report.verification.json ` +
    `— write-then-validated; fails closed if it does not project to a valid L3 finding. If a report of record already exists ` +
    `at this path, this IS a supersession re-render, not a fresh create: the engine derives the report's @id deterministically ` +
    `from its namespace+slug, so re-running this exact command with the same topic/slug preserves the SAME @id automatically ` +
    `(version increments, temporal.validFrom carries forward) — do not delete the existing file first, and do not attempt to ` +
    `hand-copy an @id forward yourself.\n` +
    `6. Re-confirm: bash ${H}/scripts/mif-project.sh ${RDIR}/${SLUG}.md — must report "projects to a valid MIF L3 finding".\n` +
    `Return the report path, the achieved MIF level, which goal check ids the report addresses, the verification verdict ` +
    `ACTUALLY WRITTEN by falsify.sh (never hand-authored), and the report's own @id (read it back from the rendered file's ` +
    `frontmatter after step 5/6, not invented).`,
  { label: 'projection:report', model: 'sonnet', schema: REPORT_SCHEMA },
)
if (!report) throw new Error('research-projection: report rendering failed')
if (report.verificationVerdict === 'falsified') {
  log(`Report quarantined: the falsification gate returned "falsified" over the report's own claims — NOT shipping ${report.reportPath}`)
  return { ok: false, reason: 'report-falsified', reportPath: report.reportPath, verificationVerdict: report.verificationVerdict }
}

phase('Index')
const index = await agent(
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
  { label: 'projection:index', model: 'haiku', schema: INDEX_SCHEMA },
)
if (index && (!index.readmeCheckPassed || !index.graphAssertPassed)) {
  log(`WARNING: Index phase did not fully validate (readmeCheckPassed=${index.readmeCheckPassed}, graphAssertPassed=${index.graphAssertPassed}) — surfacing rather than silently proceeding`)
}

phase('Verify')
const changed = [report.reportPath].concat(index ? index.changedFiles : [])
const verify = await agent(
  `Targeted verification of ONLY these changed files in harness ${H} (never the full verify.sh suite here — D-10): ` +
    `${JSON.stringify(changed)}. Run markdownlint-cli2 (repo config) on the markdown; ajv-validate any touched JSON against ` +
    `its schema under ${H}/schemas/ (knowledge-graph, findings). Report problems verbatim; do not fix anything, and never run ` +
    `this concurrently with scripts/ontology-review.sh (shared temp/catalog state races).`,
  { label: 'projection:verify', model: 'haiku', effort: 'low', schema: VERIFY_SCHEMA },
)

return {
  ok: !!(verify && verify.lintClean && verify.schemaClean),
  reportPath: report.reportPath,
  reportId: report.reportId,
  mifLevel: report.frontmatterLevel,
  checksAddressed: report.checksAddressed,
  verificationVerdict: report.verificationVerdict,
  readmePath: index ? index.readmePath : null,
  readmeCheckPassed: index ? index.readmeCheckPassed : false,
  graphRefreshed: index ? index.graphRefreshed : false,
  graphAssertPassed: index ? index.graphAssertPassed : false,
  problems: verify ? verify.problems : ['verify agent failed'],
}
