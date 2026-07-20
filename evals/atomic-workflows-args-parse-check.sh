#!/usr/bin/env bash
# atomic-workflows-args-parse-check.sh — regression eval for
# research-harness-template#654: every one of the eleven ATOMIC workflow
# modules (research-goal.js, research-fanout.js, research-falsify.js,
# research-synthesis.js, research-projection.js, research-deliverables.js,
# research-augment.js, research-add-dimensions.js, research-pivot.js,
# research-import.js, research-coverage-audit.js) threw an instant, zero-
# transcript "args.topic is required" when invoked directly as a top-level
# Workflow-tool scriptPath call, even with topic genuinely present in the
# call's args.
#
# ROOT CAUSE (confirmed by reading every module's own args-handling code
# against research-pipeline.js's PRE-EXISTING fix for the identical failure
# mode, #617/research-pipeline-args-parse-check.sh): the Workflow tool's
# top-level `args` parameter arrives at a DIRECT top-level scriptPath
# invocation as a JSON-ENCODED STRING, not a parsed object — confirmed
# empirically in #617. research-pipeline.js already guards its own external
# entry point for this (`const A = typeof args === 'string' ? JSON.parse(args)
# : (args || {})`). Every one of the eleven atomic modules, however, read
# `args.topic` directly with NO such guard — #654's escalation comment
# established this is systemic (research-falsify.js, research-synthesis.js,
# research-goal.js all reproduced identically), and #617's own header comment
# had INCORRECTLY assumed "every other vendored module is only ever invoked
# internally via this script's own workflow() calls" — #654 disproves that
# assumption (research-goal.js's own `whenToUse` already documents standalone
# use). `args.topic` on a raw JSON string is always `undefined` (a string
# property access, never a thrown error), so every one of these modules'
# `if (!TOPIC) throw` line fired even when the caller's `topic` argument was
# genuinely present in the call.
#
# This eval drives each REAL, unmodified atomic module source via the same
# Workflow-runtime async-function-body framing technique
# research-pipeline-args-parse-check.sh already established, so it fails on
# any pre-fix module and passes once every module carries the guard — both
# statically provable, no LLM/agent calls required:
#
#   For EVERY module:
#     1. STRING args, topic (+ that module's own other required arg, if any)
#        present -> does NOT throw "<module>: args.topic is required";
#        instead reaches the module's first real agent()/parallel() call, and
#        that first call's captured payload demonstrably carries the TOPIC
#        value threaded from the parsed JSON STRING (never just "didn't
#        throw" — proves the parsed value actually flows through).
#     2. STRING args, topic MISSING -> still throws the module's own
#        documented '<module>: args.topic is required' message, with ZERO
#        agent/parallel calls made first (the guard fires before any work
#        starts).
#     3. OBJECT args (already-parsed — the shape every module receives when
#        invoked as a nested child, and the shape every pre-existing sibling
#        eval in this repo already drives each module with) -> continues to
#        behave identically to case 1, proving the fix does not regress the
#        nested-child invocation path.
#
# Exit 0 = every case, every module, holds. Exit 1 = a case failed. Exit 2 =
# a required tool is missing, or a module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  atomic-workflows-args-parse-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }

# ============================================================================
# Driver: runs a REAL atomic workflow module via the Workflow-runtime's own
# async-function-body framing. Reads the args payload as a RAW STRING from
# disk and hands it to `fn` UNPARSED when argsMode=string -- reproducing
# exactly what the real Workflow tool hands a module at a direct top-level
# scriptPath invocation (#617/#654). agent()/parallel() are stubbed generically
# (never module-specific): the first one invoked records its payload and
# throws a sentinel to short-circuit the rest of the module's real behavior --
# this eval only needs to prove args threading reaches that first real call,
# not exercise each module's full multi-phase behavior (already covered by
# each module's own dedicated eval, e.g. goal-lint-repair.sh, pivot-check.sh).
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsPath, argsMode, outPath] = process.argv;
if (!wfPath || !argsPath || !argsMode || !outPath) {
  console.error('usage: driver.cjs <module.js> <argsPath> <string|object> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
// Superset of every global any single atomic module actually references
// (agent/phase/log always; workflow/parallel/pipeline/budget only by some) --
// declaring an unused parameter name is harmless, and no atomic module calls
// workflow() (confirmed at research-pipeline.js implementation time: zero
// real composition calls among the eleven siblings).
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'pipeline', 'budget', src)

const rawArgsText = fs.readFileSync(argsPath, 'utf8');
const args = argsMode === 'string' ? rawArgsText : JSON.parse(rawArgsText);

const calls = [];
const SENTINEL = 'EVAL_SENTINEL_STOP';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  calls.push({ fn: 'agent', prompt: p, opts: opts || null });
  // research-projection.js and research-deliverables.js both open with a
  // same-process-contract preflight agent() call that (by design) checks
  // only synthesisPath -- it never mentions topic, so it cannot itself prove
  // JSON-string args threading. Let it succeed (matching PREFLIGHT_SCHEMA)
  // so execution reaches each module's NEXT real agent() call instead, which
  // does reference topic (research-projection's Report-phase render prompt,
  // research-deliverables' Route-phase plan prompt) -- every other module's
  // very first call already references topic directly, so this special case
  // never triggers for them.
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  throw new Error(SENTINEL);
}
async function parallelStub(fns) {
  calls.push({ fn: 'parallel', count: (fns || []).length });
  // Delegate to the first thunk so a module whose FIRST real call is
  // parallel() (research-coverage-audit.js's Sweep phase) still reaches a
  // real agent() call inside it, proving threading the same way every other
  // module's direct-agent-first path does.
  if (fns && fns[0]) return [await fns[0]()];
  throw new Error(SENTINEL);
}
async function pipelineStub(items, mapFn) {
  calls.push({ fn: 'pipeline', items: Array.isArray(items) ? items : null });
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
    result = await fn(args, phaseStub, agentStub, logStub, workflowStub, parallelStub, pipelineStub, budgetObj);
  } catch (e) {
    threw = { message: e.message };
  }
  const firstCall = calls.find((c) => c.fn === 'agent' || c.fn === 'parallel' || c.fn === 'pipeline' || c.fn === 'workflow') || null;
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls, firstCall }, null, 2));
})();
NODE

run_case() { # run_case <caseName> <modulePath> <argsPath> <string|object> <outFile>
  local caseName="$1" modulePath="$2" argsFile="$3" argsMode="$4" outFile="$5"
  if ! node "$TMP/driver.cjs" "$modulePath" "$argsFile" "$argsMode" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver invocation itself failed (not a caught throw): $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

# name : file : extra required JSON fields (comma-joined "key":"value" pairs, or empty)
MODULES=(
  "research-goal:.claude/workflows/research-goal.js:"
  "research-synthesis:.claude/workflows/research-synthesis.js:"
  "research-falsify:.claude/workflows/research-falsify.js:"
  "research-fanout:.claude/workflows/research-fanout.js:"
  "research-projection:.claude/workflows/research-projection.js:\"synthesisPath\":\"/tmp/eval-synthesis.json\""
  "research-deliverables:.claude/workflows/research-deliverables.js:\"synthesisPath\":\"/tmp/eval-synthesis.json\""
  "research-augment:.claude/workflows/research-augment.js:"
  "research-add-dimensions:.claude/workflows/research-add-dimensions.js:"
  "research-pivot:.claude/workflows/research-pivot.js:\"delta\":\"scope narrowed to EU only\""
  "research-import:.claude/workflows/research-import.js:\"containerDir\":\"/tmp/eval-container\""
  "research-coverage-audit:.claude/workflows/research-coverage-audit.js:"
)

TOPIC_VALUE="atomic-args-eval-topic"

for entry in "${MODULES[@]}"; do
  name="${entry%%:*}"
  rest="${entry#*:}"
  modulePath="${rest%%:*}"
  extra="${rest#*:}"

  [ -f "$modulePath" ] || { note "$modulePath not found — the vendored $name workflow must ship"; fail=1; continue; }

  extraJson=""
  [ -n "$extra" ] && extraJson=",$extra"

  # ---- Case 1: STRING args, topic present -> no "args.topic is required" throw ----
  presentArgs="{\"harnessDir\":\".\",\"topic\":\"$TOPIC_VALUE\"$extraJson}"
  printf '%s' "$presentArgs" > "$TMP/$name-present.json"
  run_case "$name-c1" "$modulePath" "$TMP/$name-present.json" string "$TMP/$name-out1.json"
  if [ -f "$TMP/$name-out1.json" ]; then
    python3 - "$TMP/$name-out1.json" "$name" "$TOPIC_VALUE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
name = sys.argv[2]
topic = sys.argv[3]
bad_msg = f"{name}: args.topic is required"
ok = True
if d['threw'] is not None and d['threw'].get('message') == bad_msg:
    print(f"  FAIL {name} c1: string args with topic present STILL threw the missing-topic guard: {d['threw']}")
    ok = False
elif d['firstCall'] is None:
    print(f"  FAIL {name} c1: no agent/parallel/pipeline/workflow call was ever reached (result={d['result']}, threw={d['threw']})")
    ok = False
else:
    # Search every call captured, not just the first -- a module whose first
    # real call is parallel()/a preflight (research-coverage-audit.js,
    # research-projection.js, research-deliverables.js) still proves
    # threading via a call reached slightly deeper, not necessarily the very
    # first one recorded.
    blob = json.dumps(d['calls'])
    if topic not in blob:
        print(f"  FAIL {name} c1: topic value {topic!r} parsed from the JSON string did not thread into any real call reached: {blob[:400]}")
        ok = False
    else:
        print(f"  ok  {name} c1: string args, topic present -> no missing-topic throw, value threaded into a real call")
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || fail=1
  fi

  # ---- Case 2: STRING args, topic MISSING -> still throws, zero calls made ----
  missingArgs="{\"harnessDir\":\".\"$extraJson}"
  printf '%s' "$missingArgs" > "$TMP/$name-missing.json"
  run_case "$name-c2" "$modulePath" "$TMP/$name-missing.json" string "$TMP/$name-out2.json"
  if [ -f "$TMP/$name-out2.json" ]; then
    python3 - "$TMP/$name-out2.json" "$name" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
name = sys.argv[2]
want = f"{name}: args.topic is required"
got = d['threw'] and d['threw'].get('message')
ok = True
if got != want:
    print(f"  FAIL {name} c2: expected throw {want!r}, got {got!r} (result={d['result']})")
    ok = False
elif d['calls']:
    print(f"  FAIL {name} c2: guard should fire before any real work — but calls were made: {d['calls']}")
    ok = False
else:
    print(f"  ok  {name} c2: string args, topic missing -> still throws the documented guard message, no work started")
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || fail=1
  fi

  # ---- Case 3: OBJECT args (already-parsed) -> unchanged, no regression ----
  run_case "$name-c3" "$modulePath" "$TMP/$name-present.json" object "$TMP/$name-out3.json"
  if [ -f "$TMP/$name-out3.json" ]; then
    python3 - "$TMP/$name-out3.json" "$name" "$TOPIC_VALUE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
name = sys.argv[2]
topic = sys.argv[3]
bad_msg = f"{name}: args.topic is required"
ok = True
if d['threw'] is not None and d['threw'].get('message') == bad_msg:
    print(f"  FAIL {name} c3: already-parsed object args threw the missing-topic guard: {d['threw']}")
    ok = False
elif d['firstCall'] is None:
    print(f"  FAIL {name} c3: no agent/parallel/pipeline/workflow call was ever reached (result={d['result']}, threw={d['threw']})")
    ok = False
else:
    blob = json.dumps(d['calls'])
    if topic not in blob:
        print(f"  FAIL {name} c3: topic value did not thread into any real call reached: {blob[:400]}")
        ok = False
    else:
        print(f"  ok  {name} c3: already-parsed object args -> unchanged, no regression")
sys.exit(0 if ok else 1)
PY
    [ $? -eq 0 ] || fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "atomic-workflows-args-parse-check: PASS (all modules, all cases)"
  exit 0
else
  echo "atomic-workflows-args-parse-check: FAIL"
  exit 1
fi
