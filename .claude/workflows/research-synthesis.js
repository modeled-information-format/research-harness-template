// research-synthesis.js — atomic step 4 of the research pipeline (synthesis).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560 precedent.
//
// Vendored from the workspace engine reference (Epic #542, Task #564). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the established
// precedent from research-goal.js/research-fanout.js/research-falsify.js;
// #563's review flagged this to get right the first time). Select-phase
// verdict handling was verified against the CURRENT substrate rather than
// assumed:
//
//   - VERDICT ENUM + QUARANTINE. schemas/findings.schema.json's
//     extensions.harness.verification.verdict enum is exactly
//     ["falsified", "weakened", "survived", "inconclusive"], and
//     research-falsify.js's REMEDIATION_CONTRACT (#560/#563) already moves
//     every falsified finding to reports/<topic>/quarantine/ and downgrades
//     (never removes) weakened ones. This module's Select phase therefore
//     treats survived/weakened/inconclusive as the citable survivor set,
//     structurally excludes quarantine/archive by directory (falsified
//     findings never appear under findings/ once research-falsify.js has
//     run), and counts findings with no verification block separately as
//     "unverified" (ungated) — never silently promoted into the survivor
//     set just because they haven't been falsified yet.
//   - COMPLETION_CONDITION.CHECKS[] SHAPE. schemas/goal.schema.json's
//     completion_condition.checks[] requires {id, assertion} with optional
//     verify, exactly what research-goal.js (#539/#555) authors via jq+ajv.
//     The Draft phase organizes the synthesis around these check ids
//     unchanged from the reference script.
//
// GENUINE SUBSTRATE GAP — the ephemeral-output contract (surfaced, not
// silently resolved, per #560/#541's precedent for handling gaps):
//
//   No canonical mktemp/scratch-path convention exists anywhere in this
//   repo — every script invents its own ad hoc mktemp usage (scripts/
//   build-graph-viz.sh mktemp -d's a dir OUTSIDE the tree by default;
//   scripts/mif-container-export.sh mktemp -d's a throwaway scratch dir;
//   scripts/falsify.sh-adjacent code in research-falsify.js mktemps a
//   fixture file OUTSIDE the tree and removes it when done). There is no
//   shared helper module and no single documented "ephemeral synthesis
//   output" contract to reuse — so this module INVENTS and STATES one here,
//   explicitly, for research-projection (#543, not yet started) to consume:
//
//     EPHEMERAL-OUTPUT CONTRACT (v1, this module):
//     1. The Draft phase's agent produces the typed synthesis as a JSON
//        document written to a path obtained via a bare `mktemp` (a single
//        file, not a directory) OUTSIDE the repo tree — matching the spirit
//        of every other ad hoc convention in this repo (nothing derived
//        ever lands under reports/<topic>/; see CLAUDE.md "Ephemeral
//        artifacts go to mktemp outside the tree").
//     2. The absolute path is returned to the caller in the top-level
//        `synthesisPath` field of this module's final return value (see
//        DRAFT_SCHEMA / the `return` at the bottom) — never nested, never
//        renamed. A consumer (research-projection today; any future
//        workflow tomorrow) reads `result.synthesisPath` to locate the
//        artifact.
//     3. LIFETIME: the file is process-ephemeral. This module does NOT
//        delete it (unlike research-falsify.js's fixture, which is
//        single-use and cleaned up immediately after falsify.sh consumes
//        it) — the synthesis output's whole purpose is to be read by a
//        LATER phase/workflow in the same pipeline run. The contract is
//        therefore: the path is valid for the lifetime of the invoking
//        process/session; a caller composing research-synthesis ->
//        research-projection in one pipeline run must read synthesisPath
//        before that process exits. Nothing in this module or elsewhere
//        guarantees survival across process boundaries (no cleanup trap is
//        installed here for the same reason — there is nothing durable to
//        clean up on this module's own timeline).
//     4. SHAPE ON DISK: the JSON document itself is `{ sections: [...],
//        findingsUsed, ...synthesis body keyed to check ids and finding
//        @ids }` — the exact structure an agent composes (see the Draft
//        phase prompt below); this module does not itself enforce a schema
//        on the file's contents beyond what the Critique phase grades.
//
//   This is a NEW convention, not an existing one lifted from elsewhere —
//   flagged here for reviewer sign-off in the PR, same as #560 flagged its
//   regate design question rather than deciding it silently.
export const meta = {
  name: 'research-synthesis',
  description: 'Atomic step 4 (synthesis): evaluator-optimizer loop — a sonnet synthesizer drafts a typed, @id-keyed synthesis from surviving findings; an opus critic grades it against the goal completion condition and citation-key integrity; bounded repair rounds until clean',
  whenToUse: 'After the falsification gate — turns the surviving corpus into the typed synthesis the projection and deliverable workflows consume',
  phases: [
    { title: 'Select', detail: 'survivors + goal checks, structurally excluding falsified/quarantined', model: 'haiku' },
    { title: 'Draft', detail: 'typed synthesis keyed to finding @ids, ephemeral (mktemp, OUTSIDE the repo tree — see the ephemeral-output contract above)', model: 'sonnet' },
    { title: 'Critique', detail: 'opus grader vs completion condition, bounded repair loop' },
  ],
}

// args: { harnessDir, topic, maxRepairRounds?: number (default 2) }
const H = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
if (!TOPIC) throw new Error('research-synthesis: args.topic is required')
const RDIR = `${H}/reports/${TOPIC}`
const MAX_REPAIR = (args && args.maxRepairRounds) || 2

const SELECT_SCHEMA = {
  type: 'object',
  properties: {
    survivors: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          path: { type: 'string' },
          dimension: { type: 'string' },
          verdict: { type: 'string', enum: ['survived', 'weakened', 'inconclusive'] },
          claimSummary: { type: 'string' },
        },
        required: ['id', 'path', 'dimension', 'verdict', 'claimSummary'],
      },
    },
    excluded: { type: 'integer', description: 'falsified/quarantined count left out' },
    unverified: { type: 'integer', description: 'findings with no verification block — must be 0 for a clean synthesis' },
    checks: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, assertion: { type: 'string' }, verify: { type: 'string' } },
        required: ['id', 'assertion'],
      },
    },
    goalStatement: { type: 'string' },
  },
  required: ['survivors', 'excluded', 'unverified', 'checks', 'goalStatement'],
}
const DRAFT_SCHEMA = {
  type: 'object',
  properties: {
    // Ephemeral-output contract field 2 (see module header): this exact
    // field name, at the top level of this module's own return value too —
    // research-projection (#543) and any future consumer reads
    // result.synthesisPath, never a nested or renamed variant.
    synthesisPath: { type: 'string', description: 'mktemp FILE path OUTSIDE the repo tree (ephemeral-output contract v1 — see module header)' },
    sections: { type: 'array', items: { type: 'string' } },
    findingsUsed: { type: 'integer' },
  },
  required: ['synthesisPath', 'sections', 'findingsUsed'],
}
const CRITIQUE_SCHEMA = {
  type: 'object',
  properties: {
    clean: { type: 'boolean' },
    perCheck: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          checkId: { type: 'string' },
          answered: { type: 'string', enum: ['yes', 'partially', 'no'] },
          note: { type: 'string' },
        },
        required: ['checkId', 'answered', 'note'],
      },
    },
    issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['clean', 'perCheck', 'issues'],
}

phase('Select')
const sel = await agent(
  `Build the synthesis input set for topic ${TOPIC}, harness ${H}.\n` +
    `1. Survivors: every finding under ${RDIR}/findings/ whose extensions.harness.verification.verdict is survived, weakened, or inconclusive (report the verdict per finding — weakened/inconclusive are usable but must be marked). Structurally EXCLUDE everything under ${RDIR}/quarantine/ or ${RDIR}/archive/ (research-falsify.js already moved every falsified finding there — count them in excluded, do not re-derive falsified status from the verdict field). Count findings with NO verification block in unverified (they are not survivors — they are ungated, run research-falsify first).\n` +
    `2. Goal: read ${RDIR}/goal.json — return goal_statement and completion_condition.checks[] (each {id, assertion, verify?} per schemas/goal.schema.json).\n` +
    `Return one row per survivor: @id, path, dimension, verdict, one-sentence claim summary.`,
  { label: 'synthesis:select', model: 'haiku', effort: 'low', schema: SELECT_SCHEMA },
)
if (!sel) throw new Error('research-synthesis: selection failed')
if (sel.unverified > 0) log(`WARNING: ${sel.unverified} ungated finding(s) exist — run research-falsify first; they are excluded from this synthesis`)
if (!sel.survivors.length) {
  log('No surviving findings to synthesize — nothing to do')
  return { ok: false, reason: 'no-survivors', excluded: sel.excluded, unverified: sel.unverified }
}
log(`Synthesizing ${sel.survivors.length} survivor(s) (${sel.excluded} excluded, ${sel.unverified} ungated) against ${sel.checks.length} goal check(s)`)

phase('Draft')
const draft = await agent(
  `Produce the TYPED SYNTHESIS for research topic ${TOPIC} (harness ${H}) — the structured intermediate the output channels render. It is NOT a finished report, blog post, or fixed section taxonomy.\n` +
    `GOAL: ${sel.goalStatement}\n` +
    `COMPLETION CHECKS (the synthesis is organized around ANSWERING these):\n${sel.checks.map((c) => `- [${c.id}] ${c.assertion}`).join('\n')}\n` +
    `INPUT SET (read each file; use ONLY these — nothing outside it):\n${sel.survivors.map((s) => `- ${s.id} (${s.verdict}, ${s.dimension}): ${s.claimSummary} — ${s.path}`).join('\n')}\n` +
    `RULES: every synthesis claim cites the supporting finding @id(s) inline; a claim resting on a weakened/inconclusive finding carries that confidence marker explicitly; contradictions between survivors are surfaced as tensions, never silently resolved; each goal check gets a section stating the answer the evidence supports (or that it remains open).\n` +
    `OUTPUT: a JSON synthesis document (sections keyed to check ids, claims keyed to finding @ids, a confidence field per claim) written to a SINGLE FILE obtained via a bare \`mktemp\` (not mktemp -d) OUTSIDE the repo tree — the ephemeral-output contract this module documents in its header: derived output never goes under ${RDIR}, and the path you return travels in the synthesisPath field verbatim, nothing else touches or renames it. Return its path.`,
  { label: 'synthesis:draft', model: 'sonnet', schema: DRAFT_SCHEMA },
)
if (!draft) throw new Error('research-synthesis: draft failed')

phase('Critique')
const survivorIds = new Set(sel.survivors.map((s) => s.id))
const critiquePrompt = (path) =>
  `You are the synthesis critic. Grade ${path} (read it) against the session contract — adversarially, not charitably.\n` +
  `GOAL: ${sel.goalStatement}\nCHECKS:\n${sel.checks.map((c) => `- [${c.id}] ${c.assertion}`).join('\n')}\n` +
  `VALID FINDING IDS (the ONLY citable set): ${JSON.stringify(Array.from(survivorIds))}\n` +
  `Grade: (1) per check — does the synthesis answer it from the evidence: yes/partially/no; (2) citation-key integrity — flag any synthesis claim citing an @id outside the valid set, or citing nothing; (3) fidelity — spot-check claims against the cited finding files: flag overreach beyond what the finding supports and any weakened/inconclusive finding used without its confidence marker; (4) tension-burial — flag contradictory survivors merged into one smooth claim. clean=true only if zero issues AND no check graded 'no'.`
let critique = await agent(critiquePrompt(draft.synthesisPath), {
  label: 'synthesis:critique', model: 'opus', effort: 'high', schema: CRITIQUE_SCHEMA,
})
let rounds = 0
while (critique && !critique.clean && rounds < MAX_REPAIR) {
  rounds++
  log(`Critique found ${critique.issues.length} issue(s) — repair round ${rounds}/${MAX_REPAIR}`)
  await agent(
    `Repair the typed synthesis at ${draft.synthesisPath} in place against these critique findings (fix ONLY what is flagged — do not restructure wholesale, do not import evidence outside the valid finding set):\n` +
      critique.issues.map((i) => `- ${i}`).join('\n') +
      `\nPer-check grades needing attention: ${JSON.stringify(critique.perCheck.filter((p) => p.answered !== 'yes'))}. A check the evidence genuinely cannot answer stays marked open — never paper over a gap.`,
    { label: `synthesis:repair-${rounds}`, model: 'sonnet' },
  )
  critique = await agent(critiquePrompt(draft.synthesisPath), {
    label: `synthesis:recritique-${rounds}`, model: 'opus', effort: 'high', schema: CRITIQUE_SCHEMA,
  })
}
if (critique && !critique.clean && rounds >= MAX_REPAIR) {
  log(`Repair loop bounded at ${MAX_REPAIR} round(s) without converging — returning with the unresolved-check report below rather than looping further`)
}

return {
  ok: !!(critique && critique.clean),
  // Ephemeral-output contract field 2 (see module header): top-level,
  // unrenamed — the handoff research-projection (#543) consumes.
  synthesisPath: draft.synthesisPath,
  sections: draft.sections,
  findingsUsed: draft.findingsUsed,
  checkCoverage: critique ? critique.perCheck : [],
  openIssues: critique ? critique.issues : ['critic failed'],
  ungatedFindings: sel.unverified,
}
