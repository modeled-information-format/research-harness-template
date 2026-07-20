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
    { title: 'Rollup' },
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
const WRITE_SCHEMA = {
  type: 'object',
  properties: {
    written: { type: 'boolean' },
    remediation: { type: 'string', description: 'quarantined | downgraded | annotated | skipped-one-round | write-failed' },
  },
  required: ['written', 'remediation'],
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
const gated = await pipeline(
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
        ).then((lensResults) => ({ f, dec, lensResults: lensResults.filter(Boolean) }))
      : null,
  async (g) => {
    if (!g || !g.lensResults.length) return null
    const votes = g.lensResults.map((r) => r.verdict)
    let { verdict, contested } = mergeVotes(votes)
    let basis = g.lensResults.map((r, i) => `[${LENSES[i] ? LENSES[i].key : 'lens'}:${r.verdict}] ${r.basis}`).join(' | ')
    if (contested) {
      const adj = await agent(
        `Adjudicate a CONTESTED falsification verdict. Finding: ${g.f.path} (read it). Lens votes disagree:\n` +
          g.lensResults.map((r, i) => `- ${LENSES[i] ? LENSES[i].key : 'lens'}: ${r.verdict} — ${r.basis}`).join('\n') +
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
    const written = await agent(
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
            `remediation="skipped-one-round" and do NOT hand-edit the verification block around it.`
          : ''),
      { label: `write:${g.f.id.slice(-8)}`, phase: 'Gate', model: 'haiku', effort: 'low', schema: WRITE_SCHEMA },
    )
    return { id: g.f.id, dimension: g.f.dimension, verdict, contested, remediation: written ? written.remediation : 'write-failed' }
  },
)

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
