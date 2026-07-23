#!/usr/bin/env bash
# deliverables-channel-validation-check.sh — regression eval for
# research-harness-template#764: research-deliverables.js's GENRE STRING
# VALIDATION guard (#640, mirrors #633's own guard in research-projection.js)
# validates a caller-controlled `route.plan[].genre` against the pack-name
# pattern before interpolating it into a shell-command argument / Skill()
# reference, but the identical `channel` field — interpolated into the same
# two positions (render-artifact.sh's `${p.channel}` argument, and mechanism
# 2's `Skill(${p.channel}:${skillName})` reference) — had NO equivalent
# validation. Since Route is a model call (`{label: 'deliverables:route',
# model: 'haiku', schema: ROUTE_SCHEMA}`), a malformed/hallucinated channel
# string could reach those interpolation points unchecked. This eval covers
# the new CHANNEL STRING validation guard added by this fix, not the
# pre-existing genre guard it mirrors.
#
# This eval drives the REAL, unmodified module source via the Workflow-
# runtime's own async-function-body framing (the same technique
# projection-slug-genre-args-check.sh/atomic-workflows-args-parse-check.sh
# use), stubbing `agent()` to return a CONTROLLED route.plan so the fix can
# be proven without a live model call:
#
#   1. An unknown channel string ("not-a-real-channel") -> the module must
#      throw its fail-closed validation error BEFORE any Render agent() call.
#      Pre-fix code fails this: the unknown channel is never checked, so the
#      module proceeds straight to Render and interpolates it unvalidated.
#   2. A mechanism/channel mismatch (mechanism="source-direct" naming an
#      artifact-only channel, "blog") -> same fail-closed requirement; a
#      known-but-wrong-mechanism channel is just as unsafe to interpolate as
#      an unknown one (Route's own mechanism/channel pairing is inconsistent).
#   3. A genuinely valid channel ("blog", mechanism="artifact") -> the module
#      must proceed PAST the validation guard into Render (proven by reaching
#      the driver's sentinel throw at the first real Render agent() call,
#      not the validation guard's own error text) — proves the fix does not
#      false-positive-reject a real channel.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE="${DELIVERABLES_MODULE:-.claude/workflows/research-deliverables.js}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deliverables-channel-eval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  deliverables-channel-validation-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found — the vendored research-deliverables workflow must ship (Epic #544, Task #573)"; exit 2; }

# ============================================================================
# Driver: same async-function-body technique as
# projection-slug-genre-args-check.sh. Stubs `agent()` to answer the
# preflight check and the Route call with a CALLER-CONTROLLED route.plan
# (passed in via the args' own "__routePlan" test hook field, read only by
# this driver's stub — never by the real module), then throws a sentinel on
# the first subsequent agent() call (Render) so we can tell "reached Render"
# apart from "the validation guard threw" by inspecting which error surfaced.
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
const SENTINEL = 'EVAL_SENTINEL_STOP_AT_RENDER';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  calls.push({ fn: 'agent', label: opts && opts.label, prompt: p.slice(0, 80) });
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  if (p.startsWith('Build the deliverables render plan')) return { plan: routePlan, unavailable: [] };
  // Any call past Route (i.e. Render) throws the sentinel — reaching here
  // proves the channel-validation guard did NOT block this route.plan.
  throw new Error(SENTINEL);
}
async function parallelStub(fns) {
  calls.push({ fn: 'parallel', count: (fns || []).length });
  throw new Error(SENTINEL);
}
async function pipelineStub(items, mapFn) {
  calls.push({ fn: 'pipeline', items: Array.isArray(items) ? items.length : null });
  // pipeline's mapFn is what actually issues the first Render agent() call —
  // invoke it exactly like the real Workflow-tool pipeline() would, so the
  // sentinel throw happens at the real call site, not a stub short-circuit.
  if (Array.isArray(items) && items.length && typeof mapFn === 'function') {
    return Promise.all(items.map((it) => Promise.resolve(mapFn(it))));
  }
  throw new Error(SENTINEL);
}
async function workflowStub(spec, wfArgs) {
  calls.push({ fn: 'workflow', spec: spec || null, wfArgs: wfArgs || null });
  throw new Error(SENTINEL);
}
function phaseStub(name) { calls.push({ fn: 'phase', name }); }
function logStub(msg) { calls.push({ fn: 'log', msg: String(msg) }); }
const budgetObj = { total: 0, remaining: () => 0 };

(async () => {
  let result = null;
  let threw = null;
  try {
    result = await fn(parsedArgs, phaseStub, agentStub, logStub, workflowStub, parallelStub, pipelineStub, budgetObj);
  } catch (e) {
    threw = { message: e.message };
  }
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls }, null, 2));
})();
NODE

run_case() { # run_case <caseName> <argsFile> <outFile>
  local caseName="$1" argsFile="$2" outFile="$3"
  if ! node "$TMP/driver.cjs" "$MODULE" "$argsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver invocation itself failed (not a caught throw): $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

TOPIC_VALUE="channel-validation-eval-topic"
BASE_ARGS='{"harnessDir":".","topic":"'"$TOPIC_VALUE"'","synthesisPath":"/tmp/eval-synthesis.json"'

# ---- Case 1: unknown channel string -> fail-closed throw before Render ----
unknownChannelArgs="$BASE_ARGS"',"__routePlan":[{"genre":"general","channel":"not-a-real-channel","mechanism":"artifact","templateSource":"blog","outputHint":"out.md"}]}'
printf '%s' "$unknownChannelArgs" > "$TMP/case1.json"
run_case case1 "$TMP/case1.json" "$TMP/out1.json"
if [ -f "$TMP/out1.json" ]; then
  python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'is not one of the channels this module can' not in got:
    print(f"  FAIL case1: an unknown route.plan channel did NOT trigger the #764 fail-closed channel-validation throw — threw={d['threw']}")
    ok = False
elif any(c.get('fn') in ('pipeline', 'parallel', 'workflow') for c in d['calls']):
    print(f"  FAIL case1: the channel-validation guard should fire before Render is ever reached, but Render-phase calls were made: {d['calls']}")
    ok = False
else:
    print("  ok  case1: unknown channel fails closed before Render")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
else
  fail=1
fi

# ---- Case 2: mechanism/channel mismatch -> fail-closed throw before Render ----
mismatchArgs="$BASE_ARGS"',"__routePlan":[{"genre":"-","channel":"blog","mechanism":"source-direct","templateSource":"blog","outputHint":"out.md"}]}'
printf '%s' "$mismatchArgs" > "$TMP/case2.json"
run_case case2 "$TMP/case2.json" "$TMP/out2.json"
if [ -f "$TMP/out2.json" ]; then
  python3 - "$TMP/out2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'mechanism/channel pairing is inconsistent' not in got:
    print(f"  FAIL case2: a mechanism/channel mismatch (source-direct + blog) did NOT trigger the #764 fail-closed guard — threw={d['threw']}")
    ok = False
elif any(c.get('fn') in ('pipeline', 'parallel', 'workflow') for c in d['calls']):
    print(f"  FAIL case2: the channel-validation guard should fire before Render is ever reached, but Render-phase calls were made: {d['calls']}")
    ok = False
else:
    print("  ok  case2: mechanism/channel mismatch fails closed before Render")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
else
  fail=1
fi

# ---- Case 3: a genuinely valid channel -> proceeds PAST the guard into Render ----
validArgs="$BASE_ARGS"',"__routePlan":[{"genre":"general","channel":"blog","mechanism":"artifact","templateSource":"blog","outputHint":"out.md"}]}'
printf '%s' "$validArgs" > "$TMP/case3.json"
run_case case3 "$TMP/case3.json" "$TMP/out3.json"
if [ -f "$TMP/out3.json" ]; then
  python3 - "$TMP/out3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'EVAL_SENTINEL_STOP_AT_RENDER' not in got:
    print(f"  FAIL case3: a genuinely valid channel (blog, mechanism=artifact) was rejected by the #764 guard (false positive) — threw={d['threw']}")
    ok = False
else:
    print("  ok  case3: a valid channel proceeds past the guard into Render (sentinel reached, not the validation error)")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
else
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "deliverables-channel-validation-check: PASS (unknown channel and mechanism/channel mismatch fail closed before Render; a valid channel still renders)"
  exit 0
else
  echo "deliverables-channel-validation-check: FAIL"
  exit 1
fi
