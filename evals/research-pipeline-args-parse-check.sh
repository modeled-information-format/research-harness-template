#!/usr/bin/env bash
# research-pipeline-args-parse-check.sh — regression eval for
# research-harness-template#617: research-pipeline.js threw
# "args.topic is required" on EVERY real /research invocation because it
# read `args.topic` directly, but the Workflow tool's top-level `args`
# parameter arrives at this external entry point as a JSON-ENCODED STRING,
# not a parsed object (confirmed empirically in the issue via a zero-agent
# diagnostic run: `typeof args === 'string'`, `Object.keys(args)` returning
# numeric character indices). `args.topic` on a raw string is always
# `undefined`, so the guard threw unconditionally.
#
# research-pipeline.js is the ONE vendored module this bites: per the
# architecture's D-9 (composition exactly two levels deep), it is the only
# one of the twelve workflow modules invoked externally through the
# Workflow-tool boundary — every other module is only ever invoked
# internally via this script's own workflow() calls, which pass real
# in-process JS objects, never a re-serialized string.
#
# This eval drives the REAL, unmodified research-pipeline.js source via the
# Workflow-runtime's own async-function-body framing (same technique as
# research-pipeline-full-mode-check.sh / research-pipeline-audit-check.sh),
# so it fails on the pre-fix source and passes on the fix, both statically
# provable:
#
#   1. STRING args, topic present (audit mode) -> does NOT throw, and the
#      topic/harnessDir/workflowsDir values threaded from the JSON STRING
#      really reach the child wf() call (proves the parsed values, not
#      just "no throw", flow through).
#   2. STRING args, topic MISSING -> still throws the documented
#      'research-pipeline: args.topic is required' (the guard itself must
#      keep working, not just stop firing).
#   3. STRING args, import mode, containerDir present -> succeeds and
#      threads containerDir/trustImportedVerdicts from the string (proves
#      the fix isn't scoped to just the topic read -- issue's suggested fix
#      explicitly calls for every `args.*` read to move to the parsed form).
#   4. STRING args, import mode, containerDir MISSING -> still throws
#      'import mode requires args.containerDir'.
#   5. STRING args, pivot mode, delta present -> succeeds and threads delta.
#   6. STRING args, pivot mode, delta MISSING -> still throws
#      'pivot mode requires args.delta'.
#   7. OBJECT args (already-parsed, the shape research-pipeline.js's OWN
#      workflow() calls always pass to their children, and the shape every
#      pre-existing sibling eval in this repo already drives the module
#      with) -> continues to work identically, proving the fix does not
#      regress the non-string case.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  research-pipeline-args-parse-check: %s\n' "$1"; }

WF=.claude/workflows/research-pipeline.js

# ============================================================================
# Driver: runs the REAL research-pipeline.js via the Workflow-runtime's own
# async-function-body framing. Unlike the sibling evals' drivers, this one
# reads the args payload as a RAW STRING from disk and hands it to `fn`
# UNPARSED when the case says so -- reproducing exactly what the real
# Workflow tool hands the module at the external entry point (issue #617).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsPath, argsMode, stubsPath, outPath] = process.argv;
if (!wfPath || !argsPath || !argsMode || !stubsPath || !outPath) {
  console.error('usage: driver.cjs <research-pipeline.js> <argsPath> <string|object> <stubs.cjs> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'budget', src);

const rawArgsText = fs.readFileSync(argsPath, 'utf8');
// argsMode 'string' reproduces the real runtime: args IS the JSON text
// itself, unparsed. argsMode 'object' reproduces every sibling eval's
// existing assumption: args is already a parsed JS object.
const args = argsMode === 'string' ? rawArgsText : JSON.parse(rawArgsText);

// eslint-disable-next-line import/no-dynamic-require, global-require
const stubs = require(stubsPath);

const wfCalls = [];
const logs = [];

async function workflowStub(spec, wfArgs) {
  const scriptPath = (spec && spec.scriptPath) || '';
  const m = /research-([a-zA-Z-]+)\.js$/.exec(scriptPath);
  const name = m && m[1];
  wfCalls.push({ name, scriptPath, args: wfArgs });
  const handler = stubs.wf && stubs.wf[name];
  if (!handler) throw new Error('workflowStub: unexpected/unstubbed scriptPath ' + JSON.stringify({ scriptPath, name }));
  return handler(wfArgs);
}

async function agentStub(prompt, opts) {
  throw new Error('agentStub: this eval never expects agent() to be called (label ' + JSON.stringify(opts && opts.label) + ')');
}

function phaseStub(name) { logs.push({ phase: name }); }
function logStub(msg) { logs.push({ log: msg }); }
async function parallelStub(fns) { return Promise.all((fns || []).map((f) => f())); }
const budgetObj = { total: 0, remaining: () => 0 };

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

run_case() { # run_case <caseName> <argsPath> <string|object> <stubsFile> <outFile>
  local caseName="$1" argsFile="$2" argsMode="$3" stubsFile="$4" outFile="$5"
  if ! node "$TMP/driver.cjs" "$WF" "$argsFile" "$argsMode" "$stubsFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver invocation itself failed (not a caught throw): $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

AUDIT_STUB='
  wf: {
    "coverage-audit": async () => ({ backlog: [], summary: "nothing to route", rawItems: [], uncoveredAngles: [] }),
  },
'

# ----------------------------------------------------------------------
# 1. STRING args, topic present, audit mode -> no throw; topic/harnessDir
#    threaded from the JSON STRING actually reach the child wf() call.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"audit","workflowsDir":".claude/workflows"}' > "$TMP/args-1.json"
cat > "$TMP/stubs-1.cjs" <<NODE
module.exports = { $AUDIT_STUB };
NODE
run_case c1 "$TMP/args-1.json" string "$TMP/stubs-1.cjs" "$TMP/out-1.json"
if [ -f "$TMP/out-1.json" ]; then
  python3 - "$TMP/out-1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
if d['threw'] is not None:
    print(f"  FAIL c1: string args with topic present threw: {d['threw']}")
    ok = False
elif d['result'] is None or d['result'].get('mode') != 'audit':
    print(f"  FAIL c1: unexpected result: {d['result']}")
    ok = False
else:
    calls = d['wfCalls']
    if len(calls) != 1 or calls[0]['name'] != 'coverage-audit':
        print(f"  FAIL c1: expected exactly one coverage-audit call, got {calls}")
        ok = False
    elif calls[0]['args'].get('topic') != 'pipeline-args-eval-topic':
        print(f"  FAIL c1: topic parsed from the JSON string did not thread into the child call: {calls[0]['args']}")
        ok = False
    elif calls[0]['args'].get('harnessDir') != 'h1':
        print(f"  FAIL c1: harnessDir parsed from the JSON string did not thread into the child call: {calls[0]['args']}")
        ok = False
    elif calls[0]['scriptPath'] != '.claude/workflows/research-coverage-audit.js':
        print(f"  FAIL c1: workflowsDir parsed from the JSON string did not thread into the child scriptPath: {calls[0]['scriptPath']}")
        ok = False
    else:
        print("  ok  c1: string args, topic present, audit mode -> no throw, values threaded correctly")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 2. STRING args, topic MISSING -> the guard still fires, with its
#    documented message.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","mode":"audit"}' > "$TMP/args-2.json"
cat > "$TMP/stubs-2.cjs" <<NODE
module.exports = { $AUDIT_STUB };
NODE
run_case c2 "$TMP/args-2.json" string "$TMP/stubs-2.cjs" "$TMP/out-2.json"
if [ -f "$TMP/out-2.json" ]; then
  python3 - "$TMP/out-2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
want = 'research-pipeline: args.topic is required'
got = d['threw'] and d['threw'].get('message')
if got != want:
    print(f"  FAIL c2: expected throw {want!r}, got {got!r} (result={d['result']})")
    sys.exit(1)
print("  ok  c2: string args, topic missing -> still throws the documented guard message")
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 3. STRING args, import mode, containerDir present -> succeeds, threads
#    containerDir/trustImportedVerdicts parsed from the string.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"import","containerDir":"/tmp/some-container","trustImportedVerdicts":true}' > "$TMP/args-3.json"
cat > "$TMP/stubs-3.cjs" <<'NODE'
module.exports = {
  wf: {
    import: async () => ({ ok: true, needsGating: [], imported: [] }),
    synthesis: async () => ({ ok: false }),
  },
};
NODE
run_case c3 "$TMP/args-3.json" string "$TMP/stubs-3.cjs" "$TMP/out-3.json"
if [ -f "$TMP/out-3.json" ]; then
  python3 - "$TMP/out-3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
if d['threw'] is not None:
    print(f"  FAIL c3: string args, import mode with containerDir present threw: {d['threw']}")
    ok = False
else:
    calls = [c for c in d['wfCalls'] if c['name'] == 'import']
    if not calls:
        print(f"  FAIL c3: no import wf() call recorded: {d['wfCalls']}")
        ok = False
    elif calls[0]['args'].get('containerDir') != '/tmp/some-container' or calls[0]['args'].get('trustImportedVerdicts') is not True:
        print(f"  FAIL c3: containerDir/trustImportedVerdicts parsed from the JSON string did not thread into the child call: {calls[0]['args']}")
        ok = False
    else:
        print("  ok  c3: string args, import mode, containerDir present -> no throw, values threaded correctly")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 4. STRING args, import mode, containerDir MISSING -> still throws.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"import"}' > "$TMP/args-4.json"
cat > "$TMP/stubs-4.cjs" <<'NODE'
module.exports = { wf: {} };
NODE
run_case c4 "$TMP/args-4.json" string "$TMP/stubs-4.cjs" "$TMP/out-4.json"
if [ -f "$TMP/out-4.json" ]; then
  python3 - "$TMP/out-4.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
want = 'import mode requires args.containerDir'
got = d['threw'] and d['threw'].get('message')
if got != want:
    print(f"  FAIL c4: expected throw {want!r}, got {got!r} (result={d['result']})")
    sys.exit(1)
print("  ok  c4: string args, import mode, containerDir missing -> still throws the documented guard message")
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 5. STRING args, pivot mode, delta present -> succeeds, threads delta.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"pivot","delta":"scope narrowed to EU only"}' > "$TMP/args-5.json"
cat > "$TMP/stubs-5.cjs" <<'NODE'
module.exports = {
  wf: {
    pivot: async (wfArgs) => ({
      goalVersion: 'v2',
      goalStatement: 'narrowed goal',
      carry: [],
      stale: [],
      reverifyIds: [],
      gapDimensions: [],
      _receivedDelta: wfArgs.delta,
    }),
    synthesis: async () => ({ ok: false }),
  },
};
NODE
run_case c5 "$TMP/args-5.json" string "$TMP/stubs-5.cjs" "$TMP/out-5.json"
if [ -f "$TMP/out-5.json" ]; then
  python3 - "$TMP/out-5.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
if d['threw'] is not None:
    print(f"  FAIL c5: string args, pivot mode with delta present threw: {d['threw']}")
    ok = False
else:
    calls = [c for c in d['wfCalls'] if c['name'] == 'pivot']
    if not calls or calls[0]['args'].get('delta') != 'scope narrowed to EU only':
        print(f"  FAIL c5: delta parsed from the JSON string did not thread into the child call: {calls}")
        ok = False
    else:
        print("  ok  c5: string args, pivot mode, delta present -> no throw, value threaded correctly")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 6. STRING args, pivot mode, delta MISSING -> still throws.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"pivot"}' > "$TMP/args-6.json"
cat > "$TMP/stubs-6.cjs" <<'NODE'
module.exports = { wf: {} };
NODE
run_case c6 "$TMP/args-6.json" string "$TMP/stubs-6.cjs" "$TMP/out-6.json"
if [ -f "$TMP/out-6.json" ]; then
  python3 - "$TMP/out-6.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
want = 'pivot mode requires args.delta'
got = d['threw'] and d['threw'].get('message')
if got != want:
    print(f"  FAIL c6: expected throw {want!r}, got {got!r} (result={d['result']})")
    sys.exit(1)
print("  ok  c6: string args, pivot mode, delta missing -> still throws the documented guard message")
PY
  [ $? -eq 0 ] || fail=1
fi

# ----------------------------------------------------------------------
# 7. OBJECT args (already-parsed) -> unchanged behavior, no regression.
# ----------------------------------------------------------------------
printf '%s' '{"harnessDir":"h1","topic":"pipeline-args-eval-topic","mode":"audit"}' > "$TMP/args-7.json"
cat > "$TMP/stubs-7.cjs" <<NODE
module.exports = { $AUDIT_STUB };
NODE
run_case c7 "$TMP/args-7.json" object "$TMP/stubs-7.cjs" "$TMP/out-7.json"
if [ -f "$TMP/out-7.json" ]; then
  python3 - "$TMP/out-7.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
ok = True
if d['threw'] is not None:
    print(f"  FAIL c7: already-parsed object args threw: {d['threw']}")
    ok = False
elif d['result'] is None or d['result'].get('mode') != 'audit':
    print(f"  FAIL c7: unexpected result: {d['result']}")
    ok = False
else:
    print("  ok  c7: already-parsed object args -> unchanged, no regression")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "research-pipeline-args-parse-check: PASS (all cases)"
  exit 0
else
  echo "research-pipeline-args-parse-check: FAIL"
  exit 1
fi
