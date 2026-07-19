#!/usr/bin/env bash
# workflow-research-structure.sh — structural eval for .claude/workflows/research.js
# (ADR-0020), complementing workflow-research-parses.sh. No live agent spawning --
# purely static checks, fast and free to run in CI:
#
#   1. Every `const *_SCHEMA = {...}` constant is itself a structurally valid
#      JSON Schema (ajv can compile it).
#   2. Every `scripts/<name>.sh` path referenced anywhere in the file
#      actually exists under scripts/ (a renamed/removed script silently
#      breaking a prompt template is otherwise invisible until a live run).
#   3. Every agent() prompt that mentions one of the engine-delegating
#      scripts (exit 5 = engine missing/stale, per scripts/lib/engine.sh)
#      also interpolates ENGINE_FAILURE_CLAUSE, so exit-5 handling can't
#      silently regress in one phase while present in the others. This is a
#      best-effort heuristic (regex-delimited prompt-block extraction, not a
#      real JS parse) -- see the node -e block below for exactly what it matches.
#   4. Augment-mode branch structure (issue #20; seeds the mode-coverage
#      convention issue #22 wires up more fully): the `args.mode === 'augment'`
#      branch actually exists, both dimension-analyst prompt sites (the main
#      pass and the shortfall retry) reference AUGMENT_CLAUSE, and the
#      round-loop's thin-dimension fallback is scoped through MODE_DIMENSIONS
#      rather than the unconditional ALL_DIMENSIONS (the exact regression this
#      story's "only that dimension is re-researched" acceptance criterion
#      guards against).
#
# Exit 0 = all four hold. Exit 1 = any fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SCRIPT="$ROOT/.claude/workflows/research.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  workflow-research-structure: %s\n' "$1"; }

if [ ! -f "$SCRIPT" ]; then
  note "$SCRIPT does not exist"
  exit 1
fi
for tool in node ajv jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    note "'$tool' is required on PATH and was not found"
    exit 1
  fi
done

# --- 1. every *_SCHEMA constant is a compilable JSON Schema -----------------
node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  const re = /const (\w+_SCHEMA) = (\{[\s\S]*?\n\})\n\n/g;
  let m, out = {};
  while ((m = re.exec(src))) {
    try { out[m[1]] = eval('(' + m[2] + ')'); }
    catch (e) { console.error('FAILED_TO_EVAL:' + m[1] + ':' + e.message); process.exit(1); }
  }
  if (Object.keys(out).length === 0) { console.error('FAILED_TO_EVAL:none:no *_SCHEMA constants found'); process.exit(1); }
  fs.writeFileSync(process.argv[2], JSON.stringify(out, null, 2));
" "$SCRIPT" "$TMP/schemas.json" 2>"$TMP/eval.log"
if [ $? -ne 0 ]; then
  note "could not extract *_SCHEMA constants:"
  sed 's/^/    /' "$TMP/eval.log"
  fail=1
else
  for name in $(jq -r 'keys[]' "$TMP/schemas.json"); do
    jq ".\"$name\"" "$TMP/schemas.json" > "$TMP/$name.json"
    if ! ajv compile --spec=draft2020 -s "$TMP/$name.json" >"$TMP/$name.compile.log" 2>&1; then
      note "$name is not a valid JSON Schema:"
      sed 's/^/    /' "$TMP/$name.compile.log"
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] && note "$(jq -r 'keys | length' "$TMP/schemas.json") schema constant(s) all compile"
fi

# --- 2. every scripts/*.sh reference resolves to a real file ---------------
missing_scripts=""
for name in $(grep -oE 'scripts/[A-Za-z0-9_.-]+\.sh' "$SCRIPT" | sort -u); do
  [ -f "$ROOT/$name" ] || missing_scripts="$missing_scripts $name"
done
if [ -n "$missing_scripts" ]; then
  note "referenced script(s) do not exist:$missing_scripts"
  fail=1
else
  note "every referenced scripts/*.sh path exists"
fi

# --- 3. ENGINE_FAILURE_CLAUSE present alongside every engine-delegating script ---
node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  const ENGINE_SCRIPTS = [
    'falsify.sh', 'ontology-review.sh', 'check-shippable-typing.sh',
    'reconcile-session.sh', 'synthesize-artifact.sh', 'render-artifact.sh',
    'resolve-membership.sh', 'build-index.sh', 'build-graph.sh',
    'assert-graph-mif.sh', 'build-concordance.sh', 'validate-concordance.sh',
  ];
  // Best-effort prompt-block extraction: each agent() call's first argument
  // is a backtick template ending in a backtick immediately followed by a
  // comma, newline, and the options object's opening brace -- the pattern
  // every call site in this file follows.
  const blockRe = /agent\(\s*\n?\s*\x60([\s\S]*?)\x60,\s*\n\s*\{/g;
  let m, gaps = [];
  while ((m = blockRe.exec(src))) {
    const block = m[1];
    const mentioned = ENGINE_SCRIPTS.filter((s) => block.includes(s));
    if (mentioned.length && !block.includes('ENGINE_FAILURE_CLAUSE')) {
      gaps.push(mentioned.join(',') + ' at offset ' + m.index);
    }
  }
  if (gaps.length) { console.error(gaps.join('\n')); process.exit(1); }
" "$SCRIPT" 2>"$TMP/gaps.log"
if [ $? -ne 0 ]; then
  note "prompt block(s) mention an engine-delegating script without ENGINE_FAILURE_CLAUSE:"
  sed 's/^/    /' "$TMP/gaps.log"
  fail=1
else
  note "every engine-delegating-script prompt also carries ENGINE_FAILURE_CLAUSE"
fi

# --- 4. augment-mode branch structure (issue #20) ---------------------------
augment_gaps=""
grep -qE "MODE === 'augment'" "$SCRIPT" || augment_gaps="$augment_gaps no_mode_augment_branch"
grep -q "const AUGMENT_CLAUSE" "$SCRIPT" || augment_gaps="$augment_gaps no_augment_clause_constant"
[ "$(grep -c "AUGMENT_CLAUSE" "$SCRIPT")" -ge 3 ] || augment_gaps="$augment_gaps augment_clause_not_referenced_at_both_dimension_analyst_call_sites"
grep -q "const MODE_DIMENSIONS" "$SCRIPT" || augment_gaps="$augment_gaps no_mode_dimensions_constant"
grep -q "MODE_DIMENSIONS.slice()" "$SCRIPT" || augment_gaps="$augment_gaps mode_dimensions_not_used_as_initial_workdims"
grep -qE 'workDims = reportedThin\.length \? reportedThin : MODE_DIMENSIONS\.slice\(\)' "$SCRIPT" || augment_gaps="$augment_gaps thin_dimension_fallback_not_scoped_to_mode_dimensions"
if [ -n "$augment_gaps" ]; then
  note "augment-mode branch structure incomplete:$augment_gaps"
  fail=1
else
  note "augment-mode branches (mode guard, AUGMENT_CLAUSE at both call sites, MODE_DIMENSIONS-scoped fan-out/fallback) all present"
fi

exit "$fail"
