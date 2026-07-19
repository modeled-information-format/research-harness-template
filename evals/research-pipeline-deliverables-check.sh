#!/usr/bin/env bash
# research-pipeline-deliverables-check.sh — deterministic eval for the
# research-pipeline.js orchestrator's MODE 'deliverables' branch
# (research-harness-template#624, companion to research-pipeline-audit-
# check.sh / -import-check.sh / -pivot-check.sh / -augment-check.sh).
#
# The issue: after a completed run (findings gathered, gated, synthesized),
# there was no way to render a genre/channel deliverable from the EXISTING
# corpus without re-running fanout/falsify — the only escape hatch was
# hand-invoking research-deliverables.js directly through the Workflow tool,
# bypassing the documented /research entry point. `deliverables` mode closes
# that gap: it re-drafts a fresh synthesis from the survivor corpus already
# on disk (cheap — no fan-out, no falsification gate) and feeds that fresh
# synthesisPath straight into research-deliverables in the same process
# (satisfying research-deliverables.js's same-process preflight check on
# research-synthesis.js's ephemeral-output contract). It deliberately never
# calls research-projection — the report of record is untouched by this
# mode, a considered design choice (mirrors `audit` mode's own minimalism),
# not a silent omission.
#
# This eval also covers the adjacent fix landed in the same PR: every mode
# branch is an independent early-return `if` with no terminal `else`, so an
# unrecognized `mode` string previously fell through silently into the
# full-mode round loop. A `KNOWN_MODES` guard now throws before any branch
# dispatches.
#
# What this eval proves WITHOUT a live model call (research-synthesis and
# research-deliverables are both stubbed; their own internal judgment is
# already covered by synthesis-citation-check.sh / the deliverables suite —
# this eval tests ONLY what research-pipeline.js's deliverables branch does
# with those children's results):
#
#   A. STRUCTURAL, against the real, unmodified module source:
#      - The deliverables branch span contains EXACTLY two wf() calls,
#        `synthesis` then `deliverables`, in that order.
#      - No other wf() call name (fanout/falsify/projection/augment/pivot/
#        import/add-dimensions/coverage-audit/goal) appears anywhere inside
#        that span.
#      - The required-arg guard (`args.genres` or `args.channels`) appears
#        inside the span, before either wf() call.
#      - The `KNOWN_MODES` unrecognized-mode guard exists in the module,
#        naming 'deliverables' among the known modes, and appears BEFORE the
#        first mode-dispatch `if` in file order (proving it guards every
#        branch, not just this one).
#
#   B. BEHAVIORAL, driving the REAL research-pipeline.js source via the
#      Workflow-runtime's own async-function-body framing (same technique as
#      research-pipeline-audit-check.sh), with every child wf() stubbed:
#
#      B0 (required-arg throw fires before any wf() call): neither
#         `args.genres` nor `args.channels` supplied -> throws
#         'deliverables mode requires args.genres or args.channels' with
#         ZERO child workflow calls having happened.
#      B1/B2 (synthesis first, deliverables second, correct args): `wf()` is
#         called exactly twice, in order — `synthesis` with no extra config
#         beyond the always-merged harnessDir/topic (proving `{}` was
#         genuinely passed), then `deliverables` with the stub's own
#         returned `synthesisPath` verbatim plus `genres`/`channels` passed
#         through from the caller's args. No other wf() name is ever
#         invoked (every sibling stub throws if called).
#      B3 (synthesis.ok===false short-circuits before deliverables runs): a
#         synthesis stub returning `{ ok: false }` results in
#         `{ deliverables: null }` and the deliverables stub — which throws
#         if invoked — never fires.
#      B4 (unrecognized mode throws before ANY wf() call): `mode:
#         'deliverabels'` (typo) throws `unknown mode 'deliverabels'` with
#         every child stub (all of which throw if called) left uninvoked —
#         proving the guard fires before the full-mode fallthrough, not
#         after it silently ran.
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly,
# not faked): whether a live research-synthesis run over a real corpus
# actually produces a citable, check-covering synthesis, and whether a live
# research-deliverables run actually renders a faithful genre artifact from
# it — both are each already covered by their own dedicated evals. This
# eval's job is only the one branch of orchestration code that composes
# them.
#
# Hermetic: node/python3, no network, no fixture files needed on disk (the
# deliverables branch never touches the filesystem itself — that's
# delegated entirely to the stubbed children).
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-pipeline.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  research-pipeline-deliverables-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pipeline workflow must ship"; exit 2; }

# ============================================================================
# A. Structural checks against the real, unmodified module source.
# ============================================================================

# A1. The deliverables branch span, extracted from the guard line to its
#     closing brace.
del_span="$(awk "/if \(MODE === 'deliverables'\) \{/{f=1} f{print} f && /^\}/{exit}" "$WF")"
[ -n "$del_span" ] || { note "could not locate the MODE === 'deliverables' branch in $WF — has the mode router been reshaped?"; fail=1; }

# A2. Exactly two wf() calls in the span, synthesis then deliverables, in order.
wf_calls_in_span="$(grep -oE "wf\('[a-zA-Z-]+'" <<<"$del_span" | sed -E "s/wf\('([a-zA-Z-]+)'/\1/")"
expected_calls="synthesis
deliverables"
if [ "$wf_calls_in_span" != "$expected_calls" ]; then
  note "the deliverables branch's wf() call sequence is not exactly [synthesis, deliverables]. Got: $(echo "$wf_calls_in_span" | tr '\n' ',')"
  fail=1
fi

# A3. No OTHER child workflow name appears inside that span.
for other in fanout falsify projection augment pivot import add-dimensions coverage-audit goal; do
  if grep -qF "wf('$other'" <<<"$del_span"; then
    note "the deliverables branch unexpectedly calls wf('$other', ...) — this mode must be synthesis+deliverables only, never fanout/falsify/projection"
    fail=1
  fi
done

# A4. The required-arg guard appears in the span, before either wf() call.
if ! grep -qF "requires args.genres or args.channels" <<<"$del_span"; then
  note "the deliverables branch is missing its required-arg guard (args.genres or args.channels)"
  fail=1
fi
guard_line="$(grep -n "requires args.genres or args.channels" "$WF" | head -1 | cut -d: -f1)"
first_wf_line="$(grep -n "await wf(" "$WF" | awk -F: -v span_start="$(grep -n "if (MODE === 'deliverables')" "$WF" | head -1 | cut -d: -f1)" '$1 > span_start {print $1; exit}')"
if [ -n "$guard_line" ] && [ -n "$first_wf_line" ] && [ "$guard_line" -gt "$first_wf_line" ]; then
  note "the required-arg guard appears AFTER a wf() call in the deliverables branch — it must guard before any child runs"
  fail=1
fi

# A5. The KNOWN_MODES unrecognized-mode guard exists, names 'deliverables',
#     and appears before the first mode-dispatch `if` in file order.
if ! grep -qE "KNOWN_MODES\s*=\s*\[.*'deliverables'" "$WF"; then
  note "KNOWN_MODES guard missing or does not list 'deliverables' — research-harness-template#624's adjacent fix (closing the missing else/default guard) is not present"
  fail=1
fi
known_modes_line="$(grep -n "KNOWN_MODES.includes(MODE)" "$WF" | head -1 | cut -d: -f1)"
first_if_line="$(grep -n "^if (MODE === " "$WF" | head -1 | cut -d: -f1)"
if [ -z "$known_modes_line" ] || [ -z "$first_if_line" ] || [ "$known_modes_line" -ge "$first_if_line" ]; then
  note "the KNOWN_MODES guard does not appear before the first mode-dispatch 'if' — it must guard every branch, not run after one has already dispatched"
  fail=1
fi

# ============================================================================
# Shared driver: runs the REAL research-pipeline.js via the Workflow-
# runtime's own async-function-body framing (mirrors
# research-pipeline-audit-check.sh's driver exactly).
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
  throw new Error('agentStub: deliverables mode must never call agent() directly (label ' + JSON.stringify(opts && opts.label) + ') — only wf() children');
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

ALL_OTHER_THROW_STUBS='
    fanout: async () => { throw new Error("fanout must NOT be called"); },
    falsify: async () => { throw new Error("falsify must NOT be called"); },
    projection: async () => { throw new Error("projection must NOT be called — deliverables mode never touches the report of record"); },
    augment: async () => { throw new Error("augment must NOT be called"); },
    pivot: async () => { throw new Error("pivot must NOT be called"); },
    import: async () => { throw new Error("import must NOT be called"); },
    "add-dimensions": async () => { throw new Error("add-dimensions must NOT be called"); },
    "coverage-audit": async () => { throw new Error("coverage-audit must NOT be called"); },
    goal: async () => { throw new Error("goal must NOT be called"); },
'

# ============================================================================
# B0. missing genres AND channels throws before any wf() call.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"deliverables\"}" > "$TMP/args-b0.json"
cat > "$TMP/stubs-b0.cjs" <<NODE
'use strict';
module.exports = {
  wf: {
    synthesis: async () => { throw new Error('synthesis must NOT be called — the required-arg guard must fire first'); },
    deliverables: async () => { throw new Error('deliverables must NOT be called — the required-arg guard must fire first'); },
$ALL_OTHER_THROW_STUBS
  },
};
NODE
run_case b0 "$TMP/args-b0.json" "$TMP/stubs-b0.cjs" "$TMP/out-b0.json"

if [ -f "$TMP/out-b0.json" ]; then
  python3 - "$TMP/out-b0.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B0: {name}")
    else:
        ok = False
        print(f"FAIL  B0: {name}{(' -- ' + detail) if detail else ''}")

check("threw the documented required-arg error",
      d['threw'] is not None and 'requires args.genres or args.channels' in (d['threw'] or {}).get('message', ''),
      json.dumps(d['threw']))
check('zero child workflow calls happened before the throw', len(d['wfCalls']) == 0, str(d['wfCalls']))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B0: no out-b0.json produced"
  fail=1
fi

# ============================================================================
# B1/B2. synthesis first (no extra config), deliverables second (fresh
# synthesisPath + genres/channels passed through verbatim).
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"deliverables\",\"genres\":[\"engineering\",\"exec-summary\"],\"channels\":[\"blog\"]}" > "$TMP/args-b1.json"
cat > "$TMP/stubs-b1.cjs" <<NODE
'use strict';
module.exports = {
  wf: {
    synthesis: async () => ({ ok: true, synthesisPath: '/tmp/pipeline-eval-fresh-synthesis.json', checkCoverage: { met: 2, unmet: 0 } }),
    deliverables: async (a) => ({ rendered: [{ genre: 'engineering', channel: 'report' }], receivedArgs: a }),
$ALL_OTHER_THROW_STUBS
  },
};
NODE
run_case b1 "$TMP/args-b1.json" "$TMP/stubs-b1.cjs" "$TMP/out-b1.json"

if [ -f "$TMP/out-b1.json" ]; then
  python3 - "$TMP/out-b1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B1/B2: {name}")
    else:
        ok = False
        print(f"FAIL  B1/B2: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw', d['threw'] is None, str(d['threw']))
wf = d['wfCalls']
check('exactly two child workflow calls happened', len(wf) == 2, str(len(wf)))
if len(wf) == 2:
    check("call 1 is named 'synthesis'", wf[0]['name'] == 'synthesis', wf[0]['name'])
    call1_args = wf[0]['args'] or {}
    extra_keys = sorted(k for k in call1_args if k not in ('harnessDir', 'topic', 'runDate'))
    check("call 1 carries no config beyond the always-merged harnessDir/topic/runDate (proving '{}' was genuinely passed)", extra_keys == [], json.dumps(call1_args))

    check("call 2 is named 'deliverables'", wf[1]['name'] == 'deliverables', wf[1]['name'])
    call2_args = wf[1]['args'] or {}
    check("call 2 receives the FRESH synthesisPath from call 1's own stubbed return, verbatim",
          call2_args.get('synthesisPath') == '/tmp/pipeline-eval-fresh-synthesis.json', json.dumps(call2_args))
    check("call 2 receives genres passed through verbatim from caller args",
          call2_args.get('genres') == ['engineering', 'exec-summary'], json.dumps(call2_args))
    check("call 2 receives channels passed through verbatim from caller args",
          call2_args.get('channels') == ['blog'], json.dumps(call2_args))

r = d.get('result') or {}
check("result.mode is 'deliverables'", r.get('mode') == 'deliverables', str(r.get('mode')))
check('result.synthesis is the stub\'s own return, verbatim', (r.get('synthesis') or {}).get('synthesisPath') == '/tmp/pipeline-eval-fresh-synthesis.json', json.dumps(r.get('synthesis')))
check('result.deliverables is the stub\'s own return, verbatim', (r.get('deliverables') or {}).get('rendered') == [{'genre': 'engineering', 'channel': 'report'}], json.dumps(r.get('deliverables')))
check('result has no projection field — this mode never calls research-projection', 'projection' not in r, json.dumps(sorted(r.keys())))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B1/B2: no out-b1.json produced"
  fail=1
fi

# ============================================================================
# B3. synthesis.ok === false short-circuits before deliverables ever runs.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"deliverables\",\"genres\":[\"engineering\"]}" > "$TMP/args-b3.json"
cat > "$TMP/stubs-b3.cjs" <<NODE
'use strict';
module.exports = {
  wf: {
    synthesis: async () => ({ ok: false, reason: 'no surviving findings for this topic' }),
    deliverables: async () => { throw new Error('deliverables must NOT be called — synthesis.ok is false, the branch must short-circuit'); },
$ALL_OTHER_THROW_STUBS
  },
};
NODE
run_case b3 "$TMP/args-b3.json" "$TMP/stubs-b3.cjs" "$TMP/out-b3.json"

if [ -f "$TMP/out-b3.json" ]; then
  python3 - "$TMP/out-b3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B3: {name}")
    else:
        ok = False
        print(f"FAIL  B3: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw (proves the deliverables stub, which throws if called, was never invoked)', d['threw'] is None, str(d['threw']))
wf = d['wfCalls']
check('exactly one child workflow call happened (synthesis only)', len(wf) == 1, str(len(wf)))
if wf:
    check("that one call is named 'synthesis'", wf[0]['name'] == 'synthesis', wf[0]['name'])

r = d.get('result') or {}
check("result.mode is 'deliverables'", r.get('mode') == 'deliverables', str(r.get('mode')))
check('result.deliverables is null — the branch short-circuits on a failed synthesis', r.get('deliverables') is None, json.dumps(r.get('deliverables')))
check("result.synthesis carries the failed stub's own return, verbatim (ok: false surfaced, not swallowed)", (r.get('synthesis') or {}).get('ok') is False, json.dumps(r.get('synthesis')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B3: no out-b3.json produced"
  fail=1
fi

# ============================================================================
# B4. an unrecognized mode string throws before ANY wf() call — the
# research-harness-template#624 adjacent fix (KNOWN_MODES guard).
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"deliverabels\"}" > "$TMP/args-b4.json"
cat > "$TMP/stubs-b4.cjs" <<NODE
'use strict';
module.exports = {
  wf: {
    synthesis: async () => { throw new Error('synthesis must NOT be called — an unrecognized mode must be rejected before any dispatch'); },
    deliverables: async () => { throw new Error('deliverables must NOT be called — an unrecognized mode must be rejected before any dispatch'); },
$ALL_OTHER_THROW_STUBS
  },
};
NODE
run_case b4 "$TMP/args-b4.json" "$TMP/stubs-b4.cjs" "$TMP/out-b4.json"

if [ -f "$TMP/out-b4.json" ]; then
  python3 - "$TMP/out-b4.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
def check(name, cond, detail=''):
    global ok
    if cond:
        print(f"  ok  B4: {name}")
    else:
        ok = False
        print(f"FAIL  B4: {name}{(' -- ' + detail) if detail else ''}")

check("threw an 'unknown mode' error naming the bad mode string, rather than silently falling through to full mode",
      d['threw'] is not None and "unknown mode 'deliverabels'" in (d['threw'] or {}).get('message', ''),
      json.dumps(d['threw']))
check('zero child workflow calls happened (proves the guard fires BEFORE the full-mode fallthrough would have run goal/fanout/etc.)', len(d['wfCalls']) == 0, str(d['wfCalls']))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B4: no out-b4.json produced"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the deliverables branch is proven, structurally and behaviorally, to be research-synthesis -> research-deliverables ONLY: no fan-out, falsify, or projection ever runs; the required-arg guard fires before either child call when both genres and channels are omitted; synthesis runs first with no extra config, its fresh synthesisPath feeds deliverables verbatim alongside the caller's genres/channels; a failed synthesis (ok:false) short-circuits to deliverables:null without ever invoking the deliverables child; and the adjacent KNOWN_MODES guard rejects an unrecognized mode string before any dispatch, closing the silent full-mode fallthrough research-harness-template#624 also flagged. The gap this eval cannot close -- whether a live synthesis/deliverables run's own judgment produces well-formed output -- is each already covered by its own dedicated eval."
else
  echo "research-pipeline-deliverables-check: FAILED (see notes above)"
fi
exit "$fail"
