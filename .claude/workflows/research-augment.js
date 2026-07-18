// research-augment.js — atomic action A of the research pipeline (augment).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573 precedent.
//
// Vendored from the workspace engine reference (Epic #545, Task #578). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the established
// precedent from research-goal.js/research-fanout.js/research-falsify.js/
// research-synthesis.js/research-projection.js/research-deliverables.js).
// This module is a pure DECIDE workflow — Assess computes, Decide judges —
// with no live-orchestrator-context dependency: the reference's optional
// checkCoverage/focusHint args are honored when supplied, but the module is
// confirmed safe to run standalone (the orchestrator, #550, is not yet
// vendored). An empty deepening plan with stated reasoning is a valid,
// non-error outcome, never surfaced as a failure.
//
// CONFIRMED DELEGATION GAP — same class as #543/#544's finding, fixed here.
// The reference research-augment.js's Assess phase re-derives the
// per-dimension coverage/verdict matrix via a free-form haiku prompt reading
// raw finding files, even though this repo's own `discover` skill
// (.claude/skills/discover/SKILL.md) already computes exactly this
// deterministically: `jq group_by(.dimension)` over research-index.json
// (the coverage-gaps pipeline) plus a verdict `select()` filter (the
// stale-findings pipeline) — read verbatim from that SKILL.md, not guessed.
// The fix here composes those two documented idioms into ONE jq pipeline
// that groups by dimension AND breaks each group out by research-index.json's
// top-level `.verdict` field (survived/weakened/falsified/inconclusive, plus a
// null-verdict "ungated" bucket) — the exact same
// data source (research-index.json) and the exact same grouping/filtering
// primitives discover already uses, never a free-form re-count over raw
// finding files. The ONE piece the index cannot supply (it carries no
// timestamp — discover's own README says as much for its age-based staleness
// signal) is oldestFindingDate; that is genuinely incremental logic layered
// on top, read from the raw finding files' `created` +
// `extensions.harness.dimension` fields, exactly as discover's own
// age-based staleness pipeline does. The Assess prompt below names both jq
// pipelines explicitly so the model runs the deterministic computation
// rather than reimplementing it from a description.
//
// Decide-phase priority (unmet-check-impact > attrition > thinness >
// staleness) is carried forward unchanged from the reference; attrition is a
// distinct sourcing-strategy signal, never folded into thinness.
//
// SUPERSESSION NOTE: vs. the orchestrator's (#550, not yet vendored)
// `augment` mode flag — this module decides, it gathers nothing. The
// orchestrator, once vendored, is what feeds this module's `deepen[]` plan
// to research-fanout (for the gathering) and research-falsify (for the
// gate); this module never calls either directly.
export const meta = {
  name: 'research-augment',
  description: 'Atomic action A (augment): evidence-driven deepening decision — compute the per-dimension coverage/verdict matrix (delegated to the discover skill\'s jq pipelines for the count/verdict portion), then have a judgment agent pick which dimensions to deepen and why; emits a typed deepening plan the orchestrator feeds to research-fanout + research-falsify',
  whenToUse: 'When the corpus needs MORE depth on what the goal already covers — thin dimensions, checks graded partially, high falsification attrition. Decides; does not itself gather',
  phases: [
    { title: 'Assess', detail: 'coverage matrix: findings × verdicts × age per dimension — count/verdict portion delegated to the discover skill\'s jq pipelines over research-index.json; oldestFindingDate/ungated/goal-check extraction layered on top', model: 'haiku' },
    { title: 'Decide', detail: 'judgment agent picks dimensions + depth with stated reasoning and rejected alternatives', model: 'sonnet' },
  ],
}

// args: { harnessDir, topic, focusHint?: string (user steer, e.g. a dimension or unmet check ids),
//         checkCoverage?: [] (research-synthesis perCheck output, if a round just ran) }
const HDIR = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
if (!TOPIC) throw new Error('research-augment: args.topic is required')
const RDIR = `${HDIR}/reports/${TOPIC}`

const MATRIX_SCHEMA = {
  type: 'object',
  properties: {
    dimensions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          dimension: { type: 'string' },
          findings: { type: 'integer' },
          survived: { type: 'integer' },
          weakened: { type: 'integer' },
          falsified: { type: 'integer' },
          inconclusive: { type: 'integer' },
          ungated: { type: 'integer' },
          oldestFindingDate: { type: ['string', 'null'] },
        },
        required: ['dimension', 'findings', 'survived', 'weakened', 'falsified', 'inconclusive', 'ungated', 'oldestFindingDate'],
      },
    },
    goalStatement: { type: 'string' },
    checks: { type: 'array', items: { type: 'object', properties: { id: { type: 'string' }, assertion: { type: 'string' } }, required: ['id', 'assertion'] } },
  },
  required: ['dimensions', 'goalStatement', 'checks'],
}
const DECISION_SCHEMA = {
  type: 'object',
  properties: {
    deepen: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          dimension: { type: 'string' },
          depth: { type: 'string', enum: ['standard', 'deep'] },
          rationale: { type: 'string' },
          targetChecks: { type: 'array', items: { type: 'string' } },
        },
        required: ['dimension', 'depth', 'rationale', 'targetChecks'],
      },
    },
    rejected: {
      type: 'array',
      items: {
        type: 'object',
        properties: { dimension: { type: 'string' }, why: { type: 'string' } },
        required: ['dimension', 'why'],
      },
    },
    reasoning: { type: 'string' },
  },
  required: ['deepen', 'rejected', 'reasoning'],
}

phase('Assess')
const matrix = await agent(
  `Compute the coverage matrix for topic ${TOPIC}, harness ${HDIR} — DELEGATE the count/verdict portion to the same deterministic jq ` +
    `pipelines the harness's own discover skill (.claude/skills/discover/SKILL.md) already uses over the SAME data source ` +
    `(research-index.json); never re-derive these counts by reading and eyeballing raw finding files.\n` +
    `1. COUNT/VERDICT MATRIX (discover-delegated — its coverage-gaps pipeline groups by dimension, its stale-findings pipeline ` +
    `filters by verdict; compose both into one pipeline over the same index):\n` +
    `   jq -n --slurpfile goal ${RDIR}/goal.json --slurpfile idx ${RDIR}/research-index.json '\n` +
    `     ($idx[0].findings | group_by(.dimension) | map({\n` +
    `       dimension: .[0].dimension, findings: length,\n` +
    `       survived: ([.[] | select(.verdict==\"survived\")] | length),\n` +
    `       weakened: ([.[] | select(.verdict==\"weakened\")] | length),\n` +
    `       falsified: ([.[] | select(.verdict==\"falsified\")] | length),\n` +
    `       inconclusive: ([.[] | select(.verdict==\"inconclusive\")] | length),\n` +
    `       ungated: ([.[] | select(.verdict==null)] | length)\n` +
    `     })) as $byDim\n` +
    `     | $goal[0].dimensions | map(. as $d | (($byDim | map(select(.dimension==$d)) | first)\n` +
    `       // {dimension: $d, findings:0, survived:0, weakened:0, falsified:0, inconclusive:0, ungated:0}))'\n` +
    `   Run this exactly (adjust only for jq availability); it reads goal.json's OWN dimensions[] (the topic-scoped subset), not ` +
    `the corpus-wide harness.config.json taxonomy discover itself reads (discover audits the whole corpus; this module is ` +
    `scoped to one topic).\n` +
    `2. OLDEST-FINDING-DATE (incremental — research-index.json carries no timestamp, exactly as discover's own README notes for ` +
    `its age-based staleness signal, so this reads the raw finding files instead, grouped the same way):\n` +
    `   jq -s '[.[] | {dimension: .extensions.harness.dimension, created}] | group_by(.dimension)\n` +
    `     | map({dimension: .[0].dimension, oldestFindingDate: (map(.created) | sort | first)})' ${RDIR}/findings/*.json\n` +
    `   Merge each dimension's oldestFindingDate (null if the dimension has zero findings) into the matrix from step 1 by ` +
    `dimension id.\n` +
    `3. Also read ${RDIR}/goal.json's goal_statement and completion_condition.checks (id + assertion) verbatim — do not ` +
    `paraphrase or invent checks.\n` +
    `Pure computation — no judgment. Return the merged per-dimension matrix, goalStatement, and checks.`,
  { label: 'augment:assess', model: 'haiku', effort: 'low', schema: MATRIX_SCHEMA },
)
if (!matrix) throw new Error('research-augment: coverage assessment failed')

phase('Decide')
const decision = await agent(
  `You are the augmentation judge for a research corpus. Decide which dimensions to DEEPEN — with stated reasoning and rejected alternatives, never a silent default.\n` +
    `GOAL: ${matrix.goalStatement}\nCHECKS: ${JSON.stringify(matrix.checks)}\n` +
    `COVERAGE MATRIX: ${JSON.stringify(matrix.dimensions)}\n` +
    ((args && args.checkCoverage) ? `LATEST SYNTHESIS CHECK GRADES: ${JSON.stringify(args.checkCoverage)}\n` : '') +
    ((args && args.focusHint) ? `USER STEER (honor unless it contradicts the evidence, and say so if it does): ${args.focusHint}\n` : '') +
    `Deepening signals, in priority order: a check graded no/partially whose evidence would come from a dimension; high attrition (falsified+weakened dominating survived — the dimension's sourcing strategy needs a different angle, note that in its rationale); thin absolute coverage; staleness. A dimension already saturated with survivors is a REJECT (diminishing returns). Choose at most 3; each entry names the checks it targets. If NOTHING warrants deepening, return an empty deepen[] and say why — that is a valid outcome, not a failure.`,
  { label: 'augment:decide', model: 'sonnet', schema: DECISION_SCHEMA },
)
if (!decision) throw new Error('research-augment: decision failed')
log(decision.deepen.length
  ? `Deepening plan: ${decision.deepen.map((d) => `${d.dimension}(${d.depth})`).join(', ')}`
  : `No deepening warranted: ${decision.reasoning.slice(0, 200)}`)

return {
  deepen: decision.deepen,
  rejected: decision.rejected,
  reasoning: decision.reasoning,
  matrix: matrix.dimensions,
}
