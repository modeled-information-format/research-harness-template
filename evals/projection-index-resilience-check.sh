#!/usr/bin/env bash
# projection-index-resilience-check.sh — regression eval for
# research-harness-template#720: research-projection.js's Index phase
# (.claude/workflows/research-projection.js) completed its real README/graph
# work in production, then never called StructuredOutput — and, when the
# harness's structured-output-enforce nudge fired, asserted in prose that it
# HAD already called the tool, which it never did. `agent({schema})` surfaces
# that specific non-compliance class as a THROW (not the documented "returns
# null on death" contract for timeout/exhausted-retry/user-skip), and the
# Index phase had no try/catch around its one `agent()` call — the throw
# propagated all the way up and hard-failed a 304-agent-call, ~3.4-hour
# pipeline run one phase from the finish line.
#
# The fix (mirroring this eval's own precedent in
# projection-supersession-check.sh's brace-matched verbatim-extraction
# technique, cases C/D): route projection:index to `sonnet` (matching the
# Report phase's existing precedent for the identical mixed judgment-plus-
# script-pipeline task shape) and wrap the call in try/catch, degrading to a
# null index with a specific, named warning on any throw rather than
# re-throwing.
#
# Two proof classes:
#
#   A. Structural: `model: 'sonnet'` appears inside the Index-phase agent()
#      options (regression trap against silently reverting to haiku).
#
#   B. Behavioral: the actual try/catch block is extracted VERBATIM
#      (brace-matched, never re-typed) from the module and driven with three
#      stubbed agent() implementations:
#        (a) throws the exact observed failure signature -> the block must
#            NOT re-throw; index ends up null/falsy; a warning naming the
#            underlying error is logged.
#        (b) resolves to null (the documented "returns null on death"
#            contract path) -> unchanged behavior, no crash.
#        (c) resolves normally -> the happy path and index shape are
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
note() { printf '  projection-index-resilience-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-projection workflow must ship (Epic #543, Task #569)"; exit 2; }

# ============================================================================
# A: structural — model: 'sonnet' inside the Index phase's own agent() options
# span (phase('Index') .. phase('Verify')), never haiku. This is the exact
# regression this eval exists to trap: reverting the model choice back to
# haiku while leaving the try/catch in place would still leave every full-mode
# pipeline run exposed to the same nondeterministic StructuredOutput
# non-compliance the issue observed, just silently degraded instead of
# crashing — quieter, not fixed.
# ============================================================================
index_span="$(awk '/^phase\(.Index.\)/{f=1} f{print} /^phase\(.Verify.\)/{exit}' "$WF")"
[ -n "$index_span" ] || { note "could not locate the Index phase body (phase('Index') .. phase('Verify') span) in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF "label: 'projection:index', model: 'sonnet'" <<<"$index_span" \
  || { note "Index phase's agent() call is no longer 'model: sonnet' — research-harness-template#720's model-escalation fix has regressed (back to haiku, or the option shape changed)"; fail=1; }
grep -qF "model: 'haiku'" <<<"$index_span" \
  && { note "Index phase still (or again) specifies model: 'haiku' somewhere in its span — this is exactly the model class that produced the observed StructuredOutput non-compliance in #720"; fail=1; }

grep -qF 'try {' <<<"$index_span" \
  || { note "Index phase no longer wraps its agent() call in a try block — the #720 non-fatal-degrade fix has regressed; a StructuredOutput non-compliance throw would once again propagate and hard-fail the whole pipeline"; fail=1; }
grep -qF 'catch (err)' <<<"$index_span" \
  || { note "Index phase no longer has a catch block around its agent() call — the #720 non-fatal-degrade fix has regressed"; fail=1; }

# ============================================================================
# B: behavioral — extract the try/catch block VERBATIM (brace-matched, same
# technique as projection-supersession-check.sh's preflight-guard extraction)
# and drive it with three stubbed agent() implementations.
# ============================================================================
cat > "$TMP/extract-index-try-catch.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-index-try-catch.cjs <research-projection.js> <tmpdir>');
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

// Verbatim extraction of `let index = null` through the closing brace of the
// `} catch (err) { ... }` block -- the SAME span the module runs, never a
// bash/JS reimplementation of the try/catch logic.
let runIndexTryCatch;
try {
  const spanText = extractSpan(
    src,
    'let index = null',
    '} catch (err) {',
  );
  const harnessSrc =
    'async function runIndexTryCatch(agent, log, TOPIC, H, RDIR, INDEX_SCHEMA) {\n' +
    spanText + '\n' +
    '  return { index };\n' +
    '}\n' +
    'module.exports = { runIndexTryCatch };\n';
  const harnessPath = path.join(tmpDir, 'index-try-catch-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ runIndexTryCatch } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the Index-phase try/catch from ${wfPath}: ${e.message}`);
  process.exit(1);
}

async function driveThrowsCase() {
  // The exact observed failure signature (research-harness-template#720):
  // the subagent completes its real work but never calls StructuredOutput,
  // then asserts (falsely) that it already did when nudged -- surfaced by
  // agent({schema}) as a thrown Error, not a null return.
  const agent = async () => {
    throw new Error('agent({schema}): subagent completed without calling StructuredOutput (after in-conversation nudge)');
  };
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runIndexTryCatch(agent, log, 'evaltopic', '.', 'reports/evaltopic', {});
  } catch (e) {
    threw = e;
  }
  check('throws case: the block does NOT re-throw (the pipeline must survive this phase)', threw === null, threw ? threw.message : undefined);
  check('throws case: index degrades to null/falsy rather than a stale or partial value', !!(result && !result.index), result ? JSON.stringify(result) : undefined);
  check('throws case: a warning was logged', logged.length > 0, 'no log() calls captured');
  check('throws case: the warning names research-harness-template#720', logged.some((m) => m.includes('#720')), JSON.stringify(logged));
  check('throws case: the warning surfaces the underlying error text', logged.some((m) => m.includes('subagent completed without calling StructuredOutput')), JSON.stringify(logged));
}

async function driveNullCase() {
  // The documented "agent() returns null on death (timeout, unrecoverable
  // error, exhausted schema retries, or user skip)" contract path -- must
  // remain unaffected by the #720 fix (this was already handled before).
  const agent = async () => null;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runIndexTryCatch(agent, log, 'evaltopic', '.', 'reports/evaltopic', {});
  } catch (e) {
    threw = e;
  }
  check('null-return case: the block does not throw', threw === null, threw ? threw.message : undefined);
  check('null-return case: index is null (unchanged behavior)', !!(result && result.index === null), result ? JSON.stringify(result) : undefined);
}

async function driveHappyCase() {
  const goodIndex = {
    readmePath: 'reports/evaltopic/README.md',
    readmeCheckPassed: true,
    graphRefreshed: true,
    graphAssertPassed: true,
    changedFiles: ['reports/evaltopic/README.md', 'reports/evaltopic/knowledge-graph.json'],
  };
  const agent = async () => goodIndex;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runIndexTryCatch(agent, log, 'evaltopic', '.', 'reports/evaltopic', {});
  } catch (e) {
    threw = e;
  }
  check('happy-path case: the block does not throw', threw === null, threw ? threw.message : undefined);
  check('happy-path case: index is returned through unmutated', !!(result && result.index && result.index.readmePath === goodIndex.readmePath), result ? JSON.stringify(result) : undefined);
  check('happy-path case: no spurious warning logged on a clean success', logged.length === 0, JSON.stringify(logged));
}

(async () => {
  await driveThrowsCase();
  await driveNullCase();
  await driveHappyCase();
  process.exit(failed);
})();
NODE

if ! node "$TMP/extract-index-try-catch.cjs" "$WF" "$TMP" > "$TMP/index-try-catch.out" 2>&1; then
  note "Index-phase try/catch extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/index-try-catch.out"
  fail=1
else
  sed 's/^/    /' "$TMP/index-try-catch.out"
fi

[ "$fail" -eq 0 ] && note "Index phase runs on model: 'sonnet' (never haiku, matching the Report phase's precedent for the identical mixed judgment-plus-script-pipeline task shape); its agent() call is wrapped in try/catch (grepped structurally, never a comment-only mention); and driving the verbatim-extracted try/catch block with three stubbed agent() implementations proves it does NOT re-throw and degrades to a null index with a named, error-quoting warning when agent() throws the exact #720 failure signature, leaves the documented null-return contract path unaffected, and does not disturb or spuriously warn on the happy path"
exit "$fail"