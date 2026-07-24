#!/usr/bin/env bash
# research-pipeline-pivot-check.sh — deterministic eval for the
# research-pipeline.js orchestrator's MODE 'pivot' branch
# (research-harness-template#603, Epic #550, companion to sibling Task #602's
# full-mode eval; mirrors #588's pivot->falsify interface fixture, but at the
# ORCHESTRATOR's own composition layer this time -- research-pivot.js itself
# and its Reshape/Classify/Plan pipeline are pivot-check.sh's own subject,
# not re-tested here).
#
# Per the architecture doc's mode-routing table (docs/reference/
# engine-workflows.md's "Mode router" section, reproduced verbatim from the
# real module source below): `pivot` mode is `research-pivot` -> a DRAINING
# regate falsify pass scoped to `pivot.reverifyIds` (`regate: true`, via
# falsifyAll() — research-harness-template#743) -> (if `gapDimensions` is
# non-empty and the budget floor hasn't been hit) `research-fanout` over just
# the gap dimensions plus a falsify drain -> `research-synthesis` ->
# `research-projection`.
#
# What this eval proves WITHOUT a live model call (research-pivot,
# research-falsify, research-fanout, research-synthesis, and
# research-projection are all stubbed -- their own internal judgment is each
# already covered by their own dedicated eval):
#
#   A. STRUCTURAL, against the real, unmodified module source:
#      - The `args.delta` precondition throw (against the parsed args, `A`
#        — #617's args-string parse guard) is a real code guard.
#      - The regate falsify call is scoped literally to
#        `{ ids: pivot.reverifyIds }` with `regate: true`, gated on
#        `pivot.reverifyIds && pivot.reverifyIds.length`.
#      - The gap-fill fanout is gated on BOTH `pivot.gapDimensions.length`
#        AND `!budgetLow()` -- a real two-condition guard, not just one.
#      - `synthesis`/`projection` always run after the gate/gap-fill
#        sequence, with `projection` itself still gated on `syn && syn.ok`.
#
#   B. BEHAVIORAL, driving the REAL research-pipeline.js source via the
#      Workflow-runtime's own async-function-body framing (same technique as
#      research-pipeline-full-mode-check.sh):
#
#      B1 (missing delta throws before any wf() call).
#      B2 (reverifyIds non-empty: the regate falsify call carries the EXACT
#         scope/regate/claimBudget shape the architecture doc documents --
#         `{ scope: { ids: [...] }, regate: true, claimBudget }`).
#      B3 (reverifyIds EMPTY: the regate falsify call never happens at all).
#      B4 (gapDimensions non-empty and budget not low: fanout runs over
#         EXACTLY the gap dimensions, followed by a SEPARATE falsifyAll()
#         drain call -- distinguishing the regate call (B2's `regate: true`,
#         scoped to specific ids) from the drain call (`scope: 'all'`) as
#         two behaviorally distinct falsify invocations in the same run).
#      B5 (gapDimensions EMPTY: fanout never runs, `fan` stays null in the
#         final result).
#      B6 (gapDimensions non-empty but budgetLow() is true: fanout is
#         SKIPPED despite having gap dimensions to fill -- proving the
#         budget-floor half of the two-condition guard is real, not
#         decorative).
#      B7 (synthesis.ok === false skips projection; result carries
#         goalVersion/carried/stale/reverifyGate/fanout/synthesis/projection
#         with carried and stale as plain LENGTHS, not the raw arrays).
#      B8 (research-harness-template#743: the reverify pass actually DRAINS
#         past a single call. When the first regate falsify call defers ids
#         — the exact real-world shape of reverifyIds.length exceeding the
#         child's own default claimBudget — a SECOND regate call must run,
#         scoped to EXACTLY the first call's deferredIds, still regate: true.
#         Proves the fix: pivot's reverify path now behaves identically to
#         import mode's #678 falsifyAll() drain, never the pre-#743 bare
#         single wf('falsify', ...) call that silently dropped anything past
#         the first round. result.reverifyGate.gated sums both iterations.
#         result.reverifyGate on the reverifyIds-EMPTY path (the zero-gate
#         default `{ gated: 0, rollup: {} }`) is already proven by B3.)
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly,
# not faked): whether a live research-pivot run's own Reshape/Classify/Plan
# judgment correctly classifies findings and computes gapDimensions/
# reverifyIds, and whether a live fanout/synthesis/projection call would
# really behave as these fixtures assume. Those judgments are each already
# covered by pivot-check.sh, fanout-lane-contract.sh, synthesis-citation-
# check.sh, and projection-supersession-check.sh. This eval's job is the
# orchestration code around those calls, not the calls' own judgment.
#
# Hermetic: node/python3, no network, no fixture files needed on disk.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-pipeline.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  research-pipeline-pivot-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pipeline workflow must ship (Epic #550, Task #599)"; exit 2; }

# ============================================================================
# A. Structural checks against the real, unmodified module source.
# ============================================================================

pivot_span="$(awk "/if \(MODE === 'pivot'\) \{/{f=1} f{print} f && /^\}/{exit}" "$WF")"
[ -n "$pivot_span" ] || { note "could not locate the MODE === 'pivot' branch in $WF — has the mode router been reshaped?"; fail=1; }

grep -qF "if (!A.delta) throw new Error('pivot mode requires args.delta')" <<<"$pivot_span" \
  || { note "the delta precondition guard is missing or reshaped"; fail=1; }

grep -qF "const pivot = await wf('pivot', { delta: A.delta })" <<<"$pivot_span" \
  || { note "wf('pivot', ...) no longer passes delta straight through from args"; fail=1; }

grep -qF "const reverifyGate = (pivot.reverifyIds && pivot.reverifyIds.length)" <<<"$pivot_span" \
  || { note "the regate falsify gate is no longer literally on reverifyIds.length"; fail=1; }

grep -qF "? await falsifyAll({ scope: { ids: pivot.reverifyIds }, regate: true })" <<<"$pivot_span" \
  || { note "the regate falsify pass no longer drains via falsifyAll() with { scope: { ids }, regate: true } (research-harness-template#743 -- a single wf('falsify', ...) call silently drops anything past the child's own default claimBudget)"; fail=1; }

grep -qF ": { gated: 0, rollup: {} }" <<<"$pivot_span" \
  || { note "the reverifyIds-empty branch no longer falls back to the zero-gate default { gated: 0, rollup: {} }"; fail=1; }

grep -qF "if (pivot.gapDimensions && pivot.gapDimensions.length && !budgetLow()) {" <<<"$pivot_span" \
  || { note "the gap-fill fanout guard is no longer the documented two-condition (gapDimensions.length AND !budgetLow()) guard"; fail=1; }

grep -qF "fan = await wf('fanout', { dimensions: pivot.gapDimensions, depth: 'standard'," <<<"$pivot_span" \
  || { note "the gap-fill fanout call no longer targets pivot.gapDimensions at depth 'standard'"; fail=1; }

grep -qF "await falsifyAll({})" <<<"$pivot_span" \
  || { note "the gap-fill fanout is no longer followed by a falsifyAll() drain call"; fail=1; }

grep -qF "const syn = await wf('synthesis', {})" <<<"$pivot_span" \
  || { note "the unconditional synthesis call is missing or reshaped"; fail=1; }

grep -qF "const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null" <<<"$pivot_span" \
  || { note "the projection call is no longer gated on syn && syn.ok"; fail=1; }

grep -qF "goalVersion: pivot.goalVersion, carried: pivot.carry.length, stale: pivot.stale.length, reverifyGate" <<<"$pivot_span" \
  || { note "the final return no longer maps carry/stale to plain lengths, or dropped the reverifyGate field (research-harness-template#743 -- the caller needs a way to detect an undrained reverify shortfall)"; fail=1; }

# ============================================================================
# Shared driver: runs the REAL research-pipeline.js via the Workflow-
# runtime's own async-function-body framing (mirrors
# research-pipeline-full-mode-check.sh's driver exactly).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsJsonPath, stubsPath, outPath] = process.argv;
if (!wfPath || !argsJsonPath || !stubsPath || !outPath) {
  console.error('usage: driver.cjs <research-pipeline.js> <argsJson> <stubs.cjs> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'budget', src);

const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
// eslint-disable-next-line import/no-dynamic-require, global-require
const stubs = require(stubsPath);

const wfCalls = [];
const logs = [];

async function workflowStub(spec, wfArgs) {
  const scriptPath = (spec && spec.scriptPath) || '';
  const m = /research-([a-zA-Z-]+)\.js$/.exec(scriptPath);
  const name = m && m[1];
  wfCalls.push({ name, args: wfArgs });
  const handler = stubs.wf && stubs.wf[name];
  if (!handler) throw new Error('workflowStub: unexpected/unstubbed scriptPath ' + JSON.stringify({ scriptPath, name }));
  return handler(wfArgs);
}

async function agentStub(prompt, opts) {
  throw new Error('agentStub: pivot mode must never call agent() directly (label ' + JSON.stringify(opts && opts.label) + ') — only wf() children');
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
async function parallelStub(fns) { return Promise.all((fns || []).map((f) => f())); }
const budgetObj = stubs.budget || { total: 0, remaining: () => 0 };

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub, parallelStub, budgetObj);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, wfCalls, logs }, null, 2));
})();
NODE

run_case() { # run_case <caseName> <argsJsonPath> <stubsFile> <outFile>
  local caseName="$1" argsFile="$2" stubsFile="$3" outFile="$4"
  if ! node "$TMP/driver.cjs" "$WF" "$argsFile" "$stubsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver run failed: $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

by_name_py='
def by_name(calls):
    d = {}
    for c in calls:
        d.setdefault(c["name"], []).append(c)
    return d
'

# ============================================================================
# B1. missing delta throws before any wf() call.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\"}" > "$TMP/args-b1.json"
cat > "$TMP/stubs-b1.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    pivot: async () => { throw new Error('pivot must NOT be called — delta is missing, the precondition throw must fire first'); },
  },
};
NODE
run_case b1 "$TMP/args-b1.json" "$TMP/stubs-b1.cjs" "$TMP/out-b1.json"

if [ -f "$TMP/out-b1.json" ]; then
  python3 - "$TMP/out-b1.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B1: {name}")
    else:
        ok = False
        print(f"FAIL  B1: {name}{(' -- ' + detail) if detail else ''}")

check("threw the exact precondition error", d['threw'] is not None and d['threw'].get('message') == 'pivot mode requires args.delta', json.dumps(d['threw']))
check('zero child workflow calls happened', len(d['wfCalls']) == 0, str(len(d['wfCalls'])))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B1: no out-b1.json produced"
  fail=1
fi

# ============================================================================
# B2+B4. reverifyIds non-empty AND gapDimensions non-empty with budget fine:
# the regate falsify call carries the exact { scope: {ids}, regate: true,
# claimBudget, queryBudget, lenses } shape; fanout runs over exactly the gap
# dimensions; a SEPARATE falsifyAll() drain call (scope: 'all') follows --
# two behaviorally distinct falsify invocations in one run.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"scope narrowed to defensive use-cases only\",\"claimBudget\":40,\"queryBudget\":12,\"lenses\":3}" > "$TMP/args-b24.json"
cat > "$TMP/stubs-b24.cjs" <<'NODE'
'use strict';
let falsifyCalls = 0;
module.exports = {
  wf: {
    pivot: async () => ({
      goalVersion: 'gv-2222222',
      supersedes: 'gv-1111111',
      goalStatement: 'Evaluate defensive use-cases only.',
      carry: ['urn:mif:concept:x:finding-1', 'urn:mif:concept:x:finding-2', 'urn:mif:concept:x:finding-3'],
      stale: ['urn:mif:concept:x:finding-4'],
      outOfScope: ['urn:mif:concept:x:finding-5'],
      gapDimensions: ['defensive-tactics'],
      reverifyIds: ['urn:mif:concept:x:finding-4'],
    }),
    falsify: async (a) => {
      falsifyCalls += 1;
      return { gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 };
    },
    fanout: async (a) => ({ dimensions: a.dimensions, findings: [], perDimension: (a.dimensions || []).map((d) => ({ dimension: d, written: 1, valid: 1, searches: 2, saturation: 'not saturated' })), crossDimensionLeads: [], related: 0 }),
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-pivot.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
};
NODE
run_case b24 "$TMP/args-b24.json" "$TMP/stubs-b24.cjs" "$TMP/out-b24.json"

if [ -f "$TMP/out-b24.json" ]; then
  python3 - "$TMP/out-b24.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B2/B4: {name}")
    else:
        ok = False
        print(f"FAIL  B2/B4: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('pivot ran exactly once', len(bn.get('pivot', [])) == 1)
check('fanout ran exactly once, over EXACTLY the gap dimensions', len(bn.get('fanout', [])) == 1 and bn['fanout'][0]['args'].get('dimensions') == ['defensive-tactics'], json.dumps(bn.get('fanout')))
check("fanout's depth is 'standard' (the documented fixed depth for gap-fill)", bn['fanout'][0]['args'].get('depth') == 'standard', json.dumps(bn['fanout'][0]['args']))

falsify_calls = bn.get('falsify', [])
check('falsify ran EXACTLY TWICE (one regate call, one falsifyAll() drain call) -- two behaviorally distinct invocations in one run', len(falsify_calls) == 2, str(len(falsify_calls)))
if len(falsify_calls) >= 1:
    regate_call = falsify_calls[0]['args']
    check("the FIRST falsify call is the regate call: scope={ids: reverifyIds}, regate:true, claimBudget/queryBudget/lenses all passed through", regate_call.get('scope') == {'ids': ['urn:mif:concept:x:finding-4']} and regate_call.get('regate') is True and regate_call.get('claimBudget') == 40 and regate_call.get('queryBudget') == 12 and regate_call.get('lenses') == 3, json.dumps(regate_call))
if len(falsify_calls) >= 2:
    drain_call = falsify_calls[1]['args']
    check("the SECOND falsify call is the falsifyAll() drain call: scope='all', distinct from the regate call's ids-scope", drain_call.get('scope') == 'all', json.dumps(drain_call))

check('synthesis ran exactly once', len(bn.get('synthesis', [])) == 1)
check('projection ran exactly once, using synthesis''s own synthesisPath', len(bn.get('projection', [])) == 1 and bn['projection'][0]['args'].get('synthesisPath') == 'reports/pipeline-eval-topic/synthesis-pivot.json', json.dumps(bn.get('projection')))

r = d.get('result') or {}
check("result.mode is 'pivot'", r.get('mode') == 'pivot')
check('result.goalVersion is pivot''s own goalVersion', r.get('goalVersion') == 'gv-2222222', str(r.get('goalVersion')))
check('result.carried is a plain LENGTH (3), not the raw carry array', r.get('carried') == 3, str(r.get('carried')))
check('result.stale is a plain LENGTH (1), not the raw stale array', r.get('stale') == 1, str(r.get('stale')))
check('result.fanout is the real fanout result, not null', r.get('fanout') is not None and r['fanout'].get('dimensions') == ['defensive-tactics'], json.dumps(r.get('fanout')))
check('result.reverifyGate carries the drained falsifyAll() rollup (gated: 1, from the single-round regate call)', r.get('reverifyGate') == {'gated': 1, 'rollup': {'survived': 1}}, json.dumps(r.get('reverifyGate')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B2/B4: no out-b24.json produced"
  fail=1
fi

# ============================================================================
# B3. reverifyIds EMPTY: the regate falsify call never happens at all.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"scope widened\"}" > "$TMP/args-b3.json"
cat > "$TMP/stubs-b3.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    pivot: async () => ({ goalVersion: 'gv-3333333', supersedes: 'gv-2222222', goalStatement: 'Widen scope.', carry: ['urn:mif:concept:x:finding-1'], stale: [], outOfScope: [], gapDimensions: [], reverifyIds: [] }),
    falsify: async () => { throw new Error('falsify must NOT be called — reverifyIds is empty AND gapDimensions is empty (nothing to regate or drain)'); },
    fanout: async () => { throw new Error('fanout must NOT be called — gapDimensions is empty'); },
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-pivot-nogap.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
};
NODE
run_case b3 "$TMP/args-b3.json" "$TMP/stubs-b3.cjs" "$TMP/out-b3.json"

if [ -f "$TMP/out-b3.json" ]; then
  python3 - "$TMP/out-b3.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B3: {name}")
    else:
        ok = False
        print(f"FAIL  B3: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the falsify/fanout stubs, which throw if called, were never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('falsify never ran at all (reverifyIds empty, gapDimensions empty)', len(bn.get('falsify', [])) == 0)
check('fanout never ran (gapDimensions empty)', len(bn.get('fanout', [])) == 0)
r = d.get('result') or {}
check('result.fanout is null (fan stayed null, gapDimensions was empty)', r.get('fanout') is None, str(r.get('fanout')))
check('result.reverifyGate is the zero-gate default { gated: 0, rollup: {} }, never a falsify call''s own shape', r.get('reverifyGate') == {'gated': 0, 'rollup': {}}, json.dumps(r.get('reverifyGate')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B3: no out-b3.json produced"
  fail=1
fi

# ============================================================================
# B5. gapDimensions EMPTY (but reverifyIds non-empty): fanout never runs,
# fan stays null in the final result, while the regate call still happens.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"weights reprioritized only\"}" > "$TMP/args-b5.json"
cat > "$TMP/stubs-b5.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    pivot: async () => ({ goalVersion: 'gv-4444444', supersedes: 'gv-3333333', goalStatement: 'Reprioritize.', carry: ['urn:mif:concept:x:finding-1', 'urn:mif:concept:x:finding-2'], stale: ['urn:mif:concept:x:finding-3'], outOfScope: [], gapDimensions: [], reverifyIds: ['urn:mif:concept:x:finding-3'] }),
    falsify: async (a) => ({ gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    fanout: async () => { throw new Error('fanout must NOT be called — gapDimensions is empty (only reweighting, no new gaps)'); },
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-pivot-regateonly.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
};
NODE
run_case b5 "$TMP/args-b5.json" "$TMP/stubs-b5.cjs" "$TMP/out-b5.json"

if [ -f "$TMP/out-b5.json" ]; then
  python3 - "$TMP/out-b5.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B5: {name}")
    else:
        ok = False
        print(f"FAIL  B5: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the fanout stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('the regate falsify call still ran once (reverifyIds was non-empty)', len(bn.get('falsify', [])) == 1, str(len(bn.get('falsify', []))))
check('fanout never ran (gapDimensions was empty)', len(bn.get('fanout', [])) == 0)
r = d.get('result') or {}
check('result.fanout is null', r.get('fanout') is None, str(r.get('fanout')))
check('result.reverifyGate carries the drained gate rollup (gated: 1)', r.get('reverifyGate') == {'gated': 1, 'rollup': {'survived': 1}}, json.dumps(r.get('reverifyGate')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B5: no out-b5.json produced"
  fail=1
fi

# ============================================================================
# B6. gapDimensions non-empty but budgetLow() is TRUE: fanout is SKIPPED
# despite having gap dimensions to fill -- proving the budget-floor half of
# the two-condition guard is real, not decorative.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"scope widened, budget nearly exhausted\"}" > "$TMP/args-b6.json"
cat > "$TMP/stubs-b6.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    pivot: async () => ({ goalVersion: 'gv-5555555', supersedes: 'gv-4444444', goalStatement: 'Widen scope under budget pressure.', carry: ['urn:mif:concept:x:finding-1'], stale: [], outOfScope: [], gapDimensions: ['new-angle'], reverifyIds: [] }),
    falsify: async () => { throw new Error('falsify must NOT be called — reverifyIds empty, and the budget floor must block the gap-fill fanout before its own falsifyAll() drain'); },
    fanout: async () => { throw new Error('fanout must NOT be called — budgetLow() is true, the second half of the two-condition guard must block it despite gapDimensions being non-empty'); },
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-pivot-budgetlow.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
  // total is truthy AND remaining() is well under BUDGET_FLOOR (60000) --
  // budgetLow() must read true, blocking the gap-fill fanout.
  budget: { total: 500000, remaining: () => 1000 },
};
NODE
run_case b6 "$TMP/args-b6.json" "$TMP/stubs-b6.cjs" "$TMP/out-b6.json"

if [ -f "$TMP/out-b6.json" ]; then
  python3 - "$TMP/out-b6.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B6: {name}")
    else:
        ok = False
        print(f"FAIL  B6: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the fanout/falsify stubs, which throw if called, were never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('fanout never ran DESPITE gapDimensions being non-empty -- the budget floor blocked it (the second half of the two-condition guard is real)', len(bn.get('fanout', [])) == 0)
check('falsify never ran either (no regate needed, and the gap-fill drain never got a chance to run)', len(bn.get('falsify', [])) == 0)
r = d.get('result') or {}
check('result.fanout is null (budget floor blocked the gap-fill entirely)', r.get('fanout') is None, str(r.get('fanout')))
check('synthesis/projection still ran -- the budget floor only blocks the gap-fill step, not the rest of the pivot composition', (r.get('synthesis') or {}).get('ok') is True and (r.get('projection') or {}).get('ok') is True)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B6: no out-b6.json produced"
  fail=1
fi

# ============================================================================
# B7. synthesis.ok === false skips projection entirely.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"scope narrowed\"}" > "$TMP/args-b7.json"
cat > "$TMP/stubs-b7.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    pivot: async () => ({ goalVersion: 'gv-6666666', supersedes: 'gv-5555555', goalStatement: 'Narrow scope.', carry: [], stale: [], outOfScope: [], gapDimensions: [], reverifyIds: [] }),
    falsify: async () => { throw new Error('falsify must NOT be called'); },
    fanout: async () => { throw new Error('fanout must NOT be called'); },
    synthesis: async () => ({ ok: false, reason: 'no-survivors', excluded: [], unverified: [] }),
    projection: async () => { throw new Error('projection must NOT be called — synthesis failed (ok: false)'); },
  },
};
NODE
run_case b7 "$TMP/args-b7.json" "$TMP/stubs-b7.cjs" "$TMP/out-b7.json"

if [ -f "$TMP/out-b7.json" ]; then
  python3 - "$TMP/out-b7.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B7: {name}")
    else:
        ok = False
        print(f"FAIL  B7: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the projection stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('projection never ran (synthesis.ok was false)', len(bn.get('projection', [])) == 0)
r = d.get('result') or {}
check('result.projection is null', r.get('projection') is None, str(r.get('projection')))
check('result.synthesis still carries the failed synthesis result, honestly reported', (r.get('synthesis') or {}).get('ok') is False, json.dumps(r.get('synthesis')))
check('result.carried and result.stale are both 0 (empty carry/stale arrays -> length 0, not omitted)', r.get('carried') == 0 and r.get('stale') == 0, json.dumps({'carried': r.get('carried'), 'stale': r.get('stale')}))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B7: no out-b7.json produced"
  fail=1
fi

# ============================================================================
# B8 (research-harness-template#743). The reverify pass actually DRAINS past
# a single call: when the first regate falsify call defers ids -- the exact
# real-world shape of reverifyIds.length exceeding the child's own default
# claimBudget (50) -- a SECOND regate call must run, scoped to EXACTLY the
# first call's deferredIds, still regate: true. Before the fix, pivot mode
# called wf('falsify', ...) exactly once and discarded its return value
# entirely -- this fixture's falsify stub would have left the second batch
# ungated with zero retry and zero signal to the caller, exactly the bug
# report's failure scenario.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"pivot\",\"delta\":\"reclassified 80 findings as stale\"}" > "$TMP/args-b8.json"
cat > "$TMP/stubs-b8.cjs" <<'NODE'
'use strict';
let falsifyCalls = 0;
module.exports = {
  wf: {
    pivot: async () => ({
      goalVersion: 'gv-7777777',
      supersedes: 'gv-6666666',
      goalStatement: 'Reclassify stale carry-overs.',
      carry: ['urn:mif:concept:x:finding-1'],
      stale: ['urn:mif:concept:x:finding-2', 'urn:mif:concept:x:finding-3'],
      outOfScope: [],
      gapDimensions: [],
      reverifyIds: ['urn:mif:concept:x:finding-2', 'urn:mif:concept:x:finding-3'],
    }),
    falsify: async () => {
      falsifyCalls += 1;
      if (falsifyCalls === 1) return { gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: ['urn:mif:concept:x:finding-3'], alreadyVerified: 0 };
      return { gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 };
    },
    fanout: async () => { throw new Error('fanout must NOT be called — gapDimensions is empty'); },
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-pivot-drain.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
};
NODE
run_case b8 "$TMP/args-b8.json" "$TMP/stubs-b8.cjs" "$TMP/out-b8.json"

if [ -f "$TMP/out-b8.json" ]; then
  python3 - "$TMP/out-b8.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B8: {name}")
    else:
        ok = False
        print(f"FAIL  B8: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
falsify = bn.get('falsify', [])
check('falsify ran exactly twice (drain stopped once deferredIds emptied on round 2) -- NOT once, which was the #743 bug (a single call silently left the second batch ungated)', len(falsify) == 2, str(len(falsify)))
if len(falsify) == 2:
    a1 = falsify[0]['args']
    a2 = falsify[1]['args']
    check('first call was scoped to the FULL reverifyIds set with regate: true', a1.get('scope') == {'ids': ['urn:mif:concept:x:finding-2', 'urn:mif:concept:x:finding-3']} and a1.get('regate') is True, json.dumps({'scope': a1.get('scope'), 'regate': a1.get('regate')}))
    check("second call narrowed to EXACTLY the first call's deferredIds (never the full reverifyIds set, which under regate would re-open verification on the finding the drain just gated)", a2.get('scope') == {'ids': ['urn:mif:concept:x:finding-3']}, json.dumps(a2.get('scope')))
    check('second call still carried regate: true', a2.get('regate') is True, json.dumps(a2.get('regate')))

r = d.get('result') or {}
check('result.reverifyGate.gated sums BOTH drain iterations (2), proving the caller can now see the full drained total instead of nothing at all', (r.get('reverifyGate') or {}).get('gated') == 2, json.dumps(r.get('reverifyGate')))
check('fanout never ran (gapDimensions was empty)', len(bn.get('fanout', [])) == 0)
check('synthesis/projection still ran after the drain completed', (r.get('synthesis') or {}).get('ok') is True and (r.get('projection') or {}).get('ok') is True)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B8: no out-b8.json produced"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the pivot branch's composition is proven, structurally and behaviorally, to match the architecture doc exactly: a missing delta throws before any child runs; the regate falsify pass DRAINS via falsifyAll() with the documented { scope: { ids: reverifyIds }, regate: true } shape (research-harness-template#743) and is genuinely conditional on reverifyIds.length in both directions, narrowing each subsequent drain iteration to the previous call's deferredIds exactly as import mode's #678 fix does, and reporting the drained total through result.reverifyGate so a caller can finally detect a shortfall; the gap-fill fanout is gated on a REAL two-condition guard (gapDimensions.length AND !budgetLow()), proven to block on EITHER condition independently, and runs over exactly the gap dimensions followed by a behaviorally distinct falsifyAll() drain call (scope:'all', separate from the regate call's ids-scope); synthesis always runs and projection is genuinely conditional on synthesis.ok, receiving synthesis's own synthesisPath verbatim; and the final result maps carry/stale to plain lengths, never raw arrays. The gap this eval cannot close -- whether a live research-pivot run's own Reshape/Classify/Plan judgment produces correct gapDimensions/reverifyIds in the first place, and whether a live fanout/synthesis/projection call would really behave as these fixtures assume -- is each already covered by its own dedicated eval (pivot-check.sh, fanout-lane-contract.sh, synthesis-citation-check.sh, projection-supersession-check.sh)."
else
  echo "research-pipeline-pivot-check: FAILED (see notes above)"
fi
exit "$fail"
