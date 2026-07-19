// research-pipeline.js — the workflow-of-workflows: deterministic mode
// router + bounded autonomous round loop composing the eleven atomic
// research workflows via workflow().
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573/#578/#582/#586/#590/#595
// precedent.
//
// Vendored from the workspace engine reference (Epic #550, Task #599). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569/#573/#578/#582/#586/#590/#595 precedent) — the
// reference's own default (a workspace-relative
// 'repos/research-harness-template' path) does not apply inside the
// instance/template itself. `workflowsDir` keeps its own reference default
// ('.claude/workflows') unchanged: that path is already correct in-repo, on
// both sides of the template/instance boundary.
//
// THE ONE COMPOSER (D-9, architecture doc, .claude/workflows/
// research-pipeline-architecture.md). Every other vendored module bottoms
// out in agent()/parallel() calls; this is the sole script in the set that
// calls workflow() — confirmed by re-grepping all eleven sibling modules for
// `workflow(` at implementation time (zero real composition calls; the only
// hit, in research-projection.js, is a comment referencing this module's
// usage, not an actual call). The platform's own one-level `workflow()`
// nesting rule means none of the eleven may themselves compose a child
// workflow — they only ever return plans/results for THIS script to act on.
//
// wf() SCRIPTPATH VERIFICATION (re-confirmed against on-disk source at
// implementation time, not from prior planning notes): `${W}/research-${name}.js`
// resolves exactly against every one of the eleven real vendored filenames,
// call by call — goal, fanout, falsify (used directly in the full-mode loop
// and via the falsifyAll() drain helper), synthesis, projection,
// deliverables, augment, add-dimensions, pivot, import, coverage-audit. No
// stale or renamed reference exists.
//
// MODE ROUTER. Six modes share this one entry point: `full` runs the
// bounded autonomous goal loop (goal -> [fanout -> falsify-drain -> synthesis
// -> independent completion check]* -> audit-driven adaptation ->
// projection -> optional deliverables); `augment`, `pivot`, `import`, and
// `audit` are each a shorter, mode-specific composition of the same atomic
// workflows, matching the architecture doc's Level-3 orchestrator flowchart
// exactly (no mode invents a step the flowchart does not show).
//
// MODE 'deliverables' (research-harness-template#624): render genre/channel
// deliverables from a topic's EXISTING, already-gated corpus without
// re-running fanout/falsify. research-synthesis.js's own ephemeral-output
// contract (see that module's header) is explicitly SAME-PROCESS-ONLY — a
// prior run's synthesisPath cannot be recovered here, so this mode cheaply
// re-drafts a fresh synthesis (synthesis alone, never fanout/falsify) from
// the survivor corpus already on disk and feeds that fresh synthesisPath
// straight into wf('deliverables', ...) in the same process, satisfying
// research-deliverables.js's same-process preflight check. This is a
// deliberate, narrower composition than `full`'s Project+Deliver tail: it
// does NOT call research-projection — the report of record
// (reports/<topic>/<slug>.md) is left untouched by design (mirrors `audit`
// mode's own minimalism; flagged here for reviewer sign-off, not decided
// silently). Re-synthesizing is not byte-identical to any prior run's
// synthesis (LLM drafting is non-deterministic) — it is a fresh synthesis
// over the same already-gated findings, satisfying the issue's actual
// acceptance driver ("without re-gathering findings or re-running the
// falsification gate") even though it is not literally "replay the exact
// prior synthesis."
//
// HONEST-TERMINATION SEMANTICS (NFR-9/NFR-10): the round loop's `done` flag
// is set ONLY by `unmet.length === 0` from the independent completionCheck()
// agent — never by activity, and never by this script's own narrative. When
// the augment judge in the adaptation step returns an empty `deepen` plan,
// the loop breaks immediately with the judge's own stated reasoning logged —
// a real code path (the `else` branch below), not merely documented
// behavior. All bounds (`maxRounds`, the `budgetLow()` token floor, the
// goal's own `boundHit`) are code comparisons on typed agent output, never
// prompt-enforced discipline (D-5).
//
// The old agent engine (.claude/agents/orchestrator.md, /start) is left
// completely untouched by this vendor — this script supersedes it in
// capability only; the supersession itself is documented separately (a Docs
// task), never by silent deletion here.
export const meta = {
  name: 'research-pipeline',
  description: 'The workflow-of-workflows: deterministic router + bounded autonomous goal loop composing the atomic research workflows (goal → [fanout → falsify → synthesis → check]* → audit-adapt → projection → deliverables) via workflow(); all mode routing, round bounds, budget floors, and done-decisions live in this script, never in a model prompt',
  whenToUse: 'The single entry point for a research campaign against a harness instance: full runs, augment/pivot/import/audit/deliverables modes — each mode a different composition of the same atomic workflows',
  phases: [
    { title: 'Route', detail: 'deterministic mode routing (full | augment | pivot | import | audit | deliverables)' },
    { title: 'Goal', detail: 'research-goal child workflow (full mode)' },
    { title: 'Rounds', detail: 'fanout → falsify(+drain) → synthesis → independent completion check, adapted per round' },
    { title: 'Project', detail: 'research-projection child workflow' },
    { title: 'Deliver', detail: 'research-deliverables child workflow (when genres/channels requested)' },
  ],
}

// args: {
//   harnessDir, topic,                       — the instance and topic (topic required)
//   mode?: 'full'|'augment'|'pivot'|'import'|'audit'|'deliverables'   (default 'full')
//   ask?: string                             — full: the raw research ask for research-goal
//   focusHint?: string                       — augment: user steer
//   delta?: string                           — pivot: what changed (required for pivot)
//   containerDir?: string                    — import: the MIF container dir (required for import)
//   trustImportedVerdicts?: boolean          — import
//   genres?: string[], channels?: string[]   — deliverables to render at the end
//   maxRounds?: number (default 3), claimBudget?, queryBudget?, lenses?
//   workflowsDir?: string (default '.claude/workflows') — where the atomic scripts live
//   runDate?: string — a stamped ISO-8601 timestamp supplied by THIS SCRIPT'S OWN CALLER (the /research command's
//             own `date` invocation, run before it ever calls the Workflow tool). This script cannot compute one
//             itself: new Date()/Date.now() are disallowed inside any Workflow-runtime script's own body (breaks
//             resume determinism — #618), and research-pipeline.js is itself such a script. Forwarded verbatim,
//             unvalidated, to every child call via wf() below — research-falsify.js is the only child that
//             consumes it, and only once a finding actually needs gating (so 'audit' mode, which never gates
//             anything, works fine with runDate omitted).
// }
// The Workflow tool's top-level `args` parameter arrives at this external
// entry point as a JSON-encoded STRING, not a parsed object (confirmed
// empirically — issue #617). Every other vendored module is only ever
// invoked internally via this script's own workflow() calls, which pass
// real in-process JS objects, so only THIS module needs the guard.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})
const H = A.harnessDir || '.'
const TOPIC = A.topic
if (!TOPIC) throw new Error('research-pipeline: args.topic is required')
const MODE = A.mode || 'full'
// research-harness-template#624 (adjacent fix): every mode branch below is
// an independent early-return `if`, with no terminal `else` — so an
// unrecognized MODE string (a typo, e.g. 'deliverabels') fell through
// silently into the full-mode round loop with no error at all. Guard once,
// before dispatch, rather than adding a terminal else to a chain that isn't
// actually if/else-linked (each mode's `if` returns independently; 'full'
// is the fallthrough remainder of the script, not its own `if` branch).
const KNOWN_MODES = ['full', 'augment', 'pivot', 'import', 'audit', 'deliverables']
if (!KNOWN_MODES.includes(MODE)) throw new Error(`research-pipeline: unknown mode '${MODE}' (expected one of ${KNOWN_MODES.join(', ')})`)
const MAX_ROUNDS = A.maxRounds || 3
const W = A.workflowsDir || '.claude/workflows'
const RUN_DATE = A.runDate
const BUDGET_FLOOR = 60000 // stop opening new rounds below this many remaining tokens

const wf = (name, wfArgs) => workflow({ scriptPath: `${W}/research-${name}.js` }, { harnessDir: H, topic: TOPIC, runDate: RUN_DATE, ...wfArgs })
const budgetLow = () => !!(budget.total && budget.remaining() < BUDGET_FLOOR)

const CHECK_SCHEMA = {
  type: 'object',
  properties: {
    met: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, evidence: { type: 'string' } }, required: ['id', 'evidence'] } },
    unmet: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] } },
    boundHit: { type: 'boolean', description: 'true if the goal declares a bound this run has now reached' },
  },
  required: ['met', 'unmet', 'boundHit'],
}

// Independent completion evaluator — never the agent that did the work. Checks are graded
// against the corpus and each check's own verify command, not against the narrative.
//
// research-harness-template#623: research-fanout.js's per-dimension validate/repair lane
// (the documented, sanctioned write-validate-repair-revalidate contract) can mutate findings
// in place BEFORE this evaluator ever runs — so a corpus that arrived heavily defective and a
// corpus that was clean from the start look identical from "current corpus state" alone. Pass
// this round's repair count through explicitly so a schema/citation-validity check (e.g.
// finding_valid, citation_integrity) can never be graded 'met' from the post-repair state
// without disclosing that repair happened — the exact self-dealing #623 reported.
async function completionCheck(roundNo, roundRepaired) {
  return agent(
    `Independent completion evaluation, round ${roundNo}, topic ${TOPIC}, harness ${H}. Read ${H}/reports/${TOPIC}/goal.json. ` +
      `For each completion_condition.check: run its verify command if it has one (report actual output as evidence), else grade its assertion strictly against the CURRENT corpus state (findings + verdicts + synthesis surfaces on disk) — a check is met only when a transcript-verifiable fact proves it, never because work happened. ` +
      `DISCLOSURE (research-harness-template#623): research-fanout repaired ${roundRepaired} schema-invalid or citation-defective finding(s) this round before any check was graded — repair-then-revalidate at authoring time is the documented, sanctioned contract, never by itself a reason to fail a check. But grading a check about finding schema or citation validity (e.g. finding_valid, citation_integrity) 'met' from the CURRENT post-repair state, without disclosing that repair count, is exactly the self-dealing this independent evaluation exists to catch. If roundRepaired > 0 and a check you grade concerns finding schema or citation validity, your evidence string for that check MUST state the repair count verbatim — never grade it met silently as if the corpus arrived clean. ` +
      `Also report boundHit per the goal's bound (max_rounds=${MAX_ROUNDS} rounds have run: ${roundNo}). You did none of this research; grade adversarially.`,
    { label: `check:round-${roundNo}`, phase: 'Rounds', model: 'sonnet', schema: CHECK_SCHEMA },
  )
}

// Falsify with drain: the claim budget makes each call bounded; drain until nothing is deferred.
async function falsifyAll(extra) {
  let total = 0
  const rollup = {}
  for (let i = 0; i < 5; i++) {
    const r = await wf('falsify', { scope: 'all', claimBudget: A.claimBudget, queryBudget: A.queryBudget, lenses: A.lenses, ...extra })
    if (!r) break
    total += r.gated
    for (const k of Object.keys(r.rollup || {})) rollup[k] = (rollup[k] || 0) + r.rollup[k]
    if (!r.deferredIds || !r.deferredIds.length) break
    if (budgetLow()) { log(`Budget floor: ${r.deferredIds.length} finding(s) left ungated`); break }
    log(`Draining falsification backlog: ${r.deferredIds.length} deferred`)
  }
  return { gated: total, rollup }
}

phase('Route')
log(`Mode: ${MODE}; harness: ${H}; topic: ${TOPIC}`)

if (MODE === 'audit') {
  const audit = await wf('coverage-audit', {})
  return { mode: MODE, ...audit }
}

if (MODE === 'import') {
  if (!A.containerDir) throw new Error('import mode requires args.containerDir')
  const imp = await wf('import', { containerDir: A.containerDir, trustImportedVerdicts: A.trustImportedVerdicts })
  if (!imp || !imp.ok) return { mode: MODE, imported: imp }
  const gate = imp.needsGating.length ? await falsifyAll({}) : { gated: 0, rollup: {} }
  const syn = await wf('synthesis', {})
  const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null
  return { mode: MODE, imported: imp.imported.length, gate, synthesis: syn, projection: proj }
}

if (MODE === 'pivot') {
  if (!A.delta) throw new Error('pivot mode requires args.delta')
  const pivot = await wf('pivot', { delta: A.delta })
  // Re-gate the stale carry-overs through falsify.sh's re-verify path, then research only the gaps.
  if (pivot.reverifyIds && pivot.reverifyIds.length) {
    await wf('falsify', { scope: { ids: pivot.reverifyIds }, regate: true, claimBudget: A.claimBudget, queryBudget: A.queryBudget, lenses: A.lenses })
  }
  let fan = null
  if (pivot.gapDimensions && pivot.gapDimensions.length && !budgetLow()) {
    fan = await wf('fanout', { dimensions: pivot.gapDimensions, depth: 'standard', roundContext: `Goal pivoted (${pivot.goalVersion}): ${pivot.goalStatement}. Carried ${pivot.carry.length} findings; you are filling the gaps only.` })
    await falsifyAll({})
  }
  const syn = await wf('synthesis', {})
  const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null
  return { mode: MODE, goalVersion: pivot.goalVersion, carried: pivot.carry.length, stale: pivot.stale.length, fanout: fan, synthesis: syn, projection: proj }
}

if (MODE === 'augment') {
  const plan = await wf('augment', { focusHint: A.focusHint })
  if (!plan.deepen.length) return { mode: MODE, deepened: [], reasoning: plan.reasoning }
  const dims = plan.deepen.map((d) => d.dimension)
  const fan = await wf('fanout', { dimensions: dims, depth: plan.deepen.some((d) => d.depth === 'deep') ? 'deep' : 'standard', roundContext: `Augmentation round targeting: ${plan.deepen.map((d) => `${d.dimension} (${d.rationale})`).join('; ')}` })
  const gate = await falsifyAll({})
  const syn = await wf('synthesis', {})
  const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null
  return { mode: MODE, deepened: dims, fanout: fan, gate, synthesis: syn, projection: proj }
}

if (MODE === 'deliverables') {
  if (!((A.genres && A.genres.length) || (A.channels && A.channels.length))) {
    throw new Error('deliverables mode requires args.genres or args.channels')
  }
  // Cheap: synthesis alone, never fanout/falsify — the survivor corpus
  // already on disk is reused as-is. See the module-header note above for
  // why this re-synthesizes rather than reusing a prior run's synthesisPath
  // (research-synthesis.js's ephemeral-output contract is same-process-only).
  const syn = await wf('synthesis', {})
  if (!syn || !syn.ok) return { mode: MODE, synthesis: syn, deliverables: null }
  const del = await wf('deliverables', { synthesisPath: syn.synthesisPath, genres: A.genres, channels: A.channels })
  return { mode: MODE, synthesis: syn, deliverables: del }
}

// ---- MODE full: the bounded autonomous goal loop ----
phase('Goal')
const goal = await wf('goal', { ask: A.ask || '' })
if (!goal || !goal.ok) return { mode: MODE, stage: 'goal', failed: true, detail: goal }

phase('Rounds')
let dims = goal.dimensions
let depth = 'standard'
let roundContext = ''
let leads = []
let lastSyn = null
let lastCheck = null
let done = false
// research-harness-template#623: running total of findings repaired across every round —
// surfaced in the final report so a heavily-repaired corpus is never indistinguishable from a
// clean one just because the completion check only ever sees post-repair state.
let totalRepaired = 0

for (let round = 1; round <= MAX_ROUNDS && !done; round++) {
  if (budgetLow()) { log(`Budget floor before round ${round} — stopping with unmet checks`); break }
  log(`— Round ${round}/${MAX_ROUNDS}: dimensions [${dims.join(', ')}], depth ${depth}`)

  const fan = await wf('fanout', { dimensions: dims, depth, roundContext })
  if (fan && fan.crossDimensionLeads) leads = leads.concat(fan.crossDimensionLeads)
  const roundRepaired = (fan && fan.repaired) || 0
  totalRepaired += roundRepaired
  if (roundRepaired) log(`Round ${round}: research-fanout repaired ${roundRepaired} schema-invalid/citation-defective finding(s) after the initial validate pass, before the completion check`)

  await falsifyAll({})
  lastSyn = await wf('synthesis', {})

  lastCheck = await completionCheck(round, roundRepaired)
  if (!lastCheck) { log('Completion evaluator failed — stopping conservatively'); break }
  log(`Checks: ${lastCheck.met.length} met, ${lastCheck.unmet.length} unmet`)
  if (!lastCheck.unmet.length) { done = true; break }
  if (lastCheck.boundHit) { log('Goal bound hit — stopping per contract'); break }
  if (round === MAX_ROUNDS || budgetLow()) break

  // Adapt: audit routes the next round instead of blindly re-running everything.
  const audit = await wf('coverage-audit', { leads, checkCoverage: lastSyn ? lastSyn.checkCoverage : undefined })
  const top = (audit.backlog || []).filter((b) => b.priority <= 3)
  const wantsNewDim = top.some((b) => b.action === 'add-dimensions')
  if (wantsNewDim) {
    const added = await wf('add-dimensions', { leads })
    if (added.added.length) { dims = added.added; depth = 'standard'; roundContext = `New dimensions added by audit (${audit.summary}); research ONLY these.`; continue }
  }
  const plan = await wf('augment', { checkCoverage: lastSyn ? lastSyn.checkCoverage : undefined, focusHint: `Unmet checks: ${lastCheck.unmet.map((u) => `${u.id} (${u.why})`).join('; ')}` })
  if (plan.deepen.length) {
    dims = plan.deepen.map((d) => d.dimension)
    depth = plan.deepen.some((d) => d.depth === 'deep') ? 'deep' : 'standard'
    roundContext = `Round ${round} left checks unmet: ${lastCheck.unmet.map((u) => u.id).join(', ')}. Deepening: ${plan.deepen.map((d) => d.rationale).join('; ')}`
  } else {
    log(`Augment judge found nothing to deepen (${plan.reasoning.slice(0, 150)}) — evidence may not exist; stopping`)
    break
  }
}

phase('Project')
// research-harness-template#626: the goal's own elicited deliverables.genres
// (never the CLI A.genres — that arg is the Deliver phase's own axis, see
// below) drives how many canonical L3 reports this phase renders. Default
// ['general'] when the goal declared none, preserving the pre-#626 single-
// neutral-report behavior exactly. A genre other than 'general' gets its own
// genre-suffixed slug (reports/<topic>/<topic>.<genre>.md) so multiple
// requested genres never collide on the one canonical report path.
const projectGenres =
  goal.deliverables && Array.isArray(goal.deliverables.genres) && goal.deliverables.genres.length
    ? goal.deliverables.genres
    : ['general']
const projections = []
if (lastSyn && lastSyn.synthesisPath) {
  for (const genre of projectGenres) {
    const slug = genre === 'general' ? TOPIC : `${TOPIC}.${genre}`
    const result = await wf('projection', { synthesisPath: lastSyn.synthesisPath, genre, slug })
    projections.push({ genre, slug, result })
  }
}
// Back-compat single `projection` field: the 'general' render when one was
// produced (the common/default case — matches every caller before #626),
// else the first requested genre's result. `projections[]` below carries
// every render for a caller that requested more than one genre.
const projection = (projections.find((p) => p.genre === 'general') || projections[0] || {}).result || null

phase('Deliver')
// research-harness-template#626: an explicit CLI --genres/--channels arg
// always wins (Array.isArray, not truthiness — an explicit `[]` is a real
// "render nothing" answer, never conflated with "not passed at all", the
// exact class of bug #626 also fixes in research-deliverables.js's own
// CHANNELS default). Absent CLI args fall back to the goal's own elicited
// deliverables.genres/.channels; absent both, this phase's trigger condition
// below (unchanged from before #626) simply finds nothing to render.
const deliverGenres = Array.isArray(A.genres)
  ? A.genres
  : goal.deliverables && Array.isArray(goal.deliverables.genres)
    ? goal.deliverables.genres
    : undefined
const deliverChannels = Array.isArray(A.channels)
  ? A.channels
  : goal.deliverables && Array.isArray(goal.deliverables.channels)
    ? goal.deliverables.channels
    : undefined
let deliverables = null
if (lastSyn && lastSyn.synthesisPath && ((deliverGenres && deliverGenres.length) || (deliverChannels && deliverChannels.length))) {
  deliverables = await wf('deliverables', { synthesisPath: lastSyn.synthesisPath, genres: deliverGenres, channels: deliverChannels })
}

return {
  mode: MODE,
  goal: { file: goal.goalFile, dimensions: goal.dimensions },
  done,
  checks: lastCheck ? { met: lastCheck.met.map((m) => ({ id: m.id, evidence: m.evidence })), unmet: lastCheck.unmet.map((u) => ({ id: u.id, why: u.why })) } : null,
  synthesis: lastSyn ? { path: lastSyn.synthesisPath, ok: lastSyn.ok, coverage: lastSyn.checkCoverage } : null,
  // research-harness-template#623: total findings repaired across every round of this run —
  // 0 when every finding validated on first write.
  repaired: totalRepaired,
  projection,
  // research-harness-template#626: every genre-projection this run actually
  // rendered, `{ genre, slug, result }` per entry — `projection` above is
  // just this array's 'general' (or first) entry, kept for back-compat.
  projections,
  deliverables,
}
