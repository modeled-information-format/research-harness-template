#!/usr/bin/env bash
# deliverables-refix-null-repair-check.sh — regression eval for
# research-harness-template#740: research-deliverables.js's repair loop
# (`const refixed = await parallel(dirty.map((a) => async () => { ... }))`)
# destructured `{ a, rv }` straight out of each `refixed` entry without
# guarding against `null`. Per the runtime's documented `parallel()`
# contract, a thunk that THROWS makes its own slot in the returned array
# resolve to `null` rather than rejecting the whole `parallel()` call. If the
# 'fix' `agent()` call inside a repair thunk throws (e.g. the subagent dies
# on a terminal error after retries — one of agent()'s two documented
# failure modes), the enclosing thunk rejects, its slot in `refixed` is
# `null`, and `for (const { a, rv } of refixed)` throws a TypeError
# ("Cannot destructure property `a` of `null`"), crashing the ENTIRE
# workflow run — including losing the already-succeeded fix/recheck results
# for every OTHER artifact in the same repair batch, and never returning the
# `{ ok, artifacts, unavailable }` result the caller expects.
#
# This eval proves the fix: a repair thunk whose 'fix' call throws no longer
# crashes the run. It (1) is caught inside the thunk itself, logging a
# WARNING naming the artifact and returning `{ a, rv: null }` instead of
# rejecting, (2) leaves that artifact's prior (failing) validation recorded
# rather than throwing, and (3) does NOT prevent a DIFFERENT artifact in the
# same repair batch from being fixed and re-checked to a real `clean: true`
# verdict.
#
# This eval drives the REAL, unmodified module source via the Workflow-
# runtime's own async-function-body framing (the same technique
# deliverables-null-check-repair-check.sh/deliverables-channel-validation-
# check.sh use), stubbing `agent()`/`pipeline()`/`parallel()` so the fix can
# be proven without a live model call. Unlike those two evals' `parallel()`
# stubs (which run every thunk via a bare `Promise.all` and let a thunk's
# rejection propagate as a whole-call rejection), THIS eval's `parallel()`
# stub matches the real runtime's documented contract exactly: each thunk's
# rejection is caught and mapped to a `null` in that slot, never rejecting
# the whole call — that distinction is exactly what research-harness-
# template#740 is about, so the stub must reproduce it faithfully or this
# eval would not actually exercise the bug.
#
# DELIVERABLES_MODULE can be pointed at an arbitrary copy of the module
# source (used below to also prove this exact eval FAILS against the
# pre-fix code, satisfying "a fix without a test that fails before and
# passes after is not done" — not merely asserted, checked).
#
# Exit 0 = the fix holds. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE="${DELIVERABLES_MODULE:-.claude/workflows/research-deliverables.js}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/deliverables-refix-null-eval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  deliverables-refix-null-repair-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found — the vendored research-deliverables workflow must ship (Epic #544, Task #573)"; exit 2; }

# ============================================================================
# Driver: same async-function-body technique as
# deliverables-null-check-repair-check.sh, but with a `parallel()` stub that
# reproduces the REAL runtime's documented per-thunk-catch contract (a
# throwing thunk resolves to `null` in its own slot, the call itself never
# rejects) instead of running the thunks via a bare `Promise.all` (which
# would let one thunk's rejection reject the whole `parallel()` call — the
# wrong contract for this bug).
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
const OUTPUT_PATH_BLOG = '/tmp/eval-refix-null-artifact.blog.md';
const OUTPUT_PATH_BOOK = '/tmp/eval-refix-null-artifact.book.md';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  const label = (opts && opts.label) || '';
  calls.push({ fn: 'agent', label, prompt: p.slice(0, 100) });
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  if (p.startsWith('Build the deliverables render plan')) return { plan: routePlan, unavailable: [] };
  if (label.startsWith('render:')) {
    const outputPath = label.includes('xblog') ? OUTPUT_PATH_BLOG : OUTPUT_PATH_BOOK;
    return {
      outputPath,
      genre: 'general',
      channel: label.includes('xblog') ? 'blog' : 'book',
      mechanism: 'artifact',
      citationsCount: 3,
      genreApplied: false,
      genreSkillInvoked: '',
      provenanceOutcome: 'not-applicable',
      provenanceReason: 'eval fixture',
    };
  }
  // Both rows fail their INITIAL check so both enter the repair loop.
  if (label.startsWith('check:')) return { clean: false, problems: ['placeholder text left in body'] };
  // research-harness-template#740's failure scenario: the FIRST agent()
  // call inside the blog row's repair thunk (the 'fix' call) throws, e.g.
  // the subagent dying on a terminal error after retries. The book row's
  // fix call succeeds normally, proving the blog row's failure does not
  // take down the book row's repair.
  if (label === 'fix:generalxblog') throw new Error('simulated subagent terminal failure after retries');
  if (label === 'fix:generalxbook') return { fixed: true };
  // The blog row's recheck must NEVER be reached — its thunk should have
  // already thrown and been caught at the 'fix' call above.
  if (label === 'recheck:generalxblog') throw new Error('agentStub: recheck:generalxblog should not be reached — fix: threw first');
  if (label === 'recheck:generalxbook') return { clean: true, problems: [] };
  throw new Error('agentStub: unexpected call ' + JSON.stringify({ label, prompt: p.slice(0, 120) }));
}

// Runs pipeline stages for real so the repair loop downstream of `rendered`
// can actually observe two dirty artifacts.
async function pipelineStub(items, ...stages) {
  calls.push({ fn: 'pipeline', items: Array.isArray(items) ? items.length : null, stages: stages.length });
  if (!Array.isArray(items)) return [];
  let current = items;
  for (const stageFn of stages) {
    current = await Promise.all(current.map((val, idx) => Promise.resolve(stageFn(val, items[idx]))));
  }
  return current;
}

// THE CONTRACT UNDER TEST: a thunk that throws must resolve to `null` in
// its own slot, never reject the whole parallel() call — exactly what the
// real runtime's parallel() does per research-harness-template#740's own
// description, and exactly what distinguishes this eval's stub from the
// bare-`Promise.all` stubs used by other deliverables evals (which would
// propagate a throwing thunk as a whole-call rejection instead).
async function parallelStub(fns) {
  calls.push({ fn: 'parallel', count: (fns || []).length });
  return Promise.all(
    (fns || []).map((f) =>
      Promise.resolve()
        .then(f)
        .catch((e) => {
          calls.push({ fn: 'parallel-thunk-rejected', message: e && e.message });
          return null;
        }),
    ),
  );
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
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls, logs, OUTPUT_PATH_BLOG, OUTPUT_PATH_BOOK }, null, 2));
})();
NODE

TOPIC_VALUE="refix-null-repair-eval-topic"
BASE_ARGS='{"harnessDir":".","topic":"'"$TOPIC_VALUE"'","synthesisPath":"/tmp/eval-synthesis.json"'
routePlanArgs="$BASE_ARGS"',"__routePlan":[{"genre":"general","channel":"blog","mechanism":"artifact","templateSource":"blog","outputHint":"out-blog.md"},{"genre":"general","channel":"book","mechanism":"artifact","templateSource":"book","outputHint":"out-book.md"}]}'
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
    msg = d['threw'].get('message', '')
    print(f"  FAIL: the module threw instead of handling a null repair-loop entry — threw={d['threw']}")
    if 'destructure' in msg.lower() or 'null' in msg.lower():
        print("        (this looks like exactly the pre-fix crash research-harness-template#740 describes)")
    ok = False
else:
    print("  ok  the module did not crash when one repair thunk's fix() call threw")

logs = d.get('logs', [])
# Specifically the "repair ... threw" WARNING, not just any WARNING that
# happens to mention the blog path — a broader match would also pass on the
# generic "re-validation after fix produced no result" warning, which is a
# DIFFERENT condition (a resolved-but-empty recheck, not a thrown repair)
# and must not fire for this thrown case (see the duplicate-warning check
# just below).
threw_warning_logs = [
    l for l in logs
    if 'WARNING' in l and 'repair (fix and/or re-check) threw' in l and d['OUTPUT_PATH_BLOG'] in l
]
if not threw_warning_logs:
    print(f"  FAIL: no 'repair ... threw' WARNING was logged naming the artifact whose repair thunk threw (research-harness-template#740) — logs={logs}")
    ok = False
else:
    print("  ok  a 'repair ... threw' WARNING is logged naming the artifact whose repair (fix/recheck) threw")

# The thrown case must not ALSO trigger the generic re-validation-produced-
# no-result warning for the same artifact — that would be a duplicate,
# misleading pair of warnings for one failure (the second reads as a null
# recheck, not a thrown repair).
duplicate_warning_logs = [
    l for l in logs
    if 'WARNING' in l and 're-validation after fix produced no result' in l and d['OUTPUT_PATH_BLOG'] in l
]
if duplicate_warning_logs:
    print(f"  FAIL: the generic re-validation warning ALSO fired for the thrown artifact — duplicate/misleading warnings for one failure: {duplicate_warning_logs}")
    ok = False
else:
    print("  ok  the generic re-validation warning did not also fire for the artifact whose repair threw (no duplicate warnings)")

recheck_calls_blog = [c for c in d['calls'] if c.get('fn') == 'agent' and c.get('label') == 'recheck:generalxblog']
if recheck_calls_blog:
    print(f"  FAIL: recheck:generalxblog was called even though fix:generalxblog should have thrown first — calls={recheck_calls_blog}")
    ok = False
else:
    print("  ok  the blog row's recheck was never reached, consistent with its fix call throwing first")

res = d.get('result') or {}
artifacts = res.get('artifacts') or []
if len(artifacts) != 2:
    print(f"  FAIL: expected both artifacts to survive in the final result (one repaired, one left failing) — artifacts={artifacts}")
    ok = False
else:
    print("  ok  both artifacts from the same repair batch survive in the final result")

by_path = {a.get('path'): a for a in artifacts}
blog_artifact = by_path.get(d['OUTPUT_PATH_BLOG'])
book_artifact = by_path.get(d['OUTPUT_PATH_BOOK'])

if not blog_artifact or blog_artifact.get('clean') is not False:
    print(f"  FAIL: the artifact whose repair threw should keep its prior FAILING validation (clean: false), not crash or silently pass — blog_artifact={blog_artifact}")
    ok = False
else:
    print("  ok  the artifact whose repair threw keeps its prior failing (clean: false) verdict instead of crashing the run")

if not book_artifact or book_artifact.get('clean') is not True:
    print(f"  FAIL: the OTHER artifact in the same repair batch should still be genuinely fixed and re-checked to clean: true — book_artifact={book_artifact}")
    ok = False
else:
    print("  ok  the other artifact in the same repair batch is still fixed and re-checked to a real clean: true verdict")

sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
else
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "deliverables-refix-null-repair-check: PASS (a repair thunk that throws no longer crashes the run, and sibling artifacts in the same batch still get repaired)"
  exit 0
else
  echo "deliverables-refix-null-repair-check: FAIL"
  exit 1
fi
