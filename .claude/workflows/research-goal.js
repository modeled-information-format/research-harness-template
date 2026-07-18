// research-goal.js — atomic step 1 of the research pipeline (goal-writing).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552.
//
// Vendored from the workspace engine reference (Epic #539). In-repo defaults:
// harnessDir defaults to the instance root '.'; re-authoring an existing goal
// routes through the ADR-0006 content-hashed append-only lineage
// (scripts/goal-version.sh, gv-* versions), never an ad hoc snapshot.
export const meta = {
  name: 'research-goal',
  description: 'Atomic step 1 (goal-writing): turn a raw research ask into a schema-valid, transcript-verifiable session goal — prompt chaining with a validation gate after every link',
  whenToUse: 'First step of the research pipeline, or standalone to author/repair reports/<topic>/goal.json in a research-harness instance',
  phases: [
    { title: 'Context', detail: 'read harness.config.json topic registry + any existing goal', model: 'haiku' },
    { title: 'Draft', detail: 'goal-engineering agent writes goal.json + /goal prose', model: 'sonnet' },
    { title: 'Gate', detail: 'ajv schema check + verifiability lint, bounded repair loop', model: 'haiku' },
  ],
}

// args: { harnessDir, topic, ask }
const H = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
const ASK = (args && args.ask) || ''
if (!TOPIC) throw new Error('research-goal: args.topic is required')

const CONTEXT_SCHEMA = {
  type: 'object',
  properties: {
    topicRegistered: { type: 'boolean' },
    configDimensions: { type: 'array', items: { type: 'string' } },
    existingGoalPath: { type: ['string', 'null'] },
    existingGoalSummary: { type: ['string', 'null'] },
    notes: { type: 'string' },
  },
  required: ['topicRegistered', 'configDimensions', 'existingGoalPath', 'notes'],
}

const DRAFT_SCHEMA = {
  type: 'object',
  properties: {
    goalFile: { type: 'string' },
    goalProse: { type: 'string', description: 'the /goal paragraph for the user' },
    dimensions: { type: 'array', items: { type: 'string' } },
    checks: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, assertion: { type: 'string' }, verify: { type: 'string' } },
        required: ['id', 'assertion'],
      },
    },
    ajvPassed: { type: 'boolean' },
  },
  required: ['goalFile', 'goalProse', 'dimensions', 'checks', 'ajvPassed'],
}

const LINT_SCHEMA = {
  type: 'object',
  properties: {
    valid: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['valid', 'issues'],
}

phase('Context')
const ctx = await agent(
  `You are inspecting a research-harness instance at ${H} (relative to cwd).\n` +
    `1. Read ${H}/harness.config.json: is topic "${TOPIC}" registered in topics[]? List the config-declared dimensions[] ids.\n` +
    `2. Check whether ${H}/reports/${TOPIC}/goal.json exists; if it does, summarize its goal_statement, dimensions, and version (gv-*) in 2 sentences.\n` +
    `Return only the structured result.`,
  { label: 'goal:context', model: 'haiku', effort: 'low', schema: CONTEXT_SCHEMA },
)
if (!ctx) throw new Error('research-goal: context agent failed')
if (!ctx.topicRegistered) {
  log(`Topic "${TOPIC}" is not registered in ${H}/harness.config.json topics[] — register it first (/configure topics).`)
  return { ok: false, reason: 'topic-not-registered', context: ctx }
}

phase('Draft')
const draft = await agent(
  `You are the goal-writer for the research harness at ${H}. Read ${H}/.claude/commands/goal-writer.md and follow it as your operating manual (SPEC §2/§6b: the goal initiates, steers, and gates the run).\n` +
    `RAW ASK: ${ASK || '(none given — derive the sharpest decision-enabling goal from the topic and existing goal context)'}\n` +
    `TOPIC: ${TOPIC}. Config dimensions available: ${JSON.stringify(ctx.configDimensions)}. ` +
    (ctx.existingGoalPath
      ? `An existing goal exists (${ctx.existingGoalSummary}); you are re-authoring it. The goal is immutable per version (ADR-0006, content-hashed append-only lineage): follow the update flow in ${H}/.claude/commands/goal-writer.md — snapshot the live version FIRST (OLD=$(bash ${H}/scripts/goal-version.sh ${H}/reports/${TOPIC}/goal.json); mkdir -p ${H}/reports/${TOPIC}/goals; cp ${H}/reports/${TOPIC}/goal.json ${H}/reports/${TOPIC}/goals/goal-$OLD.json), then write the new content and mint its lineage (NEW=$(bash ${H}/scripts/goal-version.sh ${H}/reports/${TOPIC}/goal.json); stamp .version=$NEW, .supersedes=$OLD, and .revision {rationale, changed, date} with jq, then re-validate). Never overwrite the live goal without minting — no ad hoc goal.prior.json snapshots.`
      : 'No existing goal — author fresh.') +
    `\nProduce: (1) ${H}/reports/${TOPIC}/goal.json composed with jq and validated with ajv against ${H}/schemas/goal.schema.json (draft2020, ajv-formats); (2) the /goal prose paragraph. ` +
    `One checkable end state, not a plan of steps: goal_statement is the decision this session enables; every completion_condition.check is a transcript-verifiable fact with a printable verify where possible; dimensions[] drawn from the config-declared set. Do not proceed past a failing ajv run — fix and re-validate.`,
  { label: 'goal:draft', model: 'sonnet', schema: DRAFT_SCHEMA },
)
if (!draft) throw new Error('research-goal: draft agent failed')

phase('Gate')
let lint = await agent(
  `Verifiability lint for ${draft.goalFile} in harness ${H}.\n` +
    `1. Run the deterministic gate (#554): bash ${H}/scripts/lint-goal.sh ${draft.goalFile} --config ${H}/harness.config.json — it performs the ajv schema validation (${H}/schemas/goal.schema.json) plus the step-shaped-assertion and off-config-dimension flags. Every line it reports is a lint issue; it must exit 0.\n` +
    `2. Beyond the deterministic gate, flag any completion_condition.check that is a step rather than an end-state fact, or that is not transcript-verifiable (no printable fact or verify command could prove it).\n` +
    `3. Flag any dimensions[] entry not in ${JSON.stringify(ctx.configDimensions)}.\n` +
    `Return valid=true only if lint-goal.sh exits 0 AND no check-level flags.`,
  { label: 'goal:lint', model: 'haiku', effort: 'low', schema: LINT_SCHEMA },
)
let repairs = 0
while (lint && !lint.valid && repairs < 2) {
  repairs++
  log(`Goal lint found ${lint.issues.length} issue(s) — repair round ${repairs}`)
  await agent(
    `Repair the session goal ${draft.goalFile} (harness ${H}) against these lint issues, editing with jq and re-validating with bash ${H}/scripts/lint-goal.sh ${draft.goalFile} --config ${H}/harness.config.json (ajv against ${H}/schemas/goal.schema.json plus the deterministic flags) until it exits 0:\n` +
      lint.issues.map((i) => `- ${i}`).join('\n') +
      `\nKeep the goal_statement's intent; only strengthen verifiability/schema-validity. If the goal carries ADR-0006 lineage (version/supersedes/revision), preserve it — restamp .version with ${H}/scripts/goal-version.sh only if the content changed. Return a one-line confirmation.`,
    { label: `goal:repair-${repairs}`, model: 'sonnet' },
  )
  lint = await agent(
    `Re-run the verifiability lint for ${draft.goalFile} (harness ${H}): bash ${H}/scripts/lint-goal.sh ${draft.goalFile} --config ${H}/harness.config.json (must exit 0) plus the check-level end-state/verifiability flags. Return the structured result.`,
    { label: `goal:relint-${repairs}`, model: 'haiku', effort: 'low', schema: LINT_SCHEMA },
  )
}

return {
  ok: !!(lint && lint.valid),
  goalFile: draft.goalFile,
  goalProse: draft.goalProse,
  dimensions: draft.dimensions,
  checks: draft.checks,
  lintIssues: lint ? lint.issues : ['lint agent failed'],
}
