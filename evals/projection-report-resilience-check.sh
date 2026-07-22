#!/usr/bin/env bash
# projection-report-resilience-check.sh — regression eval for
# research-harness-template#727: research-projection.js's Report phase
# (.claude/workflows/research-projection.js) shares the same unguarded
# agent()-throw exposure that #720 already fixed for the Index phase.
# `agent({schema})` surfaces the "subagent completed its real work but never
# called StructuredOutput" non-compliance class as a THROW (not the
# documented "returns null on death" contract for timeout/exhausted-retry/
# user-skip), and the Report phase had no try/catch around its one
# `agent()` call — a throw there propagated unexplained all the way up.
#
# UNLIKE Index (#720), the fix here does NOT degrade to a null/ok:false
# report: every downstream field (reportPath/reportId/frontmatterLevel/
# genreApplied/genreSkillInvoked/provenanceOutcome/provenanceReason) is read
# unconditionally by this phase's own `if (!report) throw` a few lines below
# and by the Index/Verify phases and final return further down — inventing a
# degraded report shape would be a caller-visible-contract decision this
# issue explicitly declines to prescribe. The fix instead re-throws a
# clearer, #727-tagged Error naming the underlying failure, after logging a
# named WARNING — never silently swallowed, never degraded.
#
# Three proof classes:
#
#   A. Structural: `model: 'sonnet'` stays in the Report-phase agent()
#      options (regression trap against silently downgrading to haiku,
#      mirroring projection-index-resilience-check.sh's own model-guard
#      case), and the call is wrapped in try/catch.
#
#   B. Behavioral: the actual try/catch block (plus the immediately
#      following pre-existing `if (!report) throw` line) is extracted
#      VERBATIM (brace-matched, never re-typed) from the module and driven
#      with three stubbed agent() implementations:
#        (a) throws the exact observed failure signature -> the block must
#            re-throw a NEW Error naming research-harness-template#727,
#            never swallow it into a degraded report.
#        (b) resolves to null (the documented "returns null on death"
#            contract path) -> the pre-existing `if (!report) throw` still
#            fires, UNCHANGED by this fix.
#        (c) resolves normally -> the happy path and report shape are
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
note() { printf '  projection-report-resilience-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-projection workflow must ship (Epic #543, Task #569)"; exit 2; }

# ============================================================================
# A: structural — model: 'sonnet' inside the Report phase's own agent()
# options span (phase('Report') .. phase('Index')), never haiku; try/catch
# present around the call.
# ============================================================================
report_span="$(awk '/^phase\(.Report.\)/{f=1} f{print} /^phase\(.Index.\)/{exit}' "$WF")"
[ -n "$report_span" ] || { note "could not locate the Report phase body (phase('Report') .. phase('Index') span) in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF "label: 'projection:report', model: 'sonnet'" <<<"$report_span" \
  || { note "Report phase's agent() call is no longer 'model: sonnet' — has been downgraded, or the option shape changed"; fail=1; }

grep -qF 'let report' <<<"$report_span" \
  || { note "Report phase no longer declares 'let report' — the #727 guard shape has regressed or the module's structure changed"; fail=1; }
grep -qF 'try {' <<<"$report_span" \
  || { note "Report phase does not wrap its agent() call in a try block — the #727 guard-and-rethrow fix is missing or has regressed"; fail=1; }
grep -qF 'catch (err)' <<<"$report_span" \
  || { note "Report phase has no catch block around its agent() call — the #727 guard-and-rethrow fix is missing or has regressed"; fail=1; }
grep -qF "if (!report) throw new Error('research-projection: report rendering failed')" <<<"$report_span" \
  || { note "the pre-existing 'if (!report) throw' guard is missing or has changed wording — this must survive the #727 fix unchanged (it covers a clean-but-falsy return, a different case than agent() itself throwing)"; fail=1; }

# ============================================================================
# B: behavioral — extract the try/catch block PLUS the immediately following
# pre-existing null-guard line VERBATIM (brace-matched for the try/catch,
# same technique as projection-index-resilience-check.sh /
# projection-supersession-check.sh) and drive it with three stubbed agent()
# implementations.
# ============================================================================
cat > "$TMP/extract-report-try-catch.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-report-try-catch.cjs <research-projection.js> <tmpdir>');
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

// Verbatim extraction of `let report` through the closing brace of the
// `} catch (err) { ... }` block, PLUS the immediately following pre-existing
// null-guard line -- proven to still be exactly adjacent (no drift) by
// requiring it to appear immediately after the extracted try/catch span in
// the live source before appending it.
let runReportTryCatch;
try {
  const tryCatchSpan = extractSpan(
    src,
    'let report',
    '} catch (err) {',
  );
  const afterTryCatch = src.slice(src.indexOf(tryCatchSpan) + tryCatchSpan.length);
  const nullGuardLine = "if (!report) throw new Error('research-projection: report rendering failed')";
  const trimmedAfter = afterTryCatch.replace(/^\s*\n/, '').split('\n')[0];
  if (!trimmedAfter.trim().startsWith(nullGuardLine)) {
    throw new Error(`expected the pre-existing null-guard line immediately after the try/catch block, found: ${JSON.stringify(trimmedAfter)}`);
  }
  const spanText = tryCatchSpan + '\n' + nullGuardLine;
  const harnessSrc =
    'async function runReportTryCatch(agent, log, TOPIC, H, RDIR, SYN, GENRE, genreResolution, SLUG, genreStepText, REPORT_SCHEMA) {\n' +
    spanText + '\n' +
    '  return { report };\n' +
    '}\n' +
    'module.exports = { runReportTryCatch };\n';
  const harnessPath = path.join(tmpDir, 'report-try-catch-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ runReportTryCatch } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the Report-phase try/catch (+ null-guard) from ${wfPath}: ${e.message}`);
  process.exit(1);
}

const commonArgs = ['evaltopic', '.', 'reports/evaltopic', '/tmp/eval-synthesis.json', 'general', { genreArg: 'general', genrePackEnabled: false, genreSkillRef: '' }, 'evaltopic', '', {}];

async function driveThrowsCase() {
  // The exact observed failure signature (mirroring #720): the subagent
  // completes its real render/falsify/provenance work but never calls
  // StructuredOutput -- surfaced by agent({schema}) as a thrown Error, not a
  // null return.
  const agent = async () => {
    throw new Error('agent({schema}): subagent completed without calling StructuredOutput (after in-conversation nudge)');
  };
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  try {
    await runReportTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('throws case: the block DOES re-throw (Report cannot safely degrade — every downstream field is read unconditionally)', threw !== null);
  check('throws case: the re-thrown error names research-harness-template#727', !!(threw && threw.message.includes('#727')), threw ? threw.message : undefined);
  check('throws case: the re-thrown error is a NEW Error, not the original bubbling unexplained (message names "Report phase failed")', !!(threw && threw.message.includes('Report phase failed')), threw ? threw.message : undefined);
  check('throws case: the underlying error text is not lost (surfaced in the re-thrown message)', !!(threw && threw.message.includes('subagent completed without calling StructuredOutput')), threw ? threw.message : undefined);
  check('throws case: a WARNING was logged before the re-throw', logged.length > 0, 'no log() calls captured');
  check('throws case: the warning names research-harness-template#727', logged.some((m) => m.includes('#727')), JSON.stringify(logged));
}

async function driveNullCase() {
  // The documented "agent() returns null on death (timeout, unrecoverable
  // error, exhausted schema retries, or user skip)" contract path -- must
  // remain unaffected by the #727 fix: the pre-existing `if (!report) throw`
  // still fires, unchanged.
  const agent = async () => null;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  try {
    await runReportTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('null-return case: the pre-existing null-guard still throws', threw !== null);
  check('null-return case: the thrown message is the ORIGINAL unchanged guard message, not the #727 wrapper', !!(threw && threw.message === 'research-projection: report rendering failed'), threw ? threw.message : undefined);
  check('null-return case: no #727 WARNING was logged (this is the pre-existing guard, not the new catch block)', logged.length === 0, JSON.stringify(logged));
}

async function driveHappyCase() {
  const goodReport = {
    reportPath: 'reports/evaltopic/evaltopic.md',
    reportId: 'urn:mif:evaltopic:report',
    frontmatterLevel: 3,
    checksAddressed: ['check-1'],
    verificationVerdict: 'survived',
    genreApplied: false,
    genreSkillInvoked: '',
    provenanceOutcome: 'declined',
    provenanceReason: 'capture disabled',
  };
  const agent = async () => goodReport;
  const logged = [];
  const log = (msg) => logged.push(msg);
  let threw = null;
  let result = null;
  try {
    result = await runReportTryCatch(agent, log, ...commonArgs);
  } catch (e) {
    threw = e;
  }
  check('happy-path case: the block does not throw', threw === null, threw ? threw.message : undefined);
  check('happy-path case: report is returned through unmutated', !!(result && result.report && result.report.reportPath === goodReport.reportPath), result ? JSON.stringify(result) : undefined);
  check('happy-path case: no spurious warning logged on a clean success', logged.length === 0, JSON.stringify(logged));
}

(async () => {
  await driveThrowsCase();
  await driveNullCase();
  await driveHappyCase();
  process.exit(failed);
})();
NODE

if ! node "$TMP/extract-report-try-catch.cjs" "$WF" "$TMP" > "$TMP/report-try-catch.out" 2>&1; then
  note "Report-phase try/catch extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/report-try-catch.out"
  fail=1
else
  sed 's/^/    /' "$TMP/report-try-catch.out"
fi

[ "$fail" -eq 0 ] && note "Report phase stays on model: 'sonnet'; its agent() call is wrapped in try/catch (grepped structurally); the pre-existing 'if (!report) throw' null-guard is unchanged; and driving the verbatim-extracted try/catch (+ null-guard) block with three stubbed agent() implementations proves it RE-THROWS a new, #727-tagged error (never swallowing) when agent() throws the exact #720/#727 failure signature, leaves the pre-existing null-return guard unaffected, and does not disturb or spuriously warn on the happy path"
exit "$fail"
