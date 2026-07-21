#!/usr/bin/env bash
# research-pipeline-augment-check.sh — deterministic eval for the
# research-pipeline.js orchestrator's MODE 'augment' branch
# (research-harness-template#603, Epic #550, companion to sibling Task #602's
# full-mode eval; augment-decide-check.sh already covers research-augment.js's
# own Decide-phase judgment -- this eval tests ONLY what research-pipeline.js
# does with that child's result, at the orchestrator's own composition
# layer).
#
# Per the architecture doc's mode-routing table (docs/reference/
# engine-workflows.md's "Mode router" section, reproduced verbatim from the
# real module source below): `augment` mode is `research-augment` -> an
# empty `deepen[]` returns `{ deepened: [], reasoning }` immediately (an
# honest, non-error terminal state) -> otherwise `research-fanout` over the
# deepen plan's dimensions plus a falsify drain -> `research-synthesis` ->
# `research-projection`.
#
# What this eval proves WITHOUT a live model call (research-augment,
# research-fanout, research-falsify, research-synthesis, and
# research-projection are all stubbed):
#
#   A. STRUCTURAL, against the real, unmodified module source:
#      - `wf('augment', { focusHint: A.focusHint })` passes focusHint
#        straight through from the parsed args (`A`, #617's args-string
#        parse guard).
#      - The empty-deepen early return (`if (!plan.deepen.length) return
#        { mode: MODE, deepened: [], reasoning: plan.reasoning }`) is a real
#        code guard -- the SAME honest-termination shape research-augment's
#        own empty-plan-is-valid precedent (#545/#580) already documents,
#        applied here at the mode-router layer.
#      - The fanout depth escalates to 'deep' if ANY deepen entry requests
#        'deep' (`plan.deepen.some((d) => d.depth === 'deep')`), never only
#        on the FIRST entry or requiring ALL entries to agree.
#      - `projection` is gated on `syn && syn.ok`, never unconditional.
#
#   B. BEHAVIORAL, driving the REAL research-pipeline.js source via the
#      Workflow-runtime's own async-function-body framing (same technique as
#      research-pipeline-full-mode-check.sh):
#
#      B1 (empty deepen[] is an honest terminal state, not an error): the
#         augment judge returns `deepen: []` with real stated reasoning --
#         the branch returns `{ mode, deepened: [], reasoning }` immediately;
#         fanout/falsify/synthesis/projection never run at all. Mirrors
#         research-augment's own empty-plan-is-valid precedent (#545/#580)
#         at the orchestrator layer this time.
#      B2 (focusHint passes through unchanged) and (deepen non-empty, all
#         'standard': fanout's depth stays 'standard', dims = the deepen
#         plan's own dimension list -- not the whole goal's dimension set).
#      B3 (depth escalates to 'deep' the moment ANY ONE deepen entry
#         requests it, even when a majority of entries request 'standard'):
#         proves the escalation is an "any", not "all" or "first-wins",
#         semantic.
#      B4 (synthesis.ok === false skips projection; final result carries
#         deepened/fanout/gate/synthesis/projection).
#      B5 (research-harness-template#685: the budget floor guards the fanout
#         dispatch): with a non-empty deepen plan but budget.remaining()
#         under BUDGET_FLOOR, fanout/falsify/synthesis/projection never run
#         -- the branch returns an honest budget-floor terminal state
#         ({ deepened: [], planned, reasoning, budgetFloor: true }) with a
#         log line, the same guard pivot and the full-mode loop always had.
#         B2 carries the inverse: a real budget object comfortably above the
#         floor, proving the guard does not misfire when tokens remain.
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly,
# not faked): whether a live research-augment Decide-phase judgment actually
# picks the right dimensions to deepen (or correctly decides nothing
# warrants it) -- that judgment is augment-decide-check.sh's own subject,
# not this one's. This eval's job is the orchestration code around that
# call, not the call's own judgment.
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
note() { printf '  research-pipeline-augment-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pipeline workflow must ship (Epic #550, Task #599)"; exit 2; }

# ============================================================================
# A. Structural checks against the real, unmodified module source.
# ============================================================================

augment_span="$(awk "/if \(MODE === 'augment'\) \{/{f=1} f{print} f && /^\}/{exit}" "$WF")"
[ -n "$augment_span" ] || { note "could not locate the MODE === 'augment' branch in $WF — has the mode router been reshaped?"; fail=1; }

grep -qF "const plan = await wf('augment', { focusHint: A.focusHint })" <<<"$augment_span" \
  || { note "wf('augment', ...) no longer passes focusHint straight through from args"; fail=1; }

grep -qF "if (!plan.deepen.length) return { mode: MODE, deepened: [], reasoning: plan.reasoning }" <<<"$augment_span" \
  || { note "the empty-deepen honest-termination early return is missing or reshaped — mirrors research-augment's own empty-plan-is-valid precedent (#545/#580)"; fail=1; }

grep -qF "depth: plan.deepen.some((d) => d.depth === 'deep') ? 'deep' : 'standard'" <<<"$augment_span" \
  || { note "the fanout depth escalation is no longer an 'ANY entry requests deep' (.some) check"; fail=1; }

# research-harness-template#685: the budget-floor guard must sit between the
# deepen plan and the fanout dispatch — augment was the one fanout-triggering
# path with no budgetLow() check (pivot and the full-mode loop both had one).
grep -qF "if (budgetLow())" <<<"$augment_span" \
  || { note "the budgetLow() guard before the fanout dispatch is missing — the #685 regression (augment spends on fanout/falsify/synthesis/projection below the budget floor)"; fail=1; }
awk "/if \(budgetLow\(\)\)/{f=1} /await wf\('fanout'/{if (!f) exit 1; exit 0}" <<<"$augment_span" \
  || { note "the budgetLow() guard no longer precedes the await wf('fanout', ...) dispatch (#685)"; fail=1; }

grep -qF "const gate = await falsifyAll({})" <<<"$augment_span" \
  || { note "the falsifyAll() drain call after fanout is missing or reshaped"; fail=1; }

grep -qF "const syn = await wf('synthesis', {})" <<<"$augment_span" \
  || { note "the unconditional synthesis call is missing or reshaped"; fail=1; }

grep -qF "const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null" <<<"$augment_span" \
  || { note "the projection call is no longer gated on syn && syn.ok"; fail=1; }

grep -qF "return { mode: MODE, deepened: dims, fanout: fan, gate, synthesis: syn, projection: proj }" <<<"$augment_span" \
  || { note "the final return no longer carries deepened/fanout/gate/synthesis/projection"; fail=1; }

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
  throw new Error('agentStub: augment mode must never call agent() directly (label ' + JSON.stringify(opts && opts.label) + ') — only wf() children');
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
# B1. empty deepen[] is an honest terminal state -- fanout/falsify/synthesis/
# projection never run, and the branch returns { mode, deepened: [],
# reasoning } immediately.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"augment\"}" > "$TMP/args-b1.json"
REASONING_TEXT='Every declared dimension already rests on multiple independently-sourced survivors; no evidence gap or high-attrition dimension warrants another pass.'
cat > "$TMP/stubs-b1.cjs" <<NODE
'use strict';
module.exports = {
  wf: {
    augment: async () => ({ deepen: [], rejected: [{ dimension: 'landscape', reason: 'already saturated with survivors' }], reasoning: '$REASONING_TEXT', matrix: [] }),
    fanout: async () => { throw new Error('fanout must NOT be called — deepen[] is empty, this is an honest terminal state'); },
    falsify: async () => { throw new Error('falsify must NOT be called — deepen[] is empty'); },
    synthesis: async () => { throw new Error('synthesis must NOT be called — deepen[] is empty'); },
    projection: async () => { throw new Error('projection must NOT be called — deepen[] is empty'); },
  },
};
NODE
run_case b1 "$TMP/args-b1.json" "$TMP/stubs-b1.cjs" "$TMP/out-b1.json"

if [ -f "$TMP/out-b1.json" ]; then
  python3 - "$TMP/out-b1.json" "$REASONING_TEXT" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
reasoning = sys.argv[2]
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B1: {name}")
    else:
        ok = False
        print(f"FAIL  B1: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the fanout/falsify/synthesis/projection stubs, which throw if called, were never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check("exactly one call happened, named 'augment'", list(bn.keys()) == ['augment'], json.dumps(list(bn.keys())))
r = d.get('result') or {}
check("result.mode is 'augment'", r.get('mode') == 'augment')
check('result.deepened is an empty array', r.get('deepened') == [], json.dumps(r.get('deepened')))
check("result.reasoning carries the judge's OWN real reasoning text verbatim (never a generic placeholder)", r.get('reasoning') == reasoning, str(r.get('reasoning')))
check('result has no fanout/gate/synthesis/projection keys from a run that never happened', not any(k in r for k in ('fanout', 'gate', 'synthesis', 'projection')), json.dumps(list(r.keys())))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B1: no out-b1.json produced"
  fail=1
fi

# ============================================================================
# B2. focusHint passes through unchanged; deepen non-empty with ALL entries
# 'standard' keeps fanout's depth 'standard'; dims = the deepen plan's OWN
# dimension list, not the whole goal's dimension set.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"augment\",\"focusHint\":\"unmet checks: landscape_check\"}" > "$TMP/args-b2.json"
cat > "$TMP/stubs-b2.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    augment: async (a) => {
      if (a.focusHint !== 'unmet checks: landscape_check') throw new Error('augment did not receive the expected focusHint: ' + JSON.stringify(a));
      return { deepen: [{ dimension: 'landscape', depth: 'standard', rationale: 'thin coverage' }, { dimension: 'technical', depth: 'standard', rationale: 'high attrition' }], rejected: [], reasoning: 'two dimensions need standard-depth deepening', matrix: [] };
    },
    fanout: async (a) => ({ dimensions: a.dimensions, findings: [], perDimension: (a.dimensions || []).map((d) => ({ dimension: d, written: 1, valid: 1, searches: 2, saturation: 'not saturated' })), crossDimensionLeads: [], related: 0 }),
    falsify: async () => ({ gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-augment.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
  },
  // A real, healthy budget (well above the 60k floor) — proves the #685
  // budgetLow() guard does NOT misfire when tokens remain (the default stub
  // budget's total: 0 makes budgetLow() vacuously false, which would mask a
  // guard that trips on every real budget object).
  budget: { total: 500000, remaining: () => 400000 },
};
NODE
run_case b2 "$TMP/args-b2.json" "$TMP/stubs-b2.cjs" "$TMP/out-b2.json"

if [ -f "$TMP/out-b2.json" ]; then
  python3 - "$TMP/out-b2.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B2: {name}")
    else:
        ok = False
        print(f"FAIL  B2: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves augment received the expected focusHint — the stub throws otherwise)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('fanout ran exactly once, over EXACTLY the deepen plan''s own two dimensions (not the whole goal''s dimension set)', len(bn.get('fanout', [])) == 1 and bn['fanout'][0]['args'].get('dimensions') == ['landscape', 'technical'], json.dumps(bn.get('fanout')))
check("fanout's depth stays 'standard' when every deepen entry requests 'standard'", bn['fanout'][0]['args'].get('depth') == 'standard', json.dumps(bn['fanout'][0]['args']))
check('falsify (falsifyAll drain) ran', len(bn.get('falsify', [])) >= 1)
check('synthesis ran exactly once', len(bn.get('synthesis', [])) == 1)
check('projection ran exactly once, using synthesis''s own synthesisPath', len(bn.get('projection', [])) == 1 and bn['projection'][0]['args'].get('synthesisPath') == 'reports/pipeline-eval-topic/synthesis-augment.json', json.dumps(bn.get('projection')))

r = d.get('result') or {}
check("result.mode is 'augment'", r.get('mode') == 'augment')
check('result.deepened is the deepen plan''s own dimension list', r.get('deepened') == ['landscape', 'technical'], json.dumps(r.get('deepened')))
check('result.gate/synthesis/projection are all present and well-formed', (r.get('gate') or {}).get('gated') == 1 and (r.get('synthesis') or {}).get('ok') is True and (r.get('projection') or {}).get('ok') is True)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B2: no out-b2.json produced"
  fail=1
fi

# ============================================================================
# B3. depth escalates to 'deep' the moment ANY ONE deepen entry requests it
# -- even when a MAJORITY of entries request 'standard'. Proves the
# escalation is an "any", not "all-must-agree" or "first-entry-wins",
# semantic.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"augment\"}" > "$TMP/args-b3.json"
cat > "$TMP/stubs-b3.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    augment: async () => ({
      deepen: [
        { dimension: 'landscape', depth: 'standard', rationale: 'thin coverage' },
        { dimension: 'technical', depth: 'standard', rationale: 'moderate attrition' },
        { dimension: 'adversarial', depth: 'deep', rationale: 'the ONE dimension that needs a deep pass' },
      ],
      rejected: [],
      reasoning: 'two standard passes and one deep pass',
      matrix: [],
    }),
    fanout: async (a) => ({ dimensions: a.dimensions, findings: [], perDimension: [], crossDimensionLeads: [], related: 0 }),
    falsify: async () => ({ gated: 0, rollup: {}, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-augment-deep.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
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

check('module did not throw', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check("fanout's depth escalates to 'deep' because ONE of three entries requested it, despite a majority requesting 'standard' -- proving the semantic is 'any', not 'all' or 'first-wins'", len(bn.get('fanout', [])) == 1 and bn['fanout'][0]['args'].get('depth') == 'deep', json.dumps(bn.get('fanout')))
r = d.get('result') or {}
check('result.deepened carries all three dimensions', r.get('deepened') == ['landscape', 'technical', 'adversarial'], json.dumps(r.get('deepened')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B3: no out-b3.json produced"
  fail=1
fi

# ============================================================================
# B4. synthesis.ok === false skips projection entirely.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"augment\"}" > "$TMP/args-b4.json"
cat > "$TMP/stubs-b4.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    augment: async () => ({ deepen: [{ dimension: 'landscape', depth: 'standard', rationale: 'thin coverage' }], rejected: [], reasoning: 'one dimension needs deepening', matrix: [] }),
    fanout: async (a) => ({ dimensions: a.dimensions, findings: [], perDimension: [], crossDimensionLeads: [], related: 0 }),
    falsify: async () => ({ gated: 0, rollup: {}, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    synthesis: async () => ({ ok: false, reason: 'no-survivors', excluded: [], unverified: [] }),
    projection: async () => { throw new Error('projection must NOT be called — synthesis failed (ok: false)'); },
  },
};
NODE
run_case b4 "$TMP/args-b4.json" "$TMP/stubs-b4.cjs" "$TMP/out-b4.json"

if [ -f "$TMP/out-b4.json" ]; then
  python3 - "$TMP/out-b4.json" <<PY
import json, sys
$by_name_py
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B4: {name}")
    else:
        ok = False
        print(f"FAIL  B4: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the projection stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('projection never ran (synthesis.ok was false)', len(bn.get('projection', [])) == 0)
r = d.get('result') or {}
check('result.projection is null', r.get('projection') is None, str(r.get('projection')))
check('result.synthesis still carries the failed synthesis result, honestly reported', (r.get('synthesis') or {}).get('ok') is False, json.dumps(r.get('synthesis')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B4: no out-b4.json produced"
  fail=1
fi

# ============================================================================
# B5 (research-harness-template#685). Budget below the floor with a NON-empty
# deepen plan: the branch must stop before dispatching fanout — no fanout, no
# falsify drain, no synthesis, no projection (the corpus is unchanged, so
# re-synthesizing would be pure spend) — returning an honest budget-floor
# terminal state that discloses the never-run plan. This is the guard pivot
# (line-266 `!budgetLow()`) and the full-mode round loop already had, and
# augment lacked.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"augment\"}" > "$TMP/args-b5.json"
cat > "$TMP/stubs-b5.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    augment: async () => ({ deepen: [{ dimension: 'landscape', depth: 'deep', rationale: 'thin coverage' }, { dimension: 'technical', depth: 'standard', rationale: 'high attrition' }], rejected: [], reasoning: 'two dimensions warrant deepening', matrix: [] }),
    fanout: async () => { throw new Error('fanout must NOT be called — the budget is below the floor (#685)'); },
    falsify: async () => { throw new Error('falsify must NOT be called — the budget is below the floor (#685)'); },
    synthesis: async () => { throw new Error('synthesis must NOT be called — fanout never ran, the corpus is unchanged (#685)'); },
    projection: async () => { throw new Error('projection must NOT be called — the budget is below the floor (#685)'); },
  },
  // total set and remaining under the 60k BUDGET_FLOOR: budgetLow() is true.
  budget: { total: 500000, remaining: () => 10000 },
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

check('module did not throw (proves the fanout/falsify/synthesis/projection stubs, which throw if called, were never invoked below the budget floor)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check("exactly one call happened, named 'augment' -- fanout was never dispatched below the floor", list(bn.keys()) == ['augment'], json.dumps(list(bn.keys())))
r = d.get('result') or {}
check("result.mode is 'augment'", r.get('mode') == 'augment')
check('result.deepened is an empty array (nothing was actually deepened)', r.get('deepened') == [], json.dumps(r.get('deepened')))
check('result.planned discloses the never-run deepen plan', r.get('planned') == ['landscape', 'technical'], json.dumps(r.get('planned')))
check('result.budgetFloor is true (the stop reason is machine-readable, not narrative-only)', r.get('budgetFloor') is True, str(r.get('budgetFloor')))
check("result.reasoning carries the judge's own reasoning verbatim", r.get('reasoning') == 'two dimensions warrant deepening', str(r.get('reasoning')))
check('a budget-floor log line was emitted', any('Budget floor' in (l.get('log') or '') for l in d['logs']), json.dumps(d['logs']))
check('result has no fanout/gate/synthesis/projection keys from a run that never happened', not any(k in r for k in ('fanout', 'gate', 'synthesis', 'projection')), json.dumps(list(r.keys())))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B5: no out-b5.json produced"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the augment branch's composition is proven, structurally and behaviorally, to match the architecture doc exactly: focusHint passes through to wf('augment', ...) unchanged; an empty deepen[] is a real honest-termination code path returning { mode, deepened: [], reasoning } immediately -- fanout/falsify/synthesis/projection never run at all, mirroring research-augment's own empty-plan-is-valid precedent (#545/#580) at the orchestrator layer; a budget below the floor stops the branch BEFORE the fanout dispatch with an honest { deepened: [], planned, budgetFloor: true } terminal state (#685 -- the same guard pivot and the full-mode loop always had), while a healthy budget never trips it; when deepen is non-empty and budget remains, fanout runs over EXACTLY the deepen plan's own dimensions (never the whole goal's set) at a depth that escalates to 'deep' the moment ANY ONE entry requests it (an 'any', never an 'all' or 'first-wins', semantic); and projection is genuinely conditional on synthesis.ok, receiving synthesis's own synthesisPath verbatim when it does run. The gap this eval cannot close -- whether a live research-augment Decide-phase judgment picks the right dimensions to deepen (or correctly decides nothing warrants it) -- is augment-decide-check.sh's own subject, documented here rather than re-tested."
else
  echo "research-pipeline-augment-check: FAILED (see notes above)"
fi
exit "$fail"
