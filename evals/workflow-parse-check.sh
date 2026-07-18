#!/usr/bin/env bash
# workflow-parse-check.sh — regression eval for the workflow-module
# parse-check (research-harness-template#552, Epic #539).
#
# Workflow-runtime modules (.claude/workflows/*.js) are evaluated by the
# runtime as the BODY of an async function, so top-level `return`/`await`
# are legal in the file and a bare `node --check` rejects a valid module.
# scripts/check-workflow-syntax.sh wraps before checking; verify.sh's
# gate_workflows puts it on the required CI surface.
#
# Covers:
#   1. the vendored .claude/workflows/research-goal.js passes the checker;
#   2. bare `node --check` REJECTS the same file — proves the module really
#      carries the runtime's async-body shape and the wrap is load-bearing,
#      not decorative;
#   3. a seeded syntax error fails the checker, and the failure names the
#      offending file;
#   4. a seeded valid async-body module (export + top-level return) passes,
#      so the checker accepts the shape itself, not just this one file;
#   5. the verify.sh surface covers it: a scoped run of gate_workflows
#      exits 0 on the shipped tree;
#   6. a module with an extra `export` beyond `export const meta` FAILS —
#      the runtime only rewrites the meta export, so any other export is a
#      real runtime failure the checker must not mask by stripping it.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  workflow-parse-check: %s\n' "$1"; }

WF=.claude/workflows/research-goal.js

# Case 1: the vendored module passes the async-body checker.
if ! bash scripts/check-workflow-syntax.sh "$WF" > "$TMP/ok.out" 2>&1; then
  note "checker rejected the vendored module: $(tail -2 "$TMP/ok.out")"
  fail=1
fi

# Case 2: bare `node --check` rejects the same file (async-body shape is real).
if node --check "$WF" >/dev/null 2>&1; then
  note "bare node --check unexpectedly accepts $WF — the module no longer carries the runtime's async-body shape (top-level return); if that is deliberate, update this eval and #552's rationale"
  fail=1
fi

# Case 3: a seeded syntax error fails the checker and the error names the file.
cat > "$TMP/broken.js" <<'EOF'
export const meta = { name: 'broken-eval-seed' }
const x = (   // deliberately unbalanced
return { ok: true }
EOF
if bash scripts/check-workflow-syntax.sh "$TMP/broken.js" > "$TMP/broken.out" 2>&1; then
  note "checker passed a module with a seeded syntax error"
  fail=1
fi
grep -q "broken.js" "$TMP/broken.out" || { note "syntax failure does not name the offending file"; fail=1; }

# Case 4: a minimal valid async-body module (export + top-level return) passes.
cat > "$TMP/valid.js" <<'EOF'
export const meta = { name: 'valid-eval-seed' }
const who = (args && args.who) || 'world'
log(`hello ${who}`)
return { ok: true, who }
EOF
if ! bash scripts/check-workflow-syntax.sh "$TMP/valid.js" > "$TMP/valid.out" 2>&1; then
  note "checker rejected a minimal valid async-body module: $(tail -2 "$TMP/valid.out")"
  fail=1
fi

# Case 6: an extra export (beyond `export const meta`) fails loudly — the
# runtime does not rewrite it, so the checker must not strip it either.
cat > "$TMP/extra-export.js" <<'EOF'
export const meta = { name: 'extra-export-eval-seed' }
export function helper() {}
return { ok: true }
EOF
if bash scripts/check-workflow-syntax.sh "$TMP/extra-export.js" > "$TMP/extra.out" 2>&1; then
  note "checker passed a module with an export the runtime does not rewrite (only 'export const meta' is legal)"
  fail=1
fi

# Case 5: the gate itself is green on the shipped tree via the verify surface.
if ! bash scripts/verify.sh --gates 'gate_workflows$' > "$TMP/gate.out" 2>&1; then
  note "scoped verify.sh run of gate_workflows failed: $(tail -3 "$TMP/gate.out")"
  fail=1
fi

[ "$fail" -eq 0 ] && note "async-body parse-check is load-bearing: wrap accepts the runtime shape, bare --check proves the shape, seeded errors fail loudly inside the verify surface"
exit "$fail"
