#!/usr/bin/env bash
# projection-verify-resilience-check.sh — regression eval for
# research-harness-template#727: research-projection.js's Verify phase
# (.claude/workflows/research-projection.js) shares the same unguarded
# agent()-throw exposure that #720 already fixed for the Index phase.
# `agent({schema})` surfaces the "subagent completed its real work but never
# called StructuredOutput" non-compliance class as a THROW (not the
# documented "returns null on death" contract for timeout/exhausted-retry/
# user-skip), and the Verify phase had no try/catch around its one
# `agent()` call — a throw there would hard-fail the whole pipeline one
# phase from the finish line, after Report and Index have already succeeded.
#
# UNLIKE Report (#727's own other half), Verify DOES degrade to a null
# result on a throw, mirroring Index's (#720) shape exactly: the final
# `return { ... problems: verify ? verify.problems : ['verify agent failed'] }`
# already treats a null verify as a safe, non-fatal ok:false outcome — this
# was true before this fix too, so degrading here is a safe no-op path, not
# a caller-visible-contract change the way a degraded Report would be.
#
# The model deliberately STAYS `haiku` here (an explicit ANTI-REGRESSION
# TRAP in the opposite direction of Index's own eval, which traps against
# staying on haiku) — Verify's task (targeted markdownlint/ajv-validate,
# report problems verbatim, do not fix) is a single-shot mechanical
# check-and-report with no authored-prose sub-step, closer in shape to this
# same file's own `projection:preflight`/`projection:genre-resolve` haiku
# calls (neither has ever shown this failure class) than to Index's "author
# 4-10 synthesis bullets" task that #720's own analysis pinned as the actual
# driver of haiku's non-compliance there.
#
# Three proof classes:
#
#   A. Structural: `model: 'haiku'` stays in the Verify-phase agent()
#      options (regression trap against an unnecessary/unreasoned escalation
#      to sonnet — the opposite direction of projection-index-resilience-
#      check.sh's own model-guard case), and the call is wrapped in
#      try/catch.
#
#   B. Behavioral: the actual try/catch block is extracted VERBATIM
#      (brace-matched, never re-typed) from the module and driven with three
#      stubbed agent() implementations:
#        (a) throws the exact observed failure signature -> the block must
#            NOT re-throw; verify ends up null/falsy; a warning naming the
#            underlying error is logged.
#        (b) resolves to null (the documented "returns null on death"
#            contract path) -> unchanged behavior, no crash.
#        (c) resolves normally -> the happy path and verify shape are
#            unaffected; nothing swallowed that shouldn't be.
#
# Hermetic: node only, plus a stubbed agent()/log() — no network, no live
# model/API calls.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing or the module's shape has changed enough that extraction itself
# failed — this eval refuses to silently skip.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-projection.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  projection-verify-resilience-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-projection workflow must ship (Epic #543, Task #569)"; exit 2; }

# ============================================================================
# A: structural — model: 'haiku' inside the Verify phase's own agent()
# options span (phase('Verify') through end of file), never escalated to
# sonnet without deliberate reconsideration; try/catch present around the
# call.
# ============================================================================
verify_span="$(awk '/^phase\(.Verify.\)/{f=1} f{print}' "$WF")"
[ -n "$verify_span" ] || { note "could not locate the Verify phase body (phase('Verify') .. end of file span) in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF "label: 'projection:verify', model: 'haiku'" <<<"$verify_span" \
  || { note "Verify phase's agent() call is no longer 'model: haiku' — this is a deliberate no-op decision (see this eval's header); an escalation to sonnet should be a reasoned, examined change, not silent drift, and must update this eval's expectation explicitly"; fail=1; }

grep -qF 'let verify = null' <<<"$verify_span" \
  || { note "Verify phase no longer declares 'let verify = null' — the #727 guard shape has regressed or the module's structure changed"; fail=1; }
grep -qF 'try {' <<<"$verify_span" \
  || { note "Verify phase does not wrap its agent() call in a try block — the #727 guard-and-degrade fix is missing or has regressed"; fail=1; }
grep -qF 'catch (err)' <<<"$verify_span" \
  || { note "Verify phase has no catch block around its agent() call — the #727 guard-and-degrade fix is missing or has regressed"; fail=1; }

# ============================================================================
# B: behavioral — extract the try/catch block VERBATIM (brace-matched, same
# technique as projection-index-resilience-check.sh /
# projection-supersession-check.sh) and drive it with three stubbed agent()
# implementations.
# ============================================================================
cat > "$TMP/extract-verify-try-catch.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-verify-try-catch.cjs <research-projection.js> <tmpdir>');
  process.exit(2);
}
const src = fs.readFileSync(wfPath, 'utf8');

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
  if (s < 0) throw new Error(`start marker not found: ${JSON.stringify(startMarker)}`);
  const t = text.indexOf(throughMarker, s);
  if (t < 0) throw new Error(`through-marker not found after start: ${JSON.stringify(throughMarker)}`);
  return extractBlockFrom(text, t, s);
}

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ok  ${name}`);
  else { failed = 1; console.log(`FAIL  ${name}${detail ? ' -- ' + detail : ''}`); }
}

// Verbatim extraction of `let verify = null` through the closing brace of
// the `} catch (err) { ... }` block -- the SAME span the module runs, never
// a bash/JS reimplementation of the try/catch logic.
let runVerifyTryCatch;
try {
  const spanText = extractSpan(
    src,
    'let verify = null',
    '} catch (err) {',
  );
  const harnessSrc =
    'async function runVerifyTryCatch(agent, log, H, changed, VERIFY_SCHEMA) {\n' +
    spanText + '\n' +
    '  return { verify };\n' +
    '}\n' +
    'module.exports = { runVerifyTryCatch };\n';
  const harnessPath = path.join(tmpDir, 'verify-try-catch-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ runVerifyTryCatch } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the Verify-phase try/catch from ${wfPath}: ${e.message}`);
  process.exit(1);
}

const commonArgs = ['.', ['reports/evaltopic/evaltopic.md'], {}];

async function driveThrowsCase() {
  // The exact observed failure signature (mirroring #720): the subagent
  // completes its real markdownlint/ajv-validate work but never calls
  // StructuredOutput -- surfaced by agent({schema}) as a thrown Error, not a
  // null return.
  const agent = async () => {
    throw new Error('agent({schema}): subagent completed without calling StructuredOutput (after in-conversation nudge)');
  };
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runVerifyTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('throws case: the block does NOT re-throw (the pipeline must survive this phase — Verify is the last one)', threw === null, threw ? threw.message : undefined);
  check('throws case: verify degrades to null/falsy rather than a stale or partial value', !!(result && !result.verify), result ? JSON.stringify(result) : undefined);
  check('throws case: a warning was logged', logged.length > 0, 'no log() calls captured');
  check('throws case: the warning names research-harness-template#727', logged.some((m) => m.includes('#727')), JSON.stringify(logged));
  check('throws case: the warning surfaces the underlying error text', logged.some((m) => m.includes('subagent completed without calling StructuredOutput')), JSON.stringify(logged));
}

async function driveNullCase() {
  // The documented "agent() returns null on death (timeout, unrecoverable
  // error, exhausted schema retries, or user skip)" contract path -- must
  // remain unaffected by the #727 fix (this was already handled before,
  // via the final return's `verify ? verify.problems : [...]` ternary).
  const agent = async () => null;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runVerifyTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('null-return case: the block does not throw', threw === null, threw ? threw.message : undefined);
  check('null-return case: verify is null (unchanged behavior)', !!(result && result.verify === null), result ? JSON.stringify(result) : undefined);
}

async function driveHappyCase() {
  const goodVerify = {
    lintClean: true,
    schemaClean: true,
    problems: [],
  };
  const agent = async () => goodVerify;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runVerifyTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('happy-path case: the block does not throw', threw === null, threw ? threw.message : undefined);
  check('happy-path case: verify is returned through unmutated', !!(result && result.verify && result.verify.lintClean === true), result ? JSON.stringify(result) : undefined);
  check('happy-path case: no spurious warning logged on a clean success', logged.length === 0, JSON.stringify(logged));
}

(async () => {
  await driveThrowsCase();
  await driveNullCase();
  await driveHappyCase();
  process.exit(failed);
})();
NODE

if ! node "$TMP/extract-verify-try-catch.cjs" "$WF" "$TMP" > "$TMP/verify-try-catch.out" 2>&1; then
  note "Verify-phase try/catch extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/verify-try-catch.out"
  fail=1
else
  sed 's/^/    /' "$TMP/verify-try-catch.out"
fi

[ "$fail" -eq 0 ] && note "Verify phase stays on model: 'haiku' (a deliberate, examined no-op decision — see this eval's header — never a silent regression check to flip without reconsidering); its agent() call is wrapped in try/catch (grepped structurally); and driving the verbatim-extracted try/catch block with three stubbed agent() implementations proves it does NOT re-throw and degrades to a null verify with a named, error-quoting warning when agent() throws the exact #720/#727 failure signature, leaves the documented null-return contract path unaffected, and does not disturb or spuriously warn on the happy path"
exit "$fail"
