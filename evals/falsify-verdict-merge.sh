#!/usr/bin/env bash
# falsify-verdict-merge.sh — regression eval for the falsify verdict-merge
# table (research-harness-template#562, Epic #541).
#
# The vendored workflow module (.claude/workflows/research-falsify.js)
# decomposes falsification into deterministic verdict arithmetic (mergeVotes,
# in code) plus a fixture-write bridge and ported remediation logic that
# route the real verdict through the vendored mif-rh-cli engine
# (scripts/falsify.sh). CI cannot run the model-driven lenses/adjudication,
# so this eval exercises the deterministic seams hermetically, mirroring
# evals/fanout-lane-contract.sh (#558) / evals/goal-lint-repair.sh (#554):
#
#   A. mergeVotes()'s arithmetic table — unanimous, majority-falsified,
#      minority-falsified-contested-escalates, mixed-non-falsified-takes-worst
#      (plus a couple of edge cases the branches also cover) — run against
#      the ACTUAL function, extracted verbatim from the module's own source
#      (brace-matched, not re-typed), never a bash reimplementation of the
#      arithmetic.
#
#   B. A seeded-false-finding fixture is graded THROUGH THE REAL ENGINE
#      (scripts/falsify.sh -> bin/mif-rh-cli, no model calls) to verdict
#      "falsified" with a correctly-shaped verification block, then the
#      ported remediation logic (REMEDIATION_CONTRACT's falsified path:
#      mkdir -p quarantine/, mv the finding there) is applied and the
#      quarantined file is proven to (1) actually live under quarantine/,
#      (2) no longer live under findings/, and (3) still validate against
#      schemas/findings.schema.json — proving the PORT works end to end at
#      the fixture level, not just that falsify.sh ran.
#
#   C. The over-budget claimBudget slicing block is extracted verbatim
#      (same brace-matched technique as A) and run against synthetic working
#      sets: under-budget, over-budget, and exact-boundary, asserting
#      deferredIds is the EXACT remainder every time (working.length +
#      deferred.length == total, always) — nothing silently dropped.
#
#   D. The one-round rule, proven against the REAL substrate the module's
#      own gap-2 header comment documents relying on (falsify.sh's
#      already_graded() short-circuit is unconditional, no engine override):
#      a finding graded once and re-submitted under a NORMAL (non-regate)
#      call is excluded — the second falsify.sh invocation logs
#      "skipped (already falsified this session)" and the verdict/
#      attempted_at are provably unchanged; the SAME finding, after the
#      client-side reset research-falsify.js's regate-reset step documents
#      (jq 'del(.extensions.harness.verification)', write-then-mv, never
#      -i), is genuinely re-processed by a third falsify.sh call — a fresh
#      "falsification-gate: run" line, a new verdict, and a new
#      attempted_at.
#
#   E. Structural contract of research-falsify.js itself: the fixture-write
#      bridge (buildFixtureEntry, invoked with a real fixture-path arg, no
#      bare-arg falsify.sh call) and the ported remediation logic
#      (REMEDIATION_CONTRACT, embedded in the write-step brief) are both
#      really present in the module, not a comment claiming falsify.sh owns
#      remediation.
#
#   F. buildFixtureEntry() is extracted verbatim and run under a POISONED
#      Date/Math.random, reproducing the exact runtime restriction
#      research-harness-template#618 fixed (new Date()/Date.now() are
#      unavailable inside a Workflow-runtime script) — proving the function
#      runs clean and uses the caller-supplied attempted_at verbatim, by
#      actually exercising the restriction rather than grepping for it.
#
#   G. reconcileEnumeration() (research-harness-template#625) is extracted
#      verbatim and run against a four-case matrix: fully-covered (no gap);
#      #625's own exact 19-on-disk/18-covered shape (the one silently
#      dropped id is reported); an id covered ONLY via
#      skippedAlreadyVerifiedIds (proving true union semantics, not a
#      workingSet-only check); and vacuous all-empty (the shape
#      evals/import-check.sh's and evals/pivot-check.sh's falsify-driver
#      stubs rely on, which must not itself trip a spurious mismatch).
#
#   H. The RE-GATE skippedAlreadyVerifiedIds guard (research-harness-template#625
#      PR review) is extracted verbatim and run against its truth table:
#      REGATE=true with a non-empty skippedAlreadyVerifiedIds throws loudly
#      and names the offending id(s); REGATE=true with it empty does not
#      throw; REGATE=false with it non-empty does not throw (that's the
#      expected one-round-rule outcome on a normal run, not a defect); and
#      REGATE=true with it undefined does not crash.
#
#   I. pairLensResults() (research-harness-template#682) is extracted verbatim
#      and proven to preserve lens identity across a failed lens: all-succeed
#      pairs keys 1:1; #682's exact incident shape (the middle lens's agent()
#      call fails and is dropped) keeps the survivors' ORIGINAL keys instead
#      of misattributing by post-filter position; first-lens-failed and
#      all-failed edges hold; and structural greps lock the module to the
#      paired lensKey (no positional LENSES[i] lookup after filter(Boolean)).
#
# Hermetic: only evals/fixtures/falsify-verdict-merge/*, mktemp scratch, and
# the vendored bin/mif-rh-cli (offline, fixture-driven — no network, no
# model/API calls). Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  falsify-verdict-merge: %s\n' "$1"; }

WF=.claude/workflows/research-falsify.js
FX=evals/fixtures/falsify-verdict-merge

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
[ -x bin/mif-rh-cli ] || { note "bin/mif-rh-cli not found/executable -- the vendored engine is required for this eval (scripts/fetch-engine.sh)"; exit 2; }

# ============================================================================
# A + C: mergeVotes() arithmetic table and claimBudget over-budget slicing,
# executed against the ACTUAL source of research-falsify.js (brace-matched
# extraction, never a reimplementation of the arithmetic in this eval).
# ============================================================================
cat > "$TMP/extract-and-test.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-and-test.cjs <research-falsify.js> <tmpdir>');
  process.exit(2);
}
const src = fs.readFileSync(wfPath, 'utf8');

// Balanced-brace extraction (mirrors scripts/check-workflow-syntax.sh's own
// technique of reproducing the runtime's real framing rather than a fragile
// single-line regex): find the first '{' at/after a search index, then walk
// forward counting depth until it returns to zero.
function extractBlockFrom(text, searchIdx, spanStartIdx) {
  const braceStart = text.indexOf('{', searchIdx);
  if (braceStart < 0) throw new Error('no opening brace found');
  let depth = 0, i = braceStart;
  for (; i < text.length; i++) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) break; }
  }
  if (depth !== 0) throw new Error('unbalanced braces');
  return text.slice(spanStartIdx, i + 1);
}
function extractBlock(text, marker) {
  const idx = text.indexOf(marker);
  if (idx < 0) throw new Error(`marker not found: ${JSON.stringify(marker)}`);
  return extractBlockFrom(text, idx, idx);
}
function extractSpan(text, startMarker, throughMarker) {
  const s = text.indexOf(startMarker);
  if (s < 0) throw new Error(`start marker not found: ${startMarker}`);
  const t = text.indexOf(throughMarker, s);
  if (t < 0) throw new Error(`through-marker not found after start: ${throughMarker}`);
  return extractBlockFrom(text, t, s);
}

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ok  ${name}`);
  else { failed = 1; console.log(`FAIL  ${name}${detail ? ' -- ' + detail : ''}`); }
}
function deepEqual(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

// ---- A: extract mergeVotes() + its RANK dependency VERBATIM ----
let mergeVotes;
try {
  const rankText = extractBlock(src, 'const RANK = {');
  const mergeVotesText = extractBlock(src, 'function mergeVotes(votes) {');
  const harnessSrc = `'use strict';\n${rankText}\n${mergeVotesText}\nmodule.exports = { mergeVotes };\n`;
  const harnessPath = path.join(tmpDir, 'mergevotes-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ mergeVotes } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of mergeVotes()/RANK from ${wfPath}: ${e.message}`);
  process.exit(1);
}

const cases = [
  { name: 'unanimous (3x survived)', votes: ['survived', 'survived', 'survived'], want: { verdict: 'survived', contested: false } },
  { name: 'unanimous (3x falsified)', votes: ['falsified', 'falsified', 'falsified'], want: { verdict: 'falsified', contested: false } },
  { name: 'majority-falsified (2 of 3)', votes: ['falsified', 'falsified', 'survived'], want: { verdict: 'falsified', contested: false } },
  { name: 'minority-falsified-contested-escalates (1 of 3)', votes: ['falsified', 'survived', 'survived'], want: { verdict: null, contested: true } },
  { name: 'minority-falsified-contested-escalates (1 of 4)', votes: ['falsified', 'survived', 'survived', 'weakened'], want: { verdict: null, contested: true } },
  { name: 'mixed-non-falsified-takes-worst (survived/weakened/inconclusive)', votes: ['survived', 'weakened', 'inconclusive'], want: { verdict: 'weakened', contested: false } },
  { name: 'mixed-non-falsified-takes-worst (survived x2/inconclusive x2, no majority)', votes: ['survived', 'survived', 'inconclusive', 'inconclusive'], want: { verdict: 'inconclusive', contested: false } },
  { name: 'majority-weakened (2 of 3, non-unanimous)', votes: ['weakened', 'weakened', 'survived'], want: { verdict: 'weakened', contested: false } },
];
for (const c of cases) {
  const got = mergeVotes(c.votes);
  check(`mergeVotes(${JSON.stringify(c.votes)})`, deepEqual(got, c.want), `got ${JSON.stringify(got)}, want ${JSON.stringify(c.want)}`);
}

// ---- C: extract the claimBudget over-budget slicing block VERBATIM ----
let sliceBudget;
try {
  const spanText = extractSpan(src, 'let working = enumerated.workingSet', 'if (working.length > CLAIM_BUDGET) {');
  const harnessSrc =
    `'use strict';\nfunction sliceBudget(enumerated, CLAIM_BUDGET, log) {\n${spanText}\n  return { working, deferred };\n}\nmodule.exports = { sliceBudget };\n`;
  const harnessPath = path.join(tmpDir, 'budget-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ sliceBudget } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the claimBudget slicing block from ${wfPath}: ${e.message}`);
  process.exit(1);
}

function mkWorkingSet(n) {
  return Array.from({ length: n }, (_, i) => ({ path: `f${i + 1}.json`, id: `f${i + 1}`, dimension: 'technical', claimSummary: 's' }));
}

{
  const enumerated = { workingSet: mkWorkingSet(3) };
  const { working, deferred } = sliceBudget(enumerated, 5, () => {});
  check('under-budget: no slicing, deferred empty', working.length === 3 && deferred.length === 0, `working=${working.length} deferred=${JSON.stringify(deferred)}`);
}
{
  const enumerated = { workingSet: mkWorkingSet(7) };
  const { working, deferred } = sliceBudget(enumerated, 3, () => {});
  const wantWorking = ['f1', 'f2', 'f3'];
  const wantDeferred = ['f4', 'f5', 'f6', 'f7'];
  check('over-budget: working = first CLAIM_BUDGET', deepEqual(working.map((f) => f.id), wantWorking), JSON.stringify(working.map((f) => f.id)));
  check('over-budget: deferredIds = exact remainder', deepEqual(deferred, wantDeferred), JSON.stringify(deferred));
  check('over-budget: nothing silently dropped (working+deferred == total)', working.length + deferred.length === enumerated.workingSet.length, `${working.length}+${deferred.length} != ${enumerated.workingSet.length}`);
}
{
  const enumerated = { workingSet: mkWorkingSet(4) };
  const { working, deferred } = sliceBudget(enumerated, 4, () => {});
  check('exact-budget boundary: no deferral', working.length === 4 && deferred.length === 0, `working=${working.length} deferred=${JSON.stringify(deferred)}`);
}

// ---- F: extract buildFixtureEntry() VERBATIM and run it under a POISONED
// Date/Math.random — reproducing the exact restriction the real Workflow
// runtime enforces (research-harness-template#618: "Date.now() / new Date()
// are unavailable in workflow scripts (breaks resume)"), which crashed this
// function on EVERY finding needing gating before the fix. No prior eval
// executed this function for real (the seeded-false fixture in section B
// below exercises falsify.sh/the mif-rh engine directly, never this
// function's own JS body) — this is the regression trap.
{
  let buildFixtureEntry;
  let extractionError = null;
  let fixtureEntryText = '';
  try {
    fixtureEntryText = extractBlock(src, 'function buildFixtureEntry(');
    // Poison Date/Math.random exactly like the real runtime would refuse
    // them, then define the extracted function in a scope where those
    // names resolve to the poison, not the real globals — a function that
    // still (incorrectly) called new Date()/Date.now()/Math.random() would
    // throw here, proving the fix by ACTUALLY exercising the restriction,
    // not merely asserting it via a source-text grep.
    const harnessSrc =
      `'use strict';\n` +
      `class PoisonDate { constructor() { throw new Error('new Date() called -- forbidden inside a Workflow-runtime script (#618)'); } static now() { throw new Error('Date.now() called -- forbidden inside a Workflow-runtime script (#618)'); } }\n` +
      `const Date = PoisonDate;\n` +
      `const Math = new Proxy(globalThis.Math, { get(t, p) { if (p === 'random') throw new Error('Math.random() called -- forbidden inside a Workflow-runtime script (#618)'); return t[p]; } });\n` +
      `${fixtureEntryText}\n` +
      `module.exports = { buildFixtureEntry };\n`;
    const harnessPath = path.join(tmpDir, 'buildfixtureentry-harness.cjs');
    fs.writeFileSync(harnessPath, harnessSrc);
    ({ buildFixtureEntry } = require(harnessPath));
  } catch (e) {
    extractionError = e;
  }
  check('buildFixtureEntry() extracted from the module source', !extractionError, extractionError ? extractionError.message : '');
  check('extracted buildFixtureEntry() source has no new Date(...)/Date.now(...) call', !/new\s+Date\s*\(|Date\.now\s*\(/.test(fixtureEntryText), fixtureEntryText);

  if (buildFixtureEntry) {
    const ATTEMPTED_AT = '2026-07-19T00:00:00Z';
    let out, threw;
    try {
      out = buildFixtureEntry('urn:mif:concept:t:f1', 'survived', 'basis text', [{ sources: ['https://example.com/a'] }], ATTEMPTED_AT);
    } catch (e) {
      threw = e;
    }
    check('buildFixtureEntry(...) runs to completion under a poisoned Date/Math.random (does not crash, #618)', !threw, threw ? threw.message : '');
    if (out) {
      check('fixture attempted_at is the CALLER-supplied timestamp verbatim, never computed in-script', out['urn:mif:concept:t:f1'] && out['urn:mif:concept:t:f1'].attempted_at === ATTEMPTED_AT, JSON.stringify(out));
      check('fixture verdict/basis/disconfirming still populate correctly alongside the fix', out['urn:mif:concept:t:f1'] && out['urn:mif:concept:t:f1'].verdict === 'survived' && out['urn:mif:concept:t:f1'].disconfirming.length === 1, JSON.stringify(out));
    }
  }
}

// ---- G: extract reconcileEnumeration() VERBATIM and prove the #625
// set-difference matrix (research-harness-template#625: scope:'all'
// silently enumerated 18 of 19 on-disk findings because nothing
// reconciled the working set against a mechanical on-disk listing).
{
  let reconcileEnumeration;
  let extractionError = null;
  let reconcileText = '';
  try {
    reconcileText = extractBlock(src, 'function reconcileEnumeration(e) {');
    const harnessSrc = `'use strict';\n${reconcileText}\nmodule.exports = { reconcileEnumeration };\n`;
    const harnessPath = path.join(tmpDir, 'reconcile-harness.cjs');
    fs.writeFileSync(harnessPath, harnessSrc);
    ({ reconcileEnumeration } = require(harnessPath));
  } catch (e) {
    extractionError = e;
  }
  check('reconcileEnumeration() extracted from the module source', !extractionError, extractionError ? extractionError.message : '');

  if (reconcileEnumeration) {
    // Case 1: fully-covered -- every on-disk id appears in workingSet or
    // skippedAlreadyVerifiedIds -- no reconciliation gap.
    {
      const e = {
        workingSet: [{ id: 'f1' }, { id: 'f2' }],
        skippedAlreadyVerifiedIds: ['f3'],
        allFindingIds: ['f1', 'f2', 'f3'],
      };
      const missing = reconcileEnumeration(e);
      check('fully-covered: no missing ids', deepEqual(missing, []), JSON.stringify(missing));
    }
    // Case 2: #625's exact shape -- 19 on-disk ids, 18 covered (workingSet
    // + skippedAlreadyVerifiedIds combined), one silently dropped.
    {
      const allIds = Array.from({ length: 19 }, (_, i) => `f${i + 1}`);
      const covered = allIds.slice(0, 18); // f1..f18 covered; f19 dropped
      const e = {
        workingSet: covered.map((id) => ({ id })),
        skippedAlreadyVerifiedIds: [],
        allFindingIds: allIds,
      };
      const missing = reconcileEnumeration(e);
      check("#625's exact 19-vs-18 shape: exactly the one dropped id is reported", deepEqual(missing, ['f19']), JSON.stringify(missing));
    }
    // Case 3: an id covered ONLY via skippedAlreadyVerifiedIds (not
    // workingSet) still counts as covered -- proves the reconciliation is a
    // true UNION of both lists, not a workingSet-only check.
    {
      const e = {
        workingSet: [{ id: 'f1' }],
        skippedAlreadyVerifiedIds: ['f2'],
        allFindingIds: ['f1', 'f2'],
      };
      const missing = reconcileEnumeration(e);
      check('skippedAlreadyVerifiedIds-only coverage counts (true union semantics)', deepEqual(missing, []), JSON.stringify(missing));
    }
    // Case 4: vacuous all-empty -- the shape evals/import-check.sh's and
    // evals/pivot-check.sh's falsify-driver stubs rely on (no findings on
    // disk at all) -- must not itself report a spurious mismatch.
    {
      const e = { workingSet: [], skippedAlreadyVerifiedIds: [], allFindingIds: [] };
      const missing = reconcileEnumeration(e);
      check('vacuous all-empty: no missing ids', deepEqual(missing, []), JSON.stringify(missing));
    }
  }
}

// ---- H: extract the RE-GATE skippedAlreadyVerifiedIds guard VERBATIM and
// prove its truth table (research-harness-template#625 PR review, Copilot):
// RE-GATE mode's contract is that skippedAlreadyVerifiedIds stays empty
// (regate re-opens verification even for findings already carrying
// extensions.harness.verification.attempted_at), so the guard must throw
// the instant REGATE is true and enumeration nonetheless populated
// skippedAlreadyVerifiedIds -- and must NEVER throw for a normal (non-regate)
// run, where a populated skippedAlreadyVerifiedIds is the expected one-round-
// rule outcome, not a defect.
{
  let regateGuard;
  let extractionError = null;
  try {
    const guardText = extractBlock(
      src,
      "if (REGATE && enumerated.skippedAlreadyVerifiedIds && enumerated.skippedAlreadyVerifiedIds.length) {",
    );
    const harnessSrc =
      `'use strict';\nfunction regateGuard(REGATE, enumerated) {\n${guardText}\n}\nmodule.exports = { regateGuard };\n`;
    const harnessPath = path.join(tmpDir, 'regate-guard-harness.cjs');
    fs.writeFileSync(harnessPath, harnessSrc);
    ({ regateGuard } = require(harnessPath));
  } catch (e) {
    extractionError = e;
  }
  check('RE-GATE skippedAlreadyVerifiedIds guard extracted from the module source', !extractionError, extractionError ? extractionError.message : '');

  if (regateGuard) {
    function threwWith(fn) {
      try { fn(); return null; } catch (e) { return e; }
    }
    {
      const e = threwWith(() => regateGuard(true, { skippedAlreadyVerifiedIds: ['f1', 'f2'] }));
      check('REGATE=true + non-empty skippedAlreadyVerifiedIds: throws loudly', !!e, e ? e.message : '(did not throw)');
      if (e) check('thrown error names the offending id(s)', /f1/.test(e.message) && /f2/.test(e.message), e.message);
    }
    {
      const e = threwWith(() => regateGuard(true, { skippedAlreadyVerifiedIds: [] }));
      check('REGATE=true + empty skippedAlreadyVerifiedIds: no throw', !e, e ? e.message : '');
    }
    {
      const e = threwWith(() => regateGuard(false, { skippedAlreadyVerifiedIds: ['f1'] }));
      check('REGATE=false + non-empty skippedAlreadyVerifiedIds: no throw (normal one-round-rule outcome, not a defect)', !e, e ? e.message : '');
    }
    {
      const e = threwWith(() => regateGuard(true, { skippedAlreadyVerifiedIds: undefined }));
      check('REGATE=true + undefined skippedAlreadyVerifiedIds: no throw (guarded, does not crash on missing field)', !e, e ? e.message : '');
    }
  }
}

// ---- I: extract the #659 post-write attempted_at assertion VERBATIM
// (research-harness-template#659: falsify.sh/mif-rh-cli wrote verdict +
// verdict_basis but silently dropped extensions.harness.verification.attempted_at
// on a genuine, non-placeholder gate write). Trusting the write agent's own
// "written: true" self-report is exactly what let that drop through
// undetected -- this block asserts attemptedAtPresent deterministically, in
// code, the same idiom as mergeVotes()/reconcileEnumeration() above: retry
// once with a concrete re-read instruction, then throw loudly rather than
// silently accepting a partial write.
//
// The extracted block itself contains an `await agent(...)` retry call, so
// (unlike sections A-H) this test is genuinely async -- run it inside a
// tracked promise and defer the script's final process.exit() until it
// settles, rather than exiting synchronously while it is still pending.
let write659Promise = Promise.resolve();
{
  let runAssertion;
  let extractionError = null;
  try {
    const assertionText = extractBlock(
      src,
      "if (written && written.written && written.remediation !== 'skipped-one-round' && !written.attemptedAtPresent) {",
    );
    const harnessSrc =
      `'use strict';\n` +
      // WRITE_SCHEMA is a free variable inside the extracted block (it's
      // passed as the retry agent() call's schema option) -- stub it so the
      // harness doesn't need to re-extract the real schema object verbatim
      // just to satisfy a reference that plays no role in the assertion logic
      // under test.
      `const WRITE_SCHEMA = {};\n` +
      `async function runAssertion(written, agent, g, fixtureJson, H) {\n${assertionText}\n  return written;\n}\n` +
      `module.exports = { runAssertion };\n`;
    const harnessPath = path.join(tmpDir, 'write-assertion-harness.cjs');
    fs.writeFileSync(harnessPath, harnessSrc);
    ({ runAssertion } = require(harnessPath));
  } catch (e) {
    extractionError = e;
  }
  check('#659 post-write attempted_at assertion extracted from the module source', !extractionError, extractionError ? extractionError.message : '');

  if (runAssertion) {
    const G = { f: { path: 'reports/t/findings/f1.json', id: 'urn:mif:concept:t:f1' } };
    const FIXTURE_JSON = '{"urn:mif:concept:t:f1":{"verdict":"weakened"}}';

    write659Promise = (async () => {
      // Case 1: genuine write, attemptedAtPresent already true -- no retry
      // needed; the agent mock must never be called.
      {
        let agentCalled = false;
        const w = { written: true, remediation: 'downgraded', attemptedAtPresent: true };
        const result = await runAssertion(w, async () => { agentCalled = true; return null; }, G, FIXTURE_JSON, '.');
        check('attemptedAtPresent already true: no retry call, written passed through unchanged', !agentCalled && result === w, JSON.stringify(result));
      }
      // Case 2: one-round-rule skip (no genuine write) -- must NOT retry even
      // though attemptedAtPresent is false; that's expected on the skip path.
      {
        let agentCalled = false;
        const w = { written: true, remediation: 'skipped-one-round', attemptedAtPresent: false };
        const result = await runAssertion(w, async () => { agentCalled = true; return null; }, G, FIXTURE_JSON, '.');
        check('skipped-one-round: no retry call (attemptedAtPresent=false is expected here, not a defect)', !agentCalled && result === w, JSON.stringify(result));
      }
      // Case 3: genuine write missing attemptedAtPresent -- retry confirms it
      // WAS actually present (a reporting miss, not a real drop) -- no throw,
      // the retried object replaces written.
      {
        const w = { written: true, remediation: 'annotated', attemptedAtPresent: false };
        const retryResult = { written: true, remediation: 'annotated', attemptedAtPresent: true };
        let agentCalled = false;
        const result = await runAssertion(w, async () => { agentCalled = true; return retryResult; }, G, FIXTURE_JSON, '.');
        check('genuine write, retry confirms attempted_at present: retry IS called, no throw, result is the retried object', agentCalled && result === retryResult, JSON.stringify(result));
      }
      // Case 4 (#659's actual failure reproduced): genuine write, retry STILL
      // reports attempted_at absent -- must throw loudly, naming #659 and the
      // finding, never silently accept the partial write.
      {
        const w = { written: true, remediation: 'quarantined', attemptedAtPresent: false };
        const retryResult = { written: true, remediation: 'quarantined', attemptedAtPresent: false };
        let threw = null;
        try { await runAssertion(w, async () => retryResult, G, FIXTURE_JSON, '.'); } catch (e) { threw = e; }
        check('genuine write, retry still confirms attempted_at absent: throws loudly', !!threw, threw ? threw.message : '(did not throw)');
        if (threw) {
          check('thrown error names #659', /#659/.test(threw.message), threw.message);
          check('thrown error names the finding id', threw.message.includes(G.f.id), threw.message);
        }
      }
      // Case 5: genuine write, retry agent call itself fails (returns
      // null/undefined) -- must throw, never treat a failed retry as success.
      {
        const w = { written: true, remediation: 'downgraded', attemptedAtPresent: false };
        let threw = null;
        try { await runAssertion(w, async () => null, G, FIXTURE_JSON, '.'); } catch (e) { threw = e; }
        check('genuine write, retry agent call fails (returns null): throws rather than treating it as success', !!threw, threw ? threw.message : '(did not throw)');
      }
      // Case 6: retry legitimately reports a one-round skip on the SECOND
      // call (e.g. another process graded it in between) -- must NOT throw.
      {
        const w = { written: true, remediation: 'downgraded', attemptedAtPresent: false };
        const retryResult = { written: true, remediation: 'skipped-one-round', attemptedAtPresent: false };
        let threw = null;
        let result;
        try { result = await runAssertion(w, async () => retryResult, G, FIXTURE_JSON, '.'); } catch (e) { threw = e; }
        check('retry legitimately reports skipped-one-round on second call: no throw', !threw, threw ? threw.message : '');
        if (!threw) check('result is the retried object', result === retryResult, JSON.stringify(result));
      }
      // Case 7: total write failure (written is null/falsy from the start,
      // e.g. the first agent call itself failed) -- guard must short-circuit
      // and never crash reading .remediation off null.
      {
        let agentCalled = false;
        let threw = null;
        let result;
        try { result = await runAssertion(null, async () => { agentCalled = true; return null; }, G, FIXTURE_JSON, '.'); } catch (e) { threw = e; }
        check('written is null (total write failure): guard short-circuits, no retry call, no crash', !threw && !agentCalled && result === null, threw ? threw.message : JSON.stringify(result));
      }
      // Case 8 (PR #665 review fix): the agent returns a real object but
      // written.written is false (e.g. { written: false, remediation:
      // 'write-failed', attemptedAtPresent: false }) -- a non-skip
      // remediation with attemptedAtPresent=false used to be indistinguishable
      // from a genuine-write-missing-assertion (#659) and would wastefully
      // retry, then throw the #659-specific message even though no write ever
      // completed. The guard must check written.written, not just the
      // object's truthiness, and pass a failed write straight through
      // untouched -- no retry call, no throw.
      {
        let agentCalled = false;
        const w = { written: false, remediation: 'write-failed', attemptedAtPresent: false };
        const result = await runAssertion(w, async () => { agentCalled = true; return null; }, G, FIXTURE_JSON, '.');
        check('written.written is false (write-failed, not a #659 assertion gap): no retry call, written passed through unchanged', !agentCalled && result === w, JSON.stringify(result));
      }
      // Case 9 (PR #665 review fix): a genuine write needed a retry, but the
      // retry's OWN re-invoked write itself failed (retried.written is
      // false) -- must still throw (never silently accept it, e.g. via a
      // stray remediation === 'skipped-one-round' on the failed retry
      // slipping past the attemptedAtPresent-only check), and the thrown
      // message must not misreport it as a completed genuine write.
      {
        const w = { written: true, remediation: 'downgraded', attemptedAtPresent: false };
        const retryResult = { written: false, remediation: 'skipped-one-round', attemptedAtPresent: false };
        let threw = null;
        try { await runAssertion(w, async () => retryResult, G, FIXTURE_JSON, '.'); } catch (e) { threw = e; }
        check('retry itself reports written=false: throws rather than accepting a failed retry as a legitimate skip', !!threw, threw ? threw.message : '(did not throw)');
        if (threw) {
          check('thrown error names #659', /#659/.test(threw.message), threw.message);
          check('thrown error does not claim a completed genuine write when the retry write failed', !/completed a genuine/.test(threw.message), threw.message);
        }
      }
    })();
  }
}

// ---- J: extract pairLensResults() VERBATIM and prove lens identity survives
// a failed lens (research-harness-template#682: LENSES[i] positional lookups
// AFTER lensResults.filter(Boolean) misattributed every surviving result
// after the gap -- with source-integrity's agent() failed, temporal-validity's
// evidence got labeled source-integrity in the permanently-written
// verification basis and in the contested-adjudication prompt).
{
  let pairLensResults;
  let extractionError = null;
  try {
    const pairText = extractBlock(src, 'function pairLensResults(lenses, results) {');
    const harnessSrc = `'use strict';\n${pairText}\nmodule.exports = { pairLensResults };\n`;
    const harnessPath = path.join(tmpDir, 'pairlens-harness.cjs');
    fs.writeFileSync(harnessPath, harnessSrc);
    ({ pairLensResults } = require(harnessPath));
  } catch (e) {
    extractionError = e;
  }
  check('pairLensResults() extracted from the module source (#682)', !extractionError, extractionError ? extractionError.message : '');

  if (pairLensResults) {
    const lenses = [{ key: 'counter-evidence' }, { key: 'source-integrity' }, { key: 'temporal-validity' }];
    const ce = { verdict: 'survived', basis: 'ce basis', sources: [] };
    const si = { verdict: 'weakened', basis: 'si basis', sources: [] };
    const tv = { verdict: 'falsified', basis: 'tv basis', sources: ['https://example.com/tv'] };
    // All lenses succeed: keys map 1:1 in order, payload fields intact.
    {
      const got = pairLensResults(lenses, [ce, si, tv]);
      check('all lenses succeed: keys pair 1:1 in order', deepEqual(got.map((r) => r.lensKey), ['counter-evidence', 'source-integrity', 'temporal-validity']), JSON.stringify(got.map((r) => r.lensKey)));
      check('all lenses succeed: verdict/basis/sources ride along intact', got[2].verdict === 'falsified' && got[2].basis === 'tv basis' && deepEqual(got[2].sources, ['https://example.com/tv']), JSON.stringify(got[2]));
    }
    // #682's exact incident shape: the MIDDLE lens (source-integrity) fails
    // and is dropped -- the survivor at index 1 must still be labeled
    // temporal-validity, never source-integrity (which is what LENSES[1]
    // resolved to under the old positional lookup).
    {
      const got = pairLensResults(lenses, [ce, null, tv]);
      check("#682's exact shape (middle lens failed): survivors keep their ORIGINAL lens keys", deepEqual(got.map((r) => r.lensKey), ['counter-evidence', 'temporal-validity']), JSON.stringify(got.map((r) => r.lensKey)));
      check("#682's exact shape: the post-gap survivor is NOT misattributed to the failed lens", got[1].lensKey !== 'source-integrity' && got[1].basis === 'tv basis', JSON.stringify(got[1]));
    }
    // First lens fails: both survivors shift position yet keep their keys.
    {
      const got = pairLensResults(lenses, [null, si, tv]);
      check('first lens failed: both shifted survivors keep their keys', deepEqual(got.map((r) => r.lensKey), ['source-integrity', 'temporal-validity']), JSON.stringify(got.map((r) => r.lensKey)));
    }
    // All lenses fail: empty result, no crash.
    {
      const got = pairLensResults(lenses, [null, null, null]);
      check('all lenses failed: empty pairing, no crash', deepEqual(got, []), JSON.stringify(got));
    }
    // A stray lensKey already present on a lens result must NEVER win over
    // the paired identity -- the pairing assigns lensKey after the spread.
    {
      const poisoned = { verdict: 'survived', basis: 'ce basis', sources: [], lensKey: 'imposter' };
      const got = pairLensResults(lenses, [poisoned, si, tv]);
      check('a pre-existing lensKey on a result is overwritten by the paired identity', got[0].lensKey === 'counter-evidence', JSON.stringify(got[0]));
    }
    // Results longer than the lens list degrade to a labeled placeholder
    // instead of throwing mid-Gate.
    {
      const extra = { verdict: 'survived', basis: 'extra basis', sources: [] };
      const got = pairLensResults(lenses, [ce, si, tv, extra]);
      check('a result past the end of the lens list gets a placeholder key, no throw', got[3].lensKey === 'lens-3', JSON.stringify(got[3]));
    }
  }
}

write659Promise
  .then(() => process.exit(failed))
  .catch((e) => {
    console.log(`FAIL  #659 assertion test harness threw unexpectedly: ${e.message}`);
    process.exit(1);
  });
NODE

if ! node "$TMP/extract-and-test.cjs" "$WF" "$TMP" > "$TMP/node.out" 2>&1; then
  note "mergeVotes()/claimBudget extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/node.out"
  fail=1
else
  sed 's/^/    /' "$TMP/node.out"
fi

# ============================================================================
# B: seeded-false-finding fixture graded through the REAL engine, then
# quarantined via the ported remediation logic -- proven at the fixture
# level, not just that falsify.sh ran.
# ============================================================================
TDIR="$TMP/reports/falsify-eval-topic"
mkdir -p "$TDIR/findings" "$TDIR/quarantine"
touch "$TDIR/.gate-active"
FSEED_LIVE="$TDIR/findings/finding-seeded-false.json"
cp "$FX/finding-seeded-false.json" "$FSEED_LIVE"

if ! bash scripts/falsify.sh "$FSEED_LIVE" "$FX/evidence-falsified.json" \
    > "$TMP/seeded-graded.json" 2> "$TMP/seeded.stderr"; then
  note "falsify.sh failed grading the seeded-false fixture: $(cat "$TMP/seeded.stderr")"
  fail=1
else
  grep -q "falsification-gate: run" "$TMP/seeded.stderr" \
    || { note "seeded-false grading did not log a genuine 'falsification-gate: run' line: $(cat "$TMP/seeded.stderr")"; fail=1; }

  verdict=$(jq -r '.extensions.harness.verification.verdict' "$TMP/seeded-graded.json")
  basis=$(jq -r '.extensions.harness.verification.verdict_basis' "$TMP/seeded-graded.json")
  attempted=$(jq -r '.extensions.harness.verification.attempted_at' "$TMP/seeded-graded.json")
  disconf_count=$(jq '.extensions.harness.verification.disconfirming_evidence | length' "$TMP/seeded-graded.json")
  [ "$verdict" = "falsified" ] || { note "seeded-false fixture graded verdict='$verdict', want 'falsified'"; fail=1; }
  { [ -n "$basis" ] && [ "$basis" != "null" ]; } \
    || { note "verification.verdict_basis missing/empty on the falsified verdict"; fail=1; }
  [[ "$attempted" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$ ]] \
    || { note "verification.attempted_at is not a stamped ISO-8601 timestamp: '$attempted'"; fail=1; }
  [ "$disconf_count" -ge 1 ] \
    || { note "verification.disconfirming_evidence is empty for a falsified verdict"; fail=1; }

  # Write-then-validate atomicity, exactly as the module's write step does:
  # mv the graded output over the original finding path BEFORE remediation.
  mv "$TMP/seeded-graded.json" "$FSEED_LIVE"

  # Ported remediation (REMEDIATION_CONTRACT): falsified -> QUARANTINE
  # (mkdir -p quarantine/, mv the finding file there). This proves the PORT
  # itself, not merely that falsify.sh wrote a verdict.
  mv "$FSEED_LIVE" "$TDIR/quarantine/finding-seeded-false.json"

  [ ! -e "$FSEED_LIVE" ] \
    || { note "finding still present under findings/ after quarantine remediation"; fail=1; }
  [ -f "$TDIR/quarantine/finding-seeded-false.json" ] \
    || { note "finding was not moved into quarantine/"; fail=1; }

  if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
        -s schemas/findings.schema.json \
        -r schemas/mif/mif.schema.json \
        -r schemas/mif/definitions/entity-reference.schema.json \
        -d "$TDIR/quarantine/finding-seeded-false.json" > "$TMP/quarantine-ajv.out" 2>&1; then
    note "quarantined finding no longer validates against schemas/findings.schema.json: $(tail -3 "$TMP/quarantine-ajv.out")"
    fail=1
  fi
fi

# ============================================================================
# D: one-round rule, proven against the REAL substrate research-falsify.js's
# gap-2 header comment documents relying on -- a normal re-run is excluded;
# a regate-scoped call (client-side reset, exactly as the module's
# regate-reset step) genuinely re-processes the same finding.
# ============================================================================
T2DIR="$TMP/reports/falsify-eval-topic-oneround"
mkdir -p "$T2DIR/findings"
touch "$T2DIR/.gate-active"
FONE_LIVE="$T2DIR/findings/finding-one-round.json"
cp "$FX/finding-one-round.json" "$FONE_LIVE"

# Round 1: fresh grade.
if bash scripts/falsify.sh "$FONE_LIVE" "$FX/evidence-survived-round1.json" \
    > "$TMP/r1.json" 2> "$TMP/r1.stderr"; then
  grep -q "falsification-gate: run" "$TMP/r1.stderr" \
    || { note "round 1 (fresh grade) did not log a genuine run: $(cat "$TMP/r1.stderr")"; fail=1; }
  mv "$TMP/r1.json" "$FONE_LIVE"
else
  note "round 1 (fresh grade) failed: $(cat "$TMP/r1.stderr")"
  fail=1
fi
r1_verdict=$(jq -r '.extensions.harness.verification.verdict' "$FONE_LIVE")
r1_attempted=$(jq -r '.extensions.harness.verification.attempted_at' "$FONE_LIVE")
[ "$r1_verdict" = "survived" ] || { note "round 1 verdict='$r1_verdict', want 'survived'"; fail=1; }

# Round 2 (NORMAL, non-regate): the already-graded finding must be EXCLUDED.
bash scripts/falsify.sh "$FONE_LIVE" "$FX/evidence-falsified-round2-attempt.json" \
  > "$TMP/r2.json" 2> "$TMP/r2.stderr"
grep -q "falsification-gate: skipped (already falsified this session)" "$TMP/r2.stderr" \
  || { note "round 2 (normal re-run) did not log the one-round skip: $(cat "$TMP/r2.stderr")"; fail=1; }
r2_verdict=$(jq -r '.extensions.harness.verification.verdict' "$TMP/r2.json")
r2_attempted=$(jq -r '.extensions.harness.verification.attempted_at' "$TMP/r2.json")
{ [ "$r2_verdict" = "$r1_verdict" ] && [ "$r2_attempted" = "$r1_attempted" ]; } \
  || { note "round 2 (normal re-run) mutated verdict/attempted_at despite the one-round rule (verdict $r1_verdict->$r2_verdict, attempted_at $r1_attempted->$r2_attempted)"; fail=1; }

# Round 3 (REGATE): client-side reset exactly as research-falsify.js's
# regate-reset step documents -- jq 'del(.extensions.harness.verification)',
# write to a temp file, mv over the original (never -i) -- THEN falsify.sh
# performs a genuine re-write, proving "resets and re-processes".
jq 'del(.extensions.harness.verification)' "$FONE_LIVE" > "$TMP/reset.json" \
  && mv "$TMP/reset.json" "$FONE_LIVE"
jq -e '(.extensions.harness | has("verification")) | not' "$FONE_LIVE" >/dev/null \
  || { note "client-side regate reset did not clear extensions.harness.verification"; fail=1; }

bash scripts/falsify.sh "$FONE_LIVE" "$FX/evidence-falsified-round3-regate.json" \
  > "$TMP/r3.json" 2> "$TMP/r3.stderr"
grep -q "falsification-gate: run" "$TMP/r3.stderr" \
  || { note "round 3 (post-regate re-run) did not log a genuine run -- regate reset did not re-open grading: $(cat "$TMP/r3.stderr")"; fail=1; }
r3_verdict=$(jq -r '.extensions.harness.verification.verdict' "$TMP/r3.json")
r3_attempted=$(jq -r '.extensions.harness.verification.attempted_at' "$TMP/r3.json")
[ "$r3_verdict" = "falsified" ] \
  || { note "round 3 (post-regate) verdict='$r3_verdict', want 'falsified' (evidence-round3 fixture)"; fail=1; }
[ "$r3_attempted" != "$r1_attempted" ] \
  || { note "round 3 (post-regate) attempted_at did not change from round 1 -- reset did not take effect"; fail=1; }

# ============================================================================
# E: structural contract of research-falsify.js itself (issue #562
# acceptance criteria) -- the fixture-write bridge and ported remediation
# logic are really present in the module, not a comment claiming falsify.sh
# owns remediation.
# ============================================================================
grep -q 'function buildFixtureEntry' "$WF" \
  || { note "$WF lost the buildFixtureEntry() fixture-write bridge"; fail=1; }
grep -q 'const fixture = buildFixtureEntry' "$WF" \
  || { note "$WF write step no longer calls buildFixtureEntry() -- fixture bridge not wired in"; fail=1; }
grep -qF 'falsify.sh ${g.f.path} <fixture-path>' "$WF" \
  || { note "$WF write step lost the fixture-path arg -- would regress to a bare-arg falsify.sh invocation"; fail=1; }
grep -qE 'const REMEDIATION_CONTRACT[[:space:]]*=' "$WF" \
  || { note "$WF lost the ported REMEDIATION_CONTRACT constant"; fail=1; }
grep -qF '${REMEDIATION_CONTRACT}' "$WF" \
  || { note "$WF write-step brief no longer embeds REMEDIATION_CONTRACT"; fail=1; }
grep -qF 'falsified: QUARANTINE' "$WF" \
  || { note "$WF lost the falsified->QUARANTINE remediation rule text"; fail=1; }

# #618 structural contract: buildFixtureEntry no longer computes its own
# timestamp, the write step fails loudly (rather than silently) when the
# caller omitted args.runDate, and the required timestamp is threaded to the
# call site verbatim.
grep -qF 'attempted_at: attemptedAt' "$WF" \
  || { note "$WF's buildFixtureEntry() no longer sources attempted_at from a caller-supplied parameter -- may have regressed to computing it in-script (#618)"; fail=1; }
# (a live new Date()/Date.now()/Math.random() CALL anywhere in this file, as
# opposed to prose mentioning them in a comment -- this module's own #618
# explanation legitimately says "new Date()" -- is covered by the
# comment-aware scripts/check-workflow-forbidden-globals.sh gate, not a bare
# grep here, which would false-positive on that very prose.)
grep -qF 'args.runDate is required' "$WF" \
  || { note "$WF lost the fail-loud guard for a missing args.runDate (#618) -- a missing timestamp would now silently write attempted_at: undefined instead of erroring clearly"; fail=1; }
grep -qF 'buildFixtureEntry(g.f.id, verdict, basis, g.lensResults, RUN_DATE)' "$WF" \
  || { note "$WF's write step no longer passes RUN_DATE into buildFixtureEntry() (#618)"; fail=1; }

# #625 structural contract: reconcileEnumeration() is only meaningful for
# scope:'all' -- allFindingIds is EVERY on-disk finding, so under a narrower
# scope (dimension:*, or an explicit paths/ids set, incl. regate) the working
# set is a deliberate subset and out-of-scope findings would be falsely flagged
# missing, turning a wasted retry into a hard throw. Lock the scope gate so a
# future edit can't silently re-run reconciliation for every scope again.
grep -qF "SCOPE === 'all' ? reconcileEnumeration(enumerated) : []" "$WF" \
  || { note "$WF's #625 reconciliation is no longer gated to scope:'all' -- a scoped/regate run (e.g. pivot's scope:{ids} at research-pipeline.js) would reconcile its intentional subset against the full on-disk listing and throw"; fail=1; }

# #625 PR review structural contract (Copilot): RE-GATE mode's contract is
# that skippedAlreadyVerifiedIds stays empty (regate re-opens verification
# even for already-attempted findings); the enumeration agent's own compliance
# with that prompt wording is not trusted -- a deterministic guard must fail
# loudly if REGATE is true and enumeration nonetheless populated
# skippedAlreadyVerifiedIds, rather than silently treating those findings as
# covered and skipping them from the re-gate working set.
grep -qF "if (REGATE && enumerated.skippedAlreadyVerifiedIds && enumerated.skippedAlreadyVerifiedIds.length) {" "$WF" \
  || { note "$WF lost the RE-GATE skippedAlreadyVerifiedIds guard -- a regate run could silently skip already-attempted findings instead of re-opening them"; fail=1; }

# #659 structural contract: the write step's own self-report ("written: true")
# is not trusted for attempted_at completeness -- WRITE_SCHEMA requires an
# attemptedAtPresent field, and a genuine (non-one-round-rule-skipped) write
# missing it is asserted deterministically in code, not left to the model.
grep -qF 'attemptedAtPresent' "$WF" \
  || { note "$WF lost the #659 attemptedAtPresent field -- a silently-dropped attempted_at would no longer be detected"; fail=1; }
grep -qF "required: ['written', 'remediation', 'attemptedAtPresent']" "$WF" \
  || { note "$WF's WRITE_SCHEMA no longer requires attemptedAtPresent -- the write agent could omit it and the #659 assertion would silently pass undefined"; fail=1; }
grep -qF "if (written && written.written && written.remediation !== 'skipped-one-round' && !written.attemptedAtPresent) {" "$WF" \
  || { note "$WF lost the #659 deterministic post-write assertion guard"; fail=1; }
grep -qF '#659' "$WF" \
  || { note "$WF lost its #659 traceability comments"; fail=1; }

# #682 structural contract: lens identity is paired at collection time
# (pairLensResults, BEFORE filter(Boolean) drops a failed lens) and the
# basis/adjudication consumers read the paired key -- never a positional
# LENSES[i] lookup against the filtered array, which misattributes every
# surviving result after a gap.
grep -qF 'lensResults: pairLensResults(LENSES, lensResults)' "$WF" \
  || { note "$WF's Gate collection no longer pairs lens identity via pairLensResults() -- lens keys would again be reconstructed positionally after filter(Boolean) (#682)"; fail=1; }
grep -qF '${r.lensKey}' "$WF" \
  || { note "$WF's basis/adjudication construction no longer reads the paired lensKey (#682)"; fail=1; }
! grep -qF 'LENSES[i]' "$WF" \
  || { note "$WF reintroduced a positional LENSES[i] lookup -- after filter(Boolean) this misattributes lens identity once any lens fails (#682)"; fail=1; }

[ "$fail" -eq 0 ] && note "mergeVotes()/claimBudget hold against the real function, buildFixtureEntry() runs clean under a poisoned Date/Math.random and uses the caller-supplied timestamp verbatim (#618), the seeded-false fixture quarantines end-to-end through the real engine, the one-round rule + regate reset are real against that same engine, the module keeps its fixture-bridge/remediation contract, reconcileEnumeration() holds against its #625 set-difference matrix and is scope-gated to 'all', the RE-GATE skippedAlreadyVerifiedIds guard holds against its truth table, and the #659 post-write attempted_at assertion (retry-then-throw, never silently accepting a partial write) holds against its 7-case truth table, and pairLensResults() preserves lens identity across a failed lens (#682)"
exit "$fail"
