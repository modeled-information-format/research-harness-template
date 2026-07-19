export const meta = {
  name: 'research',
  description: 'Deterministic Workflow-tool orchestration for full-, augment-, and update-mode research sessions (parallel path to the orchestrator subagent, ADR-0020; issues #19, #20, #21)',
  phases: [
    { title: 'Prepare' },
    { title: 'Research' },
    { title: 'Gate & Remediate' },
    { title: 'Type' },
    { title: 'Check' },
    { title: 'Synthesize' },
    { title: 'Render' },
    { title: 'Project' },
    { title: 'Finalize' },
  ],
}

// ---------------------------------------------------------------------------
// args guard -- confirmed empirically (research-workflow-spike, 2026-07-17):
// this runtime delivers `args` as a JSON-encoded STRING, not a parsed object,
// even when passed as a real JSON value in the Workflow tool call. Guard here
// or every args.<field> access silently becomes "undefined" with no error.
// ---------------------------------------------------------------------------
const A = typeof args === 'string' ? JSON.parse(args) : (args || {})

if (!A.topic || !A.goalFile || !A.runDate) {
  throw new Error('research.js requires args.topic, args.goalFile, and args.runDate (ISO date -- Date.now() is unavailable in the workflow sandbox)')
}

const TOPIC = A.topic
const GOAL_FILE = A.goalFile
const REPORTS_DIR = `reports/${TOPIC}`

// Mode (issues #19, #20): mirrors the orchestrator subagent's MODE input
// (orchestrator.md "## Modes"). `full` (default) fans out every goal
// dimension from round 1, unchanged. `augment` deepens a single named
// dimension -- or, when none is named, every goal dimension -- with
// additional findings, UNCONDITIONALLY: it never second-guesses which
// dimensions "need" it (start.md's documented augment framing) and never
// gates/re-verifies findings that already carry a verdict (the one-round
// rule, enforced downstream by the existing "ungated findings only" gate-list
// query in Phase 2 -- unchanged by this mode). `update` is membership-aware
// (SPEC §11): it reuses in-scope, still-fresh findings as-is and only fans
// out gap dimensions / re-verifies stale ones (Phase 0b below).
//
// NOTE (research-harness#21 forensic fix): this used to be TWO separate
// top-level `const MODE` declarations -- one from #20's augment-mode work
// (SUPPORTED_MODES limited to ['full', 'augment']) and one from #19's
// update-mode work (`A.mode === 'update' ? 'update' : 'full'`) -- left over
// from a merge that never reconciled them. A duplicate top-level `const`
// binding is a hard SyntaxError under this repo's `"type": "module"`
// package.json, so research.js could not even be loaded by the Workflow
// runtime in ANY mode (full included) until this was fixed. The static
// evals (workflow-research-parses.sh) missed it because their `node --check`
// runs the file copied into a bare mktemp dir with no package.json in its
// ancestry, so Node's module-type auto-detection silently skips the ESM
// duplicate-binding early-error check it performs when the real package.json
// (`"type": "module"`) is in scope -- confirmed empirically, not a
// hypothetical. Consolidated into the single resolution below.
const MODE = A.mode || 'full'
const DIMENSION = A.dimension || null
const SUPPORTED_MODES = ['full', 'augment', 'update']
if (!SUPPORTED_MODES.includes(MODE)) {
  throw new Error(`research.js mode "${MODE}" is not supported -- only ${JSON.stringify(SUPPORTED_MODES)} are implemented`)
}
// A named dimension only means something in augment mode; accepting it
// silently under full/update mode (which resolve their own dimension scope)
// is a footgun for a caller who passes dimension but forgets mode -- reject
// it outright instead of quietly ignoring it.
if (DIMENSION && MODE !== 'augment') {
  throw new Error(`research.js args.dimension is only valid when args.mode is "augment" (got mode="${MODE}", dimension="${DIMENSION}") -- pass mode:"augment" or omit dimension`)
}
const GENRES_REQUESTED = Array.isArray(A.genres) ? A.genres : []
// Default is both -- report is mandatory regardless, and blog should still be
// auto-included whenever harness.config.json's outputs[] enables it unless the
// caller explicitly narrows channels to exclude it.
const CHANNELS = Array.isArray(A.channels) && A.channels.length ? A.channels : ['report', 'blog']
const QUERY_BUDGET = A.queryBudget || 6
const CLAIM_BUDGET = A.claimBudget || 50
const BATCH = A.batch || 12
const RUN_DATE = A.runDate

// A single shared clause, interpolated into every phase whose agent shells
// out to an engine-delegating script (mif-rh-cli-backed; exit 5 = missing/stale).
const ENGINE_FAILURE_CLAUSE = `If any script invocation in these steps exits with code 5 (engine missing or stale), stop immediately, do not retry, and return {"status":"toolchain_broken","script":"<script-name-that-failed>"} instead of your normal fields.`

// Discovered empirically (workflow-dryrun-spike, 2026-07-17): schema-return
// pressure can crowd out an agent's own documented file-writing side effects
// (falsification-analyst's first run skipped its Step 8 report file entirely
// and substituted a prose summary in the schema's "report" field instead).
// Repeat this reminder on every agentType call whose standing instructions
// include a file write, not just the one phase where it was first caught.
const SIDE_EFFECT_CLAUSE = `The schema you return is IN ADDITION to every file your standing instructions have you write, never a substitute for writing it. Complete every documented step, including all file writes, before composing your schema return.`

// Augment mode only (issue #20) -- interpolated into every dimension-analyst
// spawn prompt so the analyst knows a prior pass on this dimension already
// happened (mirrors the orchestrator's --augment framing, start.md's "the
// harness does not second-guess which dimensions need it"). Without this the
// analyst has no way to distinguish an augment pass from a fresh full-mode
// one and will tend to re-surface findings that already exist on disk instead
// of pushing into genuinely unanswered ground.
const AUGMENT_CLAUSE = `This is an AUGMENT pass, not a first pass: at least one prior research round already ran on this dimension, and existing findings for it may already be on disk under ${REPORTS_DIR}/findings/. Read what already exists for this dimension before researching further, and target genuinely unanswered ground within the dimension's scope -- do not re-emit a finding that duplicates one already captured. Deepen coverage; do not restart it.`

// Discovered empirically (workflow-dryrun-spike, 2026-07-17): an agent hit
// build-topic-readme.sh's "topic not registered in harness.config.json" exit
// 2 and, unprompted, "fixed" it by registering the topic itself -- silently
// mutating a real tracked config file (and rewriting unrelated parts of it
// in the process) to make a downstream check pass. Registering the topic is
// the front door command's job (.claude/commands/research.md), done once,
// deliberately, before the workflow ever runs -- never an incidental side
// effect of a check failing deep in a later phase.
const NO_CONFIG_MUTATION_CLAUSE = `Never write to harness.config.json for any reason, under any circumstances. If build-topic-readme.sh (or anything else) fails because this topic isn't registered there, that is expected and acceptable here -- note it in your return and move on; do not "fix" it by registering the topic yourself.`

const LOCK_REFRESH = `Before anything else, run: bash scripts/run-lock.sh refresh "${REPORTS_DIR}"\n`

// ---------------------------------------------------------------------------
// schemas
// ---------------------------------------------------------------------------

const PREP_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { type: 'string', enum: ['ready', 'blocked'] },
    reason: { type: 'string' },
    dimensions: { type: 'array', items: { type: 'string' } },
    maxRounds: { type: 'integer' },
    minDimensionsComplete: { type: 'integer' },
    checks: { type: 'array', items: { type: 'object' } },
    preIds: { type: 'array', items: { type: 'string' } },
    gv: { type: 'string' },
  },
}

// Matches dimension-analyst.md's actual Step 7 return contract verbatim --
// finding_files (filenames, not @ids) and unresolved_gaps are real fields;
// there is no finding_ids field.
const RESEARCH_SCHEMA = {
  type: 'object',
  required: ['dimension', 'topic', 'methodology', 'finding_files', 'finding_count', 'collisions', 'oversized_sources', 'unresolved_gaps'],
  properties: {
    dimension: { type: 'string' },
    topic: { type: 'string' },
    methodology: { type: 'string' },
    finding_files: { type: 'array', items: { type: 'string' } },
    finding_count: { type: 'integer' },
    collisions: { type: 'array', items: { type: 'string' } },
    oversized_sources: { type: 'array', items: { type: 'string' } },
    unresolved_gaps: { type: 'array', items: { type: 'string' } },
    status: { type: 'string' },
  },
}

// Update-mode membership-aware gap resolution (SPEC §11), mirroring the
// orchestrator's --update behavior (research-harness#19) PLUS a tag-aware
// gap check the orchestrator itself lacks: scripts/resolve-membership.sh's
// gap_dimensions[] is dimension-level only -- a dimension with ANY in-scope
// finding reads as fully covered even when a goal reshape adds brand-new
// completion_condition.checks[] tagged sub-questions that dimension has zero
// findings for yet. Discovered in production (backstage-catalog-data-quality,
// 2026-07-17): 3/3 dimensions had baseline coverage, so gap_dimensions came
// back empty despite 7 genuinely new unanswered tagged sub-questions.
const UPDATE_MEMBERSHIP_SCHEMA = {
  oneOf: [
    {
      type: 'object',
      required: ['gapDimensions', 'staleIds', 'tagGapDimensions', 'tagGapTags'],
      properties: {
        gapDimensions: { type: 'array', items: { type: 'string' } },
        staleIds: { type: 'array', items: { type: 'string' } },
        tagGapDimensions: { type: 'array', items: { type: 'string' } },
        tagGapTags: { type: 'array', items: { type: 'string' } },
      },
    },
    {
      // ENGINE_FAILURE_CLAUSE's fail-closed shape (exit code 5) -- without
      // this arm, an engine-missing/stale path fails schema validation
      // instead of being handled cleanly by the toolchain_broken branch below.
      type: 'object',
      required: ['status', 'script'],
      properties: {
        status: { type: 'string', enum: ['toolchain_broken'] },
        script: { type: 'string' },
      },
    },
  ],
}

const CHUNK_SCHEMA = {
  type: 'object',
  properties: {
    finding_files: { type: 'array', items: { type: 'string' } },
    source_metadata: { type: 'object' },
    processing_notes: { type: 'object' },
    status: { type: 'string' },
  },
}

const RECOUNT_SCHEMA = {
  type: 'object',
  required: ['dimension', 'onDiskCount'],
  properties: {
    dimension: { type: 'string' },
    onDiskCount: { type: 'integer' },
  },
}

const GATE_LIST_SCHEMA = {
  type: 'object',
  required: ['count', 'batchFile'],
  properties: {
    count: { type: 'integer' },
    batchFile: { type: 'string' },
    status: { type: 'string' },
  },
}

const GATE_RESULT_SCHEMA = {
  type: 'object',
  required: ['report'],
  properties: {
    status: { type: 'string' },
    report: { type: 'string', description: 'Filesystem path to the {date}-falsification-report.md file you wrote in Step 8 -- a real path, never a prose summary.' },
    verdicts: {
      type: 'object',
      properties: {
        falsified: { type: 'integer' },
        weakened: { type: 'integer' },
        survived: { type: 'integer' },
        inconclusive: { type: 'integer' },
      },
    },
    quarantined: { type: 'integer' },
    downgraded: { type: 'integer' },
  },
}

const TYPE_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { type: 'string', enum: ['ok', 'blocked', 'toolchain_broken'] },
    reason: { type: 'string' },
    enriched: { type: 'integer' },
  },
}

const CHECK_SCHEMA = {
  type: 'object',
  required: ['status'],
  properties: {
    status: { type: 'string' },
    passed: { type: 'array', items: { type: 'string' } },
    unmet: { type: 'array', items: { type: 'string' } },
    thinDimensions: { type: 'array', items: { type: 'string' } },
  },
}

const GENRE_FILTER_SCHEMA = {
  type: 'object',
  properties: {
    enabled: { type: 'array', items: { type: 'string' } },
    skipped: { type: 'array', items: { type: 'string' } },
    blogEnabled: { type: 'boolean' },
  },
}

// Matches report-synthesizer.md's actual Step 6 return contract verbatim.
const RENDER_SCHEMA = {
  type: 'object',
  required: ['topic', 'genre', 'synthesis_file', 'surviving_findings', 'excluded_falsified', 'provenance_warnings'],
  properties: {
    topic: { type: 'string' },
    genre: { type: 'string' },
    synthesis_file: { type: 'string' },
    surviving_findings: { type: 'integer' },
    excluded_falsified: { type: 'integer' },
    provenance_warnings: { type: 'array', items: { type: 'string' } },
    status: { type: 'string' },
  },
}

const PROJECT_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string' },
    nodes: { type: 'integer' },
    edges: { type: 'integer' },
  },
}

const FINALIZE_SCHEMA = {
  type: 'object',
  properties: {
    status: { type: 'string' },
    readmeOk: { type: 'boolean' },
  },
}

// ---------------------------------------------------------------------------
// Phase 0 -- Prepare
// ---------------------------------------------------------------------------

phase('Prepare')
log(`Preparing research workflow for topic "${TOPIC}"`)

const prep = await agent(
  `Run these steps in order against the repo root, then return exactly the JSON fields described:

1. Resolve the mif-rh-cli engine: run \`bash -c 'source scripts/lib/engine.sh && engine_bin "$(pwd)" >/dev/null'\` (engine_bin takes the repo root as its one argument -- do not call it with no argument). If that fails, return {"status":"blocked","reason":"engine_missing"} immediately and do nothing else.
2. Validate the goal: \`ajv validate --spec=draft2020 --strict=false -c ajv-formats -s schemas/goal.schema.json -d "${GOAL_FILE}"\`. Non-zero exit -> return {"status":"blocked","reason":"goal_invalid"}.
3. Acquire the run lock: \`bash scripts/run-lock.sh acquire "${REPORTS_DIR}" "research-workflow"\`. Exit 3 means a live run already owns it -- return {"status":"blocked","reason":"lock_held"} and do NOT proceed to later steps (never steal the lock).
4. Read from the goal file with jq: \`.dimensions[]\` (array of strings), \`.bound.max_rounds // 3\`, \`.bound.min_dimensions_complete // 1\`, \`.completion_condition.checks\` (array).
5. Snapshot existing finding @ids: \`jq -r '."@id"' ${REPORTS_DIR}/findings/*.json 2>/dev/null\` (empty/missing dir is fine, treat as no pre-existing findings).
6. Compute the goal version: \`bash scripts/goal-version.sh "${GOAL_FILE}"\`.
7. Append a session-init line to \`${REPORTS_DIR}/research-progress.md\` (create the file with an H1 if it doesn't exist yet; otherwise append-only, never overwrite): a line noting a workflow-driven run started at ${RUN_DATE}.

Return {"status":"ready","dimensions":[...],"maxRounds":N,"minDimensionsComplete":N,"checks":[...],"preIds":[...],"gv":"gv-..."}.

${ENGINE_FAILURE_CLAUSE}`,
  { schema: PREP_SCHEMA, effort: 'low', label: 'prepare' }
)

if (prep.status === 'blocked') {
  log(`Prepare blocked: ${prep.reason}`)
  return { status: 'blocked', reason: prep.reason, topic: TOPIC, mode: MODE }
}

const ALL_DIMENSIONS = prep.dimensions || []
const MAX_ROUNDS = prep.maxRounds || 3
const CHECKS = prep.checks || []
const PRE_IDS = new Set(prep.preIds || [])
const GV = prep.gv

// The dimension scope THIS mode fans out, honored across every round of the
// loop below (not just round 1) -- so augment mode with a named DIMENSION
// never widens to the full dimension set even if a later round's thin-dimension
// check comes back empty. full mode is unchanged: MODE_DIMENSIONS === every
// goal dimension, identical to the pre-#20 behavior. update mode also gets
// the full dimension set here -- Phase 0b below narrows workDims further to
// just the gap dimensions once membership resolution has run.
const MODE_DIMENSIONS = MODE === 'augment' ? (DIMENSION ? [DIMENSION] : ALL_DIMENSIONS.slice()) : ALL_DIMENSIONS.slice()

log(`Prepared: ${ALL_DIMENSIONS.length} dimensions, maxRounds=${MAX_ROUNDS}, gv=${GV}, mode=${MODE}${MODE === 'augment' ? ` (scope: [${MODE_DIMENSIONS.join(', ')}])` : ''}`)

let STALE_IDS = []
let overallStatus = 'incomplete'
let unmetChecks = []
let roundsRun = 0
let verdictTotals = { falsified: 0, weakened: 0, survived: 0, inconclusive: 0 }
let renderArtifacts = []
let projectStats = { nodes: 0, edges: 0 }

// The run lock is already held (Prepare step 3) by the time we reach this
// point, so everything from here on -- including Phase 0b below -- must sit
// inside the try/finally that guarantees its release (issue: membership
// resolution used to run before this try, so a throw there leaked the lock).
try {
  // Augment mode requires an existing goal and prior findings (it never
  // authors a goal) -- both are already guaranteed by this point (Prepare
  // validated the goal file and loaded its dimensions). A named DIMENSION
  // not among the goal's own dimensions[] is a real error to stop on, not a
  // lens to silently research anyway (mirrors orchestrator.md Phase 0 step
  // 1's identical check). This lives INSIDE the try so the outer finally
  // below still releases the run lock Prepare acquired -- an early return
  // before the try would leak it (#28 review).
  if (MODE === 'augment' && DIMENSION && !ALL_DIMENSIONS.includes(DIMENSION)) {
    log(`Augment mode blocked: dimension "${DIMENSION}" is not among this goal's dimensions [${ALL_DIMENSIONS.join(', ')}]`)
    return { status: 'blocked', reason: 'unknown_dimension', topic: TOPIC, mode: MODE }
  }

  let workDims = MODE_DIMENSIONS.slice()

  // -------------------------------------------------------------------
  // Phase 0b -- Update-mode membership-aware gap resolution (skipped
  // entirely in full/augment mode, which keep their existing dimension
  // fan-out above). Same lock-leak reasoning as the augment-mode check
  // above -- this used to run before the try even existed; now it can
  // throw (schema validation, engine exit 5) without leaking the lock.
  // -------------------------------------------------------------------
  if (MODE === 'update') {
    const membership = await agent(
      `Resolve update-mode research scope for topic "${TOPIC}" at goal version ${GV} (SPEC §11), then run a tag-aware gap check research-harness#19 added on top of it -- resolve-membership.sh alone is dimension-level only and misses a dimension that already has baseline coverage but an unanswered NEW goal-declared tagged sub-question.

1. Membership: run \`test -f "${REPORTS_DIR}/goals/goal-${GV}.members.json" || bash scripts/resolve-membership.sh "${TOPIC}" "${GV}"\` (skip re-running it if a reshape already produced the file). Read \`.gap_dimensions[]\` and \`.stale[]\` from ${REPORTS_DIR}/goals/goal-${GV}.members.json.
2. Tag-aware gap check: from ${GOAL_FILE}'s \`.completion_condition.checks[]\`, extract every check whose "verify" field tests tag membership (matches the pattern \`tags | index("<tag>")\`, against either a finding's top-level .tags or .extensions.harness.tags). For each such tag, it is MET if any finding under ${REPORTS_DIR}/findings/*.json carries that tag AND has extensions.harness.verification.verdict "survived" or "weakened"; otherwise it is an unmet tag gap.
3. Attribute each unmet tag gap to a dimension: search that check's "assertion" text for the phrase "surviving <dimension> finding" against this goal's actual dimensions [${ALL_DIMENSIONS.join(', ')}]. If one of those dimension names appears there, that dimension owns the gap. If no dimension name appears in the assertion, the gap is unattributable -- in that case add EVERY one of [${ALL_DIMENSIONS.join(', ')}] to tagGapDimensions for that tag (never silently drop an unattributable gap) and still record the tag in tagGapTags.

Return {"gapDimensions":[...values from gap_dimensions[]...],"staleIds":[...values from stale[]...],"tagGapDimensions":[...deduplicated dimensions owning >=1 unmet tag gap...],"tagGapTags":[...every unmet tag string, attributed or not...]}. Empty arrays, not omitted fields, if there is nothing to report for one.
${ENGINE_FAILURE_CLAUSE}`,
      { schema: UPDATE_MEMBERSHIP_SCHEMA, effort: 'medium', label: 'update-membership', phase: 'Prepare' }
    )

    if (membership.status === 'toolchain_broken') {
      overallStatus = 'partial'
      log(`Update-mode membership resolution: toolchain broken (${membership.script || 'unknown script'}) -- stopping before any fan-out`)
    } else {
      STALE_IDS = membership.staleIds || []
      const gapDimSet = new Set([...(membership.gapDimensions || []), ...(membership.tagGapDimensions || [])])
      workDims = ALL_DIMENSIONS.filter((d) => gapDimSet.has(d))

      log(`update mode: gap dimensions=[${(membership.gapDimensions || []).join(', ')}], tag-gap dimensions=[${(membership.tagGapDimensions || []).join(', ')}] (unmet tags: ${(membership.tagGapTags || []).join(', ') || 'none'}), stale to re-verify=${STALE_IDS.length}`)

      if (workDims.length === 0 && STALE_IDS.length === 0) {
        log('update mode: every dimension is in-scope, fresh, and tag-complete -- reusing carried findings as-is, skipping straight to Synthesize')
      }
    }
  }

  // Round 1 must still run when update mode found nothing to fan out (workDims
  // empty) but DOES have stale findings to re-verify -- the Gate phase below
  // is what re-verifies them, not the Research phase. Membership reporting
  // toolchain_broken above (overallStatus 'partial') skips the loop entirely.
  for (let round = 1; round <= MAX_ROUNDS && overallStatus !== 'partial' && (workDims.length > 0 || (round === 1 && STALE_IDS.length > 0)); round++) {
    roundsRun = round

    // -------------------------------------------------------------------
    // Phase 1 -- Research (skipped when update mode has nothing to fan out
    // this round -- e.g. only stale findings need re-verification below)
    // -------------------------------------------------------------------
    phase('Research')

    if (workDims.length === 0) {
      log(`Round ${round}: no dimensions to research (update mode, stale-only round) -- skipping fan-out`)
    } else {
    log(`Round ${round}: researching dimensions [${workDims.join(', ')}]`)

    const researchResults = await pipeline(
      workDims,
      async (dim) => agent(
        `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
TOPIC: ${TOPIC}
DIMENSION: ${dim}
(round ${round} of ${MAX_ROUNDS})

Conduct research for the ${dim} dimension per your standard methodology (Steps 1-7). Be exhaustive within the dimension's scope -- stop at saturation, not at an arbitrary count.

${MODE === 'augment' ? AUGMENT_CLAUSE + '\n\n' : ''}${SIDE_EFFECT_CLAUSE}`,
        { agentType: 'dimension-analyst', schema: RESEARCH_SCHEMA, label: `research:${dim}:r${round}`, phase: 'Research' }
      ),
      async (prevResult, dim) => {
        // Stage 2: fan out one source-chunker per oversized source, no barrier.
        const oversized = (prevResult && prevResult.oversized_sources) || []
        if (oversized.length === 0) return prevResult
        await parallel(oversized.map((src) => async () => agent(
          `${LOCK_REFRESH}
SOURCE: ${src}
DIMENSION: ${dim}
GOAL_FILE: ${GOAL_FILE}
REPORTS_DIR: ${REPORTS_DIR}

Process this oversized source per your standard chunking methodology and emit MIF-backed findings through the ${dim} lens.

${SIDE_EFFECT_CLAUSE}`,
          { agentType: 'source-chunker', schema: CHUNK_SCHEMA, label: `chunk:${dim}`, phase: 'Research' }
        )))
        return prevResult
      },
      async (prevResult, dim) => {
        // Stage 3: deterministic shortfall reconcile, in-script retry (<=2x),
        // no polling, no zombies -- every agent() call here is awaited.
        let result = prevResult
        for (let attempt = 0; attempt < 2; attempt++) {
          const recount = await agent(
            `Count on-disk findings for dimension "${dim}": \`for f in ${REPORTS_DIR}/findings/*.json; do [ -e "$f" ] || continue; jq -e --arg d "${dim}" '.extensions.harness.dimension==$d' "$f" >/dev/null 2>&1 && echo x; done | wc -l\`. Return {"dimension":"${dim}","onDiskCount":N}.`,
            { schema: RECOUNT_SCHEMA, effort: 'low', label: `recount:${dim}:${attempt}`, phase: 'Research' }
          )
          const shortfall = recount.onDiskCount === 0 || recount.onDiskCount < (result.finding_count || 0)
          if (!shortfall) break
          log(`Shortfall on dimension "${dim}" (on-disk ${recount.onDiskCount} < reported ${result.finding_count}) -- retry ${attempt + 1}/2`)
          result = await agent(
            `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
TOPIC: ${TOPIC}
DIMENSION: ${dim}
(round ${round} retry ${attempt + 1} of 2)

A prior pass on this dimension came up short. Conduct research for the ${dim} dimension per your standard methodology (Steps 1-7).

${MODE === 'augment' ? AUGMENT_CLAUSE + '\n\n' : ''}${SIDE_EFFECT_CLAUSE}`,
            { agentType: 'dimension-analyst', schema: RESEARCH_SCHEMA, label: `research:${dim}:r${round}:retry${attempt + 1}`, phase: 'Research' }
          )
        }
        return result
      }
    )
    } // end: workDims.length > 0 fan-out

    // -------------------------------------------------------------------
    // Phase 2 -- Gate & Remediate (single adversarial gate, ADR-0004)
    // -------------------------------------------------------------------
    phase('Gate & Remediate')

    // Update-mode stale findings (SPEC §11) already carry an attempted_at, so
    // the "missing attempted_at" query below never surfaces them on its own --
    // name them explicitly so they get re-verified exactly once this round,
    // not silently reused with a decayed verdict.
    const staleClause = (MODE === 'update' && round === 1 && STALE_IDS.length > 0)
      ? ` ALSO include these stale in-scope finding @ids that need re-verification this round regardless of their existing attempted_at (SPEC §11 update-mode stale re-verification): ${JSON.stringify(STALE_IDS)}.`
      : ''

    const gateList = await agent(
      `List ungated findings under ${REPORTS_DIR}/findings/ (missing extensions.harness.verification.attempted_at), take at most ${Math.min(CLAIM_BUDGET, BATCH)} of them, write their @ids one per line to a file created with mktemp, and return {"count":N,"batchFile":"<path>"}. If there are none, return {"count":0,"batchFile":""}.${staleClause}`,
      { schema: GATE_LIST_SCHEMA, effort: 'low', label: `gate-list:r${round}`, phase: 'Gate & Remediate' }
    )

    if (gateList.count > 0) {
      await agent(
        `Run: \`touch "${REPORTS_DIR}/.gate-active"\`. Return {"status":"opened"}.`,
        { effort: 'low', label: `gate-open:r${round}`, phase: 'Gate & Remediate' }
      )
      try {
        const gateResult = await agent(
          `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
SCOPE: batch:${gateList.batchFile}
QUERY_BUDGET: ${QUERY_BUDGET}
CLAIM_BUDGET: ${CLAIM_BUDGET}
taskId: workflow-gate-r${round}

Run the single adversarial falsification gate over this batch per your standard methodology (Steps 1-8), including Step 8's dated falsification-report.md file write -- "report" in your schema return must be the real path you wrote it to, never a prose substitute.

${SIDE_EFFECT_CLAUSE}
${NO_CONFIG_MUTATION_CLAUSE}
${ENGINE_FAILURE_CLAUSE}`,
          { agentType: 'falsification-analyst', schema: GATE_RESULT_SCHEMA, label: `gate:r${round}`, phase: 'Gate & Remediate' }
        )
        if (gateResult.verdicts) {
          for (const k of ['falsified', 'weakened', 'survived', 'inconclusive']) {
            verdictTotals[k] += gateResult.verdicts[k] || 0
          }
        }
      } finally {
        await agent(
          `Run: \`rm -f "${REPORTS_DIR}/.gate-active"\`. Return {"status":"closed"}.`,
          { effort: 'low', label: `gate-close:r${round}`, phase: 'Gate & Remediate' }
        )
      }
    } else {
      log(`Round ${round}: nothing to gate`)
    }

    // -------------------------------------------------------------------
    // Phase 3 -- Type (ADR-0011, fail-closed)
    // -------------------------------------------------------------------
    phase('Type')

    let typeResult = await agent(
      `${LOCK_REFRESH}
Run: \`bash scripts/ontology-review.sh --topic "${TOPIC}"\` then \`bash scripts/check-shippable-typing.sh "${REPORTS_DIR}"\`.
Exit 0 from check-shippable-typing.sh -> return {"status":"ok"}.
Exit 1 -> return {"status":"blocked","reason":"untyped_shippable_findings"}.
Exit 2 or 3 -> return {"status":"blocked","reason":"<what exit code and why>"}.
${ENGINE_FAILURE_CLAUSE}`,
      { schema: TYPE_SCHEMA, effort: 'low', label: `type-check:r${round}`, phase: 'Type' }
    )

    if (typeResult.status === 'toolchain_broken') {
      overallStatus = 'partial'
      log(`Type phase: toolchain broken (${typeResult.script || 'unknown script'}) -- stopping`)
      break
    }

    if (typeResult.status === 'blocked') {
      log(`Type phase blocked (${typeResult.reason}) -- attempting one enrichment pass`)
      const enrich = await agent(
        `${LOCK_REFRESH}
For each shippable (verdict survived|weakened) finding under ${REPORTS_DIR}/findings/ that check-shippable-typing.sh flagged as untyped/unresolved: use \`mcp__mif-rh__suggest_type\` as an advisory hypothesis, confirm before writing, then stamp the finding's MIF entity block and run \`bash scripts/resolve-ontology.sh <finding.json> --topic "${TOPIC}"\` to durably resolve it. Then re-run \`bash scripts/check-shippable-typing.sh "${REPORTS_DIR}"\`.
Exit 0 after enrichment -> return {"status":"ok","enriched":N}.
Still non-zero -> return {"status":"blocked","reason":"still_untyped_after_enrichment","enriched":N}.
${ENGINE_FAILURE_CLAUSE}`,
        { schema: TYPE_SCHEMA, effort: 'medium', label: `type-enrich:r${round}`, phase: 'Type' }
      )
      typeResult = enrich
    }

    if (typeResult.status !== 'ok') {
      await agent(
        `Run: \`touch "${REPORTS_DIR}/.synthesis-withheld"\`. Return {"status":"withheld"}.`,
        { effort: 'low', label: `synthesis-withheld:r${round}`, phase: 'Type' }
      )
      overallStatus = 'partial'
      log('Type phase still blocked after one enrichment pass -- withholding synthesis, proceeding to Finalize as PARTIAL')
      break
    }

    // -------------------------------------------------------------------
    // Phase 4 -- Check
    // -------------------------------------------------------------------
    phase('Check')

    const check = await agent(
      `${LOCK_REFRESH}
Run: \`bash scripts/reconcile-session.sh "${REPORTS_DIR}"\`. Non-zero exit -> return {"status":"toolchain_broken"} immediately.
Otherwise, evaluate each of these completion_condition checks against current repo/session state and classify pass/fail:
${JSON.stringify(CHECKS)}
Also identify any dimension among [${workDims.join(', ')}] whose finding count on disk looks thin relative to the goal's scope (a judgment call, not a hard threshold).
Return {"status":"evaluated","passed":["<check id>",...],"unmet":["<check id>",...],"thinDimensions":["<dimension>",...]}.
${ENGINE_FAILURE_CLAUSE}`,
      { schema: CHECK_SCHEMA, effort: 'medium', label: `check:r${round}`, phase: 'Check' }
    )

    if (check.status === 'toolchain_broken') {
      overallStatus = 'partial'
      log('Check phase: reconcile-session.sh reported a broken toolchain -- stopping')
      break
    }

    unmetChecks = check.unmet || []

    if (unmetChecks.length === 0) {
      overallStatus = 'complete'
      log(`Round ${round}: all completion checks pass`)
      break
    }

    if (round >= MAX_ROUNDS) {
      overallStatus = 'partial'
      log(`Bound hit (round ${round}/${MAX_ROUNDS}) with unmet checks: ${unmetChecks.join(', ')}`)
      break
    }

    if (budget.total && budget.remaining() <= 0) {
      overallStatus = 'partial'
      log('Token budget exhausted -- stopping before another round')
      break
    }

    // Scoped to MODE_DIMENSIONS (not ALL_DIMENSIONS) so a named-DIMENSION
    // augment run never widens past its one dimension in a later round, even
    // if the Check phase names a thin dimension outside that scope or comes
    // back with none at all -- the mode's own scope is the hard ceiling.
    const reportedThin = (check.thinDimensions || []).filter((d) => MODE_DIMENSIONS.includes(d))
    workDims = reportedThin.length ? reportedThin : MODE_DIMENSIONS.slice()
    log(`Round ${round} incomplete (unmet: ${unmetChecks.join(', ')}) -- looping thin dimensions [${workDims.join(', ')}]`)
  }

  // ---------------------------------------------------------------------
  // Phase 5 -- Synthesize / Phase 6 -- Render (skipped if synthesis withheld)
  // ---------------------------------------------------------------------
  if (overallStatus !== 'partial' || unmetChecks.length === 0) {
    phase('Synthesize')

    await agent(
      `${LOCK_REFRESH}
Stamp gathered_under="${GV}" on every finding under ${REPORTS_DIR}/findings/*.json whose @id is NOT in this pre-existing set and doesn't already carry a gathered_under: ${JSON.stringify(Array.from(PRE_IDS))}. Use the model layer (python3 with lib/harness_models), never hand-edit JSON in shell. Return {"status":"stamped"}.`,
      { effort: 'low', label: 'gathered-under-stamp', phase: 'Synthesize' }
    )

    const genreFilter = await agent(
      `Read harness.config.json's .packs[] (or .claude/enabled-packs.json if present) and .outputs[]. Requested genres: ${JSON.stringify(GENRES_REQUESTED)}. For each requested genre, keep it in "enabled" only if a pack with that exact name exists and is enabled; otherwise put it in "skipped". Also set "blogEnabled" to whether outputs[] has a channel:"blog" entry with enabled:true. Return {"enabled":[...],"skipped":[...],"blogEnabled":true|false}.`,
      { schema: GENRE_FILTER_SCHEMA, effort: 'low', label: 'genre-filter', phase: 'Synthesize' }
    )

    if (genreFilter.skipped && genreFilter.skipped.length) {
      log(`Genres requested but disabled/unknown, skipped: ${genreFilter.skipped.join(', ')}`)
    }

    phase('Render')

    const renderTasks = []

    renderTasks.push(() => agent(
      `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
TOPIC: ${TOPIC}
GENRE: general

Produce the canonical MIF Level-3 report per your standard methodology (Steps 1-6, including Steps 4b-4e: synthesize-artifact.sh, falsify the report's own claim projection, render-artifact.sh, re-publish via Write for witnessed provenance, mif-validate --level 3).

${SIDE_EFFECT_CLAUSE}
${NO_CONFIG_MUTATION_CLAUSE}
${ENGINE_FAILURE_CLAUSE}`,
      { agentType: 'report-synthesizer', schema: RENDER_SCHEMA, label: 'render:report', phase: 'Render' }
    ))

    for (const genre of (genreFilter.enabled || [])) {
      renderTasks.push(() => agent(
        `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
TOPIC: ${TOPIC}
GENRE: ${genre}

Produce a ${genre}-genre synthesis per your standard methodology (Steps 1-6).

${SIDE_EFFECT_CLAUSE}
${NO_CONFIG_MUTATION_CLAUSE}
${ENGINE_FAILURE_CLAUSE}`,
        { agentType: 'report-synthesizer', schema: RENDER_SCHEMA, label: `render:${genre}`, phase: 'Render' }
      ))
    }

    if (genreFilter.blogEnabled && CHANNELS.includes('blog')) {
      renderTasks.push(() => agent(
        `${LOCK_REFRESH}
REPORTS_DIR: ${REPORTS_DIR}
TOPIC: ${TOPIC}
GENRE: general
CHANNEL: blog

Produce the blog channel projection (L1, citation-leak-safe prose) per your standard methodology.

${SIDE_EFFECT_CLAUSE}
${NO_CONFIG_MUTATION_CLAUSE}
${ENGINE_FAILURE_CLAUSE}`,
        { agentType: 'report-synthesizer', schema: RENDER_SCHEMA, label: 'render:blog', phase: 'Render' }
      ))
    }

    renderArtifacts = (await parallel(renderTasks)).filter(Boolean)

    // -------------------------------------------------------------------
    // Phase 7 -- Project (strictly sequential, never parallel -- known race)
    // -------------------------------------------------------------------
    phase('Project')

    const project = await agent(
      `${LOCK_REFRESH}
Run in this exact order, stopping and reporting the first failure:
1. bash scripts/resolve-membership.sh "${TOPIC}" "${GV}"
2. bash scripts/build-index.sh "${REPORTS_DIR}/findings"
3. bash scripts/build-graph.sh "${REPORTS_DIR}/findings"
4. bash scripts/assert-graph-mif.sh "${REPORTS_DIR}/knowledge-graph.json"
5. bash scripts/build-concordance.sh
6. bash scripts/validate-concordance.sh reports/concordance.json
Then, as your literal final command before responding, run exactly: \`jq '{nodes: (.nodes|length), edges: (.edges|length)}' "${REPORTS_DIR}/knowledge-graph.json"\` -- and copy its printed numbers verbatim into your schema return. Do not estimate, round, or recall these numbers from earlier in your work; they must come from this exact command's output.
Return {"status":"ok","nodes":N,"edges":N} using those exact numbers on success, or {"status":"failed:<step>"} on the first failure.
${SIDE_EFFECT_CLAUSE}
${ENGINE_FAILURE_CLAUSE}`,
      { schema: PROJECT_SCHEMA, effort: 'low', label: 'project', phase: 'Project' }
    )
    projectStats = { nodes: project.nodes || 0, edges: project.edges || 0 }
  } else {
    log('Synthesis withheld -- skipping Synthesize/Render/Project')
  }

  // ---------------------------------------------------------------------
  // Phase 8 -- Finalize (best-effort; lock release itself is guaranteed by
  // the outer finally below, independent of whether this succeeds)
  // ---------------------------------------------------------------------
  phase('Finalize')

  await agent(
    `${LOCK_REFRESH}
Run: \`bash scripts/build-topic-readme.sh "${TOPIC}"\`, then use the readme skill to refine Key Findings into synthesis-grade cross-finding bullets, then \`bash scripts/build-topic-readme.sh "${TOPIC}" --check\`. Also append a dated "## Session Summary" section to ${REPORTS_DIR}/research-progress.md (append-only, never overwrite) noting: rounds=${roundsRun}, status=${overallStatus}, verdicts=${JSON.stringify(verdictTotals)}. Markdownlint-conformant append: a blank line between the "## {ISO_DATE} — Session Summary" heading and the bullet list under it (MD022/MD032), and any raw http(s):// URL wrapped in angle brackets, e.g. "Filed upstream: <URL>" (MD034). Also remove ${REPORTS_DIR}/.synthesis-withheld if present and overallStatus is "complete". Return {"status":"finalized","readmeOk":true|false} (readmeOk:false if build-topic-readme.sh failed for any reason, including topic-not-registered -- that is a reportable outcome, not something to work around).

${NO_CONFIG_MUTATION_CLAUSE}`,
    { schema: FINALIZE_SCHEMA, effort: 'low', label: 'finalize' }
  )
} finally {
  // Guaranteed cleanup on every exit path (normal return, break, throw, or a
  // host-level TaskStop interrupting the run -- unverified whether `finally`
  // actually fires under the latter; see plan Risk #3).
  phase('Finalize')
  await agent(
    `Run: \`bash scripts/run-lock.sh release "${REPORTS_DIR}"\` and \`rm -f "${REPORTS_DIR}/.gate-active"\` (best-effort cleanup even if already released/absent). Return {"status":"released"}.`,
    { effort: 'low', label: 'release-lock' }
  )
}

return {
  status: overallStatus,
  topic: TOPIC,
  mode: MODE,
  gv: GV,
  rounds: roundsRun,
  findings: {
    new: null,
    survived: verdictTotals.survived,
    weakened: verdictTotals.weakened,
    falsified: verdictTotals.falsified,
    inconclusive: verdictTotals.inconclusive,
  },
  unmetChecks,
  artifacts: renderArtifacts,
  graph: projectStats,
}
