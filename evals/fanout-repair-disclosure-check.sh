#!/usr/bin/env bash
# fanout-repair-disclosure-check.sh — regression eval for
# research-harness-template#623 (research-fanout.js side): the module's
# per-dimension validate/repair lane can silently mutate schema-invalid or
# citation-defective findings before the round loop's completion check ever
# runs, giving zero visibility into how much repair actually happened. This
# eval proves the module now COMPUTES and RETURNS that repair count, both
# per-dimension and as a round total, so a heavily-repaired corpus is never
# indistinguishable from one that arrived clean.
#
# Drives the REAL research-fanout.js source via the Workflow-runtime's own
# async-function-body framing (same technique as
# research-pipeline-full-mode-check.sh's driver): `agent()` is stubbed to
# canned, schema-shaped results per label; `pipeline()` is stubbed with a
# straightforward per-item stage-chain (matching the module's own
# documented "no cross-dimension barrier" semantics — each dimension's
# research -> validate -> repair chain runs independently of the others).
#
# What this proves WITHOUT a live model call:
#   A. A dimension whose findings arrive schema-invalid and get repaired
#      reports its TRUE pre-repair defect count in perDimension[].repaired
#      — not 0, not silently dropped.
#   B. A dimension whose findings validate on first write reports
#      perDimension[].repaired === 0 (repair is never fabricated when it
#      did not happen).
#   C. The top-level `repaired` field is the correct SUM across dimensions.
#   D. `findings`/`perDimension[].valid` are unaffected by this change —
#      the repaired findings are still counted as valid once they pass
#      revalidation (repair disclosure is additive, not a behavior change
#      to what "valid" means).
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly):
# whether a live sonnet repair-agent call actually fixes what it's asked to
# fix. That judgment is already covered by fanout-lane-contract.sh's own
# documented gap statement for the same reason.
#
# Hermetic: node only, no network, no model/API calls, no fixture files on
# disk (research-fanout.js's Research/Relate phases never read/write real
# files themselves in this eval — every "file" is just a path string
# threaded through the stubbed agent() calls).
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
note() { printf '  fanout-repair-disclosure-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

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
// exactly the module's own documented "no cross-dimension barrier"
// property: a slow lane never blocks a fast one.
async function pipelineStub(items, ...stages) {
  return Promise.all(
    items.map(async (item) => {
      let acc = await stages[0](item);
      for (let i = 1; i < stages.length; i++) acc = await stages[i](acc, item);
      return acc;
    }),
  );
}

// Two dimensions: 'technical' arrives with BOTH its findings schema-invalid
// (repaired, then revalidates clean); 'landscape' arrives clean on first
// write (never enters the repair branch at all).
async function agentStub(prompt, opts) {
  const label = opts && opts.label;
  agentCalls.push({ label, prompt });
  if (label === 'fanout:plan') {
    return { dimensions: ['technical', 'landscape'], goalStatement: 'eval goal', scopeBrief: 'eval scope' };
  }
  if (label === 'research:technical') {
    return { dimension: 'technical', findingPaths: ['f-tech-1.json', 'f-tech-2.json'], searchesRun: 5, saturationNote: 'covered', crossDimensionLeads: [] };
  }
  if (label === 'research:landscape') {
    return { dimension: 'landscape', findingPaths: ['f-land-1.json'], searchesRun: 3, saturationNote: 'covered', crossDimensionLeads: [] };
  }
  if (label === 'validate:technical') {
    // First validate call for technical: BOTH findings arrive schema-invalid.
    return { validPaths: [], invalid: [{ path: 'f-tech-1.json', error: 'missing citations' }, { path: 'f-tech-2.json', error: 'bad @id' }] };
  }
  if (label === 'validate:landscape') {
    return { validPaths: ['f-land-1.json'], invalid: [] };
  }
  if (label === 'repair:technical') {
    return { ok: true };
  }
  if (label === 'revalidate:technical') {
    // After repair, both technical findings now validate clean.
    return { validPaths: ['f-tech-1.json', 'f-tech-2.json'], invalid: [] };
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

printf '%s' '{"harnessDir":"'"$TMP"'/h","topic":"repair-eval-topic"}' > "$TMP/args.json"

if ! node "$TMP/driver.cjs" "$WF" "$TMP/args.json" "$TMP/out.json" >"$TMP/run.err" 2>&1; then
  note "driver run failed: $(cat "$TMP/run.err")"
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

check('module did not throw', d['threw'] is None, str(d['threw']))
r = d.get('result') or {}
by_dim = {p['dimension']: p for p in (r.get('perDimension') or [])}

check('technical repair path was exercised (repair:technical + revalidate:technical both called)',
      any(c['label'] == 'repair:technical' for c in d['agentCalls']) and any(c['label'] == 'revalidate:technical' for c in d['agentCalls']))
check('landscape never entered the repair branch (no repair:landscape / revalidate:landscape call)',
      not any(c['label'] in ('repair:landscape', 'revalidate:landscape') for c in d['agentCalls']))

check("A. technical's perDimension.repaired reports its TRUE pre-repair defect count (2), not 0 or dropped",
      by_dim.get('technical', {}).get('repaired') == 2, json.dumps(by_dim.get('technical')))
check("B. landscape's perDimension.repaired is 0 (repair never fabricated when it did not happen)",
      by_dim.get('landscape', {}).get('repaired') == 0, json.dumps(by_dim.get('landscape')))
check("C. top-level repaired is the correct SUM across dimensions (2 + 0 = 2)",
      r.get('repaired') == 2, str(r.get('repaired')))
check("D. technical's valid count is unaffected by this change -- both repaired findings still count as valid once they revalidate clean",
      by_dim.get('technical', {}).get('valid') == 2, json.dumps(by_dim.get('technical')))
check("D. landscape's valid count is unchanged (1, clean from the start)",
      by_dim.get('landscape', {}).get('valid') == 1, json.dumps(by_dim.get('landscape')))
check('result.findings carries all 3 finding paths (repair does not drop or duplicate any)',
      sorted(r.get('findings') or []) == sorted(['f-tech-1.json', 'f-tech-2.json', 'f-land-1.json']), json.dumps(r.get('findings')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "no out.json produced"
  fail=1
fi

[ "$fail" -eq 0 ] && note "a dimension whose findings arrive schema-invalid reports its true pre-repair defect count in perDimension[].repaired (never 0, never dropped); a dimension that validates on first write reports repaired:0; the top-level repaired field is the correct cross-dimension sum; and the repair-disclosure change does not alter what counts as 'valid' or which findings survive into the round's output — closing research-harness-template#623's fanout-side gap"
exit "$fail"
