#!/usr/bin/env bash
# falsify-write-failure-gated.sh — regression eval for
# research-harness-template#747 ("Failed writes are silently counted as
# gated in research-falsify.js").
#
# Root cause: the Gate-phase per-finding callback in
# .claude/workflows/research-falsify.js called the write agent, then fell
# straight through to `return { id, dimension, verdict, contested,
# remediation: written ? written.remediation : 'write-failed' }` regardless
# of whether `written.written` was true or false. The existing #659 guard
# only fires when `written.written` is already true (it retries a
# HALF-completed write missing attempted_at) -- a write agent that honestly
# reports written=false never entered that guard at all, so its fully-
# populated verdict object was returned unconditionally. Rollup's
# `gated: done.length` (done = gated.filter(Boolean)) then counted that
# finding as gated even though falsify.sh never persisted anything to disk,
# and research-pipeline.js's falsifyAll()/completionCheck() callers treated
# that count as real progress -- the next Enumerate step silently
# rediscovered the same still-ungated finding and repeated the identical
# doomed write every round, burning agent budget with no surfaced signal.
#
# This eval extracts the write/retry/return SPAN verbatim (balanced-brace
# span extraction, mirroring evals/falsify-verdict-merge.sh's technique for
# mergeVotes()/the claimBudget slice -- never a reimplementation of the
# logic) from `let written = await agent(writeBrief` through the final
# `return { id: g.f.id, ... }`, wraps it in a harness function, and drives
# it with a stubbed `agent()` across the real decision matrix:
#
#   1. written=false on both the initial call and the #747 retry -- MUST
#      throw (naming #747), and must NEVER reach the return statement.
#      Run first against a COPY of the CURRENT (fixed) module -- proving
#      the fix -- and then, as a control proving this eval actually would
#      have caught #747, against the git-committed PRE-FIX revision
#      (the parent of this fix, resolved via `git log -1 --format=%H --
#      <path>` from the branch's merge-base with origin/main): the SAME
#      stub run against the pre-fix source must NOT throw and must return
#      a fully-populated object with remediation="write-failed" -- exactly
#      the silent-gating defect #747 reported. If the control does not
#      reproduce the defect, this eval's "would have caught #747" claim is
#      false, so it is checked, never assumed.
#   2. written=false initially, retry succeeds (written=true) -- recovers:
#      no throw, the RETRIED remediation is returned (proves the retry
#      path added for #747 genuinely re-attempts the write rather than
#      just failing faster).
#   3. written=false initially, retry succeeds with
#      remediation="skipped-one-round" -- accepted, no throw (the #659
#      guard below correctly does not re-fire on a one-round-rule skip).
#   4. The pre-existing #659 half-write matrix, UNCHANGED by this fix:
#      written=true but attemptedAtPresent=false recovers on retry
#      (attemptedAtPresent=true on the #659 retry) with no throw; the same
#      shape on BOTH calls still throws (naming #659).
#   5. Happy path: written=true + attemptedAtPresent=true on the FIRST
#      call makes exactly one agent() call -- no retry of any kind fires
#      when nothing is wrong.
#
# Hermetic: mktemp scratch only, no network, no model/API calls, no
# fixtures directory (this eval only needs the module's own source text
# plus a git blob lookup for the pre-fix control).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  falsify-write-failure-gated: %s\n' "$1"; }

WF=.claude/workflows/research-falsify.js
command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v git >/dev/null 2>&1 || { note "git is required but not on PATH"; exit 2; }

# ============================================================================
# Node harness: balanced-brace span extraction (mirrors
# evals/falsify-verdict-merge.sh's extractBlockFrom/extractSpan technique)
# plus the stub-agent decision matrix. Takes the module path as argv[2] so
# it can be run against both the current module and the pre-fix control.
# ============================================================================
cat > "$TMP/harness.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');

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
function extractSpan(text, startMarker, throughMarker) {
  const s = text.indexOf(startMarker);
  if (s < 0) throw new Error(`start marker not found: ${startMarker}`);
  const t = text.indexOf(throughMarker, s);
  if (t < 0) throw new Error(`through-marker not found after start: ${throughMarker}`);
  return extractBlockFrom(text, t, s);
}

const wfPath = process.argv[2];
const mode = process.argv[3]; // 'fixed' or 'prefix'
const src = fs.readFileSync(wfPath, 'utf8');

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ok  ${name}`);
  else { failed = 1; console.log(`FAIL  ${name}${detail ? ' -- ' + detail : ''}`); }
}

let span, extractionError = null;
try {
  span = extractSpan(src, 'let written = await agent(writeBrief', 'return { id: g.f.id');
} catch (e) {
  extractionError = e;
}
check(`[${mode}] write/retry/return span extracted verbatim from ${path.basename(wfPath)}`, !extractionError, extractionError ? extractionError.message : '');
if (extractionError) process.exit(1);

async function buildRunner() {
  const harnessSrc =
    `module.exports = async function run(g, verdict, contested, fixtureJson, H, REMEDIATION_CONTRACT, WRITE_SCHEMA, agent, writeBrief) {\n${span}\n};\n`;
  const tmpFile = path.join(os.tmpdir(), `falsify-write-failure-harness-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}.cjs`);
  fs.writeFileSync(tmpFile, harnessSrc);
  const run = require(tmpFile);
  fs.unlinkSync(tmpFile);
  return run;
}

async function main() {
  const run = await buildRunner();
  const g = { f: { id: 'urn:mif:concept:t:f1', path: 'reports/t/findings/f1.json', dimension: 'technical' } };
  const REMEDIATION_CONTRACT = 'STUB-REMEDIATION-CONTRACT';
  const WRITE_SCHEMA = {};
  const call = (agent) => run(g, 'survived', false, '{}', '.', REMEDIATION_CONTRACT, WRITE_SCHEMA, agent, 'stub-write-brief');

  if (mode === 'prefix') {
    // Pre-fix CONTROL: written=false on the (only) write call. #747's own
    // defect -- must reproduce it: no throw, a fully-populated object
    // returned with remediation="write-failed".
    let calls = 0, threw = null, result = null;
    const agent = async () => { calls++; return { written: false, remediation: 'write-failed', attemptedAtPresent: false }; };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('[prefix] CONTROL reproduces #747: written=false does NOT throw', !threw, threw ? threw.message : '');
    check('[prefix] CONTROL reproduces #747: a fully-populated object is returned despite the failed write', !!(result && result.id === g.f.id && result.remediation === 'write-failed'), JSON.stringify(result));
    console.log(failed ? 'FAIL' : 'ok  ' , '-- prefix control done');
    process.exit(failed);
  }

  // ---- 1. written=false on both calls -- MUST throw, naming #747 ----
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => { calls++; return { written: false, remediation: 'write-failed', attemptedAtPresent: false }; };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('1. written=false on both calls throws (never silently returns)', !!threw, threw ? '' : `result=${JSON.stringify(result)}`);
    check('1. thrown error names #747', !!(threw && /#747/.test(threw.message)), threw ? threw.message : '');
    check('1. exactly one retry attempt was made (2 total calls)', calls === 2, `calls=${calls}`);
    check('1. never falls through to the return statement', result === null, JSON.stringify(result));
  }

  // ---- 2. written=false initially, retry succeeds -- recovers ----
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => {
      calls++;
      if (calls === 1) return { written: false, remediation: 'write-failed', attemptedAtPresent: false };
      return { written: true, remediation: 'annotated', attemptedAtPresent: true };
    };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('2. written=false then a successful retry does not throw', !threw, threw ? threw.message : '');
    check('2. the RETRIED remediation is returned, not "write-failed"', !!(result && result.remediation === 'annotated'), JSON.stringify(result));
    check('2. verdict/contested/dimension/id survive through unchanged', !!(result && result.verdict === 'survived' && result.contested === false && result.dimension === 'technical' && result.id === g.f.id), JSON.stringify(result));
  }

  // ---- 3. written=false initially, retry recovers as a one-round skip ----
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => {
      calls++;
      if (calls === 1) return { written: false, remediation: 'write-failed', attemptedAtPresent: false };
      return { written: true, remediation: 'skipped-one-round', attemptedAtPresent: false };
    };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('3. a one-round-rule skip on retry is accepted, no throw', !threw, threw ? threw.message : '');
    check('3. remediation reflects the skip', !!(result && result.remediation === 'skipped-one-round'), JSON.stringify(result));
  }

  // ---- 4. Pre-existing #659 half-write matrix, unchanged by this fix ----
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => {
      calls++;
      if (calls === 1) return { written: true, remediation: 'annotated', attemptedAtPresent: false };
      return { written: true, remediation: 'annotated', attemptedAtPresent: true };
    };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('4a. #659 half-write (attemptedAtPresent=false) recovers on retry, no throw', !threw, threw ? threw.message : '');
    check('4a. remediation from the #659 retry is returned', !!(result && result.remediation === 'annotated'), JSON.stringify(result));
  }
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => { calls++; return { written: true, remediation: 'annotated', attemptedAtPresent: false }; };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('4b. #659 half-write persisting on retry still throws, naming #659', !!(threw && /#659/.test(threw.message)), threw ? threw.message : `result=${JSON.stringify(result)}`);
  }

  // ---- 5. Happy path: exactly one agent() call, no retry fires ----
  {
    let calls = 0, threw = null, result = null;
    const agent = async () => { calls++; return { written: true, remediation: 'annotated', attemptedAtPresent: true }; };
    try { result = await call(agent); } catch (e) { threw = e; }
    check('5. happy path (written=true, attemptedAtPresent=true) makes exactly 1 agent() call', calls === 1, `calls=${calls}`);
    check('5. happy path does not throw', !threw, threw ? threw.message : '');
  }

  process.exit(failed);
}
main();
NODE

# ============================================================================
# Run against the CURRENT (fixed) module.
# ============================================================================
node "$TMP/harness.cjs" "$WF" fixed
[ "$?" -eq 0 ] || fail=1

# ============================================================================
# CONTROL: run the identical harness against the pre-fix revision of this
# module, resolved as the merge-base between HEAD and origin/main (the
# commit this fix branched from) -- proving the eval actually discriminates
# the defect rather than trivially passing against any source. If the repo
# has no origin/main reachable (a shallow/offline clone) or the file did not
# exist at that revision, the control is skipped rather than failing the
# gate on an environment limitation unrelated to the fix itself.
# ============================================================================
git fetch origin main >/dev/null 2>&1 || true
BASE_REF="$(git merge-base HEAD origin/main 2>/dev/null || true)"
if [ -n "$BASE_REF" ] && git cat-file -e "$BASE_REF:$WF" 2>/dev/null; then
  PREFIX_WF="$TMP/research-falsify-prefix.js"
  git show "$BASE_REF:$WF" > "$PREFIX_WF" 2>/dev/null
  node "$TMP/harness.cjs" "$PREFIX_WF" prefix
  [ "$?" -eq 0 ] || fail=1
else
  note "origin/main merge-base unavailable -- skipping the pre-fix control (not this eval's own gate)"
fi

[ "$fail" -eq 0 ] && note "a genuine write failure (written=false) throws loudly naming #747 instead of silently returning a fully-populated verdict object counted as gated; the retry path recovers a transient failure and a one-round-rule skip on retry; the pre-existing #659 half-write matrix and the happy path are unaffected; the pre-fix control (when available) reproduces #747's exact silent-gating defect, proving this eval would have caught it"
exit "$fail"
