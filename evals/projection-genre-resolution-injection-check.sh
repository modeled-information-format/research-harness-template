#!/usr/bin/env bash
# projection-genre-resolution-injection-check.sh — regression eval for
# research-harness-template#757: research-projection.js's GENRE RESOLUTION
# step (#633) resolves genreArg/genreSkillRef via an agent() call rather than
# reusing the caller-supplied GENRE verbatim — but genreResolution.genreArg is
# then interpolated directly into a shell command
# (synthesize-artifact.sh's ${genreResolution.genreArg} argument) and
# genreResolution.genreSkillRef directly into a Skill() reference
# (genreStepText), with NO re-validation, even though GENRE itself is
# regex-validated against ^[a-z][a-z0-9-]*$ specifically to protect those
# exact two sinks. GENRE_SCHEMA declares both fields as plain
# `{type: 'string'}` with no `pattern`, so a malformed or hallucinated
# agent() response reaches both sinks unfiltered.
#
# This eval drives the REAL, unmodified module source via the Workflow-
# runtime's own async-function-body framing (same technique as
# projection-slug-genre-args-check.sh / atomic-workflows-args-parse-check.sh),
# stubbing the genre-resolve agent() call to return exactly the kind of
# LLM-hallucinated value the real defect lets through unchecked:
#
#   1. genreArg containing shell metacharacters (e.g. `general; rm -rf /`) ->
#      the module must throw a fail-closed error BEFORE any further work,
#      the same posture GENRE's own validation already has. Pre-fix code
#      lets it through: only the ternary/schema shape is checked, not the
#      string's content.
#   2. genreSkillRef naming an unrelated skill (e.g. an unrequested
#      "evil-genre:evil-genre") that does not match "<GENRE>:<GENRE>" -> the
#      module must throw before genreStepText embeds it in a Skill()
#      reference. Pre-fix code accepts it as long as genrePackEnabled=true.
#   3. A well-formed, expected genreArg/genreSkillRef pair (matching the
#      requested genre) -> resolution proceeds normally, no regression.
#
# Exit 0 = all cases hold. Exit 1 = a case failed. Exit 2 = a required tool
# is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE="${PROJECTION_MODULE:-.claude/workflows/research-projection.js}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/projection-genre-injection-eval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  projection-genre-resolution-injection-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found — the vendored research-projection workflow must ship"; exit 2; }

# ============================================================================
# Driver: runs the REAL module via the Workflow-runtime's own async-function-
# body framing. The genre-resolve agent() call is stubbed to return an
# INJECTED genreArg/genreSkillRef (via env vars baked into the driver script,
# read at call time) rather than the honest values the real prompt asks for —
# reproducing exactly what an LLM hallucination or adversarial completion
# would hand back through GENRE_SCHEMA's unconstrained plain-string fields.
# The preflight call is let through (returns exists=true) so execution
# reaches the genre-resolve call and the validation immediately after it; the
# next real call (the Report-phase render agent()) throws a sentinel so the
# eval never actually touches the filesystem/network.
# ============================================================================
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsPath, injectedArgPath, injectedRefPath, outPath] = process.argv;
if (!wfPath || !argsPath || !injectedArgPath || !injectedRefPath || !outPath) {
  console.error('usage: driver.cjs <module.js> <argsPath> <injectedArgPath> <injectedRefPath> <outPath>');
  process.exit(2);
}

const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'pipeline', 'budget', src);

const args = JSON.parse(fs.readFileSync(argsPath, 'utf8'));
const injectedArg = fs.readFileSync(injectedArgPath, 'utf8');
const injectedRef = fs.readFileSync(injectedRefPath, 'utf8');

const calls = [];
const SENTINEL = 'EVAL_SENTINEL_STOP';

async function agentStub(prompt, opts) {
  const p = String(prompt);
  calls.push({ fn: 'agent', prompt: p, opts: opts || null });
  if (p.startsWith('SAME-PROCESS CONTRACT CHECK.')) return { exists: true, reason: 'ok' };
  if (p.startsWith('GENRE ENABLEMENT CHECK')) {
    // Return the INJECTED (adversarial/hallucinated) values instead of the
    // honest resolution the real prompt asks for — this is the exact
    // unconstrained-LLM-output shape research-harness-template#757 names:
    // GENRE_SCHEMA has no `pattern`, so nothing in the schema itself stops
    // this from being returned and used verbatim by pre-fix code.
    return { genreArg: injectedArg, genrePackEnabled: true, genreSkillRef: injectedRef };
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

run_case() { # run_case <caseName> <argsFile> <injectedArgFile> <injectedRefFile> <outFile>
  local caseName="$1" argsFile="$2" injectedArgFile="$3" injectedRefFile="$4" outFile="$5"
  if ! node "$TMP/driver.cjs" "$MODULE" "$argsFile" "$injectedArgFile" "$injectedRefFile" "$outFile" >"$TMP/$caseName-run.err" 2>&1; then
    note "$caseName driver invocation itself failed (not a caught throw): $(cat "$TMP/$caseName-run.err")"
    fail=1
    return 1
  fi
  return 0
}

TOPIC_VALUE="genre-injection-eval-topic"
GENRE_VALUE="eval-genre-757"
goodArgs="{\"harnessDir\":\".\",\"topic\":\"$TOPIC_VALUE\",\"synthesisPath\":\"/tmp/eval-synthesis.json\",\"genre\":\"$GENRE_VALUE\"}"
printf '%s' "$goodArgs" > "$TMP/args.json"

# ---- Case 1: injected genreArg with shell metacharacters -> fail-closed throw ----
printf '%s' 'general; rm -rf /' > "$TMP/injected-arg-shell.txt"
printf '%s' "$GENRE_VALUE:$GENRE_VALUE" > "$TMP/injected-ref-ok.txt"
run_case c1 "$TMP/args.json" "$TMP/injected-arg-shell.txt" "$TMP/injected-ref-ok.txt" "$TMP/out1.json"
if [ -f "$TMP/out1.json" ]; then
  python3 - "$TMP/out1.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'research-harness-template#757' not in got:
    print(f"  FAIL c1: shell-metacharacter genreArg from the genre-resolve agent() did not trigger a fail-closed #757 throw (unvalidated LLM output reached the shell-command sink): threw={d['threw']}")
    ok = False
else:
    print("  ok  c1 (malicious genreArg): fail-closed throw fired before further use")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ---- Case 2: injected genreSkillRef naming an unrelated skill -> fail-closed throw ----
printf '%s' "$GENRE_VALUE" > "$TMP/injected-arg-ok.txt"
printf '%s' 'evil-genre:evil-genre' > "$TMP/injected-ref-evil.txt"
run_case c2 "$TMP/args.json" "$TMP/injected-arg-ok.txt" "$TMP/injected-ref-evil.txt" "$TMP/out2.json"
if [ -f "$TMP/out2.json" ]; then
  python3 - "$TMP/out2.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
if not got or 'research-harness-template#757' not in got:
    print(f"  FAIL c2: unrelated genreSkillRef from the genre-resolve agent() did not trigger a fail-closed #757 throw (unvalidated LLM output reached the Skill() reference sink): threw={d['threw']}")
    ok = False
else:
    print("  ok  c2 (malicious genreSkillRef): fail-closed throw fired before further use")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

# ---- Case 3: well-formed, expected genreArg/genreSkillRef -> no regression ----
printf '%s' "$GENRE_VALUE" > "$TMP/injected-arg-good.txt"
printf '%s' "$GENRE_VALUE:$GENRE_VALUE" > "$TMP/injected-ref-good.txt"
run_case c3 "$TMP/args.json" "$TMP/injected-arg-good.txt" "$TMP/injected-ref-good.txt" "$TMP/out3.json"
if [ -f "$TMP/out3.json" ]; then
  python3 - "$TMP/out3.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
got = d['threw'] and d['threw'].get('message', '')
ok = True
# The very next real work after validation is the Report-phase agent() call,
# which the stub above throws SENTINEL for. The module's own #727 guard
# wraps that throw in a re-thrown, differently-worded error (see research-
# projection.js's try/catch around the Report-phase agent() call) — so
# assert the SENTINEL propagated through that wrapper, not a #757
# validation throw (which never mentions the sentinel at all).
if not got or 'EVAL_SENTINEL_STOP' not in got or 'research-harness-template#757' in got:
    print(f"  FAIL c3: a well-formed, expected genreArg/genreSkillRef pair was rejected (false positive): threw={d['threw']}")
    ok = False
else:
    print("  ok  c3 (well-formed genreArg/genreSkillRef): resolution proceeds past validation with no regression")
sys.exit(0 if ok else 1)
PY
  [ $? -eq 0 ] || fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "projection-genre-resolution-injection-check: PASS (malformed/unexpected genreArg and genreSkillRef from the genre-resolve agent() fail closed; well-formed values pass through unaffected)"
  exit 0
else
  echo "projection-genre-resolution-injection-check: FAIL"
  exit 1
fi
