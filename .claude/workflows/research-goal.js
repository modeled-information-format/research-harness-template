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

// research-harness-template#654: normalize a top-level standalone Workflow-tool
// invocation. `args` arrives as a JSON-encoded STRING when this module is
// invoked directly at the top level (confirmed empirically -- issue #617),
// but as a real in-process object when composed as a nested child via
// research-pipeline.js's wf() helper. research-pipeline.js already guards
// its own external entry point for this; every atomic module is ALSO a
// valid direct entry point (this one's own whenToUse above documents
// standalone use explicitly) and needs the identical guard -- this was
// #654's actual root cause: `args` was a JSON string, so `args.topic` (or
// any other args.* property) silently read `undefined` (a string property
// access, never a thrown error) rather than the real value, and the very
// next `if (!TOPIC) throw` line fired even though the caller's `topic`
// argument was genuinely present in the call.
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})

// args: { harnessDir, topic, ask }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
const ASK = (A && A.ask) || ''
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
  // research-harness-template#766: existingGoalSummary must be required, not
  // merely typed as string|null -- the Draft prompt below unconditionally
  // interpolates ctx.existingGoalSummary whenever ctx.existingGoalPath is
  // truthy, so a schema-valid Context result that OMITS the field (legal
  // before this fix) produced the literal text "(undefined)" in the Draft
  // agent's prompt instead of a real summary.
  required: ['topicRegistered', 'configDimensions', 'existingGoalPath', 'existingGoalSummary', 'notes'],
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
    // (research-harness-template#626) The engine path never ELICITS
    // deliverables (it cannot pause for AskUserQuestion — see the Draft
    // prompt's carve-out below); it only reports back whatever goal.json
    // actually carries after the draft/reshape write: an existing
    // deliverables block preserved verbatim on --reshape, or absent
    // (undefined) on a fresh author. Never invented, never a placeholder.
    deliverables: {
      type: 'object',
      properties: {
        genres: { type: 'array', items: { type: 'string' } },
        channels: { type: 'array', items: { type: 'string' } },
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
      ? `An existing goal exists (${ctx.existingGoalSummary || `summary unavailable -- read ${H}/reports/${TOPIC}/goal.json directly before re-authoring`}); you are re-authoring it. The goal is immutable per version (ADR-0006, content-hashed append-only lineage): follow the update flow in ${H}/.claude/commands/goal-writer.md — snapshot the live version FIRST (OLD=$(bash ${H}/scripts/goal-version.sh ${H}/reports/${TOPIC}/goal.json); mkdir -p ${H}/reports/${TOPIC}/goals; cp ${H}/reports/${TOPIC}/goal.json ${H}/reports/${TOPIC}/goals/goal-$OLD.json), then write the new content and mint its lineage (NEW=$(bash ${H}/scripts/goal-version.sh ${H}/reports/${TOPIC}/goal.json); stamp .version=$NEW, .supersedes=$OLD, and .revision {rationale, changed, date} with jq, then re-validate). Never overwrite the live goal without minting — no ad hoc goal.prior.json snapshots.`
      : 'No existing goal — author fresh.') +
    `\nProduce: (1) ${H}/reports/${TOPIC}/goal.json composed with jq and validated with ajv against ${H}/schemas/goal.schema.json (draft2020, ajv-formats); (2) the /goal prose paragraph. ` +
    `One checkable end state, not a plan of steps: goal_statement is the decision this session enables; every completion_condition.check is a transcript-verifiable fact with a printable verify where possible; dimensions[] drawn from the config-declared set. Do not proceed past a failing ajv run — fix and re-validate.\n` +
    `DELIVERABLES FIELD — PRESERVE OR LEAVE ABSENT, NEVER ELICIT (research-harness-template#626): the optional top-level \`deliverables\` field ` +
    `({genres[], channels[]}, schemas/goal.schema.json) is elicited ONLY by the interactive /goal-writer command via AskUserQuestion — this engine ` +
    `path CANNOT pause for user input and MUST NOT attempt to elicit it, invent a value, guess a default genre/channel, or ask a clarifying ` +
    `question about it anywhere in the goalProse. Do EXACTLY one of these two things, never anything else: ` +
    (ctx.existingGoalPath
      ? `an existing goal is being re-authored here, so if its live goal.json (${H}/reports/${TOPIC}/goal.json, read BEFORE you overwrite it) already carries a \`deliverables\` block, copy it into the new content VERBATIM, byte-for-byte, unchanged — never regenerate, re-elicit, or "improve" it, even if the delta text mentions genres or channels; if the live goal has no \`deliverables\` block, the new content has none either.`
      : `this is a fresh author with no prior goal.json, so simply OMIT the \`deliverables\` field entirely from the goal.json you write — do not add it with an empty object, a guessed genre, or a placeholder.`) +
    ` Return the actual resulting state (present-and-preserved or absent) in the draft result's own \`deliverables\` field so the Gate phase and the calling pipeline see the true on-disk fact, never a guess.`,
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
  // (research-harness-template#626) Whatever the Draft phase actually left
  // on disk — preserved verbatim on reshape, absent on fresh author. Never
  // set by this module itself; see the Draft prompt's carve-out above.
  deliverables: draft.deliverables,
  lintIssues: lint ? lint.issues : ['lint agent failed'],
}
