// research-pivot.js — atomic action C of the research pipeline
// (pivot research focus: the question itself changes).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573/#578/#582 precedent.
//
// Vendored from the workspace engine reference (Epic #547, Task #586). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569/#573/#578/#582 precedent).
//
// CONFIRMED DELEGATION GAP — same class as #543/#544/#545/#546's finding,
// fixed here. The reference implementation's Reshape phase instructs the
// sonnet agent to compute the gv- content-hash FREEHAND: it describes the
// algorithm in prose (sha256 first-12-hex over the new goal with
// version/supersedes/revision stripped, keys sorted) rather than invoking
// the script this repo already ships for exactly that purpose.
// scripts/goal-version.sh has delegated to the canonical mif-rh-cli engine
// mechanism (`mif-rh-cli harness goal-version <goal.json>`) since the
// Category-B cutover (research-harness-template#276, Story #298) —
// re-deriving the hash from a prose description invites drift from whatever
// the engine actually implements. The fix here wires the Reshape phase to
// the SAME snapshot-then-mint idiom already established and documented for
// goal evolution (.claude/commands/goal-writer.md's --reshape flow, step
// 2-4; carried into .claude/workflows/research-add-dimensions.js's Amend
// phase): snapshot the live goal to reports/<topic>/goals/goal-<OLD>.json
// BEFORE editing, apply the stated delta, then mint the new version by
// actually running `bash scripts/goal-version.sh reports/<topic>/goal.json`
// (twice — once for OLD before the edit, once for NEW after it) and
// stamping .version/.supersedes/.revision with jq — never a model-narrated
// hash. This is a deliberate deviation from the reference implementation's
// own Reshape-phase text, called out here and in the PR description, not
// ported as-is.
//
// GOAL LINEAGE RULES (ADR-0006, docs/adr/0006-content-hashed-append-only-
// goal-versioning.md): the goal is immutable per version — Reshape is a
// lineage event, an append, never an in-place edit. This workflow only
// ever runs against an already-existing goal.json (pivot EVOLVES a goal,
// it does not author one fresh — that precondition is the Reshape phase's
// own first check), so OLD is always a real gv- id scripts/goal-version.sh
// computes over that live content and supersedes is never null here.
// (schemas/goal.schema.json's null case is for the genuinely first goal a
// topic ever mints, before any content exists to hash — out of scope for a
// pivot call, which reshapes an existing goal.)
//
// Classify-phase batching and Plan-phase gap analysis are carried forward
// from the reference LARGELY UNCHANGED (confirmed against the actual
// reference source, not assumed): parallel haiku batches of `batchSize`
// (default 15) grade every existing finding against the NEW goal as
// carry / stale / out-of-scope — findings are gathered once and reused
// across goal versions, classification never deletes, out-of-scope
// findings stay on disk simply unused by the new version. The sonnet Plan
// phase then decides gapDimensions (which dimensions the carried corpus
// cannot answer the new checks from) and reverifyIds (the stale list).
//
// #758 FIX — a deliberate deviation from the reference's own Classify
// phase, called out here (this is the one part of Classify that is NOT
// carried forward unchanged from the reference, unlike the paragraph
// above). Per the Workflow-runtime's documented parallel() contract, a
// batch whose agent() call errors or whose subagent dies on a terminal API
// error resolves that batch's slot to null; the reference's own
// `.filter(Boolean)` before bucketing then silently drops that ENTIRE
// batch's finding ids from carry, stale, AND out-of-scope alike — no
// retry, no record of which ids were lost, nothing beyond an aggregate
// count mismatch in one log line. The Plan phase then reasons about gaps
// over that unaccountably incomplete carry/stale view. Fixed the same way
// research-falsify.js's write-assertion gap (#659) was: retry each failed
// batch exactly once (same retry-once idiom), and a batch still null after
// retry has its ids explicitly captured and returned as `unclassifiedIds`
// (internally the `unclassified` variable) — never silently merged away —
// logged by id, folded into `stale` (so they get RE-GATED rather than
// vanishing from every bucket), and unioned into the final `reverifyIds`
// regardless of what the Plan agent itself returns.
//
// FALSIFY REGATE HOOKUP (confirmed interface alignment, #547): reverifyIds
// is a plain array of finding @id strings. research-falsify.js's `scope`
// argument accepts exactly `{ paths?: string[], ids?: string[] }` with a
// `regate: true` flag gated to require that explicit id/path scope (it
// refuses on 'all'/'dimension:*'). No adapter is needed — the orchestrator
// hookup is `research-falsify({ ..., scope: { ids: pivotResult.reverifyIds },
// regate: true })`. See the reverifyIds return below for the call-site note.
export const meta = {
  name: 'research-pivot',
  description: 'Atomic action C (pivot research focus): reshape the goal into a new content-hashed version of its append-only lineage via scripts/goal-version.sh, then classify every existing finding against the NEW goal as carry / stale / out-of-scope and plan which dimensions are gaps (gapDimensions) — so the next round re-researches only the gaps and re-gates only the stale; findings are gathered once and reused across goal versions',
  whenToUse: 'When the question itself changes — decision reframed, scope shifted, dimensions dropped/reweighted. Not for adding depth (augment) or adding an axis (add-dimensions)',
  phases: [
    { title: 'Reshape', detail: 'mint the new goal version via scripts/goal-version.sh: snapshot, delta, gv-hash, lineage', model: 'sonnet' },
    { title: 'Classify', detail: 'every finding graded carry/stale/out-of-scope vs the new goal, in parallel batches', model: 'haiku' },
    { title: 'Plan', detail: 'gap analysis: which dimensions the new goal needs that the carried corpus cannot answer', model: 'sonnet' },
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

// args: { harnessDir, topic, delta: string (what changed and why — required),
//         batchSize?: number (findings per classification batch, default 15) }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
const DELTA = A && A.delta
if (!TOPIC) throw new Error('research-pivot: args.topic is required')
if (!DELTA) throw new Error('research-pivot: args.delta is required — a pivot without a stated delta is not a pivot')
const RDIR = `${H}/reports/${TOPIC}`
const BATCH = (A && A.batchSize) || 15
if (!Number.isInteger(BATCH) || BATCH < 1) {
  throw new Error(`research-pivot: args.batchSize must be a positive integer, got ${JSON.stringify(A && A.batchSize)}`)
}

const RESHAPE_SCHEMA = {
  type: 'object',
  properties: {
    goalVersion: { type: 'string', description: 'the gv- id scripts/goal-version.sh computed over the NEW goal content, not model-narrated' },
    supersedes: { type: 'string', description: 'the OLD gv- id scripts/goal-version.sh computed over the goal content before this edit — never null, since Reshape only ever runs against an already-existing goal.json' },
    newDimensions: { type: 'array', items: { type: 'string' } },
    droppedDimensions: { type: 'array', items: { type: 'string' } },
    newChecks: { type: 'array', items: { type: 'string' } },
    goalStatement: { type: 'string' },
  },
  required: ['goalVersion', 'supersedes', 'newDimensions', 'droppedDimensions', 'newChecks', 'goalStatement'],
}
const LIST_SCHEMA = {
  type: 'object',
  properties: { findingIds: { type: 'array', items: { type: 'string' } } },
  required: ['findingIds'],
}
const CLASSIFY_SCHEMA = {
  type: 'object',
  properties: {
    classifications: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          class: { type: 'string', enum: ['carry', 'stale', 'out-of-scope'] },
          why: { type: 'string' },
        },
        required: ['id', 'class', 'why'],
      },
    },
  },
  required: ['classifications'],
}
const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    gapDimensions: { type: 'array', items: { type: 'string' } },
    reverifyIds: { type: 'array', items: { type: 'string' } },
    rationale: { type: 'string' },
  },
  required: ['gapDimensions', 'reverifyIds', 'rationale'],
}

phase('Reshape')
const reshape = await agent(
  `Reshape the session goal for topic ${TOPIC}, harness ${H}, into a NEW VERSION of its append-only lineage (SPEC §11; ADR-0006, ${H}/docs/adr/0006-content-hashed-append-only-goal-versioning.md). DELTA (what changed and why): ${DELTA}\n` +
    `${RDIR}/goal.json must already exist — pivot EVOLVES an existing goal, it does not author one fresh; if it is missing, stop and report that /goal-writer must run first.\n` +
    `The goal is immutable PER VERSION — a version's content, once minted and snapshotted, is never rewritten after the fact. That does not forbid editing the live ${RDIR}/goal.json file itself: the snapshot-then-mint idiom below IS how a new version comes to exist — snapshot the OLD content to ${RDIR}/goals/goal-$OLD.json FIRST (so it survives untouched forever), THEN rewrite ${RDIR}/goal.json in place with the delta and mint the NEW version over the result. Follow the SAME snapshot-then-mint idiom ${H}/.claude/commands/goal-writer.md's --reshape flow and ${H}/.claude/workflows/research-add-dimensions.js's Amend phase already use — compute every gv- id via the real script, never a freehand/prose-derived hash:\n` +
    `  OLD=$(bash ${H}/scripts/goal-version.sh ${RDIR}/goal.json)\n` +
    `  mkdir -p ${RDIR}/goals\n` +
    `  cp ${RDIR}/goal.json ${RDIR}/goals/goal-$OLD.json\n` +
    `  Apply the delta to ${RDIR}/goal.json: revise goal_statement/scope/dimensions/completion_condition as the delta demands — the result must still be ONE checkable end state with transcript-verifiable checks, using only config-declared dimensions (${H}/harness.config.json dimensions[]).\n` +
    `  NEW=$(bash ${H}/scripts/goal-version.sh ${RDIR}/goal.json)\n` +
    `  jq --arg n "$NEW" --arg o "$OLD" --arg d "$(date -u +%Y-%m-%d)" '.version=$n | .supersedes=$o | .revision={rationale:"<the delta>",changed:[<field list touched>],date:$d}' ${RDIR}/goal.json > tmp.$$ && mv tmp.$$ ${RDIR}/goal.json\n` +
    `  ajv validate --spec=draft2020 --strict=false -c ajv-formats -s ${H}/schemas/goal.schema.json -d ${RDIR}/goal.json\n` +
    `  supersedes is OLD — this workflow only runs against an already-existing goal.json, so OLD is always a real gv- id and supersedes is never null here.\n` +
    `Return the NEW gv- version and its supersedes (both read back from goal.json after minting — never the value you would have computed yourself), the new/dropped dimension ids, the new check ids, and the new goal_statement.`,
  { label: 'pivot:reshape', model: 'sonnet', schema: RESHAPE_SCHEMA },
)
if (!reshape) throw new Error('research-pivot: reshape failed')
log(`Goal ${reshape.supersedes} → ${reshape.goalVersion}; +[${reshape.newDimensions}] -[${reshape.droppedDimensions}]`)

phase('Classify')
const listing = await agent(
  `List the @id of every finding file under ${RDIR}/findings/ (exclude quarantine/ and archive/ siblings), harness ${H}.`,
  { label: 'pivot:list', model: 'haiku', effort: 'low', schema: LIST_SCHEMA },
)
const ids = (listing && listing.findingIds) || []
const batches = []
for (let i = 0; i < ids.length; i += BATCH) batches.push(ids.slice(i, i + BATCH))
function classifyBatch(batch, bi, isRetry) {
  return agent(
    `Classify each finding against the NEW goal version ${reshape.goalVersion} of topic ${TOPIC} (harness ${H}; read ${RDIR}/goal.json for the authoritative new goal). Findings are GATHERED ONCE AND REUSED across goal versions; classification decides reuse, it never deletes.\n` +
      `Batch: ${JSON.stringify(batch)} (read each file under ${RDIR}/findings/).\n` +
      `Classes: carry = in the new scope and its evidence still current; stale = in scope but its verification predates conditions the delta changed, or its evidence is time-sensitive and old — needs RE-GATING, not re-gathering; out-of-scope = the new scope/non_goals exclude it (it stays on disk, simply unused by this version). One row per finding with a one-clause why.`,
    { label: `pivot:classify-${bi + 1}${isRetry ? '-retry' : ''}`, phase: 'Classify', model: 'haiku', schema: CLASSIFY_SCHEMA },
  )
}
const firstPass = await parallel(batches.map((batch, bi) => () => classifyBatch(batch, bi, false)))
// #758: a batch that resolved to null (its agent() call errored, or the
// subagent died on a terminal API error — the documented parallel()
// failure shape) is retried exactly once, matching research-falsify.js's
// write-assertion retry-once idiom (#659) — never silently accepted as a
// permanent loss on the first failure.
const failedIdx = firstPass.map((c, bi) => (c ? -1 : bi)).filter((bi) => bi >= 0)
const retried = failedIdx.length ? await parallel(failedIdx.map((bi) => () => classifyBatch(batches[bi], bi, true))) : []
const resolved = firstPass.slice()
failedIdx.forEach((bi, i) => { resolved[bi] = retried[i] })
// Any batch still null after the retry has its ids captured explicitly —
// never silently merged into carry/stale/out-of-scope, and never simply
// absent from all three either (the exact #758 defect).
const unclassified = batches.filter((_, bi) => !resolved[bi]).flat()
if (unclassified.length) {
  log(`Classification: ${unclassified.length} finding id(s) could not be classified after one retry — forcing into stale/reverify rather than silently dropping: ${JSON.stringify(unclassified)}`)
}
const rows = resolved.filter(Boolean).flatMap((c) => (Array.isArray(c.classifications) ? c.classifications : []))
const carry = rows.filter((r) => r.class === 'carry').map((r) => r.id)
// Unclassified ids are folded into `stale` (never merely appended
// out-of-band) so the Plan phase's own prompt below — which is only ever
// told about `carry`/`stale` — reasons over the true, fully-accounted-for
// set rather than a view that silently omits them.
const stale = rows.filter((r) => r.class === 'stale').map((r) => r.id).concat(unclassified)
const dropped = rows.filter((r) => r.class === 'out-of-scope').map((r) => r.id)
log(`Classification: ${carry.length} carry, ${stale.length} stale (incl. ${unclassified.length} unclassified), ${dropped.length} out-of-scope (of ${ids.length})`)

phase('Plan')
const plan = await agent(
  `Gap analysis for the pivoted goal ${reshape.goalVersion} of topic ${TOPIC} (harness ${H}; read ${RDIR}/goal.json).\n` +
    `Carried finding ids (reusable evidence): ${JSON.stringify(carry)}\nStale ids (re-gate, don't re-gather): ${JSON.stringify(stale)}\n` +
    `New checks: ${JSON.stringify(reshape.newChecks)}; new dimensions: ${JSON.stringify(reshape.newDimensions)}.\n` +
    `Decide which goal dimensions the carried corpus CANNOT answer the new checks from — those are the gap dimensions the next fan-out round researches (always include the brand-new dimensions; include an existing dimension only if its carried evidence is insufficient for the new checks). reverifyIds = the stale list. State the rationale.`,
  { label: 'pivot:plan', model: 'sonnet', schema: PLAN_SCHEMA },
)

// #758: unclassified ids are unioned into reverifyIds regardless of what
// the Plan agent itself returns — the Plan phase's own prompt tells it
// `stale` already includes them, but its output must never be trusted as
// the ONLY place they can survive; a model that dropped them from its own
// reverifyIds answer must not un-do the accounting above.
const reverifyIds = Array.from(new Set(((plan && plan.reverifyIds) || stale).concat(unclassified)))

return {
  goalVersion: reshape.goalVersion,
  supersedes: reshape.supersedes,
  goalStatement: reshape.goalStatement,
  carry,
  stale,
  outOfScope: dropped,
  // #758: findings a batch failed to classify even after one retry — always
  // a subset of `stale` above, surfaced separately so a caller can tell
  // "genuinely re-gate-worthy" apart from "classification itself broke".
  unclassifiedIds: unclassified,
  gapDimensions: (plan && plan.gapDimensions) || reshape.newDimensions,
  // Feeds DIRECTLY into research-falsify's scope argument with no adapter:
  // research-falsify({ ..., scope: { ids: reverifyIds }, regate: true }).
  // research-falsify.js's scope accepts exactly { paths?, ids? } and its
  // regate:true flag is gated to require that explicit id/path scope (it
  // refuses on 'all'/'dimension:*') — reverifyIds already IS that ids[]
  // array, so the orchestrator wires it straight through.
  reverifyIds,
  rationale: plan ? plan.rationale : 'gap-plan agent failed; defaulted to new dimensions + stale list',
}
