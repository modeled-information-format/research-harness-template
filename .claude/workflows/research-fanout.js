// research-fanout.js — atomic step 2 of the research pipeline (research fan-out).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556.
//
// Vendored from the workspace engine reference (Epic #540). In-repo defaults:
// harnessDir defaults to the instance root '.' (the #552 precedent). Analyst
// briefs are self-contained — the finding contract is the FINDING_CONTRACT
// constant below, with no dependence on .claude/agents/dimension-analyst.md
// prose.
export const meta = {
  name: 'research-fanout',
  description: 'Atomic step 2 (research fan-out): parallel evidence-gathering across goal dimensions, each analyst a stateless typed worker emitting schema-valid MIF finding records; per-dimension validate/repair with no cross-dimension barrier, then one cross-corpus relation pass',
  whenToUse: 'The gather phase of a research round — the whole goal dimension set, or an explicit subset for augment/update/pivot-gap rounds',
  phases: [
    { title: 'Plan', detail: 'resolve dimension set + researcher brief from the goal', model: 'haiku' },
    { title: 'Research', detail: 'parallel analysts, per-dimension validate + repair pipeline', model: 'sonnet' },
    { title: 'Relate', detail: 'cross-dimension duplicate/relation annotation over new findings', model: 'sonnet' },
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

// args: { harnessDir, topic, dimensions?: string[] (subset), depth?: 'standard'|'deep',
//         roundContext?: string (what earlier rounds already covered / which checks are unmet) }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
const DEPTH = (A && A.depth) || 'standard'
if (!TOPIC) throw new Error('research-fanout: args.topic is required')
const RDIR = `${H}/reports/${TOPIC}`

const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    dimensions: { type: 'array', items: { type: 'string' } },
    goalStatement: { type: 'string' },
    scopeBrief: { type: 'string', description: '2-3 sentence researcher brief: in/out of scope, non-goals' },
  },
  required: ['dimensions', 'goalStatement', 'scopeBrief'],
}
const RESEARCH_SCHEMA = {
  type: 'object',
  properties: {
    dimension: { type: 'string' },
    findingPaths: { type: 'array', items: { type: 'string' } },
    searchesRun: { type: 'integer' },
    saturationNote: { type: 'string' },
    crossDimensionLeads: {
      type: 'array',
      items: { type: 'string' },
      description: 'germane evidence encountered that belongs to ANOTHER dimension or none — fed to coverage-audit, never silently dropped',
    },
  },
  required: ['dimension', 'findingPaths', 'searchesRun', 'saturationNote', 'crossDimensionLeads'],
}
const VALIDATE_SCHEMA = {
  type: 'object',
  properties: {
    validPaths: { type: 'array', items: { type: 'string' } },
    invalid: {
      type: 'array',
      items: {
        type: 'object',
        properties: { path: { type: 'string' }, error: { type: 'string' } },
        required: ['path', 'error'],
      },
    },
  },
  required: ['validPaths', 'invalid'],
}
const RELATE_SCHEMA = {
  type: 'object',
  properties: {
    related: { type: 'integer' },
    annotations: { type: 'array', items: { type: 'string' } },
  },
  required: ['related', 'annotations'],
}

// The finding contract, stated once and embedded in every worker brief. This is the durable
// substrate (schemas/, ADR-0002) — the retired part of the old engine is its coordination
// style (agent .md manuals, filesystem hand-offs, prompt-enforced bounds), not the contract.
const FINDING_CONTRACT =
  `Each finding is ONE MIF concept object with its own @id — never an array envelope or a ` +
  `{dimension, findings:[...]} wrapper — written as an individual JSON file under ${RDIR}/findings/. ` +
  `It carries: extensions.harness.dimension (the pin for this dimension), citations to sources you ACTUALLY retrieved ` +
  `(never fabricated, never from training data alone), and provenance. Compose with jq; validate immediately with ` +
  `ajv (draft2020, ajv-formats) against ${H}/schemas/findings.schema.json registering the vendored ${H}/schemas/mif/ closure. ` +
  `A write is not done until it validates. If the mif-rh MCP find_similar tool is available, check each candidate claim ` +
  `against it first and RELATE to (or cite) a close existing finding instead of duplicating it; if the tool is absent, skip silently.`

phase('Plan')
const plan = await agent(
  `Read ${RDIR}/goal.json in the research-harness instance at ${H}. Return dimensions[], goalStatement, and scopeBrief (a 2-3 sentence researcher brief from scope.in_scope/out_of_scope/non_goals).` +
    ((A && A.dimensions && A.dimensions.length)
      ? ` Then restrict the returned dimensions to this requested subset, noting in scopeBrief any requested id absent from the goal: ${JSON.stringify(A.dimensions)}.`
      : ''),
  { label: 'fanout:plan', model: 'haiku', effort: 'low', schema: PLAN_SCHEMA },
)
if (!plan || !plan.dimensions.length) throw new Error('research-fanout: no dimensions resolved from goal')
log(`Fanning out ${plan.dimensions.length} dimension(s): ${plan.dimensions.join(', ')} (depth: ${DEPTH})`)

phase('Research')
const perDimension = await pipeline(
  plan.dimensions,
  (d) =>
    agent(
      `You are a research analyst for exactly ONE dimension of a goal-driven research session.\n` +
        `DIMENSION=${d}  TOPIC=${TOPIC}  REPORTS_DIR=${RDIR} (use exactly as given for every write — never re-derive or re-slugify).\n` +
        `GOAL: ${plan.goalStatement}\nSCOPE: ${plan.scopeBrief}\n` +
        ((A && A.roundContext) ? `PRIOR ROUNDS: ${A.roundContext}\n` : '') +
        `METHOD — real web research only (WebSearch/WebFetch): ` +
        (DEPTH === 'deep'
          ? `research to saturation. Systematically enumerate the dimension's sub-areas (standards bodies, prior-art vocabularies, taxonomies, authorities, sub-industries) and keep searching until new searches surface nothing new and germane — a broad dimension needs many dozens of searches; stopping after a handful is under-research, not efficiency.`
          : `cover the dimension's principal sub-areas; stop when marginal searches stop adding germane evidence.`) +
        ` If WebSearch is unavailable, report the limitation in saturationNote — never substitute fabricated findings.\n` +
        `CONTRACT — ${FINDING_CONTRACT}\n` +
        `Also collect crossDimensionLeads: germane evidence you encountered that belongs to a DIFFERENT dimension (or none) — record the lead, do not write a finding outside your pin.`,
      { label: `research:${d}`, phase: 'Research', model: 'sonnet', schema: RESEARCH_SCHEMA },
    ),
  (r, d) =>
    r
      ? agent(
          `Validate each finding file with ajv (draft2020, ajv-formats) against ${H}/schemas/findings.schema.json registering the vendored ${H}/schemas/mif/ schemas: ${JSON.stringify(r.findingPaths)}. ` +
            `Additionally mark invalid: extensions.harness.dimension != "${d}", empty citations, or a citation whose URL was clearly never retrieved (no retrieval metadata). Return validPaths + invalid[{path,error}].`,
          { label: `validate:${d}`, phase: 'Research', model: 'haiku', effort: 'low', schema: VALIDATE_SCHEMA },
        ).then((v) => ({ dimension: d, research: r, validation: v }))
      : null,
  (v, d) => {
    if (!v || !v.validation || !v.validation.invalid.length) return v ? { ...v, repaired: 0 } : v
    // research-harness-template#623: the count of findings that arrived
    // schema-invalid or citation-defective BEFORE this repair pass ran —
    // the defect-rate signal a completion check grading only the
    // post-repair corpus state would otherwise never see. Captured here,
    // before the repair mutates anything, and carried through unchanged.
    const repairedCount = v.validation.invalid.length
    const invalidPaths = v.validation.invalid.map((i) => i.path)
    return agent(
      `Repair these schema-invalid MIF finding files so each validates against ${H}/schemas/findings.schema.json (jq edits, re-run ajv until clean). Fix structure, citation objects, and the extensions.harness.dimension="${d}" pin ONLY — never delete a finding or weaken its claim to make validation pass:\n` +
        v.validation.invalid.map((i) => `- ${i.path}: ${i.error}`).join('\n'),
      { label: `repair:${d}`, phase: 'Research', model: 'sonnet' },
    )
      .then(() =>
        // Re-validate the repaired files — a repair is not done until it proves out
        // against the same checks that failed it (write-validate atomicity, fail-closed).
        agent(
          `Validate each finding file with ajv (draft2020, ajv-formats) against ${H}/schemas/findings.schema.json registering the vendored ${H}/schemas/mif/ schemas: ${JSON.stringify(invalidPaths)}. ` +
            `Additionally mark invalid: extensions.harness.dimension != "${d}", empty citations, or a citation whose URL was clearly never retrieved (no retrieval metadata). Return validPaths + invalid[{path,error}].`,
          { label: `revalidate:${d}`, phase: 'Research', model: 'haiku', effort: 'low', schema: VALIDATE_SCHEMA },
        ),
      )
      .then((rv) => {
        if (rv.invalid.length)
          throw new Error(
            `research-fanout: ${d}: ${rv.invalid.length} finding(s) still schema-invalid after repair: ` +
              rv.invalid.map((i) => `${i.path} (${i.error})`).join('; '),
          )
        return {
          dimension: d,
          research: v.research,
          validation: { validPaths: v.validation.validPaths.concat(rv.validPaths), invalid: [] },
          repaired: repairedCount,
        }
      })
  },
)

const results = perDimension.filter(Boolean)
const allPaths = results.flatMap((r) => (r.validation ? r.validation.validPaths : r.research.findingPaths))
const leads = results.flatMap((r) => r.research.crossDimensionLeads.map((l) => ({ from: r.dimension, lead: l })))

phase('Relate')
let relate = null
if (allPaths.length > 1) {
  relate = await agent(
    `Cross-dimension relation pass, topic ${TOPIC}, harness ${H}. Compare the core claims of these new finding files: ${JSON.stringify(allPaths)} (use mif-rh find_similar per claim if available, else direct comparison). ` +
      `Where two findings assert substantially the same claim, annotate the newer with a typed MIF relationship to the older (relates-to/duplicates semantics) — never delete either — keeping every touched file ajv-valid against ${H}/schemas/findings.schema.json. Return the count and one line per annotation.`,
    { label: 'fanout:relate', model: 'sonnet', schema: RELATE_SCHEMA },
  )
}

return {
  dimensions: plan.dimensions,
  findings: allPaths,
  perDimension: results.map((r) => ({
    dimension: r.dimension,
    written: r.research.findingPaths.length,
    valid: r.validation ? r.validation.validPaths.length : null,
    // research-harness-template#623: how many of this lane's findings
    // arrived schema-invalid/citation-defective and needed the repair
    // pass before they validated — 0 when the lane's findings were clean
    // on first write.
    repaired: r.repaired || 0,
    searches: r.research.searchesRun,
    saturation: r.research.saturationNote,
  })),
  crossDimensionLeads: leads,
  related: relate ? relate.related : 0,
  // research-harness-template#623: total findings this round that only
  // validate now because they were repaired — the defect-rate signal
  // research-pipeline.js's independent completion check must be told
  // about before it grades finding_valid/citation_integrity against the
  // (post-repair) corpus state, rather than silently trusting that state
  // as if it were always clean.
  repaired: results.reduce((sum, r) => sum + (r.repaired || 0), 0),
}
