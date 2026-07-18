#!/usr/bin/env bash
# research-pipeline-audit-check.sh — deterministic eval for the
# research-pipeline.js orchestrator's MODE 'audit' branch
# (research-harness-template#603, Epic #550, companion to sibling Task #602's
# full-mode eval and following #599's vendoring / #601's docs).
#
# Per the architecture doc's mode-routing table (docs/reference/
# engine-workflows.md's "Mode router" section, reproduced verbatim from the
# real module source below): `audit` mode is `research-coverage-audit` ALONE
# -> returns the routed backlog report. No fan-out, falsify, synthesis, or
# projection follows. This eval proves exactly that shape, both structurally
# (against the unmodified module source) and behaviorally (driving the real
# source with every workflow() child stubbed).
#
# What this eval proves WITHOUT a live model call (research-coverage-audit
# itself is stubbed; its own Sweep/Critique/Prioritize judgment is already
# covered by coverage-audit-check.sh — this eval tests ONLY what
# research-pipeline.js's audit branch does with that child's result):
#
#   A. STRUCTURAL, against the real, unmodified module source:
#      - The audit branch is EXACTLY three lines: the mode guard, the single
#        `wf('coverage-audit', {})` call, and a bare `{ mode: MODE, ...audit }`
#        return — extracted by span and diffed against that literal shape.
#      - No OTHER wf() call name (fanout/falsify/synthesis/projection/
#        augment/pivot/import/add-dimensions) appears anywhere inside that
#        span — the branch really does nothing but call coverage-audit and
#        return.
#
#   B. BEHAVIORAL, driving the REAL research-pipeline.js source via the
#      Workflow-runtime's own async-function-body framing (same technique as
#      research-pipeline-full-mode-check.sh), with wf('coverage-audit', ...)
#      stubbed to return a canned, schema-shaped backlog matching the real
#      research-coverage-audit.js return shape:
#
#      B1 (single-call, no-config, no-dispatch): wf() is called EXACTLY ONCE,
#         named 'coverage-audit', with no extra config beyond what the real
#         wf() helper always merges in (harnessDir/topic) — proving `{}` was
#         genuinely passed as this call's own args. No other wf() name is
#         ever invoked. The backlog fixture deliberately routes items to
#         EVERY one of the five downstream modules the architecture doc's
#         Prioritize step names (augment/add-dimensions/falsify/import/
#         projection) plus manual — and this eval proves NONE of those five
#         modules is ever itself invoked by the audit branch. This is the
#         positive proof of research-harness-template#595's documented
#         finding, cited by this Task's own acceptance criteria: a backlog
#         item's `target` is a human/orchestrator-readable ROUTING SIGNAL,
#         never something audit mode auto-dispatches on the caller's behalf.
#      B2 (result is a plain spread, not a re-shaped summary): the final
#         result carries `mode: 'audit'` plus the backlog/summary/rawItems/
#         uncoveredAngles fields VERBATIM from the stub — proving the
#         branch's `{ mode: MODE, ...audit }` return doesn't drop, rename, or
#         summarize any field of the routed report before handing it back.
#      B3 (a failing child workflow propagates, not swallowed): when the
#         coverage-audit stub throws, the driver's captured `threw` carries
#         that same error — proving the audit branch has no try/catch that
#         would silently swallow a failed audit and report a false success.
#
# What this eval CANNOT close (genuine, non-deterministic, stated plainly,
# not faked): whether a live coverage-audit run's own Sweep/Critique/
# Prioritize judgment produces a well-routed backlog in the first place —
# that judgment is coverage-audit-check.sh's own subject, not this one's.
# This eval's job is only the one line of orchestration code that calls it
# and returns its result.
#
# Hermetic: node/python3, no network, no fixture files needed on disk (the
# audit branch never touches the filesystem itself — that's delegated
# entirely to the stubbed child).
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
note() { printf '  research-pipeline-audit-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-pipeline workflow must ship (Epic #550, Task #599)"; exit 2; }

# ============================================================================
# A. Structural checks against the real, unmodified module source.
# ============================================================================

# A1. The audit branch span, extracted from the guard line to its closing
#     brace, must be EXACTLY the documented three-line shape.
audit_span="$(awk "/if \(MODE === 'audit'\) \{/{f=1} f{print} f && /^\}/{exit}" "$WF")"
[ -n "$audit_span" ] || { note "could not locate the MODE === 'audit' branch in $WF — has the mode router been reshaped?"; fail=1; }
expected_span="if (MODE === 'audit') {
  const audit = await wf('coverage-audit', {})
  return { mode: MODE, ...audit }
}"
if [ "$audit_span" != "$expected_span" ]; then
  note "the audit branch no longer matches the documented shape exactly. Expected:"
  note "$expected_span"
  note "Got:"
  note "$audit_span"
  fail=1
fi

# A2. No other child workflow name appears inside that span — the branch
#     really does nothing else.
for other in fanout falsify synthesis projection augment pivot import add-dimensions deliverables goal; do
  if grep -qF "wf('$other'" <<<"$audit_span"; then
    note "the audit branch unexpectedly calls wf('$other', ...) — audit mode must be coverage-audit alone, per the architecture doc's mode-routing table"
    fail=1
  fi
done

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
  throw new Error('agentStub: audit mode must never call agent() directly (label ' + JSON.stringify(opts && opts.label) + ') — only wf(\'coverage-audit\', ...)');
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

# ============================================================================
# B1/B2. single-call, no-config, no-dispatch, verbatim spread: the backlog
# fixture routes one item to EACH of the five downstream modules the
# architecture doc's Prioritize step names, plus manual — proving none of
# them is itself invoked by the audit branch (research-harness-template#595's
# "target is a routing signal, not a directly-forwardable arg" finding).
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"audit\"}" > "$TMP/args-b1.json"
cat > "$TMP/stubs-b1.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    'coverage-audit': async () => ({
      backlog: [
        { action: 'augment', target: 'landscape', why: 'thin coverage on the landscape dimension', priority: 1 },
        { action: 'add-dimensions', target: 'homeless lead: quantum-safe migration timelines', why: 'no declared dimension covers this lead', priority: 2 },
        { action: 'falsify', target: 'urn:mif:concept:pipeline-eval-topic:finding-7', why: 'ungated finding on disk', priority: 2 },
        { action: 'import', target: 'evidence known to exist in an external export, not yet in this corpus', why: 'known external evidence', priority: 3 },
        { action: 'projection', target: 'reports/pipeline-eval-topic/README.md', why: 'README finding count is stale', priority: 3 },
        { action: 'manual', target: 'ontology pin ambiguity', why: 'needs a human decision', priority: 4 },
      ],
      summary: 'Six routable items found across five downstream workflows plus one manual decision.',
      rawItems: [{ modality: 'thin-dimensions' }, { modality: 'staleness' }],
      uncoveredAngles: ['no auditor covers deployment topology drift'],
    }),
    fanout: async () => { throw new Error('fanout must NOT be called — audit mode is coverage-audit alone'); },
    falsify: async () => { throw new Error('falsify must NOT be called — audit mode is coverage-audit alone'); },
    synthesis: async () => { throw new Error('synthesis must NOT be called — audit mode is coverage-audit alone'); },
    projection: async () => { throw new Error('projection must NOT be called — audit mode is coverage-audit alone'); },
    augment: async () => { throw new Error('augment must NOT be called — audit mode is coverage-audit alone'); },
    pivot: async () => { throw new Error('pivot must NOT be called — audit mode is coverage-audit alone'); },
    import: async () => { throw new Error('import must NOT be called — audit mode is coverage-audit alone'); },
    'add-dimensions': async () => { throw new Error('add-dimensions must NOT be called — audit mode is coverage-audit alone'); },
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
        print(f"  ok  B1: {name}")
    else:
        ok = False
        print(f"FAIL  B1: {name}{(' -- ' + detail) if detail else ''}")

check('module did not throw', d['threw'] is None, str(d['threw']))
wf = d['wfCalls']
check('exactly one child workflow call happened at all', len(wf) == 1, str(len(wf)))
if wf:
    check("that one call is named 'coverage-audit'", wf[0]['name'] == 'coverage-audit', wf[0]['name'])
    call_args = wf[0]['args'] or {}
    extra_keys = sorted(k for k in call_args if k not in ('harnessDir', 'topic'))
    check("the call carries no config beyond the always-merged harnessDir/topic (proving '{}' was genuinely passed)", extra_keys == [], json.dumps(call_args))

r = d.get('result') or {}
check("result.mode is 'audit'", r.get('mode') == 'audit', str(r.get('mode')))
check('result.backlog carries all six routed items VERBATIM (never dropped/summarized)', len(r.get('backlog') or []) == 6, json.dumps(r.get('backlog')))
actions = sorted(item.get('action') for item in (r.get('backlog') or []))
check('the backlog spans all five downstream modules plus manual, unmodified', actions == sorted(['augment', 'add-dimensions', 'falsify', 'import', 'projection', 'manual']), json.dumps(actions))
check('result.summary is the stub\'s own summary text, unmodified', r.get('summary') == 'Six routable items found across five downstream workflows plus one manual decision.', str(r.get('summary')))
check('result.rawItems present verbatim', r.get('rawItems') == [{'modality': 'thin-dimensions'}, {'modality': 'staleness'}], json.dumps(r.get('rawItems')))
check('result.uncoveredAngles present verbatim', r.get('uncoveredAngles') == ['no auditor covers deployment topology drift'], json.dumps(r.get('uncoveredAngles')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B1: no out-b1.json produced"
  fail=1
fi

# ============================================================================
# B3. a failing coverage-audit child propagates rather than being swallowed.
# ============================================================================
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"pipeline-eval-topic\",\"mode\":\"audit\"}" > "$TMP/args-b3.json"
cat > "$TMP/stubs-b3.cjs" <<'NODE'
'use strict';
module.exports = {
  wf: {
    'coverage-audit': async () => { throw new Error('coverage-audit sweep failed: fixture-injected failure'); },
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

check('a failing coverage-audit child call propagates as a real thrown error (never silently swallowed into a false-success result)',
      d['threw'] is not None and 'fixture-injected failure' in (d['threw'] or {}).get('message', ''), json.dumps(d['threw']))
check('result is null (the branch never got to return anything)', d.get('result') is None, str(d.get('result')))

sys.exit(0 if ok else 1)
PY
  rc=$?
  [ "$rc" -eq 0 ] || fail=1
else
  note "B3: no out-b3.json produced"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  note "the audit branch is proven, structurally and behaviorally, to be research-coverage-audit ALONE: no fan-out, falsify, synthesis, or projection ever runs; the routed backlog is returned verbatim via a plain spread, spanning all five downstream-module targets the architecture doc names (augment/add-dimensions/falsify/import/projection) plus manual, none of which is ever itself auto-invoked -- the positive proof of research-harness-template#595's 'target is a routing signal, not a directly-forwardable arg' finding; and a failing audit child propagates rather than being swallowed into a false success. The one gap this eval cannot close -- whether a live coverage-audit run's own Sweep/Critique/Prioritize judgment produces a well-routed backlog in the first place -- is coverage-audit-check.sh's own subject, documented here rather than re-tested."
else
  echo "research-pipeline-audit-check: FAILED (see notes above)"
fi
exit "$fail"
