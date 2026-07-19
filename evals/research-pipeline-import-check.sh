#!/usr/bin/env bash
# research-pipeline-import-check.sh — deterministic eval for the
# research-pipeline.js orchestrator's MODE 'import' branch
# (research-harness-template#603, Epic #550, companion to sibling Task #602's
# full-mode eval; mirrors #594's live import->falsify interface fixture, but
# at the ORCHESTRATOR's own composition layer this time -- research-import.js
# itself and its Dry-Run/Review/Apply pipeline are import-check.sh's own
# subject, not re-tested here).
#
# Per the architecture doc's mode-routing table (docs/reference/
# engine-workflows.md's "Mode router" section, reproduced verbatim from the
# real module source below): `import` mode is `research-import` -> (if
# `needsGating` is non-empty) a falsify drain over `scope: 'all'` ->
# `research-synthesis` -> `research-projection`. An import-gate failure
# (`!imp.ok`) short-circuits before any gating runs.
#
# What this eval proves WITHOUT a live model call (research-import,
# research-falsify, research-synthesis, and research-projection are all
# stubbed -- their own internal judgment is each already covered by their own
# dedicated eval):
#
#   A. STRUCTURAL, against the real, unmodified module source:
#      - The `args.containerDir` precondition throw (against the parsed
#        args, `A` — #617's args-string parse guard) is a real code guard,
#        never a prose-only requirement.
#      - `wf('import', ...)` passes `containerDir`/`trustImportedVerdicts`
#        straight through from `args`, unchanged.
#      - The `!imp.ok` short-circuit returns `{ mode, imported: imp }` before
#        any falsify/synthesis/projection call.
#      - The falsify drain is literally gated on `imp.needsGating.length`
#        (skipped when empty, run when non-empty) -- never unconditional.
#      - `projection` is gated on `syn && syn.ok`, never called
#        unconditionally after synthesis.
#
#   B. BEHAVIORAL, driving the REAL research-pipeline.js source via the
#      Workflow-runtime's own async-function-body framing (same technique as
#      research-pipeline-full-mode-check.sh):
#
#      B1 (missing containerDir throws before any wf() call): `import mode
#         requires args.containerDir` is thrown with zero child workflow
#         calls made at all.
#      B2 (containerDir/trustImportedVerdicts pass through unchanged): the
#         `wf('import', ...)` call carries the exact containerDir and
#         trustImportedVerdicts values the caller supplied.
#      B3 (import-gate failure short-circuits): `imp.ok === false` returns
#         `{ mode: 'import', imported: <the whole failed result> }`
#         immediately -- falsify/synthesis/projection never run.
#      B4 (needsGating non-empty runs falsify, then synthesis, then
#         projection with the synthesis's own path): the falsify drain runs,
#         synthesis runs once, and projection receives EXACTLY the
#         synthesisPath synthesis returned -- proving the pass-through is
#         real, not hand-rewritten.
#      B5 (needsGating EMPTY skips falsify but still runs synthesis and
#         projection): falsify is never called when there is nothing to
#         gate, while synthesis/projection still proceed -- proving the gate
#         is genuinely conditional in both directions, not "always run" or
#         "always skip".
#      B6 (synthesis.ok === false skips projection): projection is never
#         called when synthesis itself failed, and the final result's
#         projection field is null.
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly,
# not faked): whether a live research-import run's own Dry-Run/Review/Apply
# gate correctly classifies findings needing gating, and whether a live
# synthesis/projection call would really behave as these fixtures assume.
# Those judgments are each already covered by import-check.sh,
# synthesis-citation-check.sh, and projection-supersession-check.sh. This
# eval's job is the orchestration code around those calls, not the calls'
# own judgment.
#
# Hermetic: node/python3, no network, no fixture files needed on disk (every
# filesystem interaction is delegated to the stubbed children).
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
note() { printf '  research-pipeline-import-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pipeline workflow must ship (Epic #550, Task #599)"; exit 2; }

# ============================================================================
# A. Structural checks against the real, unmodified module source.
# ============================================================================

import_span="$(awk "/if \(MODE === 'import'\) \{/{f=1} f{print} f && /^\}/{exit}" "$WF")"
[ -n "$import_span" ] || { note "could not locate the MODE === 'import' branch in $WF — has the mode router been reshaped?"; fail=1; }

grep -qF "if (!A.containerDir) throw new Error('import mode requires args.containerDir')" <<<"$import_span" \
  || { note "the containerDir precondition guard is missing or reshaped — a code guard, not a prose-only requirement"; fail=1; }

grep -qF "const imp = await wf('import', { containerDir: A.containerDir, trustImportedVerdicts: A.trustImportedVerdicts })" <<<"$import_span" \
  || { note "wf('import', ...) no longer passes containerDir/trustImportedVerdicts straight through from args"; fail=1; }

grep -qF "if (!imp || !imp.ok) return { mode: MODE, imported: imp }" <<<"$import_span" \
  || { note "the import-gate-failure short-circuit ('!imp.ok') is missing or reshaped"; fail=1; }

grep -qF "const gate = imp.needsGating.length ? await falsifyAll({}) : { gated: 0, rollup: {} }" <<<"$import_span" \
  || { note "the falsify drain is no longer gated literally on imp.needsGating.length"; fail=1; }

grep -qF "const syn = await wf('synthesis', {})" <<<"$import_span" \
  || { note "the unconditional synthesis call after gating is missing or reshaped"; fail=1; }

grep -qF "const proj = (syn && syn.ok) ? await wf('projection', { synthesisPath: syn.synthesisPath }) : null" <<<"$import_span" \
  || { note "the projection call is no longer gated on syn && syn.ok"; fail=1; }

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
  throw new Error('agentStub: import mode must never call agent() directly (label ' + JSON.stringify(opts && opts.label) + ') — only wf() children');
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
# B1. missing containerDir throws before any wf() call.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"import\"}" > "$TMP/args-b1.json"
cat > "$TMP/stubs-b1.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    import: async () => { throw new Error('import must NOT be called — containerDir is missing, the precondition throw must fire first'); },
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

check("threw the exact precondition error", d['threw'] is not None and d['threw'].get('message') == 'import mode requires args.containerDir', json.dumps(d['threw']))
check('zero child workflow calls happened', len(d['wfCalls']) == 0, str(len(d['wfCalls'])))
check('result is null', d.get('result') is None, str(d.get('result')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B1: no out-b1.json produced"
  fail=1
fi

# ============================================================================
# B2. containerDir/trustImportedVerdicts pass through to wf('import', ...)
# unchanged, AND the import-gate failure short-circuit (imp.ok === false)
# returns immediately, never touching falsify/synthesis/projection.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"import\",\"containerDir\":\"/tmp/some-export-dir\",\"trustImportedVerdicts\":true}" > "$TMP/args-b2.json"
cat > "$TMP/stubs-b2.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    import: async () => ({ ok: false, stage: 'review', detail: { blockers: ['collision on urn:mif:concept:x:finding-3'] } }),
    falsify: async () => { throw new Error('falsify must NOT be called — imp.ok is false, the gate failed'); },
    synthesis: async () => { throw new Error('synthesis must NOT be called — imp.ok is false, the gate failed'); },
    projection: async () => { throw new Error('projection must NOT be called — imp.ok is false, the gate failed'); },
  },
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

check('module did not throw', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check("exactly one call happened, named 'import'", list(bn.keys()) == ['import'], json.dumps(list(bn.keys())))
call_args = bn['import'][0]['args']
check('containerDir passed through unchanged', call_args.get('containerDir') == '/tmp/some-export-dir', json.dumps(call_args))
check('trustImportedVerdicts passed through unchanged', call_args.get('trustImportedVerdicts') is True, json.dumps(call_args))

r = d.get('result') or {}
check("result.mode is 'import'", r.get('mode') == 'import', str(r.get('mode')))
check('result.imported is the WHOLE failed import result object (not just a boolean/count)', r.get('imported') == {'ok': False, 'stage': 'review', 'detail': {'blockers': ['collision on urn:mif:concept:x:finding-3']}}, json.dumps(r.get('imported')))
check('result has no gate/synthesis/projection keys from a run that never happened', 'gate' not in r and 'synthesis' not in r and 'projection' not in r, json.dumps(list(r.keys())))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B2: no out-b2.json produced"
  fail=1
fi

# ============================================================================
# B4. needsGating non-empty: falsify runs, then synthesis, then projection
# receives EXACTLY the synthesis's own synthesisPath.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"import\",\"containerDir\":\"/tmp/some-export-dir\"}" > "$TMP/args-b4.json"
cat > "$TMP/stubs-b4.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    import: async () => ({ ok: true, imported: ['urn:mif:concept:x:finding-1', 'urn:mif:concept:x:finding-2'], needsGating: ['urn:mif:concept:x:finding-1'], trustedForeignVerdicts: [], collisionsChecked: 0 }),
    falsify: async () => ({ gated: 1, rollup: { survived: 1 }, verdicts: [], deferredIds: [], alreadyVerified: 0 }),
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-import.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
    projection: async (a) => ({ ok: true, reportPath: 'reports/pipeline-eval-topic/report.md', reportId: 'urn:mif:concept:pipeline-eval-topic:report', mifLevel: 3, checksAddressed: [], verificationVerdict: 'survived', readmePath: null, readmeCheckPassed: false, graphRefreshed: false, graphAssertPassed: false, problems: [], _receivedSynthesisPath: a.synthesisPath }),
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

check('module did not throw', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('import ran exactly once', len(bn.get('import', [])) == 1)
check('falsify ran (needsGating was non-empty)', len(bn.get('falsify', [])) >= 1, str(len(bn.get('falsify', []))))
check('synthesis ran exactly once', len(bn.get('synthesis', [])) == 1)
check('projection ran exactly once', len(bn.get('projection', [])) == 1)
proj_args = bn['projection'][0]['args']
check("projection received EXACTLY synthesis's own synthesisPath", proj_args.get('synthesisPath') == 'reports/pipeline-eval-topic/synthesis-import.json', json.dumps(proj_args))

r = d.get('result') or {}
check("result.mode is 'import'", r.get('mode') == 'import')
check('result.imported is imp.imported.length (a count, this time -- distinct from B2''s whole-object short-circuit shape)', r.get('imported') == 2, str(r.get('imported')))
check('result.gate carries the falsify rollup', (r.get('gate') or {}).get('gated') == 1, json.dumps(r.get('gate')))
check('result.synthesis and result.projection are both present and well-formed', (r.get('synthesis') or {}).get('ok') is True and (r.get('projection') or {}).get('ok') is True)

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B4: no out-b4.json produced"
  fail=1
fi

# ============================================================================
# B5. needsGating EMPTY skips falsify entirely, but synthesis and projection
# STILL run -- proving the gate is genuinely conditional in both directions.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"import\",\"containerDir\":\"/tmp/some-export-dir\"}" > "$TMP/args-b5.json"
cat > "$TMP/stubs-b5.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    import: async () => ({ ok: true, imported: ['urn:mif:concept:x:finding-9'], needsGating: [], trustedForeignVerdicts: ['urn:mif:concept:x:finding-9'], collisionsChecked: 0 }),
    falsify: async () => { throw new Error('falsify must NOT be called — needsGating is empty, nothing to gate'); },
    synthesis: async () => ({ ok: true, synthesisPath: 'reports/pipeline-eval-topic/synthesis-import-nogate.json', sections: [], findingsUsed: [], checkCoverage: [], openIssues: [], ungatedFindings: [] }),
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

check('module did not throw (proves the falsify stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('falsify never ran (needsGating was empty)', len(bn.get('falsify', [])) == 0)
check('synthesis still ran exactly once', len(bn.get('synthesis', [])) == 1)
check('projection still ran exactly once', len(bn.get('projection', [])) == 1)

r = d.get('result') or {}
check('result.gate is the zero-gate default { gated: 0, rollup: {} }, never a falsify call''s own shape', r.get('gate') == {'gated': 0, 'rollup': {}}, json.dumps(r.get('gate')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B5: no out-b5.json produced"
  fail=1
fi

# ============================================================================
# B6. synthesis.ok === false skips projection entirely.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"import\",\"containerDir\":\"/tmp/some-export-dir\"}" > "$TMP/args-b6.json"
cat > "$TMP/stubs-b6.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    import: async () => ({ ok: true, imported: [], needsGating: [], trustedForeignVerdicts: [], collisionsChecked: 0 }),
    falsify: async () => { throw new Error('falsify must NOT be called — needsGating is empty'); },
    synthesis: async () => ({ ok: false, reason: 'no-survivors', excluded: [], unverified: [] }),
    projection: async () => { throw new Error('projection must NOT be called — synthesis failed (ok: false)'); },
  },
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

check('module did not throw (proves the projection stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
bn = by_name(d['wfCalls'])
check('synthesis ran exactly once', len(bn.get('synthesis', [])) == 1)
check('projection never ran (synthesis.ok was false)', len(bn.get('projection', [])) == 0)
r = d.get('result') or {}
check('result.projection is null', r.get('projection') is None, str(r.get('projection')))
check('result.synthesis still carries the failed synthesis result, honestly reported', (r.get('synthesis') or {}).get('ok') is False, json.dumps(r.get('synthesis')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B6: no out-b6.json produced"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the import branch's composition is proven, structurally and behaviorally, to match the architecture doc exactly: a missing containerDir throws before any child runs; containerDir/trustImportedVerdicts pass through to wf('import', ...) unchanged; an import-gate failure (imp.ok===false) short-circuits to { mode, imported: imp } before falsify/synthesis/projection ever run; the falsify drain is genuinely conditional on needsGating.length in BOTH directions (runs when non-empty, skipped when empty, synthesis/projection still proceed either way); and projection is genuinely conditional on synthesis.ok, receiving synthesis's own synthesisPath verbatim when it does run. The gap this eval cannot close -- whether a live research-import/synthesis/projection call's own judgment behaves as these fixtures assume -- is each already covered by its own dedicated eval (import-check.sh, synthesis-citation-check.sh, projection-supersession-check.sh)."
else
  echo "research-pipeline-import-check: FAILED (see notes above)"
fi
exit "$fail"
