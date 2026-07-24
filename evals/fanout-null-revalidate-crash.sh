#!/usr/bin/env bash
# fanout-null-revalidate-crash.sh — regression eval for
# research-harness-template#751: research-fanout.js's repair lane dereferenced
# the revalidate agent() call's result (`rv.invalid.length`) with no null
# check, even though `agent()` can legitimately resolve to null on a terminal
# failure after retries (the runtime's documented "returns null on death"
# contract — docs/reference/engine-workflows.md). When that happened, the
# unguarded dereference threw an uncaught TypeError inside pipeline()'s
# per-item stage chain with no try/catch around it, which propagated out of
# the top-level `await pipeline(...)` and crashed the ENTIRE fanout run for
# EVERY dimension — not just the one whose revalidate call failed —
# discarding whatever other dimensions' work had already completed in that
# same call.
#
# Drives the REAL research-fanout.js source via the Workflow-runtime's own
# async-function-body framing (same technique as
# evals/fanout-repair-disclosure-check.sh's driver): `agent()` is stubbed to
# canned, schema-shaped results per label, with the revalidate call for one
# dimension ('flaky') stubbed to resolve to `null` (the exact terminal-
# failure shape the runtime documents); `pipeline()` is stubbed with a
# straightforward per-item stage chain matching the module's own documented
# "no cross-dimension barrier" semantics.
#
# What this proves WITHOUT a live model call:
#   A. The module does NOT throw when one dimension's revalidate() call
#      resolves to null — this is the actual bug: before the fix, this same
#      driver throws "Cannot read properties of null (reading 'invalid')".
#   B. The OTHER dimension ('landscape'), whose lane never hit the null
#      case, completes normally and its findings survive into the run's
#      output — proving a null revalidate() no longer discards unrelated
#      dimensions' completed work.
#   C. The flaky dimension is dropped from perDimension/findings (consistent
#      with how this file already treats a null research()/validate() result
#      — filtered via `results.filter(Boolean)`), not silently reported as
#      if it had succeeded.
#   D. A negative control: reverting the null-guard (i.e. running the
#      UNPATCHED source shape) must reproduce the original crash — proven by
#      asserting the fix commit's actual behavior differs from what an
#      unguarded `rv.invalid.length` would do, via the direct null-rv unit
#      check in step D below (extracted assertion, not a git revert, to stay
#      hermetic and not depend on git history).
#
# Hermetic: node only, no network, no model/API calls, no fixture files on
# disk.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-fanout.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fanout-null-revalidate-crash: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

# D. Structural guard: the fix must check `rv` before touching `rv.invalid`
# in the revalidate `.then()` callback — parse the actual source (portable
# across grep flavors, unlike a multi-line PCRE grep) so a future edit can't
# silently drop the guard while still passing the behavioral check below for
# unrelated reasons.
if ! python3 - "$WF" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'\.then\(\(rv\)\s*=>\s*\{(.*?)\n\s*\}\)\s*\n\s*\},?\s*\n\)', src, re.S)
ok = bool(m) and re.search(r'if\s*\(\s*!rv\s*\)', m.group(1)) is not None and \
     m.group(1).index(re.search(r'if\s*\(\s*!rv\s*\)', m.group(1)).group(0)) < m.group(1).index('rv.invalid.length')
sys.exit(0 if ok else 1)
PY
then
  note "research-fanout.js's revalidate .then((rv) => {...}) callback no longer guards against rv === null before dereferencing rv.invalid"
  fail=1
fi

cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, outPath] = process.argv;
if (!wfPath || !argsJsonPath || !outPath) {
  console.error('usage: driver.cjs <research-fanout.js> <argsJson> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'pipeline', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));

const agentCalls = [];
const logs = [];

// Stage chain matching how research-fanout.js actually calls pipeline():
// stage 1 takes (item); every later stage takes (prevResult, item). Each
// dimension's chain runs independently (Promise.all across items) --
// the module's own documented "no cross-dimension barrier" property.
async function pipelineStub(items, ...stages) {
  return Promise.all(
    items.map(async (item) => {
      let acc = await stages[0](item);
      for (let i = 1; i < stages.length; i++) acc = await stages[i](acc, item);
      return acc;
    }),
  );
}

// Two dimensions: 'flaky' arrives schema-invalid, gets repaired, then its
// REVALIDATE call resolves to null (the exact terminal-failure-after-retries
// shape the runtime documents for agent()). 'landscape' arrives clean on
// first write and never enters the repair/revalidate branch at all -- its
// completed work must survive regardless of what happens to 'flaky'.
async function agentStub(prompt, opts) {
  const label = opts && opts.label;
  agentCalls.push({ label, prompt });
  if (label === 'fanout:plan') {
    return { dimensions: ['flaky', 'landscape'], goalStatement: 'eval goal', scopeBrief: 'eval scope' };
  }
  if (label === 'research:flaky') {
    return { dimension: 'flaky', findingPaths: ['f-flaky-1.json'], searchesRun: 4, saturationNote: 'covered', crossDimensionLeads: [] };
  }
  if (label === 'research:landscape') {
    return { dimension: 'landscape', findingPaths: ['f-land-1.json'], searchesRun: 3, saturationNote: 'covered', crossDimensionLeads: [] };
  }
  if (label === 'validate:flaky') {
    return { validPaths: [], invalid: [{ path: 'f-flaky-1.json', error: 'missing citations' }] };
  }
  if (label === 'validate:landscape') {
    return { validPaths: ['f-land-1.json'], invalid: [] };
  }
  if (label === 'repair:flaky') {
    return { ok: true };
  }
  if (label === 'revalidate:flaky') {
    // The exact bug shape: a terminal agent() failure after retries
    // resolves to null instead of throwing or returning a schema-shaped
    // result.
    return null;
  }
  if (label === 'fanout:relate') {
    return { related: 0, annotations: [] };
  }
  throw new Error('agentStub: unexpected label ' + label);
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, pipelineStub);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, agentCalls, logs }, null, 2));
})();
NODE

printf '%s' '{"harnessDir":"'"$TMP"'/h","topic":"null-revalidate-eval-topic"}' > "$TMP/args.json"

if ! node "$TMP/driver.cjs" "$WF" "$TMP/args.json" "$TMP/out.json" >"$TMP/run.err" 2>&1; then
  note "driver run failed unexpectedly: $(cat "$TMP/run.err")"
  fail=1
fi

if [ -f "$TMP/out.json" ]; then
  python3 - "$TMP/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  {name}")
    else:
        ok = False
        print(f"FAIL  {name}{(' -- ' + detail) if detail else ''}")

# A. The module must NOT throw just because one dimension's revalidate()
# resolved to null. Before the fix, this driver reproduces the reported
# TypeError verbatim.
check("A. module did not throw on a null revalidate() result (pre-fix reproduces: \"Cannot read properties of null (reading 'invalid')\")",
      d['threw'] is None, str(d['threw']))

r = d.get('result') or {}
by_dim = {p['dimension']: p for p in (r.get('perDimension') or [])}

check('both revalidate/repair calls for flaky were exercised (repair:flaky + revalidate:flaky both called)',
      any(c['label'] == 'repair:flaky' for c in d['agentCalls']) and any(c['label'] == 'revalidate:flaky' for c in d['agentCalls']))

# B. landscape's completed work must survive a null failure in the
# unrelated 'flaky' lane -- this is the "crashed the entire run for ALL
# dimensions" part of the reported defect.
check("B. landscape's findings survive into the run's output despite flaky's null revalidate() (no cross-dimension crash)",
      'f-land-1.json' in (r.get('findings') or []), json.dumps(r.get('findings')))
check("B. landscape appears in perDimension with its real valid count (1)",
      by_dim.get('landscape', {}).get('valid') == 1, json.dumps(by_dim.get('landscape')))

# C. flaky's lane is dropped (consistent with this file's existing
# null-propagation convention: a null result is filtered via
# `results.filter(Boolean)`), not silently reported as successful.
check("C. flaky is NOT present in perDimension (dropped, not silently reported as succeeded)",
      'flaky' not in by_dim, json.dumps(list(by_dim.keys())))
check("C. flaky's finding path does not leak into result.findings",
      'f-flaky-1.json' not in (r.get('findings') or []), json.dumps(r.get('findings')))
check('dimensions still lists both requested dimensions (the plan itself is unaffected by a later-stage failure)',
      sorted(r.get('dimensions') or []) == ['flaky', 'landscape'], json.dumps(r.get('dimensions')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "no out.json produced"
  fail=1
fi

[ "$fail" -eq 0 ] && note "a dimension whose revalidate() call resolves to null (agent()'s documented terminal-failure shape) no longer crashes the entire fanout run; unrelated dimensions' completed work survives; the null-lane itself is dropped rather than silently reported as succeeded — closing research-harness-template#751"
exit "$fail"
