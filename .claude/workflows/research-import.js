// research-import.js — atomic action D of the research pipeline
// (include pre-existing findings: bring an external MIF Container into the
// topic through the fail-closed import gate).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#560/#564/#569/#573/#578/#582/#586
// precedent.
//
// Vendored from the workspace engine reference (Epic #548, Task #590). This
// is an ADAPTATION of the reference script, not a drop-in port. In-repo
// default: harnessDir defaults to the instance root '.' (the
// #552/#556/#560/#564/#569/#573/#578/#582/#586 precedent).
//
// CONFIRMED CLEAN DELEGATION — unlike #543/#544/#545/#546/#547's vendor
// Tasks (each of which found and fixed a freehand-reimplementation gap),
// this module has NO analogous gap. Read line by line against the actual
// reference source before writing this file: the DryRun phase's prompt runs
// exactly `bash scripts/mif-container-import.sh "<container>" "<topic>"
// --dry-run` and reports the gate's own ordered results (manifest schema,
// digests, ontology-binding compatibility — ADR-0017,
// docs/adr/0017-mif-container-instance-scoped-export-import-format.md,
// status: accepted); the Apply phase runs the identical script without
// --dry-run. Neither phase's prompt describes or re-derives any
// manifest/digest/ontology-binding logic freehand anywhere in this file —
// the entire mechanical validation surface is delegated to the real
// scripts/mif-container-import.sh (Stories #318-#328's fail-closed, ordered,
// no-partial-write design, confirmed present and matching its own header
// comment). The delegation bar matters especially here: this is the one
// workflow in the chain that ingests untrusted EXTERNAL input (another
// harness instance's export container), so the fail-closed gate's integrity
// depends entirely on zero freehand duplication of its checks. Ported
// AS-IS; do not add logic here that duplicates the script's own validation.
//
// FALSIFY REGATE HOOKUP (confirmed interface alignment, #548, with a nuance
// beyond #547's pivot hookup). needsGating is a plain array of finding @id
// strings — research-falsify.js's `scope` argument accepts exactly
// `{ paths?: string[], ids?: string[] }` with a `regate: true` flag gated to
// require that explicit id/path scope, so needsGating maps directly onto
// `scope: { ids: needsGating }` with zero adapter needed, same as #547's
// reverifyIds→falsify hookup. The nuance: when trustImportedVerdicts is
// false, needsGating also includes withForeignVerdicts ids — these already
// carry a FOREIGN extensions.harness.verification.attempted_at block from
// the source instance. Calling falsify without regate: true would silently
// skip them under the one-round rule (the enumerate step excludes anything
// with attempted_at already set). The orchestrator hookup therefore needs
// `regate: true` alongside `scope: { ids: needsGating }` —
// research-falsify.js's existing client-side regate-reset step (already
// used by pivot's reverifyIds hookup, #586/#587) already clears whatever
// verification block is present (foreign or stale) before re-invoking
// falsify.sh; it is not a separate "import-reset" mechanism. See the
// needsGating return below for the call-site note.
export const meta = {
  name: 'research-import',
  description: 'Atomic action D (include pre-existing findings): bring an external MIF Container (or a loose pre-existing finding set) into the topic through the fail-closed import gate — dry-run first, an explicit go/no-go review, apply, then hand every finding lacking a trusted verification verdict to the falsification gate; imported evidence is never exempt from gating',
  whenToUse: 'When findings from another harness instance, an earlier campaign, or an /export container should join the corpus',
  phases: [
    { title: 'DryRun', detail: 'fail-closed validation pass, no writes', model: 'haiku' },
    { title: 'Review', detail: 'go/no-go on the dry-run evidence: digests, ontology bindings, collisions', model: 'sonnet' },
    { title: 'Apply', detail: 'real import + enumerate what now needs gating', model: 'haiku' },
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

// args: { harnessDir, topic, containerDir: string (dir containing mif-package.json, as produced by /export),
//         trustImportedVerdicts?: boolean (default false — foreign verdicts are re-gated) }
const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
const CDIR = A && A.containerDir
if (!TOPIC) throw new Error('research-import: args.topic is required')
if (!CDIR) throw new Error('research-import: args.containerDir is required')
const TRUST = !!(A && A.trustImportedVerdicts)

const DRYRUN_SCHEMA = {
  type: 'object',
  properties: {
    passed: { type: 'boolean' },
    manifestValid: { type: 'boolean' },
    digestsValid: { type: 'boolean' },
    ontologyBindingsCompatible: { type: 'boolean' },
    resourceCount: { type: 'integer' },
    output: { type: 'string', description: 'the gate output, verbatim-condensed' },
  },
  required: ['passed', 'manifestValid', 'digestsValid', 'ontologyBindingsCompatible', 'resourceCount', 'output'],
}
const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    proceed: { type: 'boolean' },
    reasons: { type: 'array', items: { type: 'string' } },
    collisions: { type: 'array', items: { type: 'string' }, description: '@ids already present in the topic' },
  },
  required: ['proceed', 'reasons', 'collisions'],
}
const APPLY_SCHEMA = {
  type: 'object',
  properties: {
    applied: { type: 'boolean' },
    importedIds: { type: 'array', items: { type: 'string' } },
    withForeignVerdicts: { type: 'array', items: { type: 'string' } },
    unverified: { type: 'array', items: { type: 'string' } },
    output: { type: 'string' },
  },
  required: ['applied', 'importedIds', 'withForeignVerdicts', 'unverified', 'output'],
}

phase('DryRun')
const dry = await agent(
  `Dry-run the fail-closed MIF Container import gate in harness ${H}: run \`bash scripts/mif-container-import.sh "${CDIR}" "${TOPIC}" --dry-run\` and report its ordered validation results (manifest schema, per-resource + manifest-level digests, ontology-binding compatibility against this instance's cataloged packs). The topic must already be registered — if the gate says otherwise, passed=false. Report, do not fix.`,
  { label: 'import:dry-run', model: 'haiku', effort: 'low', schema: DRYRUN_SCHEMA },
)
if (!dry) throw new Error('research-import: dry-run failed to execute')
if (!dry.passed) {
  log(`Import dry-run REJECTED: ${dry.output.slice(0, 300)}`)
  return { ok: false, stage: 'dry-run', detail: dry }
}

phase('Review')
const review = await agent(
  `Go/no-go review of a validated MIF Container import: container ${CDIR} → topic ${TOPIC} (harness ${H}). Dry-run evidence: ${JSON.stringify(dry)}.\n` +
    `Check what the mechanical gate cannot: (1) @id collisions — list container resource @ids already present under ${H}/reports/${TOPIC}/findings/ (the gate is idempotent, but silent same-id overwrite of DIFFERENT content is a no-go); (2) provenance plausibility — does the manifest's origin metadata cohere with its contents; (3) scope fit — sample a few container findings against ${H}/reports/${TOPIC}/goal.json scope: a container that is mostly out-of-scope is a no-go worth reporting before it dilutes the corpus. proceed=true only with zero no-go hits.`,
  { label: 'import:review', model: 'sonnet', schema: REVIEW_SCHEMA },
)
if (!review || !review.proceed) {
  log(`Import NO-GO: ${((review && review.reasons) || ['review agent failed']).join('; ')}`)
  return { ok: false, stage: 'review', detail: review }
}

phase('Apply')
const applied = await agent(
  `Apply the reviewed MIF Container import in harness ${H}: run \`bash scripts/mif-container-import.sh "${CDIR}" "${TOPIC}"\` (no --dry-run). A failure at any step rejects the whole import — report it, never partial-write by hand.\n` +
    `Then enumerate what landed under ${H}/reports/${TOPIC}/findings/: all imported @ids; which carry a FOREIGN extensions.harness.verification.attempted_at (a verdict already minted by another instance — a placeholder verification block with no attempted_at still counts as unverified here); which have no attempted_at set at all. Report only — no verdict edits.`,
  { label: 'import:apply', model: 'haiku', schema: APPLY_SCHEMA },
)
if (!applied || !applied.applied) {
  log('Import application failed — the fail-closed gate rejected it; nothing was partially written')
  return { ok: false, stage: 'apply', detail: applied }
}

// Foreign verdicts are not this instance's verdicts. Unless explicitly trusted, they queue for
// re-gating — but the one-round rule keys on attempted_at, so the caller passes these ids to
// research-falsify as an explicit ids scope with regate: true (falsify.sh's client-side
// regate-reset step clears whatever verification block is present, foreign or stale, before
// re-invoking the gate — it is not a separate "import-reset" mechanism; same mechanism #586/#587
// used for pivot's reverifyIds). Feeds DIRECTLY into research-falsify's scope argument with no
// adapter: research-falsify({ ..., scope: { ids: needsGating }, regate: true }).
const needsGating = TRUST ? applied.unverified : applied.unverified.concat(applied.withForeignVerdicts)
log(`Imported ${applied.importedIds.length} finding(s); ${needsGating.length} queued for the falsification gate (${TRUST ? 'trusting' : 're-gating'} foreign verdicts)`)

return {
  ok: true,
  imported: applied.importedIds,
  needsGating,
  trustedForeignVerdicts: TRUST ? applied.withForeignVerdicts : [],
  collisionsChecked: review.collisions,
}
