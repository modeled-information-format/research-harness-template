#!/usr/bin/env bash
# fanout-null-validate-clean-pass.sh — regression eval for
# research-harness-template#742: research-fanout.js's repair-lane guard at the
# top of the third pipeline stage, `if (!v || !v.validation || !v.validation.invalid.length)`,
# treated a validate agent() call that resolved to `null` (the runtime's
# documented terminal-failure-after-retries shape — same contract
# evals/fanout-null-revalidate-crash.sh already covers for the REPAIR lane's
# revalidate() call) identically to "validation ran and found zero invalid
# findings": both take the `return v ? { ...v, repaired: 0 } : v` branch. That
# object (`{ dimension, research, validation: null, repaired: 0 }`) survives
# `results = perDimension.filter(Boolean)` since it is non-null, and then
# `allPaths`'s fallback `r.validation ? r.validation.validPaths : r.research.findingPaths`
# substitutes the RAW, never-validated research findingPaths into the run's
# canonical findings — never checked against findings.schema.json, never
# checked for the illegal extensions.harness.verification.attempted_at field,
# never confirmed to carry real citations — while the per-dimension summary's
# `valid` field honestly reports `null` for the same dimension, producing an
# internally inconsistent result: the summary flags the problem, the findings
# array quietly ships the unvalidated data anyway.
#
# Drives the REAL research-fanout.js source via the Workflow-runtime's own
# async-function-body framing (same technique as
# evals/fanout-null-revalidate-crash.sh's driver): agent() is stubbed to
# canned, schema-shaped results per label, with the FIRST validate() call
# (label `validate:${d}`, not repair's revalidate) for one dimension ('flaky')
# stubbed to resolve to `null`; pipeline() is stubbed with the module's own
# documented per-item stage chain, no cross-dimension barrier.
#
# What this proves WITHOUT a live model call:
#   A. The module does NOT throw when one dimension's validate() call
#      resolves to null.
#   B. flaky's RAW, never-validated finding path does NOT leak into
#      result.findings — this is the actual reported defect: before the fix,
#      this driver finds 'f-flaky-1.json' present in result.findings even
#      though no validate call for it ever succeeded.
#   C. flaky does not appear in perDimension as if it had completed normally
#      (dropped, consistent with this file's existing null-propagation
#      convention for a null research()/revalidate() result), never reported
#      with an inconsistent {valid: null} alongside leaked findings.
#   D. The unrelated 'landscape' dimension, whose validate() call succeeds
#      normally, is completely unaffected — its findings and valid count
#      survive.
#   E. Structural guard: the third stage must distinguish "validation is
#      null" from "validation ran clean" instead of folding both into the
#      same early-return branch.
#
# Hermetic: node only, no network, no model/API calls, no fixture files on
# disk.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-fanout.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fanout-null-validate-clean-pass: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

# E. Structural guard: the repair-lane stage function must check for a null
# `v.validation` SEPARATELY from "validation ran clean" (i.e. it must not
# fold both cases into one `!v.validation || !v.validation.invalid.length`
# early return) -- parse the actual source so a future edit can't silently
# re-collapse the two cases while still passing the behavioral check below
# for unrelated reasons.
if ! python3 - "$WF" <<'PY'
import re, sys
src = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'\(v,\s*d\)\s*=>\s*\{(.*?)\n\s*\},\s*\n\)', src, re.S)
if not m:
    sys.exit(1)
body = m.group(1)
# A standalone `if (!v.validation)` check (NOT `!v.validation.invalid.length` --
# the regex's trailing `\)` requires nothing but optional whitespace between
# `!v.validation` and the closing paren) that appears strictly BEFORE the
# first place the body dereferences `.invalid.length` proves null is handled
# on its own branch rather than folded into the "ran clean" check.
null_check = re.search(r'if\s*\(\s*!v\.validation\s*\)', body)
invalid_len_idx = body.find('v.validation.invalid.length')
ok = bool(null_check) and invalid_len_idx != -1 and null_check.start() < invalid_len_idx
sys.exit(0 if ok else 1)
PY
then
  note "research-fanout.js's repair-lane stage still folds a null v.validation (validate agent() terminal failure) into the same branch as a clean validation pass"
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
// dimension's chain runs independently (Promise.all across items) -- the
// module's own documented "no cross-dimension barrier" property.
async function pipelineStub(items, ...stages) {
  return Promise.all(
    items.map(async (item) => {
      let acc = await stages[0](item);
      for (let i = 1; i < stages.length; i++) acc = await stages[i](acc, item);
      return acc;
    }),
  );
}

// Two dimensions: 'flaky's research() succeeds but its FIRST validate() call
// resolves to null (the exact terminal-failure-after-retries shape the
// runtime documents for agent()) -- it never reaches repair/revalidate at
// all. 'landscape' validates clean on the first pass and never enters the
// repair branch -- its completed work must be entirely unaffected by what
// happens to 'flaky'.
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
    // The exact bug shape: a terminal agent() failure after retries resolves
    // to null instead of throwing or returning a schema-shaped result.
    return null;
  }
  if (label === 'validate:landscape') {
    return { validPaths: ['f-land-1.json'], invalid: [] };
  }
  if (label === 'fanout:relate') {
    return { related: 0, annotations: [] };
  }
  // repair:flaky / revalidate:flaky must NEVER be called -- a null validate()
  // result is not "N invalid findings needing repair", it's "validation
  // didn't run at all".
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

printf '%s' '{"harnessDir":"'"$TMP"'/h","topic":"null-validate-eval-topic"}' > "$TMP/args.json"

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

# A. The module must not throw just because one dimension's validate()
# resolved to null.
check("A. module did not throw on a null validate() result",
      d['threw'] is None, str(d['threw']))

check('validate:flaky was called and repair:flaky/revalidate:flaky were NEVER called (a null validate() result is not "N invalid findings")',
      any(c['label'] == 'validate:flaky' for c in d['agentCalls']) and
      not any(c['label'] in ('repair:flaky', 'revalidate:flaky') for c in d['agentCalls']))

r = d.get('result') or {}
by_dim = {p['dimension']: p for p in (r.get('perDimension') or [])}

# B. The actual reported defect: flaky's RAW, never-validated finding path
# must not leak into the run's canonical findings just because validation
# never ran.
check("B. flaky's raw, never-validated finding path does NOT leak into result.findings (pre-fix: 'f-flaky-1.json' appears here even though nothing ever validated it)",
      'f-flaky-1.json' not in (r.get('findings') or []), json.dumps(r.get('findings')))

# C. flaky must not be reported as if it completed normally -- either
# dropped entirely (this file's existing null-propagation convention), or at
# minimum never paired with a leaked finding under an honest-looking
# {valid: null} summary (the "internally inconsistent result" the issue
# names).
flaky_entry = by_dim.get('flaky')
check("C. flaky is not silently reported as succeeded (dropped from perDimension, or at minimum shows no leaked-through findings)",
      flaky_entry is None or by_dim.get('flaky', {}).get('valid') != 0,
      json.dumps(flaky_entry))

# D. landscape is completely unaffected by flaky's failure.
check("D. landscape's findings survive into the run's output despite flaky's null validate() (no cross-dimension crash)",
      'f-land-1.json' in (r.get('findings') or []), json.dumps(r.get('findings')))
check("D. landscape appears in perDimension with its real valid count (1)",
      by_dim.get('landscape', {}).get('valid') == 1, json.dumps(by_dim.get('landscape')))
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

[ "$fail" -eq 0 ] && note "a dimension whose validate() call resolves to null (agent()'s documented terminal-failure shape) is no longer treated as a clean validation pass; its raw unvalidated findings no longer leak into the run's canonical output; unrelated dimensions are unaffected — closing research-harness-template#742"
exit "$fail"
