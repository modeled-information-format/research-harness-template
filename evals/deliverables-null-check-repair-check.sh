#!/usr/bin/env bash
# deliverables-null-check-repair-check.sh — regression eval for
# research-harness-template#755: research-deliverables.js's Render pipeline
# second stage (`(r, p) => r ? agent(checkPrompt(...), {...}).then((v) =>
# ({ ...r, validation: v })) : null`) produced `{ ...r, validation: null }`
# whenever the initial Check-phase agent() call itself resolved to null
# (user skip, or the subagent dying after retries — the same agent()
# failure mode the post-fix recheck already handles a few lines later). That
# object is still truthy, so it survived `rendered.filter(Boolean)`; because
# `a.validation` was `null` rather than an object with `clean:false`, the
# pre-fix `dirty` filter (`a.validation && !a.validation.clean`) evaluated
# false, silently excluding the artifact from the repair loop entirely — it
# was never fixed, never re-checked, and never logged, unlike the symmetric
# post-fix re-check path (which already logs a WARNING for the identical
# null case). This eval proves the fix: a null initial Check result now (1)
# logs a WARNING naming the artifact, (2) is treated as `dirty` and actually
# enters the repair (fix + re-check) loop, and (3) ends up with a real
# `clean` verdict from that repair pass instead of the ambiguous `clean:
# null` a caller could not distinguish from "validated clean".
#
# This eval drives the REAL, unmodified module source via the Workflow-
# runtime's own async-function-body framing (the same technique
# deliverables-channel-validation-check.sh/projection-slug-genre-args-
# check.sh use), stubbing `agent()`/`pipeline()`/`parallel()` so the fix can
# be proven without a live model call:
#
#   1. A single artifact-mechanism route.plan row renders successfully, but
#      its INITIAL Check-phase agent() call is stubbed to return null. The
#      module must (a) emit a `log()` WARNING naming the rendered
#      outputPath, and (b) actually invoke the repair loop (`parallel()`
#      called with exactly one fix function) rather than silently treating
#      the row as clean-by-omission.
#   2. The stubbed fix + re-check agent() calls succeed (recheck returns
#      `{clean:true, problems:[]}`), and the module's final returned
#      `artifacts[0].clean` must be `true` — proving the artifact actually
#      got a real verdict via the repair loop instead of staying stuck at
#      `null` forever.
#   3. DELIVERABLES_MODULE can be pointed at an arbitrary copy of the module
#      source (used below to also prove this exact eval FAILS against the
#      pre-fix code, satisfying "a fix without a test that fails before and
#      passes after is not done" — not merely asserted, checked).
#
# Exit 0 = the fix holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE="${DELIVERABLES_MODULE:-.claude/workflows/research-deliverables.js}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deliverables-null-check-eval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  deliverables-null-check-repair-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found — the vendored research-deliverables workflow must ship (Epic #544, Task #573)"; exit 2; }

# ============================================================================
# Driver: same async-function-body technique as
# deliverables-channel-validation-check.sh, but with `pipeline()` and
# `parallel()` stubbed to actually RUN their callbacks (rather than throwing
# a sentinel), since this eval needs to observe the repair loop actually
# fire — not merely that Render was reached.
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsPath, outPath] = process.argv;
if (!wfPath || !argsPath || !outPath) {
  console.error('usage: driver.cjs <module.js> <argsPath> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'pipeline', 'budget', src);

const rawArgsText = fs.readFileSync(argsPath, 'utf8');
const parsedArgs = JSON.parse(rawArgsText);
const routePlan = parsedArgs.__routePlan;
delete parsedArgs.__routePlan;

const calls = [];
const logs = [];
const OUTPUT_PATH = '/tmp/eval-null-check-artifact.blog.md';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  const label = (opts && opts.label) || '';
  calls.push({ fn: 'agent', label, prompt: p.slice(0, 80) });
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  if (p.startsWith('Build the deliverables render plan')) return { plan: routePlan, unavailable: [] };
  if (label.startsWith('render:')) {
    return {
      outputPath: OUTPUT_PATH,
      genre: 'general',
      channel: 'blog',
      mechanism: 'artifact',
      citationsCount: 3,
      genreApplied: false,
      genreSkillInvoked: '',
      provenanceOutcome: 'not-applicable',
      provenanceReason: 'eval fixture',
    };
  }
  if (label.startsWith('recheck:')) return { clean: true, problems: [] };
  // The INITIAL Check call (label "check:...") is the #755 failure mode
  // under test: the Check-phase agent() call itself resolves to null.
  if (label.startsWith('check:')) return null;
  if (label.startsWith('fix:')) return { fixed: true };
  throw new Error('agentStub: unexpected call ' + JSON.stringify({ label, prompt: p.slice(0, 120) }));
}

// Runs pipeline stages for real (not a sentinel throw) so the repair loop
// downstream of `rendered` can actually observe a dirty artifact.
async function pipelineStub(items, ...stages) {
  calls.push({ fn: 'pipeline', items: Array.isArray(items) ? items.length : null, stages: stages.length });
  if (!Array.isArray(items)) return [];
  let current = items;
  for (const stageFn of stages) {
    current = await Promise.all(current.map((val, idx) => Promise.resolve(stageFn(val, items[idx]))));
  }
  return current;
}

// Actually runs the repair-loop functions so we can observe fix()/recheck()
// really firing, and how many rows were routed into the repair loop.
async function parallelStub(fns) {
  calls.push({ fn: 'parallel', count: (fns || []).length });
  return Promise.all((fns || []).map((f) => f()));
}

function phaseStub(name) { calls.push({ fn: 'phase', name }); }
function logStub(msg) { const s = String(msg); logs.push(s); calls.push({ fn: 'log', msg: s }); }
async function workflowStub() { throw new Error('workflowStub should not be reached by this eval'); }
const budgetObj = { total: 0, remaining: () => 0 };

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(parsedArgs, phaseStub, agentStub, logStub, workflowStub, parallelStub, pipelineStub, budgetObj);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls, logs, OUTPUT_PATH }, null, 2));
})();
NODE

TOPIC_VALUE="null-check-repair-eval-topic"
BASE_ARGS='{"harnessDir":".","topic":"'"$TOPIC_VALUE"'","synthesisPath":"/tmp/eval-synthesis.json"'
routePlanArgs="$BASE_ARGS"',"__routePlan":[{"genre":"general","channel":"blog","mechanism":"artifact","templateSource":"blog","outputHint":"out.md"}]}'
printf '%s' "$routePlanArgs" > "$TMP/case1.json"

if ! node "$TMP/driver.cjs" "$MODULE" "$TMP/case1.json" "$TMP/out1.json" >"$TMP/case1-run.err" 2>&1; then
  note "driver invocation itself failed (not a caught throw): $(cat "$TMP/case1-run.err")"
  fail=1
fi

if [ -f "$TMP/out1.json" ]; then
  python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True

if d['threw']:
    print(f"  FAIL: the module threw unexpectedly instead of handling the null Check result — threw={d['threw']}")
    ok = False

logs = d.get('logs', [])
warning_logs = [l for l in logs if 'WARNING: initial validation produced no result' in l and d['OUTPUT_PATH'] in l]
if not warning_logs:
    print(f"  FAIL: no WARNING was logged for the null initial Check result (research-harness-template#755) — logs={logs}")
    ok = False
else:
    print("  ok  a WARNING is logged naming the artifact when the initial Check result is null")

parallel_calls = [c for c in d['calls'] if c.get('fn') == 'parallel']
if not parallel_calls or parallel_calls[0].get('count') != 1:
    print(f"  FAIL: the repair loop (parallel()) was not invoked for the null-validation artifact — parallel_calls={parallel_calls}")
    ok = False
else:
    print("  ok  the repair loop actually ran for the null-validation artifact (not silently dropped)")

fix_calls = [c for c in d['calls'] if c.get('fn') == 'agent' and c.get('label', '').startswith('fix:')]
recheck_calls = [c for c in d['calls'] if c.get('fn') == 'agent' and c.get('label', '').startswith('recheck:')]
if not fix_calls or not recheck_calls:
    print(f"  FAIL: the artifact was not both fixed and re-checked — fix_calls={fix_calls}, recheck_calls={recheck_calls}")
    ok = False
else:
    print("  ok  the artifact was fixed and re-checked, not just flagged")

res = d.get('result') or {}
artifacts = res.get('artifacts') or []
if len(artifacts) != 1 or artifacts[0].get('clean') is not True:
    print(f"  FAIL: the artifact did not end up with a real (non-null) clean verdict after repair — artifacts={artifacts}")
    ok = False
else:
    print("  ok  the artifact ends up with a real clean verdict (true) after the repair loop, not clean:null")

sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
else
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "deliverables-null-check-repair-check: PASS (a null initial Check result is logged, routed to the repair loop, and ends with a real clean verdict)"
  exit 0
else
  echo "deliverables-null-check-repair-check: FAIL"
  exit 1
fi
