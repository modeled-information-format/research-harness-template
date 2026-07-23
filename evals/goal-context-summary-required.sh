#!/usr/bin/env bash
# goal-context-summary-required.sh — regression eval for
# research-harness-template#766: research-goal.js's CONTEXT_SCHEMA marked
# `existingGoalSummary` as optional (typed `['string', 'null']` but absent
# from `required`) even though the Draft-phase prompt unconditionally
# interpolates `ctx.existingGoalSummary` whenever `ctx.existingGoalPath` is
# truthy. A schema-valid Context result that omitted the field (legal
# before this fix) made the Draft agent's prompt read the literal text
# "An existing goal exists (undefined); you are re-authoring it." instead
# of a real 2-sentence summary — degrading the re-authoring guidance the
# ADR-0006 update flow depends on.
#
# Two independent cases, both statically provable with no LLM/agent calls:
#
#   1. CONTEXT_SCHEMA's `required` array names `existingGoalSummary` — the
#      schema-level half of the fix (an omitting agent now fails schema
#      validation instead of silently producing a valid-but-incomplete
#      result).
#   2. Driving the REAL, unmodified research-goal.js module (the same
#      Workflow-runtime async-function-body framing technique
#      atomic-workflows-args-parse-check.sh already established) with a
#      stubbed Context result that has existingGoalPath truthy and
#      existingGoalSummary OMITTED proves the Draft prompt never contains
#      the literal "(undefined)" leak — the runtime-level half of the fix
#      (defense in depth: holds even if a future schema regression lets an
#      incomplete Context result through again).
#
# Exit 0 = both cases hold. Exit 1 = a case failed. Exit 2 = a required
# tool is missing, or the module is not where this eval expects it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

MODULE=".claude/workflows/research-goal.js"
fail=0
note() { printf '  goal-context-summary-required: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -f "$MODULE" ] || { note "$MODULE not found"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Case 1: CONTEXT_SCHEMA's required array names existingGoalSummary.
# ---------------------------------------------------------------------------
# Extract the `required: [...]` line immediately following the
# CONTEXT_SCHEMA object's closing brace (the module also declares
# DRAFT_SCHEMA/LINT_SCHEMA required arrays further down — anchor on the
# CONTEXT_SCHEMA block specifically so a future addition to those other
# schemas can't produce a false pass here).
CONTEXT_BLOCK="$(awk '/^const CONTEXT_SCHEMA = \{/{flag=1} flag{print} flag && /^\}/{exit}' "$MODULE")"
if [ -z "$CONTEXT_BLOCK" ]; then
  note "could not locate CONTEXT_SCHEMA block in $MODULE — module shape changed"
  fail=1
elif ! printf '%s' "$CONTEXT_BLOCK" | grep -E "^\s*required:\s*\[" | grep -q "'existingGoalSummary'"; then
  note "CONTEXT_SCHEMA's required array does not name existingGoalSummary"
  fail=1
fi

# ---------------------------------------------------------------------------
# Case 2: behavioral — drive the real module, Context omits
# existingGoalSummary with existingGoalPath truthy, assert the Draft prompt
# never carries the literal "(undefined)" leak.
# ---------------------------------------------------------------------------
cat > "$TMP/driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const [, , wfPath, argsPath, outPath] = process.argv;
const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'workflow', 'parallel', 'pipeline', 'budget', src);

const args = JSON.parse(fs.readFileSync(argsPath, 'utf8'));
const SENTINEL = 'EVAL_SENTINEL_STOP';
const calls = [];

async function agentStub(prompt, opts) {
  const p = String(prompt);
  calls.push({ prompt: p, opts: opts || null });
  if (opts && opts.label === 'goal:context') {
    // Deliberately OMITS existingGoalSummary — the pre-#766-fix-legal,
    // schema-valid-but-incomplete Context result that produced the
    // "(undefined)" leak in the Draft prompt.
    return {
      topicRegistered: true,
      configDimensions: ['scope'],
      existingGoalPath: 'reports/766-eval-topic/goal.json',
      notes: 'eval stub',
    };
  }
  // First call after Context (Draft) — capture its prompt, then stop.
  throw new Error(SENTINEL);
}
function phaseStub() {}
function logStub() {}

(async () => {
  let threw = null;
  try {
    await fn(args, phaseStub, agentStub, logStub, () => { throw new Error(SENTINEL); }, () => { throw new Error(SENTINEL); }, () => { throw new Error(SENTINEL); }, { total: 0, remaining: () => 0 });
  } catch (e) {
    threw = { message: e.message };
  }
  const draftCall = calls.find((c) => c.opts && c.opts.label === 'goal:draft') || null;
  fs.writeFileSync(outPath, JSON.stringify({ threw, draftCall }, null, 2));
})();
NODE

TOPIC_VALUE="766-eval-topic"
printf '{"harnessDir":".","topic":"%s"}' "$TOPIC_VALUE" > "$TMP/args.json"

if ! node "$TMP/driver.cjs" "$MODULE" "$TMP/args.json" "$TMP/out.json" > "$TMP/run.err" 2>&1; then
  note "driver invocation itself failed (not a caught throw): $(cat "$TMP/run.err")"
  fail=1
elif [ ! -f "$TMP/out.json" ]; then
  note "driver produced no output"
  fail=1
else
  python3 - "$TMP/out.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
draft = d.get('draftCall')
if not draft:
    print('  goal-context-summary-required: Draft-phase agent() call was never reached')
    sys.exit(1)
prompt = draft.get('prompt', '')
if '(undefined)' in prompt:
    print('  goal-context-summary-required: Draft prompt leaks the literal "(undefined)" for a missing existingGoalSummary')
    sys.exit(1)
if 'summary unavailable' not in prompt:
    print('  goal-context-summary-required: Draft prompt does not carry the safe fallback text for a missing existingGoalSummary')
    sys.exit(1)
sys.exit(0)
PY
  case $? in
    0) ;;
    *) fail=1 ;;
  esac
fi

exit "$fail"
