#!/usr/bin/env bash
# falsify-gate-lock-window.sh — regression eval for
# research-harness-template#738 ("Falsify write step never opens the
# required .gate-active window").
#
# Root cause: scripts/falsify.sh refuses (exit 3) to write any
# reports/<topic>/findings/*.json finding unless that topic's
# <topic>/.gate-active marker is present and fresh (<240min) --
# guard-falsify-gate.sh's PreToolUse hook denies the same shape even
# earlier. SPEC §6b restricts opening that marker (and its companion
# scripts/run-lock.sh topic lock) to two callers: the orchestrator's Phase 2
# loop, and the /falsify command (.claude/commands/falsify.md). The vendored
# JS engine's OWN write step (.claude/workflows/research-falsify.js, the
# ONLY module that ever invokes scripts/falsify.sh against a session
# finding) was neither of those two callers and never touched the marker or
# the lock at all -- so every write research-pipeline.js's full/augment/
# pivot/import/falsify modes (or a direct top-level scriptPath call) made
# through this module was either denied outright by the hook, or exited 3
# from falsify.sh once the hook was bypassed. No finding's verdict was ever
# actually persisted to disk through this engine.
#
# The fix adds, to research-falsify.js's Gate phase:
#   1. an acquire step (scripts/run-lock.sh acquire + touch .gate-active)
#      BEFORE any finding write, whose failure throws immediately without
#      ever entering the write loop;
#   2. a per-finding refresh step (scripts/run-lock.sh refresh + touch
#      .gate-active) before that finding's own mutations, whose failure
#      (lost ownership) throws immediately;
#   3. a release step (rm -f .gate-active/.gate-batch + scripts/run-lock.sh
#      release) in a `finally` block around the write loop, so it runs on
#      EVERY exit path -- the loop completing normally, or ANY error thrown
#      out of it (including the acquire/refresh throws above, and the
#      pre-existing #747/#659 write-failure throws) -- mirroring
#      falsify.md's own "release the lock on EVERY exit path" Phase 2
#      contract.
#
# This eval extracts the REAL acquire/try/finally control-flow span verbatim
# from research-falsify.js (a plain marker-to-marker substring -- the span
# is a flat statement sequence, not itself a single brace-balanced block, so
# this does not reuse falsify-write-failure-gated.sh's balanced-brace
# extractor) and drives it with a stubbed pipeline()/agent(), proving:
#
#   A. acquire fails (agent() reports ok=false) -- throws BEFORE pipeline()
#      is ever called, and no release-agent call is made (the throw happens
#      before the try/finally is ever entered -- there is nothing to
#      release, since nothing was ever acquired).
#   B. acquire succeeds, the write loop (pipeline()) completes normally --
#      no throw; the release-agent call fires exactly once, naming the
#      correct topic dir and the exact token acquire returned; the acquire
#      prompt itself named run-lock.sh acquire, touch .gate-active, and the
#      topic dir.
#   C. acquire succeeds, the write loop (pipeline()) THROWS (simulating any
#      per-finding failure -- a #747 write failure, a #659 half-write, or
#      this fix's own #738 lock-refresh-lost throw) -- the SAME error
#      propagates out of the whole span (the finally does not swallow it),
#      AND the release-agent call STILL fires exactly once with the correct
#      token -- proving the window is closed even on the failure path, not
#      just the happy path.
#   D. acquire reports ok=true but omits token (the PR#831 Copilot review
#      finding: LOCK_ACQUIRE_SCHEMA only requires `ok`, so an ok=true
#      response missing `token` still passes schema validation) -- throws
#      BEFORE the try/finally is ever entered, with no release-agent call
#      (nothing was actually acquired with a usable token to release).
#   E. acquire succeeds, the write loop (pipeline()) THROWS, AND the
#      release-agent cleanup call in `finally` ALSO throws (the second
#      PR#831 Copilot review finding: the cleanup call could itself fail
#      and mask the real gating error) -- the ORIGINAL pipeline() error
#      must still be the one that propagates out of the span, not the
#      cleanup error.
#
# Structural checks (cheap, no stub execution) additionally prove the
# per-finding refresh step exists, is positioned BEFORE the write step
# (never after -- a refresh after the write would not have protected the
# write itself), and that release's rm targets exactly .gate-active and
# .gate-batch (the same two markers falsify.md's own Phase 2 closes).
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  falsify-gate-lock-window: %s\n' "$1"; }

WF=.claude/workflows/research-falsify.js
command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

# ---------------------------------------------------------------------------
# Structural checks against the real source (no execution).
# ---------------------------------------------------------------------------
src="$(cat "$WF")"

idx_acquire=$(node -e '
const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
const i=s.indexOf("const lockAcquired = await agent(");
process.stdout.write(String(i));
' "$WF")
idx_refresh=$(node -e '
const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
const i=s.indexOf("const lockFresh = await agent(");
process.stdout.write(String(i));
' "$WF")
idx_write=$(node -e '
const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
const i=s.indexOf("let written = await agent(writeBrief");
process.stdout.write(String(i));
' "$WF")
idx_finally=$(node -e '
const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
const i=s.indexOf("} finally {");
process.stdout.write(String(i));
' "$WF")
idx_rollup=$(node -e '
const fs=require("fs");const s=fs.readFileSync(process.argv[1],"utf8");
const i=s.indexOf("phase(\x27Rollup\x27)");
process.stdout.write(String(i));
' "$WF")

if [ "$idx_acquire" -lt 0 ] 2>/dev/null || [ -z "$idx_acquire" ] || [ "$idx_acquire" = "-1" ]; then
  note "acquire step (const lockAcquired = await agent() not found in $WF"; fail=1
fi
if [ "$idx_refresh" = "-1" ] || [ -z "$idx_refresh" ]; then
  note "per-finding refresh step (const lockFresh = await agent() not found in $WF"; fail=1
fi
if [ "$idx_write" = "-1" ] || [ -z "$idx_write" ]; then
  note "write step marker (let written = await agent(writeBrief) not found in $WF"; fail=1
fi
if [ "$idx_finally" = "-1" ] || [ -z "$idx_finally" ]; then
  note "finally block (} finally {) not found in $WF"; fail=1
fi
if [ "$idx_rollup" = "-1" ] || [ -z "$idx_rollup" ]; then
  note "phase('Rollup') marker not found in $WF"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  # Ordering: acquire happens before refresh, refresh happens before the
  # write, and the finally (release) block sits after the write step and
  # before Rollup -- exactly the intended acquire -> [refresh -> write]* ->
  # release sequence.
  if [ "$idx_acquire" -lt "$idx_refresh" ]; then note "ok  acquire precedes the per-finding refresh step"; else note "FAIL acquire does not precede the per-finding refresh step"; fail=1; fi
  if [ "$idx_refresh" -lt "$idx_write" ]; then note "ok  the per-finding refresh precedes that finding's own write step"; else note "FAIL the per-finding refresh step is not positioned before the write step"; fail=1; fi
  if [ "$idx_write" -lt "$idx_finally" ]; then note "ok  the write step precedes the finally (release) block"; else note "FAIL the write step is not positioned before the finally block"; fail=1; fi
  if [ "$idx_finally" -lt "$idx_rollup" ]; then note "ok  the finally (release) block precedes phase('Rollup')"; else note "FAIL the finally block is not positioned before phase('Rollup')"; fail=1; fi
fi

grep -q 'run-lock.sh acquire' "$WF" || { note "FAIL acquire prompt text does not mention run-lock.sh acquire"; fail=1; }
grep -q 'run-lock.sh refresh' "$WF" || { note "FAIL refresh prompt text does not mention run-lock.sh refresh"; fail=1; }
grep -q 'run-lock.sh release' "$WF" || { note "FAIL release prompt text does not mention run-lock.sh release"; fail=1; }
grep -q 'rm -f \${RDIR}/.gate-active \${RDIR}/.gate-batch' "$WF" \
  || { note "FAIL release step does not rm -f both \${RDIR}/.gate-active and \${RDIR}/.gate-batch"; fail=1; }
grep -q 'touch \${RDIR}/.gate-active' "$WF" \
  || { note "FAIL no step opens/refreshes \${RDIR}/.gate-active via touch"; fail=1; }

# ---------------------------------------------------------------------------
# Behavioral: extract the real acquire/try/finally span (a flat marker-to-
# marker substring -- this span is a sequence of statements, not itself one
# balanced block, so it is sliced directly rather than brace-matched) and
# drive it with a stubbed pipeline()/agent().
# ---------------------------------------------------------------------------
cat > "$TMP/harness.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const wfPath = process.argv[2];
const src = fs.readFileSync(wfPath, 'utf8');

const START = 'const lockAcquired = await agent(';
const END = "phase('Rollup')";
const s = src.indexOf(START);
const e = src.indexOf(END, s);
if (s < 0) { console.log('FAIL start marker not found'); process.exit(1); }
if (e < 0) { console.log('FAIL end marker not found'); process.exit(1); }
const span = src.slice(s, e);
console.log('  ok  acquire/try/finally span extracted verbatim (' + span.length + ' chars)');

// Build a harness module: the span references `agent`, `pipeline`, `phase`,
// `log`, `RDIR`, `H`, `working`, `LOCK_ACQUIRE_SCHEMA`, `LOCK_STATUS_SCHEMA`,
// plus a handful of names only ever referenced inside the (never-invoked, in
// this stub) pipeline() callback closures (LENSES, QUERY_BUDGET,
// DECOMPOSE_SCHEMA, LENS_SCHEMA, mergeVotes, pairLensResults, REGATE,
// RUN_DATE, buildFixtureEntry, REMEDIATION_CONTRACT, WRITE_SCHEMA) -- these
// closures are defined but this harness's pipeline() stub never calls them,
// so they only need to exist as valid names, never actually execute.
const harnessSrc = `
module.exports = async function runSpan(agent, pipeline, RDIR, H, working, LOCK_ACQUIRE_SCHEMA, LOCK_STATUS_SCHEMA) {
  const phase = () => {};
  const log = () => {};
  const LENSES = [];
  const QUERY_BUDGET = 6;
  const DECOMPOSE_SCHEMA = {};
  const LENS_SCHEMA = {};
  const REGATE = false;
  const RUN_DATE = '2026-01-01T00:00:00.000Z';
  const REMEDIATION_CONTRACT = 'stub';
  const WRITE_SCHEMA = {};
  function mergeVotes() { return { verdict: 'survived', contested: false }; }
  function pairLensResults() { return []; }
  function buildFixtureEntry() { return {}; }
${span}
};
`;
fs.writeFileSync(process.argv[3], harnessSrc);
NODE

fail_behavior=0
check() {
  if [ "$2" = "0" ]; then echo "  ok  $1"; else echo "FAIL $1"; fail_behavior=1; fi
}

node "$TMP/harness.cjs" "$WF" "$TMP/span-module.cjs" || { note "span extraction failed"; fail=1; }

if [ "$fail" -eq 0 ]; then
cat > "$TMP/run-cases.cjs" <<'NODE'
'use strict';
const runSpan = require(process.argv[2]);

async function caseA() {
  const calls = [];
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt });
    if (opts.label === 'falsify:lock-acquire') return { ok: false, error: 'run-lock: DENIED - a live run owns reports/t' };
    throw new Error('unexpected agent() call: ' + opts.label);
  };
  const pipeline = async () => { calls.push({ label: '__pipeline_called__' }); throw new Error('pipeline() must never be called when acquire failed'); };
  let threw = null;
  try { await runSpan(agent, pipeline, 'reports/t', '.', [{ id: 'f1' }], {}, {}); } catch (e) { threw = e; }
  const pipelineCalled = calls.some((c) => c.label === '__pipeline_called__');
  const releaseCalled = calls.some((c) => c.label === 'falsify:lock-release');
  return { threw, pipelineCalled, releaseCalled, calls };
}

async function caseB() {
  const calls = [];
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt });
    if (opts.label === 'falsify:lock-acquire') return { ok: true, token: 'TOK-B-123' };
    if (opts.label === 'falsify:lock-release') return { ok: true };
    throw new Error('unexpected agent() call: ' + opts.label);
  };
  const pipeline = async () => { calls.push({ label: '__pipeline_called__' }); return [{ id: 'f1', verdict: 'survived' }]; };
  let threw = null, result = null;
  try { result = await runSpan(agent, pipeline, 'reports/t', '.', [{ id: 'f1' }], {}, {}); } catch (e) { threw = e; }
  const releaseCalls = calls.filter((c) => c.label === 'falsify:lock-release');
  const acquireCall = calls.find((c) => c.label === 'falsify:lock-acquire');
  return { threw, result, releaseCalls, acquireCall, calls };
}

async function caseC() {
  const calls = [];
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt });
    if (opts.label === 'falsify:lock-acquire') return { ok: true, token: 'TOK-C-456' };
    if (opts.label === 'falsify:lock-release') return { ok: true };
    throw new Error('unexpected agent() call: ' + opts.label);
  };
  const pipeline = async () => { throw new Error('simulated per-finding failure (e.g. #747/#659/#738-refresh-lost)'); };
  let threw = null;
  try { await runSpan(agent, pipeline, 'reports/t', '.', [{ id: 'f1' }], {}, {}); } catch (e) { threw = e; }
  const releaseCalls = calls.filter((c) => c.label === 'falsify:lock-release');
  return { threw, releaseCalls, calls };
}

// D. acquire reports ok=true but no token -- PR#831 Copilot review finding.
async function caseD() {
  const calls = [];
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt });
    if (opts.label === 'falsify:lock-acquire') return { ok: true };
    throw new Error('unexpected agent() call: ' + opts.label);
  };
  const pipeline = async () => { calls.push({ label: '__pipeline_called__' }); throw new Error('pipeline() must never be called when acquire returned no token'); };
  let threw = null;
  try { await runSpan(agent, pipeline, 'reports/t', '.', [{ id: 'f1' }], {}, {}); } catch (e) { threw = e; }
  const pipelineCalled = calls.some((c) => c.label === '__pipeline_called__');
  const releaseCalled = calls.some((c) => c.label === 'falsify:lock-release');
  return { threw, pipelineCalled, releaseCalled, calls };
}

// E. acquire succeeds, pipeline() throws, AND the release cleanup agent()
// call in `finally` ALSO throws -- PR#831 Copilot review finding: the
// original pipeline() error must still be what propagates, not the cleanup
// error.
async function caseE() {
  const calls = [];
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt });
    if (opts.label === 'falsify:lock-acquire') return { ok: true, token: 'TOK-E-789' };
    if (opts.label === 'falsify:lock-release') throw new Error('simulated cleanup-call failure (network blip / model error)');
    throw new Error('unexpected agent() call: ' + opts.label);
  };
  const pipeline = async () => { throw new Error('simulated per-finding failure, ORIGINAL error'); };
  let threw = null;
  try { await runSpan(agent, pipeline, 'reports/t', '.', [{ id: 'f1' }], {}, {}); } catch (e) { threw = e; }
  return { threw, calls };
}

(async () => {
  let fail = 0;
  const check = (name, cond, detail) => {
    if (cond) console.log('  ok  ' + name);
    else { fail = 1; console.log('FAIL  ' + name + (detail ? ' -- ' + detail : '')); }
  };

  const a = await caseA();
  check('A. acquire failure throws', !!a.threw, a.threw ? '' : 'did not throw');
  check('A. thrown error mentions the topic dir', !!(a.threw && /reports\/t/.test(a.threw.message)), a.threw ? a.threw.message : '');
  check('A. pipeline() is never called when acquire failed', !a.pipelineCalled, JSON.stringify(a.calls));
  check('A. no release-agent call is made when nothing was ever acquired', !a.releaseCalled, JSON.stringify(a.calls));

  const b = await caseB();
  check('B. acquire success + normal pipeline completion: no throw', !b.threw, b.threw ? b.threw.message : '');
  check('B. acquire prompt names run-lock.sh acquire, touch .gate-active, and the topic dir', !!(b.acquireCall && /run-lock\.sh acquire/.test(b.acquireCall.prompt) && /touch reports\/t\/\.gate-active/.test(b.acquireCall.prompt) && /reports\/t/.test(b.acquireCall.prompt)), b.acquireCall ? b.acquireCall.prompt : 'no acquire call');
  check('B. release-agent call fires exactly once on the success path', b.releaseCalls.length === 1, `count=${b.releaseCalls.length}`);
  check('B. release prompt names the exact acquired token', !!(b.releaseCalls[0] && b.releaseCalls[0].prompt.includes('TOK-B-123')), b.releaseCalls[0] ? b.releaseCalls[0].prompt : 'no release call');

  const c = await caseC();
  check('C. a pipeline() throw still propagates out of the span (finally does not swallow it)', !!(c.threw && /simulated per-finding failure/.test(c.threw.message)), c.threw ? c.threw.message : 'did not throw');
  check('C. release-agent call STILL fires exactly once on the failure path', c.releaseCalls.length === 1, `count=${c.releaseCalls.length}`);
  check('C. release prompt on the failure path names the exact acquired token', !!(c.releaseCalls[0] && c.releaseCalls[0].prompt.includes('TOK-C-456')), c.releaseCalls[0] ? c.releaseCalls[0].prompt : 'no release call');

  const d = await caseD();
  check('D. acquire ok=true with no token throws', !!d.threw, d.threw ? '' : 'did not throw');
  check('D. thrown error mentions the missing token', !!(d.threw && /token/i.test(d.threw.message)), d.threw ? d.threw.message : '');
  check('D. pipeline() is never called when acquire returned no token', !d.pipelineCalled, JSON.stringify(d.calls));
  check('D. no release-agent call is made when acquire returned no token', !d.releaseCalled, JSON.stringify(d.calls));

  const e = await caseE();
  check('E. the ORIGINAL pipeline() error propagates even when cleanup itself throws', !!(e.threw && /ORIGINAL error/.test(e.threw.message)), e.threw ? e.threw.message : 'did not throw');
  check('E. the cleanup-call error does NOT mask/replace the original error', !!(e.threw && !/simulated cleanup-call failure/.test(e.threw.message)), e.threw ? e.threw.message : '');

  process.exit(fail);
})();
NODE
  node "$TMP/run-cases.cjs" "$TMP/span-module.cjs"
  [ "$?" -eq 0 ] || fail_behavior=1
fi

[ "$fail_behavior" -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && note "the gate window / run lock are acquired before any write (a failed acquire, or an acquire that omits its token, throws before pipeline() ever runs, with no release call since nothing was acquired), refreshed per finding before that finding's write, and released/closed via a finally block on EVERY exit path -- the normal-completion path, a thrown per-finding failure, and a failure where the release cleanup call itself also throws (the original error still propagates) -- with the release call always naming the exact token acquire returned"
exit "$fail"
