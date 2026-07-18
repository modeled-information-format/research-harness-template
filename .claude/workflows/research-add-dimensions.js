// research-add-dimensions.js — atomic action B of the research pipeline
// (widen the dimension set).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573/#578 precedent.
//
// Vendored from the workspace engine reference (Epic #546, Task #582). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569/#573/#578 precedent).
//
// CONFIRMED DELEGATION GAP — same class as #543/#544/#545's finding, fixed
// here. The reference implementation's Amend phase instructs the sonnet
// agent to compute the gv- content-hash FREEHAND: it describes the algorithm
// in prose (sha256 first-12-hex over the goal with version/supersedes/
// revision stripped, keys sorted) rather than invoking the script this repo
// already ships for exactly that purpose. scripts/goal-version.sh has
// delegated to the canonical mif-rh-cli engine mechanism
// (`mif-rh-cli harness goal-version <goal.json>`) since the Category-B
// cutover (research-harness-template#276, Story #298) — re-deriving the hash
// from a prose description invites drift from whatever the engine actually
// implements. The fix here wires the Amend phase to the SAME snapshot-then-
// mint idiom already established and documented for goal evolution
// (.claude/commands/goal-writer.md's update flow, step 2-4; carried into
// .claude/workflows/research-goal.js's own re-authoring branch): snapshot
// the live goal to reports/<topic>/goals/goal-<OLD>.json BEFORE editing,
// apply the dimension-widening delta, then mint the new version by actually
// running `bash scripts/goal-version.sh reports/<topic>/goal.json` (twice —
// once for OLD before the edit, once for NEW after it) and stamping
// .version/.supersedes/.revision with jq — never a model-narrated hash. This
// is a deliberate deviation from the reference implementation's own
// Amend-phase text, called out here and in the PR description, not ported
// as-is.
//
// GOAL LINEAGE RULES (ADR-0006, docs/adr/0006-content-hashed-append-only-
// goal-versioning.md): the goal is immutable per version — Amend is a
// lineage event, an append, never an in-place edit. Widening the dimension
// set is exactly the kind of scope evolution ADR-0006 exists for: the prior
// version is retained (never deleted or overwritten in place) under
// reports/<topic>/goals/goal-<gv>.json, the new version's identity is a
// content hash over the post-edit goal with the lineage fields themselves
// excluded (so stamping supersedes/revision never perturbs the hash it
// describes), and supersedes must point at the prior version's real id —
// this workflow only ever runs against an already-existing goal.json (the
// Propose phase reads it as its own precondition), so OLD is always the
// gv- id scripts/goal-version.sh computes over that live content and
// supersedes is never null here. (schemas/goal.schema.json's null case is
// for the genuinely first goal a topic ever mints, before any content
// exists to hash — out of scope for an add-dimensions call, which widens
// an existing goal.)
//
// Prune-phase attack surface (overlap / scope / decision-relevance) and the
// Propose phase's homeless-evidence-leads + user-hints inputs are carried
// forward from the reference largely unchanged — a candidate surviving
// Prune must be justified as something existing dimensions genuinely cannot
// house, never merely "related but distinct."
export const meta = {
  name: 'research-add-dimensions',
  description: 'Atomic action B (add dimensions): widen the dimension set — a proposer derives candidate new dimensions from the goal, corpus leads, and user hints; a skeptic prunes them; the survivors are wired into harness.config.json and minted into a new goal version via scripts/goal-version.sh (goals are immutable per version — widening is a lineage event, never an in-place edit)',
  whenToUse: 'When coverage needs a NEW axis (not more depth on an existing one) — e.g. cross-dimension leads keep landing outside every declared dimension',
  phases: [
    { title: 'Propose', detail: 'candidate dimensions with evidence for why the current set cannot hold them', model: 'sonnet' },
    { title: 'Prune', detail: 'skeptic: overlap/scope/decision-relevance attack on each candidate', model: 'sonnet' },
    { title: 'Amend', detail: 'config patch (ajv-clean) + reshaped goal version minted via scripts/goal-version.sh (ADR-0006 lineage)', model: 'sonnet' },
  ],
}

// args: { harnessDir, topic, hints?: string[] (user-suggested dimensions or themes),
//         leads?: [{from, lead}] (research-fanout crossDimensionLeads output) }
const H = (args && args.harnessDir) || '.'
const TOPIC = args && args.topic
if (!TOPIC) throw new Error('research-add-dimensions: args.topic is required')
const RDIR = `${H}/reports/${TOPIC}`

const PROPOSE_SCHEMA = {
  type: 'object',
  properties: {
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string', description: 'lowercase [a-z][a-z0-9_-]* dimension id' },
          description: { type: 'string' },
          evidence: { type: 'string', description: 'why the CURRENT dimension set cannot hold this line of inquiry' },
          methodologyNote: { type: 'string' },
        },
        required: ['id', 'description', 'evidence', 'methodologyNote'],
      },
    },
  },
  required: ['candidates'],
}
const PRUNE_SCHEMA = {
  type: 'object',
  properties: {
    approved: { type: 'array', items: { type: 'string' } },
    rejected: {
      type: 'array',
      items: {
        type: 'object',
        properties: { id: { type: 'string' }, why: { type: 'string' } },
        required: ['id', 'why'],
      },
    },
  },
  required: ['approved', 'rejected'],
}
const AMEND_SCHEMA = {
  type: 'object',
  properties: {
    configPatched: { type: 'boolean' },
    goalVersion: { type: 'string', description: 'the gv- id scripts/goal-version.sh computed over the NEW goal content, not model-narrated' },
    supersedes: { type: 'string', description: 'the OLD gv- id scripts/goal-version.sh computed over the goal content before this edit — never null, since Amend only ever runs against an already-existing goal.json' },
    added: { type: 'array', items: { type: 'string' } },
  },
  required: ['configPatched', 'goalVersion', 'supersedes', 'added'],
}

phase('Propose')
const proposal = await agent(
  `Propose NEW research dimensions for topic ${TOPIC}, harness ${H}. Read ${RDIR}/goal.json (goal, scope, current dimensions) and ${H}/harness.config.json dimensions[] (canonical descriptions).\n` +
    ((args && args.hints && args.hints.length) ? `USER HINTS (evaluate, don't rubber-stamp): ${JSON.stringify(args.hints)}\n` : '') +
    ((args && args.leads && args.leads.length) ? `HOMELESS EVIDENCE LEADS from prior fan-outs (evidence that fit no declared dimension — the strongest signal a dimension is missing): ${JSON.stringify(args.leads)}\n` : '') +
    `A new dimension is justified ONLY when a germane line of inquiry cannot be housed by any existing dimension without distorting its methodology. Dimensions are domain-general axes of investigation, not topics or findings. Each candidate: schema-legal id ([a-z][a-z0-9_-]*), one-sentence description matching the config's dimension style, the evidence, and a methodology note (how an analyst would research it). Propose at most 4; zero is a valid answer.`,
  { label: 'add-dim:propose', model: 'sonnet', schema: PROPOSE_SCHEMA },
)
if (!proposal || !proposal.candidates.length) {
  log('No new dimensions proposed — current set holds the evidence')
  return { added: [], rejected: [], goalVersion: null }
}

phase('Prune')
const pruned = await agent(
  `Skeptic pass over proposed research dimensions for topic ${TOPIC} (harness ${H}; read ${RDIR}/goal.json and ${H}/harness.config.json for the current set). Candidates:\n${JSON.stringify(proposal.candidates, null, 1)}\n` +
    `Attack each: (1) OVERLAP — is it really a subset/restatement of an existing dimension? (2) SCOPE — does the goal's out_of_scope/non_goals exclude it? (3) DECISION-RELEVANCE — would findings on this axis change the goal's decision, or merely be interesting? Reject on any hit, with the specific reason. Approve only what survives all three.`,
  { label: 'add-dim:prune', model: 'sonnet', schema: PRUNE_SCHEMA },
)
const approved = proposal.candidates.filter((c) => pruned && pruned.approved.includes(c.id))
if (!approved.length) {
  log(`All ${proposal.candidates.length} candidate(s) rejected by the skeptic`)
  return { added: [], rejected: (pruned && pruned.rejected) || [], goalVersion: null }
}
log(`Adding dimension(s): ${approved.map((c) => c.id).join(', ')}`)

phase('Amend')
const amend = await agent(
  `Wire approved new dimensions into the harness at ${H} for topic ${TOPIC}. Approved: ${JSON.stringify(approved)}.\n` +
    `1. CONFIG: add each to ${H}/harness.config.json dimensions[] (jq; {id, description} per the existing entry shape — no methodologyNote field in the config, that is goal-authoring context only), then validate the config against ${H}/harness.config.schema.json with ajv (draft2020, ajv-formats). Do not proceed past a failing ajv run.\n` +
    `2. GOAL LINEAGE (ADR-0006, ${H}/docs/adr/0006-content-hashed-append-only-goal-versioning.md): the goal is immutable per version — never edit ${RDIR}/goal.json in place. Follow the SAME snapshot-then-mint idiom ${H}/.claude/commands/goal-writer.md's update flow and ${H}/.claude/workflows/research-goal.js's re-authoring branch already use — compute the id via the real script, never a freehand/prose-derived hash:\n` +
    `   OLD=$(bash ${H}/scripts/goal-version.sh ${RDIR}/goal.json)\n` +
    `   mkdir -p ${RDIR}/goals\n` +
    `   cp ${RDIR}/goal.json ${RDIR}/goals/goal-$OLD.json\n` +
    `   Add the new dimension ids to ${RDIR}/goal.json dimensions[] (jq), leaving goal_statement/scope/completion_condition otherwise untouched (widening is additive, not a re-author).\n` +
    `   NEW=$(bash ${H}/scripts/goal-version.sh ${RDIR}/goal.json)\n` +
    `   jq --arg n "$NEW" --arg o "$OLD" --arg d "$(date -u +%Y-%m-%d)" '.version=$n | .supersedes=$o | .revision={rationale:"widen dimension set",changed:[<added ids, one string per new dimension>],date:$d}' ${RDIR}/goal.json > tmp.$$ && mv tmp.$$ ${RDIR}/goal.json\n` +
    `   ajv validate --spec=draft2020 --strict=false -c ajv-formats -s ${H}/schemas/goal.schema.json -d ${RDIR}/goal.json\n` +
    `   supersedes is OLD — this workflow only runs against an already-existing goal.json, so OLD is always a real gv- id and supersedes is never null here.\n` +
    `Return configPatched, the NEW gv- version (read back from goal.json after minting — never the value you would have computed yourself), what it supersedes, and the added ids.`,
  { label: 'add-dim:amend', model: 'sonnet', schema: AMEND_SCHEMA },
)
if (!amend || !amend.configPatched) throw new Error('research-add-dimensions: amendment failed')

return {
  added: amend.added,
  rejected: (pruned && pruned.rejected) || [],
  goalVersion: amend.goalVersion,
  supersedes: amend.supersedes,
  // the orchestrator fans out ONLY the new dimensions next round
  fanoutPlan: { dimensions: amend.added, depth: 'standard' },
}
