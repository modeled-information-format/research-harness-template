#!/usr/bin/env bash
# projection-slug-genre-args-check.sh — regression eval for
# research-harness-template#675: research-projection.js's #617-pattern args
# guard (`const A = typeof args === 'string' ? JSON.parse(args) : (args || {})`)
# was incomplete for one revision window — `H`/`TOPIC`/`SYN` read from the
# parsed `A`, but `SLUG`/`GENRE` still read from the raw `args`. When `args`
# arrives as a JSON-encoded STRING (the exact direct top-level Workflow-tool
# invocation shape the guard exists for, #617/#654), a property access on a
# string primitive is always `undefined` — no parse error, no exception — so
# `SLUG` silently fell back to `TOPIC` and `GENRE` silently fell back to
# 'general', dropping the caller's requested slug/genre and defeating the
# #633 genre-resolution mechanism this same module implements.
#
# The sibling eval (atomic-workflows-args-parse-check.sh, #654) proves only
# `topic` threads through string args — a regression re-introducing raw-args
# reads for the OPTIONAL fields would pass it undetected. This eval pins the
# #675 defect class specifically, driving the REAL, unmodified module source
# via the same Workflow-runtime async-function-body framing:
#
#   1. STRING args carrying a custom slug + a valid non-default genre ->
#      BOTH values demonstrably thread into the module's real agent() calls
#      (the genre-resolve prompt names the genre; the Report-phase prompt
#      embeds the slug in the report path). Pre-#661-fix code fails this:
#      genre-resolve is skipped entirely (GENRE defaulted to 'general') and
#      the report path uses TOPIC, not the slug.
#   2. STRING args carrying an INVALID genre (fails the pack-name pattern
#      ^[a-z][a-z0-9-]*$) -> the module throws its documented fail-closed
#      pattern error BEFORE any agent call. Pre-fix code fails this too:
#      the invalid genre was never seen (read as `undefined` -> 'general'),
#      so the module silently proceeded.
#   3. OBJECT args (already-parsed, the nested-child invocation shape) with
#      the same slug/genre -> identical threading, proving no regression on
#      the in-process path.
#
# Exit 0 = all cases hold. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE="${PROJECTION_MODULE:-.claude/workflows/research-projection.js}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  projection-slug-genre-args-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found — the vendored research-projection workflow must ship"; exit 2; }

# ============================================================================
# Driver: runs the REAL module via the Workflow-runtime's own async-function-
# body framing (same technique as atomic-workflows-args-parse-check.sh).
# argsMode=string hands the raw JSON text UNPARSED, reproducing exactly what
# the real Workflow tool hands a module at a direct top-level scriptPath
# invocation. Two prompts are let through so execution reaches the calls that
# actually reference slug/genre: the same-process preflight (returns
# exists=true) and the #633 genre-resolve call (returns pack-enabled, with
# the genre echoed back from the prompt itself — never from this driver's
# own knowledge of the args). The next real call throws a sentinel.
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
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'pipeline', 'budget', src);

const rawArgsText = fs.readFileSync(argsPath, 'utf8');
const args = argsMode === 'string' ? rawArgsText : JSON.parse(rawArgsText);

const calls = [];
const SENTINEL = 'EVAL_SENTINEL_STOP';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  calls.push({ fn: 'agent', prompt: p, opts: opts || null });
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  if (p.startsWith('GENRE ENABLEMENT CHECK')) {
    // Echo the genre back from the PROMPT text itself: this proves the
    // module interpolated the caller's genre into the real prompt. Match
    // the module's own phrasing.
    const m = p.match(/Genre "([^"]+)" was requested/);
    const g = m ? m[1] : 'general';
    return { genreArg: g, genrePackEnabled: true, genreSkillRef: `${g}:${g}` };
  }
  throw new Error(SENTINEL);
}
async function parallelStub(fns) {
  calls.push({ fn: 'parallel', count: (fns || []).length });
  if (fns && fns[0]) return [await fns[0]()];
  throw new Error(SENTINEL);
}
async function pipelineStub(items) {
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
  fs.writeFileSync(outPath, JSON.stringify({ result, threw, calls }, null, 2));
})();
NODE

run_case() { # run_case <caseName> <argsFile> <string|object> <outFile>
  local caseName="$1" argsFile="$2" argsMode="$3" outFile="$4"
  if ! node "$TMP/driver.cjs" "$MODULE" "$argsFile" "$argsMode" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver invocation itself failed (not a caught throw): $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

TOPIC_VALUE="slug-genre-eval-topic"
SLUG_VALUE="custom-slug-675"
GENRE_VALUE="eval-genre-675"

goodArgs="{\"harnessDir\":\".\",\"topic\":\"$TOPIC_VALUE\",\"synthesisPath\":\"/tmp/eval-synthesis.json\",\"slug\":\"$SLUG_VALUE\",\"genre\":\"$GENRE_VALUE\"}"
printf '%s' "$goodArgs" > "$TMP/good.json"
badGenreArgs="{\"harnessDir\":\".\",\"topic\":\"$TOPIC_VALUE\",\"synthesisPath\":\"/tmp/eval-synthesis.json\",\"genre\":\"NOT A Pack!\"}"
printf '%s' "$badGenreArgs" > "$TMP/bad-genre.json"

check_threading() { # check_threading <caseName> <outFile>
  python3 - "$2" "$1" "$SLUG_VALUE" "$GENRE_VALUE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
case, slug, genre = sys.argv[2], sys.argv[3], sys.argv[4]
blob = json.dumps(d['calls'])
ok = True
if genre not in blob:
    print(f"  FAIL {case}: genre {genre!r} did not thread into any real call — GENRE was read from raw args, not the parsed A (#675): {blob[:400]}")
    ok = False
if slug not in blob:
    print(f"  FAIL {case}: slug {slug!r} did not thread into any real call — SLUG was read from raw args, not the parsed A (#675): {blob[:400]}")
    ok = False
if ok:
    print(f"  ok  {case}: slug and genre both threaded into real calls")
sys.exit(0 if ok else 1)
PY
}

# ---- Case 1: STRING args -> slug AND genre both thread into real calls ----
run_case c1 "$TMP/good.json" string "$TMP/out1.json"
if [ -f "$TMP/out1.json" ]; then
  check_threading "c1 (string args)" "$TMP/out1.json" || fail=1
fi

# ---- Case 2: STRING args, invalid genre -> fail-closed throw, zero calls ----
run_case c2 "$TMP/bad-genre.json" string "$TMP/out2.json"
if [ -f "$TMP/out2.json" ]; then
  python3 - "$TMP/out2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'does not match the pack-name pattern' not in got:
    print(f"  FAIL c2: invalid genre in STRING args did not trigger the fail-closed pattern throw — GENRE was read from raw args (silently 'general', #675): threw={d['threw']}")
    ok = False
elif d['calls']:
    print(f"  FAIL c2: the genre-pattern guard should fire before any real work — but calls were made: {d['calls'][:3]}")
    ok = False
else:
    print("  ok  c2 (string args, invalid genre): fail-closed pattern throw fired before any work")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ---- Case 3: OBJECT args (nested-child shape) -> unchanged, no regression ----
run_case c3 "$TMP/good.json" object "$TMP/out3.json"
if [ -f "$TMP/out3.json" ]; then
  check_threading "c3 (object args)" "$TMP/out3.json" || fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "projection-slug-genre-args-check: PASS (slug/genre thread from string AND object args; invalid genre fails closed)"
  exit 0
else
  echo "projection-slug-genre-args-check: FAIL"
  exit 1
fi
