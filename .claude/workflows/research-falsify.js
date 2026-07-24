// research-falsify.js — atomic step 3 of the research pipeline (falsification).
//
// Workflow-runtime module: the runtime strips the `export` statement and
// evaluates the remaining source as the BODY of an async function, so
// top-level `await` and `return` are legal here and a bare `node --check`
// rejects this file by design. CI parse-checks it through
// scripts/check-workflow-syntax.sh (async-body wrap), wired into verify.sh's
// gate_workflows — see #552/#556/#559 precedent.
//
// Vendored from the workspace engine reference (Epic #541, Task #560). This
// is a genuine ADAPTATION of the reference script, not a drop-in port — three
// gaps were verified against the CURRENT substrate (scripts/falsify.sh,
// mif-rs's crates/mif-rh/src/harness_falsify.rs, mif-rh-cli's
// HarnessCommand::Falsify{finding,fixture}) before this module was written,
// and each is closed below rather than carried forward from the reference
// script's (inaccurate, for this substrate) assumptions:
//
//   1. VERDICT-WRITE SHAPE. falsify.sh's real signature is
//      `falsify.sh <finding.json> [<evidence-fixture.json>]` — there is no
//      bare verdict/basis CLI-arg form. The fixture is a JSON object keyed by
//      the finding's @id: { "<id>": { verdict, basis, disconfirming: [url,
//      ...] } }. The Gate phase's write step therefore MATERIALIZES that
//      fixture in code (from mergeVotes()'s / the adjudication agent's own
//      verdict+basis+collected source URLs — deterministic, not left to an
//      agent to improvise) and hands the exact JSON text to the write agent,
//      which mktemps it OUTSIDE the repo tree and invokes
//      `falsify.sh <finding> <fixture>` — see buildFixtureEntry() below.
//   2. REGATE = CLIENT-SIDE RESET. falsify.sh's one-round check
//      (already_graded() in harness_falsify.rs) is unconditional — there is
//      no engine override flag anywhere in the CLI. A re-gate (a goal-version
//      pivot/update classifying a finding stale) is therefore implemented by
//      this module clearing/resetting the stale finding's
//      extensions.harness.verification block itself, BEFORE re-invoking
//      falsify.sh — see the regate-reset step in the Gate phase. The actual
//      verdict write still routes exclusively through falsify.sh; only the
//      pre-condition it checks is reset client-side. falsify.sh remains the
//      one and only verdict writer either way (D-3 in the workspace
//      research-pipeline architecture doc's decision log: "falsify.sh
//      remains the only verdict writer" — that invariant is unchanged by
//      this module owning remediation, see gap 3).
//   3. REMEDIATION IS NOT IMPLEMENTED BY falsify.sh OR mif-rh-cli AT ALL
//      (confirmed: zero "quarantine" hits across harness_falsify.rs and
//      main.rs). It previously existed only as prose in
//      .claude/agents/falsification-analyst.md Step 7, executed by hand by
//      that agent. This module PORTS that logic directly (REMEDIATION_CONTRACT
//      below: falsified -> quarantine, weakened -> downgrade one
//      provenance.trustLevel rung + bounded summary qualifier,
//      survived/inconclusive -> annotate only) so the fixture-write bridge in
//      gap 1 and the remediation it triggers travel together. The reference
//      script this module is vendored from carries a comment claiming
//      "falsify.sh owns... remediation, do not reimplement by hand" — that
//      claim is FALSE against this substrate (falsify.sh/mif-rh-cli implement
//      only the one-round-guarded verdict write, nothing past it) and is not
//      carried forward here.
export const meta = {
  name: 'research-falsify',
  description: 'Atomic step 3 (falsification): the single adversarial gate, decomposed — haiku claim decomposition, perspective-diverse sonnet skeptic voting (web-only), deterministic verdict arithmetic in code, opus adjudication only on contested findings, verdicts written through the falsify.sh substrate via a code-materialized fixture, remediation (quarantine/downgrade/annotate) applied by this module',
  whenToUse: 'After any batch of findings lands (fan-out round, augment, import) — gates every unverified finding in scope; the one-round rule is enforced structurally at enumeration',
  phases: [
    { title: 'Enumerate', detail: 'working set = unverified findings in scope, budget-sliced in code', model: 'haiku' },
    { title: 'Gate', detail: 'per finding: decompose → parallel skeptic lenses → merged verdict → adjudicate if contested → materialize an ephemeral evidence fixture in code → write via falsify.sh <finding> <fixture> → apply remediation (quarantine/downgrade/annotate) ported from falsification-analyst.md' },
    { title: 'Rollup', detail: 'tally verdicts by finding, log the rollup, return gated/rollup/verdicts/deferredIds/alreadyVerified' },
  ],
}

// args: { harnessDir, topic, scope?: 'all' | 'dimension:<d>' | { paths?: string[], ids?: string[] },
//         claimBudget?: number (findings per run, default 50), queryBudget?: number (disconfirming queries per claim, default 6),
//         lenses?: number (2..4, default 3),
//         regate?: boolean — ONLY with an explicit paths/ids scope: re-open verification for findings a pivot/update
//                  classified stale. falsify.sh's already_graded() short-circuit is unconditional (no engine override
//                  exists) — this module clears/resets the stale finding's extensions.harness.verification block
//                  itself, client-side, BEFORE re-invoking falsify.sh, so the write itself still routes exclusively
//                  through falsify.sh (gap 2 above).
//         runDate: string — a stamped ISO-8601 timestamp the CALLER computed OUTSIDE the Workflow runtime
//                  (new Date()/Date.now() throw if called from inside a Workflow-runtime script's own body —
//                  "breaks resume" — see #618). research-pipeline.js forwards this from its own args (which the
//                  /research command supplies via a plain `date` invocation before ever calling the Workflow
//                  tool). Required only once a finding actually needs gating — see the Gate phase below; a run
//                  whose working set is empty never touches it. }
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

const H = (A && A.harnessDir) || '.'
const TOPIC = A && A.topic
if (!TOPIC) throw new Error('research-falsify: args.topic is required')
const RUN_DATE = A && A.runDate
const RDIR = `${H}/reports/${TOPIC}`
const SCOPE = (A && A.scope) || 'all'
const CLAIM_BUDGET = (A && A.claimBudget) || 50
const QUERY_BUDGET = (A && A.queryBudget) || 6
const LENS_COUNT = Math.min(4, Math.max(2, (A && A.lenses) || 3))
const REGATE_SCOPE_QUALIFIES = typeof SCOPE === 'object' && !!(SCOPE.paths || SCOPE.ids)
if (A && A.regate && !REGATE_SCOPE_QUALIFIES) {
  throw new Error("research-falsify: regate=true requires an explicit scope:{paths|ids:[...]} — refusing to silently fall back to the one-round rule for a broad scope ('all' or 'dimension:*')")
}
const REGATE = !!(A && A.regate && REGATE_SCOPE_QUALIFIES)

// #625: workingSet and skippedAlreadyVerifiedIds are the same agent turn's
// own classification of the findings it decided to look at — nothing here
// independently proves it looked at ALL of them. A real run (scope:'all'
// over a 19-finding corpus) silently enumerated only 18: one pre-existing
// finding appeared in neither list, and nothing detected the gap because
// only an aggregate count (skippedAlreadyVerified: integer) was ever
// returned, with no itemized on-disk listing to reconcile it against.
// allFindingIds is that itemized listing — the agent brief below requires it
// be derived mechanically (`find … | sort`), not re-derived from the same
// reasoning that produced workingSet — and skippedAlreadyVerifiedIds is now
// itemized too so every id in allFindingIds can be code-reconciled against
// exactly one of the two other lists immediately below (see the
// reconcileEnumeration()/retry block after the agent() call).
const ENUM_SCHEMA = {
  type: 'object',
  properties: {
    workingSet: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          path: { type: 'string' },
          id: { type: 'string' },
          dimension: { type: 'string' },
          claimSummary: { type: 'string' },
        },
        required: ['path', 'id', 'dimension', 'claimSummary'],
      },
    },
    skippedAlreadyVerifiedIds: { type: 'array', items: { type: 'string' }, description: '@ids excluded under the one-round rule (already carrying extensions.harness.verification.attempted_at)' },
    allFindingIds: { type: 'array', items: { type: 'string' }, description: 'EVERY @id under RDIR/findings/ (quarantine/ and archive/ excluded), derived mechanically via find|sort — not re-derived from the same pass that produced workingSet' },
  },
  required: ['workingSet', 'skippedAlreadyVerifiedIds', 'allFindingIds'],
}
const DECOMPOSE_SCHEMA = {
  type: 'object',
  properties: {
    claims: { type: 'array', items: { type: 'string' }, description: 'atomic, independently checkable claims' },
  },
  required: ['claims'],
}
const LENS_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['falsified', 'weakened', 'survived', 'inconclusive'] },
    basis: { type: 'string', description: 'the disconfirming (or absent-disconfirming) evidence, with URLs actually retrieved' },
    sources: { type: 'array', items: { type: 'string' }, description: 'URLs actually retrieved this lens that are disconfirming, weakening, or a credible alternative explanation — feeds the evidence-fixture disconfirming[] list verbatim, never fabricated or padded' },
    perClaim: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          claim: { type: 'string' },
          verdict: { type: 'string', enum: ['falsified', 'weakened', 'survived', 'inconclusive'] },
          evidence: { type: 'string' },
        },
        required: ['claim', 'verdict', 'evidence'],
      },
    },
  },
  required: ['verdict', 'basis', 'sources', 'perClaim'],
}
// research-harness-template#738: scripts/falsify.sh refuses (exit 3) to write
// any reports/<topic>/findings/*.json finding unless this topic's
// <RDIR>/.gate-active window is open and fresh (<240min) — SPEC §6b restricts
// opening it to the orchestrator's Phase 2 loop or the /falsify command
// (.claude/commands/falsify.md), which also acquire the companion
// scripts/run-lock.sh topic lock first (the same shared findings/ directory
// two concurrent writers corrupt — see run-lock.sh's own header). This
// module is neither of those two callers: it is the vendored JS engine's OWN
// write step, invoked (directly or via research-pipeline.js's wf('falsify',
// ...)) from research-pipeline.js's full/augment/pivot/import/falsify modes
// and from a direct top-level scriptPath call. Before this fix every write
// below was therefore either DENIED outright by the guard-falsify-gate.sh
// PreToolUse hook, or exited 3 from falsify.sh itself once the hook was
// bypassed — no finding's verdict was ever actually persisted to disk
// through this engine. LOCK_ACQUIRE_SCHEMA/LOCK_STATUS_SCHEMA back the
// acquire/refresh/release agent() calls in the Gate phase below, which
// mirror falsify.md's Phase 2 contract exactly: acquire once before any
// write, refresh before every finding, release on EVERY exit path (success
// or a thrown error) via try/finally.
const LOCK_ACQUIRE_SCHEMA = { type: 'object', properties: { ok: { type: 'boolean' }, token: { type: 'string' }, error: { type: 'string' } }, required: ['ok'] }
const LOCK_STATUS_SCHEMA = { type: 'object', properties: { ok: { type: 'boolean' } }, required: ['ok'] }
const WRITE_SCHEMA = {
  type: 'object',
  properties: {
    written: { type: 'boolean' },
    remediation: { type: 'string', description: 'quarantined | downgraded | annotated | skipped-one-round | write-failed' },
    // #659: falsify.sh (via mif-rh-cli) has been observed to write verdict +
    // verdict_basis but silently drop extensions.harness.verification.attempted_at
    // on a genuine (non-placeholder) gate write — verdict/basis alone are not
    // proof the write actually completed. true is only valid if the agent
    // ACTUALLY read the finding file back off disk this turn and observed a
    // present, non-null attempted_at; false covers both a genuine absence and
    // the one-round-rule skip path (remediation === 'skipped-one-round'), where
    // no attempted_at was ever expected from this call.
    attemptedAtPresent: { type: 'boolean', description: 'true only if extensions.harness.verification.attempted_at was read back from the finding file AFTER the falsify.sh invocation and found present (non-null) THIS turn — never asserted from assumption' },
  },
  required: ['written', 'remediation', 'attemptedAtPresent'],
}

// Perspective-diverse skeptic lenses: diversity catches failure modes redundancy cannot.
const LENSES = [
  {
    key: 'counter-evidence',
    brief: 'Independent disconfirmation: for each claim, generate up to the query budget of DISCONFIRMING web queries (what would be true if this claim were false?) and run them. You are trying to BREAK the claim, not corroborate it.',
  },
  {
    key: 'source-integrity',
    brief: 'Source attack: retrieve the finding\'s own citations. Does each cited source exist, actually assert what the finding attributes to it, and carry the authority the finding implies? Misquoted, dead, or overstretched sources falsify or weaken the finding regardless of the claim\'s truth.',
  },
  {
    key: 'temporal-validity',
    brief: 'Staleness attack: search for newer primary sources that supersede, correct, or invert the claim. A claim true at its citation date but overtaken by events is weakened or falsified, not survived.',
  },
  {
    key: 'scope-integrity',
    brief: 'Overclaim attack: test whether the evidence actually supports the claim at its stated GENERALITY (all/most/typical vs one observed case). Search for counterexamples at the claim\'s stated breadth; an overgeneralized claim is weakened even when its narrow core holds.',
  },
].slice(0, LENS_COUNT)

// Deterministic verdict arithmetic — verdict math lives in code, not in any model's judgment.
const RANK = { falsified: 3, weakened: 2, inconclusive: 1, survived: 0 }
function mergeVotes(votes) {
  const counts = {}
  for (const v of votes) counts[v] = (counts[v] || 0) + 1
  const majority = Math.floor(votes.length / 2) + 1
  if ((counts.falsified || 0) >= majority) return { verdict: 'falsified', contested: false }
  if (votes.every((v) => v === votes[0])) return { verdict: votes[0], contested: false }
  if ((counts.falsified || 0) > 0) return { verdict: null, contested: true } // any minority falsified vote → adjudicate
  if ((counts.weakened || 0) >= majority) return { verdict: 'weakened', contested: false }
  if ((counts.survived || 0) >= majority && !(counts.weakened || 0)) return { verdict: 'survived', contested: false }
  // survived/weakened/inconclusive mix without majority: take the most severe non-falsified vote — conservative, no adjudication cost
  const worst = votes.slice().sort((a, b) => RANK[b] - RANK[a])[0]
  return { verdict: worst, contested: false }
}

// #682: pair each lens result with the lens that PRODUCED it, in code, before
// any failed lens is dropped. parallel() preserves LENSES order, so index i is
// only trustworthy at this moment — once filter(Boolean) removes a failed
// lens's null, positional lookups back into LENSES misattribute every
// surviving result after the gap (e.g. with source-integrity failed,
// temporal-validity's evidence gets labeled source-integrity in the
// permanently-written verification basis AND in the contested-adjudication
// prompt). Same idiom as mergeVotes(): identity arithmetic lives in code,
// never reconstructed downstream.
function pairLensResults(lenses, results) {
  // lensKey is assigned AFTER the spread so no stray lensKey field on a lens
  // result can ever overwrite the paired identity, and the lenses[i] lookup is
  // guarded so a diverged results array degrades to a labeled placeholder
  // instead of throwing mid-Gate.
  return results
    .map((r, i) => (r ? { ...r, lensKey: (lenses[i] && lenses[i].key) || `lens-${i}` } : null))
    .filter(Boolean)
}

// Gap 1 (see module header): materialize the evidence-fixture entry in code,
// from the already-computed verdict/basis and the lenses' own retrieved
// URLs — deterministic, so the write agent has nothing to improvise about
// the fixture's shape or content, only where to put the file and how to
// invoke falsify.sh with it.
//
// #618: attemptedAt is a REQUIRED parameter, never computed here. A Workflow-
// runtime script's own body cannot call new Date()/Date.now() (the runtime
// throws — "breaks resume", since replaying the script on resume must be
// deterministic) — every finding this function was called for crashed on
// exactly this before the fix. The caller (the Gate phase below) supplies
// RUN_DATE, which itself is threaded in from args.runDate — a timestamp
// stamped OUTSIDE the runtime by whatever invoked this script.
function buildFixtureEntry(id, verdict, basis, lensResults, attemptedAt) {
  const urls = []
  for (const r of lensResults || []) {
    for (const u of r.sources || []) {
      if (u && !urls.includes(u)) urls.push(u)
    }
  }
  return {
    [id]: {
      verdict,
      basis: basis.slice(0, 1500),
      attempted_at: attemptedAt,
      disconfirming: urls.slice(0, 20),
    },
  }
}

// Gap 3 (see module header): the remediation logic ported verbatim from
// .claude/agents/falsification-analyst.md Step 7 — falsify.sh/mif-rh-cli
// implement only the one-round-guarded verdict write (D-3: falsify.sh
// remains the only verdict writer); everything past that write is this
// module's own responsibility now, stated once here and embedded in every
// write-step brief so the agent applies the same algorithm every time
// instead of improvising.
const TRUST_LADDER = ['verified', 'high_confidence', 'moderate_confidence', 'low_confidence', 'uncertain']
const REMEDIATION_CONTRACT =
  `Remediation is NOT implemented by falsify.sh or the mif-rh-cli engine (verified: zero "quarantine" hits across ` +
  `harness_falsify.rs/main.rs) — apply it yourself, by the verdict falsify.sh just wrote:\n` +
  `- falsified: QUARANTINE. mkdir -p ${RDIR}/quarantine and mv the finding file there. It leaves the active ` +
  `${RDIR}/findings/ set; downstream synthesis never sees it again.\n` +
  `- weakened: DOWNGRADE one rung down the real provenance.trustLevel ladder ${JSON.stringify(TRUST_LADDER)} ` +
  `(a finding already at 'uncertain' is quarantined instead, same as falsified). Lower provenance.confidence ` +
  `proportionally if present. Append the fixture's disconfirming URLs to citations[] as FULL schemas/mif/citation.schema.json ` +
  `Citation objects — every appended entry MUST carry ALL of: "@type": "Citation" (literal); "citationType", one of ` +
  `THIS standard enum: article, book, paper, website, documentation, repository, video, podcast, specification, ` +
  `dataset, tool, other (the schema also accepts a custom "namespace:value" pattern, but remediation writes must ` +
  `always use one of the standard values above for determinism — NEVER "web", "source-code", "reference", or ` +
  `"verification", none of which are in the standard enum and each has shipped in practice; pick "website" for a ` +
  `bare disconfirming URL unless a more specific standard type clearly applies); "citationRole", one of THIS ` +
  `standard enum: supports, refutes, background, methodology, ` +
  `contradicts, extends, derived, source, example, review (a disconfirming source's role is ALWAYS "refutes" — ` +
  `NEVER "disconfirms", "disconfirming", "counter-evidence", or "disconfirms-qualifier", none of which are in the ` +
  `enum and each has shipped in practice); "title", a non-empty string (the schema requires it — derive one from ` +
  `the URL or the disconfirming source's actual page title if the fixture did not already supply one; never emit ` +
  `a citation without it); and "url". "accessed" (schema format:date — a bare YYYY-MM-DD calendar date, NEVER ` +
  `a full date-time) is optional but should be set to the DATE PORTION (the leading YYYY-MM-DD only) of the ` +
  `fixture's attempted_at TIMESTAMP when present — never copy attempted_at's full ISO-8601 timestamp into ` +
  `accessed, which fails the date-format constraint the same way the enum/title violations above do. ` +
  `Append a BOUNDED qualifier to ` +
  `summary: schemas/mif/mif.schema.json caps summary at maxLength:500 (a vendored MIF Level-3 constraint, never ` +
  `raised here) — cap the qualifier text itself at 160 chars first (truncate the verdict_basis text it wraps, not ` +
  `the fixed template around it, if it runs long: ' [Falsification note: {basis}]'), THEN truncate the ORIGINAL ` +
  `summary to whatever budget remains under 500, THEN append the qualifier. Do this mutation with Python ` +
  `(json.load, mutate the dict, re-emit with lib/harness_models/'s emit.write for deterministic canonical JSON) — ` +
  `not jq -n or a heredoc: composing the appended citations[]/summary text that way breaks under the Bash eval ` +
  `wrapper's quoting on its own quotes and parentheses. SCOPE THE MUTATION STRICTLY: touch ONLY citations[], ` +
  `summary, provenance.trustLevel, and provenance.confidence — load the full dict, mutate exactly those paths, and ` +
  `re-emit every other top-level field (temporal, modified, created, extensions, etc.) with its VALUE unchanged ` +
  `(emit.write's canonical serialization may still shift incidental bytes like whitespace or key order — that is ` +
  `fine and expected; no field's VALUE may be dropped, nulled, or altered); ` +
  `never let this step touch, drop, or null out a field it was not told to change.\n` +
  `- survived / inconclusive: ANNOTATE ONLY — no file mutation beyond the verification block falsify.sh already wrote.\n` +
  `After any falsified/weakened mutation, re-validate the finding against schemas/findings.schema.json with the ` +
  `full mif/ ref closure (schemas/mif/mif.schema.json + schemas/mif/definitions/entity-reference.schema.json) — ` +
  `RUN THE ACTUAL ajv command yourself and read its ACTUAL exit code and output; do not assume it passed. A ` +
  `maxLength, enum, or structural violation MUST be caught and fixed HERE, before moving on — never deferred to ` +
  `reconcile-session.sh or left for a later pass to discover.`

phase('Enumerate')
const scopeDesc =
  typeof SCOPE === 'string'
    ? SCOPE.startsWith('dimension:')
      ? `findings whose extensions.harness.dimension == "${SCOPE.slice('dimension:'.length)}"`
      : 'every active finding'
    : `exactly these findings, given by ${SCOPE.paths ? 'file path' : '@id'}: ${JSON.stringify(SCOPE.paths || SCOPE.ids)}`
const ENUM_BRIEF_TAIL =
  `For each included finding return path, @id, dimension pin, and a one-sentence summary of its core claim. ` +
  `Separately, derive allFindingIds MECHANICALLY: run \`find ${RDIR}/findings -maxdepth 1 -name '*.json' | sort\` ` +
  `(quarantine/ and archive/ are subdirectories one level down, so -maxdepth 1 already excludes them) and read each ` +
  `@id from its file — do NOT re-derive allFindingIds from the same reasoning that produced workingSet; it must be a ` +
  `plain on-disk listing, independent of your inclusion/exclusion judgment, so it can catch a mistake in that judgment.`
let enumerated = await agent(
  `Enumerate the falsification working set under ${RDIR}/findings/ (quarantine/ and archive/ siblings are excluded). Scope: ${scopeDesc}. ` +
    (REGATE
      ? `RE-GATE MODE (stale findings re-opened by a goal-version change): include the scoped findings even when they carry extensions.harness.verification.attempted_at; skippedAlreadyVerifiedIds should be empty. `
      : `Enforce the one-round rule structurally: EXCLUDE any finding already carrying extensions.harness.verification.attempted_at from workingSet, and instead list its @id in skippedAlreadyVerifiedIds. `) +
    ENUM_BRIEF_TAIL,
  { label: 'falsify:enumerate', model: 'haiku', effort: 'low', schema: ENUM_SCHEMA },
)
if (!enumerated) throw new Error('research-falsify: enumeration failed')

// #625 reconciliation: deterministic set-equality check in code (the same
// idiom as mergeVotes()/claimBudget above — verdict/budget arithmetic never
// left to a model's own judgment). Every id the mechanical find|sort listing
// reports MUST appear in exactly one of workingSet or skippedAlreadyVerifiedIds;
// if the SAME agent turn's own classification silently dropped one, this
// catches it instead of proceeding to gate a partial working set.
//
// This only applies to scope:'all' — the exact scope #625 is about. allFindingIds
// is EVERY on-disk finding (mechanical find|sort, deliberately scope-independent),
// so the "every id must be covered by workingSet ∪ skippedAlreadyVerifiedIds"
// invariant holds ONLY when the working set is meant to span the whole corpus.
// Under a narrower scope (dimension:*, or an explicit paths/ids set, including
// regate) the working set is intentionally a subset, so out-of-scope on-disk
// findings sit in neither list legitimately; reconciling them against
// allFindingIds would falsely flag them and turn a wasted retry into a hard
// throw. An explicit paths/ids scope carries no #625-class enumeration-drop
// risk anyway — the caller named the exact set to gate.
function reconcileEnumeration(e) {
  const covered = new Set([...(e.workingSet || []).map((f) => f.id), ...(e.skippedAlreadyVerifiedIds || [])])
  return (e.allFindingIds || []).filter((id) => !covered.has(id))
}
let missing = SCOPE === 'all' ? reconcileEnumeration(enumerated) : []
if (missing.length) {
  log(`Enumerate reconciliation mismatch: ${missing.length} on-disk finding id(s) missing from BOTH workingSet and skippedAlreadyVerifiedIds — retrying once, naming them explicitly: ${JSON.stringify(missing)}`)
  const retried = await agent(
    `RETRY (research-falsify enumeration reconciliation, #625): your previous enumeration under ${RDIR}/findings/ missed ` +
      `${missing.length} finding id(s) that exist on disk (per \`find ${RDIR}/findings -maxdepth 1 -name '*.json' | sort\`) ` +
      `but were absent from BOTH workingSet and skippedAlreadyVerifiedIds: ${JSON.stringify(missing)}. Scope: ${scopeDesc}. ` +
      (REGATE
        ? `RE-GATE MODE still applies: include scoped findings even with extensions.harness.verification.attempted_at; skippedAlreadyVerifiedIds should stay empty. `
        : `The one-round rule still applies: EXCLUDE any finding already carrying extensions.harness.verification.attempted_at from workingSet, listing its @id in skippedAlreadyVerifiedIds instead. `) +
      `Re-enumerate from scratch and this time account for EVERY missing id above by placing it in exactly one of workingSet or skippedAlreadyVerifiedIds — do not omit any of them. ` +
      ENUM_BRIEF_TAIL +
      ` Return the FULL corrected workingSet, skippedAlreadyVerifiedIds, and allFindingIds — not just the previously-missing id(s).`,
    { label: 'falsify:enumerate-retry', model: 'haiku', effort: 'low', schema: ENUM_SCHEMA },
  )
  if (!retried) throw new Error('research-falsify: enumeration reconciliation retry failed')
  enumerated = retried
  missing = reconcileEnumeration(enumerated)
  if (missing.length) {
    throw new Error(
      `research-falsify: enumeration still did not account for ${missing.length} on-disk finding id(s) after one retry — ` +
        `refusing to silently gate a partial working set (this is the exact failure class reported in #625: scope:'all' ` +
        `silently skipping a pre-existing finding across gate attempts). Missing: ${JSON.stringify(missing)}. Investigate ` +
        `${RDIR}/findings/ manually rather than re-running blindly.`,
    )
  }
  log(`Enumerate reconciliation retry succeeded: all ${enumerated.allFindingIds.length} on-disk finding id(s) now accounted for.`)
}

// Review follow-up (#625 PR, Copilot): RE-GATE mode's contract is that
// skippedAlreadyVerifiedIds stays empty — regate exists specifically to
// re-open verification even for findings that already carry
// extensions.harness.verification.attempted_at (see the REGATE branch of the
// enumeration prompt above), so anything the enumeration agent placed in
// skippedAlreadyVerifiedIds instead would silently escape re-gating. Enforce
// this deterministically rather than trusting the agent's own compliance
// with the prompt wording — the same "verdict/budget arithmetic never left
// to a model's own judgment" idiom as reconcileEnumeration() above.
if (REGATE && enumerated.skippedAlreadyVerifiedIds && enumerated.skippedAlreadyVerifiedIds.length) {
  throw new Error(
    `research-falsify: RE-GATE mode requires skippedAlreadyVerifiedIds to be empty (regate re-opens verification ` +
      `even for findings that already carry extensions.harness.verification.attempted_at), but enumeration ` +
      `returned ${enumerated.skippedAlreadyVerifiedIds.length} id(s) in it: ` +
      `${JSON.stringify(enumerated.skippedAlreadyVerifiedIds)}. This means the enumeration agent treated ` +
      `already-verified findings as covered instead of re-opening them — investigate rather than silently ` +
      `dropping them from the re-gate working set.`,
  )
}

let working = enumerated.workingSet
let deferred = []
if (working.length > CLAIM_BUDGET) {
  deferred = working.slice(CLAIM_BUDGET).map((f) => f.id)
  working = working.slice(0, CLAIM_BUDGET)
  log(`Working set ${enumerated.workingSet.length} exceeds claim budget ${CLAIM_BUDGET}: gating the first ${CLAIM_BUDGET} now, DEFERRING ${deferred.length} (returned in deferredIds — re-run to continue; nothing is silently dropped)`)
}
log(`Gating ${working.length} finding(s); ${enumerated.skippedAlreadyVerifiedIds.length} already verified (one-round rule)`)
if (!working.length) return { gated: 0, deferredIds: deferred, rollup: {}, alreadyVerified: enumerated.skippedAlreadyVerifiedIds.length }

phase('Gate')
// #738: open the gate window and acquire the topic run lock BEFORE any
// finding write — see the LOCK_ACQUIRE_SCHEMA comment above for why this
// module must do this itself rather than assume some other caller already
// did. A failed acquisition (a live orchestrator run, or another /falsify,
// already owns this topic) must stop this Gate phase entirely, not proceed
// to write anyway — that is the exact concurrent-writer corruption
// scripts/run-lock.sh's own header documents as a real prior incident.
const lockAcquired = await agent(
  `Open the falsification gate window and acquire the topic run lock BEFORE any finding write, harness ${H}, topic dir ${RDIR}. ` +
    `Run exactly: bash ${H}/scripts/run-lock.sh acquire ${RDIR} research-falsify — capture its stdout (the printed ownership token) VERBATIM, nothing appended or trimmed. ` +
    `If that command exits nonzero (a live run — the orchestrator, or another /falsify — already owns this topic), report ok=false and put its stderr message in error; do NOT touch ${RDIR}/.gate-active and do NOT proceed further. ` +
    `If it exits 0, THEN run: touch ${RDIR}/.gate-active — this opens the window scripts/falsify.sh requires (SPEC §6b) for every reports/<topic>/findings/*.json write this Gate phase is about to make — and report ok=true, token=<the exact captured token, verbatim>.`,
  { label: 'falsify:lock-acquire', phase: 'Gate', model: 'haiku', effort: 'low', schema: LOCK_ACQUIRE_SCHEMA },
)
if (!lockAcquired || !lockAcquired.ok) {
  throw new Error(
    `research-falsify: could not acquire the topic run lock / open the gate window for ${RDIR}` +
      `${lockAcquired && lockAcquired.error ? ` (${lockAcquired.error})` : ''} — refusing to write any finding through ` +
      `falsify.sh while a live run may already own this topic (a second concurrent writer on the shared findings/ ` +
      `directory is the exact documented concurrency-corruption failure scripts/run-lock.sh's own header describes).`,
  )
}
// LOCK_ACQUIRE_SCHEMA only requires `ok`, not `token` (an ok=false response
// legitimately carries no token) — so an ok=true response that accidentally
// omits it still passes schema validation and LOCK_TOKEN would silently
// become undefined, making every later refresh/release call below run
// against an empty token (refresh hard-fails; release may silently no-op),
// leaving the topic lock/gate window in a bad state. Guard explicitly rather
// than trusting the schema alone.
if (!lockAcquired.token) {
  throw new Error(
    `research-falsify: lock acquisition for ${RDIR} reported ok=true but returned no token — refusing to proceed ` +
      `with an empty lock token (every subsequent refresh/release call would silently operate against an unowned lock).`,
  )
}
const LOCK_TOKEN = lockAcquired.token

let gated
try {
gated = await pipeline(
  working,
  (f) =>
    agent(
      `Decompose this research finding into its atomic, independently checkable claims (typically 1-5; never more than ${QUERY_BUDGET}). Read ${f.path} (harness ${H}). Core claim: ${f.claimSummary}. Return only the claim list.`,
      { label: `decompose:${f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: DECOMPOSE_SCHEMA },
    ),
  (dec, f) =>
    dec
      ? parallel(
          LENSES.map((lens) => () =>
            agent(
              `ADVERSARIAL FALSIFICATION — lens: ${lens.key}. ${lens.brief}\n` +
                `Finding under test: ${f.path} (read it). Atomic claims:\n${dec.claims.map((c) => `- ${c}`).join('\n')}\n` +
                `Query budget: at most ${QUERY_BUDGET} disconfirming queries per claim.\n` +
                `WEB-ONLY constraint: evidence comes ONLY from WebSearch/WebFetch — never from prior findings, internal memory, or any blackboard; the point is independent disconfirmation.\n` +
                `Helpfulness-bias warning: you are trained to confirm framings — resist it; read each claim for what could make it FALSE. Absence of disconfirming evidence is bounded epistemics, not proof: that is 'survived', never 'proven'.\n` +
                `Verdict scale: falsified (disconfirming evidence found) | weakened (partial/contextual disconfirmation) | survived (genuine disconfirmation attempts failed) | inconclusive (could not adequately test). Return the per-claim table, one overall verdict for this lens, and sources: the URLs you actually retrieved that are disconfirming, weakening, or a credible alternative explanation (never fabricated, empty array if none).`,
              { label: `lens:${lens.key}:${f.id.slice(-8)}`, phase: 'Gate', model: 'sonnet', schema: LENS_SCHEMA },
            ),
          ),
        ).then((lensResults) => ({ f, dec, lensResults: pairLensResults(LENSES, lensResults) }))
      : null,
  async (g) => {
    if (!g || !g.lensResults.length) return null
    // #738: refresh the lock/gate before ANY mutation this finding makes —
    // the regate-reset jq mutation below (when REGATE) and the falsify.sh
    // write further down are both a mutation of the shared topic findings/,
    // so both must happen only while this run still genuinely owns the lock
    // and the window is still fresh. A nonzero refresh means another run
    // stole the lock (or it aged out) — that is fatal, never a warning to
    // log and keep writing under a false assumption of exclusive access
    // (scripts/run-lock.sh's own refresh contract).
    const lockFresh = await agent(
      `Refresh this topic's run lock and gate window before writing finding ${g.f.id} (harness ${H}, topic dir ${RDIR}, token ${LOCK_TOKEN}). ` +
        `Run: bash ${H}/scripts/run-lock.sh refresh ${RDIR} ${LOCK_TOKEN} — if it exits nonzero, this run LOST ownership of the topic (another run stole it, or it aged out); report ok=false and STOP, do not write anything for this finding. ` +
        `If it exits 0, ALSO run: touch ${RDIR}/.gate-active — to keep the gate window fresh — and report ok=true.`,
      { label: `lock-refresh:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: LOCK_STATUS_SCHEMA },
    )
    if (!lockFresh || !lockFresh.ok) {
      throw new Error(
        `research-falsify: #738 — lost ownership of the run lock/gate for ${RDIR} while gating ${g.f.id} — stopping ` +
          `rather than write under a false assumption of exclusive access (scripts/run-lock.sh's own refresh contract: ` +
          `a lost lock is fatal, never a warning to log and continue).`,
      )
    }
    const votes = g.lensResults.map((r) => r.verdict)
    let { verdict, contested } = mergeVotes(votes)
    let basis = g.lensResults.map((r) => `[${r.lensKey}:${r.verdict}] ${r.basis}`).join(' | ')
    if (contested) {
      const adj = await agent(
        `Adjudicate a CONTESTED falsification verdict. Finding: ${g.f.path} (read it). Lens votes disagree:\n` +
          g.lensResults.map((r) => `- ${r.lensKey}: ${r.verdict} — ${r.basis}`).join('\n') +
          `\nWeigh the evidence quality (not the vote count): a single well-sourced disconfirmation outweighs two absent-evidence survivals. Return the final ordinal verdict and a one-paragraph basis.`,
        { label: `adjudicate:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'opus', effort: 'high', schema: { type: 'object', properties: { verdict: { type: 'string', enum: ['falsified', 'weakened', 'survived', 'inconclusive'] }, basis: { type: 'string' } }, required: ['verdict', 'basis'] } },
      )
      if (adj) { verdict = adj.verdict; basis = `[adjudicated] ${adj.basis}` }
      else { verdict = 'inconclusive' }
    }
    // Gap 2 (see module header): REGATE has no engine override — falsify.sh's
    // already_graded() short-circuit is unconditional — so a stale finding's
    // verification block is cleared client-side, HERE, before falsify.sh
    // ever runs. The actual verdict write below still routes exclusively
    // through falsify.sh; only the pre-condition it checks is reset.
    if (REGATE) {
      await agent(
        `RE-GATE client-side reset. Finding ${g.f.path} (harness ${H}) is being re-opened for verification after a ` +
          `goal-version pivot/update classified it stale. falsify.sh's one-round check is unconditional with no ` +
          `override flag, so clear the stale block yourself: jq 'del(.extensions.harness.verification)' on the ` +
          `finding file (write to a temp file, then mv over the original — never edit in place with -i), then ` +
          `re-validate against schemas/findings.schema.json with the full mif/ ref closure. After this reset the ` +
          `finding carries no attempted_at, so the falsify.sh invocation that follows performs a genuine write, not ` +
          `a one-round-rule skip.`,
        { label: `regate-reset:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low' },
      )
    }
    // Gap 1 (see module header): the fixture is built in code, from the
    // verdict/basis/sources already computed above — the write agent's job
    // is purely mechanical (mktemp, write this exact content, invoke
    // falsify.sh, clean up), not composing the fixture itself.
    //
    // #618: fail loudly HERE, right where a real timestamp first becomes
    // necessary — not at module top level (an empty working set legitimately
    // never reaches this line) and never by silently falling back to a
    // computed-in-script Date, which is exactly the crash this guards.
    if (!RUN_DATE) {
      throw new Error(
        'research-falsify: args.runDate is required once a finding needs gating — new Date()/Date.now() are ' +
          'disallowed inside Workflow-runtime scripts (breaks resume determinism; see #618). The caller must ' +
          'supply a stamped ISO-8601 timestamp from OUTSIDE the runtime (research-pipeline.js forwards ' +
          "args.runDate from the /research command's own `date` invocation).",
      )
    }
    const fixture = buildFixtureEntry(g.f.id, verdict, basis, g.lensResults, RUN_DATE)
    const fixtureJson = JSON.stringify(fixture)
    const writeBrief =
      `Write a falsification verdict through the deterministic substrate, harness ${H}. The evidence fixture is ` +
      `ALREADY COMPUTED (deterministic verdict arithmetic in code) — write it VERBATIM, do not alter or re-derive ` +
      `it: mktemp a file OUTSIDE the repo tree (e.g. $(mktemp)), write exactly this JSON as its content: ` +
      `${fixtureJson}\n` +
      `Then invoke: bash ${H}/scripts/falsify.sh ${g.f.path} <fixture-path> — redirect its stdout to a temp file ` +
      `and mv it over ${g.f.path} (write-validate atomicity: re-validate against ${H}/schemas/findings.schema.json ` +
      `with the full mif/ ref closure before considering the write done). Remove the mktemp fixture file when ` +
      `finished (it is ephemeral, never committed).\n` +
      `${REMEDIATION_CONTRACT}\n` +
      (REGATE
        ? `This is a RE-GATE (the stale verification block was already reset client-side above) — the write above ` +
          `should succeed genuinely, not skip under the one-round rule. If it still reports a skip, report ` +
          `remediation="skipped-one-round" and do NOT hand-edit the verification block around it.\n`
        : '') +
      // #659: falsify.sh (via mif-rh-cli) has been observed to write verdict +
      // verdict_basis but silently drop attempted_at on a genuine write — the
      // agent's own "written: true" is not proof of that; require an actual
      // read-back this turn before reporting attemptedAtPresent.
      `#659 CHECK (required): after the mv+re-validate above, read ${g.f.path} back off disk THIS turn (e.g. ` +
      `jq -r '.extensions.harness.verification.attempted_at' ${g.f.path}) and report attemptedAtPresent=true only if ` +
      `that value is a genuine, present, non-null string you just observed — never report true from assumption or ` +
      `from the fixture you wrote, only from what the file actually contains after falsify.sh ran. If remediation is ` +
      `"skipped-one-round" (no genuine write occurred), report attemptedAtPresent=false regardless — this field is ` +
      `about a GENUINE write, not the one-round-rule skip path.`
    let written = await agent(writeBrief, { label: `write:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: WRITE_SCHEMA })
    // #747: a genuine written=false (or a missing/malformed report) is not a
    // data point to fold into the returned verdict — it means falsify.sh
    // never persisted anything to disk for this finding, so the verdict/
    // basis computed above cannot be trusted as gated. Before this fix,
    // execution fell straight through to the `return` below regardless of
    // `written.written`, which still attached the full verdict to the
    // returned object; Rollup's `gated: done.length` then counted this
    // finding as gated even though nothing was written, and the next
    // Enumerate step silently rediscovered the same still-ungated finding
    // and repeated the identical doomed write, burning budget with no
    // surfaced signal. Retry once (the agent may have hit a transient
    // mktemp/falsify.sh/mv failure), then fail loudly — the same idiom the
    // #659 check just below already uses for a different half-completed-
    // write shape.
    if (!written || !written.written) {
      const retriedWrite = await agent(
        `RETRY (research-falsify write failure, #747): the previous attempt to write finding ${g.f.id} ` +
          `(${g.f.path}) through falsify.sh reported written=${written ? written.written : 'undefined'} — the write ` +
          `did not complete. Re-invoke the write EXACTLY as before: mktemp a file OUTSIDE the repo tree, write this ` +
          `exact fixture JSON verbatim: ${fixtureJson}\n` +
          `then invoke bash ${H}/scripts/falsify.sh ${g.f.path} <fixture-path>, redirect its stdout to a temp file, ` +
          `mv it over ${g.f.path} (re-validate against ${H}/schemas/findings.schema.json with the full mif/ ref ` +
          `closure before considering the write done), and remove the mktemp fixture file.\n${REMEDIATION_CONTRACT}\n` +
          `Report written=true only if the mv+re-validate genuinely completed THIS turn — never from assumption.`,
        { label: `write-retry-failed:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: WRITE_SCHEMA },
      )
      if (!retriedWrite || !retriedWrite.written) {
        throw new Error(
          `research-falsify: #747 — finding ${g.f.id} (${g.f.path}) did not complete a falsify.sh write (written=` +
            `${retriedWrite ? retriedWrite.written : 'undefined'}) after one retry. Refusing to silently count this ` +
            `finding as gated — the verdict/basis computed this round was never persisted to disk, so treating it as ` +
            `gated would report false progress (a compromised round) and mask the real write-path failure. Investigate ` +
            `the write path (mktemp/falsify.sh/mv/re-validate) manually rather than proceeding; ${g.f.id} will remain ` +
            `unverified and get rediscovered by the next Enumerate step until this is fixed.`,
        )
      }
      written = retriedWrite
    }
    // Deterministic post-write assertion (#659): verdict/write-completeness is
    // never left to a model's own self-report, the same idiom as
    // mergeVotes()/reconcileEnumeration() above. A genuine (non-one-round-
    // rule-skipped) write that didn't confirm attempted_at present is exactly
    // the silent-drop defect #659 reported — retry once with the concrete
    // read-back instruction, then fail loudly rather than silently accepting a
    // partial write (a finding with a real verdict but no attempted_at reads
    // as still-needing-gating to the one-round rule and fails the harness's
    // verification_verdicts_present completion check).
    if (written && written.written && written.remediation !== 'skipped-one-round' && !written.attemptedAtPresent) {
      const retried = await agent(
        `RETRY (research-falsify write assertion, #659): the previous write to ${g.f.path} reported written=${written.written} ` +
          `remediation=${written.remediation}, but did NOT confirm extensions.harness.verification.attempted_at is present ` +
          `in the finding file after invoking falsify.sh — this is the exact silent-drop defect #659 reported (verdict + ` +
          `verdict_basis written, attempted_at missing). Re-read ${g.f.path} now (harness ${H}) and check ` +
          `extensions.harness.verification.attempted_at: if it is genuinely present (a non-null string), the earlier ` +
          `write was fine and this was only a reporting miss — report written=true, remediation="${written.remediation}", ` +
          `attemptedAtPresent=true. If it is genuinely absent, re-invoke the write exactly as before (mktemp the SAME ` +
          `fixture JSON verbatim: ${fixtureJson}, then bash ${H}/scripts/falsify.sh ${g.f.path} <fixture-path>, redirect ` +
          `stdout, mv over ${g.f.path}, re-validate against ${H}/schemas/findings.schema.json with the full mif/ ref ` +
          `closure), THEN read the file back again and report the real result — never report attemptedAtPresent=true ` +
          `without having actually read it back from disk this turn.`,
        { label: `write-retry:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: WRITE_SCHEMA },
      )
      if (!retried || !retried.written || (retried.remediation !== 'skipped-one-round' && !retried.attemptedAtPresent)) {
        const retryWriteFailed = !retried || !retried.written
        throw new Error(
          `research-falsify: #659 — finding ${g.f.id} (${g.f.path}) ` +
            (retryWriteFailed
              ? `did not complete a write on retry (written=${retried ? retried.written : 'undefined'}) — the ` +
                `re-invoked falsify.sh write itself failed, so no attempted_at could have been confirmed.`
              : `completed a genuine (non-one-round-rule-skipped) falsify.sh write but ` +
                `extensions.harness.verification.attempted_at is still not confirmed present after one retry.`) +
            ` Refusing to silently accept a partial write (verdict/verdict_basis written, attempted_at dropped) — ` +
            `this is the exact intermittent engine-level drop #659 reported. Investigate ${g.f.path} manually rather ` +
            `than proceeding: a finding with a real verdict but no attempted_at reads as still-needing-gating to the ` +
            `one-round rule (wasting the adversarial work already done on a re-run) and fails the harness's ` +
            `verification_verdicts_present completion check.`,
        )
      }
      written = retried
    }
    // written is guaranteed non-null with written.written === true here (the
    // #747 check above throws rather than falling through on a genuine write
    // failure) — the `written ? ... : 'write-failed'` fallback that used to
    // sit here was the bug itself: it let a write-failed finding still
    // return a fully-populated verdict object instead of never reaching this
    // line at all.
    return { id: g.f.id, dimension: g.f.dimension, verdict, contested, remediation: written.remediation }
  },
)
} finally {
  // #738: release the topic run lock and close the gate window on EVERY exit
  // path — the pipeline() call above completing normally, or a per-finding
  // throw (#747/#659, or the lock-refresh loss below) propagating out of it —
  // mirroring falsify.md's own "release the lock on EVERY exit path" Phase 2
  // contract. This cleanup call is best-effort: the agent() invocation itself
  // (a live model call over an untrusted shell command) can still throw or
  // reject, and if it did so uncaught here it would replace whatever error
  // (if any) is already propagating out of the try block above — the exact
  // failure mode this comment used to only assert away rather than actually
  // prevent. Catch and log instead, so cleanup failure is visible but never
  // masks the real gating error.
  try {
    await agent(
      `Close the falsification gate window and release the topic run lock for ${RDIR} (harness ${H}, token ${LOCK_TOKEN}) — ` +
        `this runs on every exit path, success or failure. Run: rm -f ${RDIR}/.gate-active ${RDIR}/.gate-batch; then ` +
        `bash ${H}/scripts/run-lock.sh release ${RDIR} ${LOCK_TOKEN}. Report ok=true once both commands have been run, ` +
        `regardless of either command's own exit code (this is best-effort cleanup, never a reason to throw further).`,
      { label: 'falsify:lock-release', phase: 'Gate', model: 'haiku', effort: 'low', schema: LOCK_STATUS_SCHEMA },
    )
  } catch (cleanupErr) {
    log(
      `research-falsify: WARNING — lock-release cleanup for ${RDIR} (token ${LOCK_TOKEN}) itself failed/threw: ` +
        `${cleanupErr && cleanupErr.message ? cleanupErr.message : cleanupErr}. The topic lock/gate window may still ` +
        `be held; manual cleanup (rm -f ${RDIR}/.gate-active ${RDIR}/.gate-batch; bash ${H}/scripts/run-lock.sh release ${RDIR} ${LOCK_TOKEN}) ` +
        `may be required. Not rethrown so any real gating error already propagating out of the try block above is preserved.`,
    )
  }
}

phase('Rollup')
const done = gated.filter(Boolean)
const rollup = {}
for (const g of done) rollup[g.verdict] = (rollup[g.verdict] || 0) + 1
log(`Falsification rollup: ${JSON.stringify(rollup)}; ${done.filter((g) => g.contested).length} adjudicated; ${deferred.length} deferred`)
return {
  gated: done.length,
  rollup,
  verdicts: done,
  deferredIds: deferred,
  alreadyVerified: enumerated.skippedAlreadyVerifiedIds.length,
}
