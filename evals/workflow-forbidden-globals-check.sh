#!/usr/bin/env bash
# workflow-forbidden-globals-check.sh — regression eval for the
# forbidden-Workflow-runtime-globals static gate (research-harness-template#618).
#
# research-falsify.js's buildFixtureEntry() called new Date() from inside its
# own body — the Workflow runtime disallows this (deterministic resume), and
# it crashed EVERY finding needing gating, every real /research full-mode run,
# with the falsification gate silently never completing (findings stuck at
# 'inconclusive'). No prior eval executed research-falsify.js's Gate phase for
# real (every driver stubs the Enumerate agent to return an empty
# workingSet), so nothing caught this until a live run hit it. This eval
# covers scripts/check-workflow-forbidden-globals.sh, the static gate added
# to close that hole:
#
#   1. the shipped tree is clean (0 hits) — proves the actual fix, not just
#      the checker's own logic;
#   2. a seeded `new Date()` call fails the checker and the failure names the
#      seeded file and the correct line number;
#   3. a seeded `Date.now()` call fails the checker;
#   4. a seeded `Math.random()` call fails the checker;
#   5. seeding the SAME three forbidden strings inside a `//` comment, a
#      `/* */` block comment, and a template literal all PASS — proving the
#      checker is comment/string-aware, not a bare textual grep (a bare grep
#      would false-positive on this very module's own explanatory comments
#      and on research-falsify.js's #618 header, both of which say
#      "new Date()" in prose);
#   6. a minimal valid module (no forbidden calls) passes;
#   7. the verify.sh surface covers it: a scoped run of gate_workflows exits 0
#      on the shipped tree and its output names the #618 gate explicitly.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  workflow-forbidden-globals-check: %s\n' "$1"; }

CHECK=scripts/check-workflow-forbidden-globals.sh

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
[ -x "$CHECK" ] || [ -f "$CHECK" ] || { note "$CHECK not found"; exit 2; }

# Case 1: the shipped tree is clean.
if ! bash "$CHECK" > "$TMP/ok.out" 2>&1; then
  note "checker rejected the shipped .claude/workflows/*.js tree: $(tail -5 "$TMP/ok.out")"
  fail=1
fi

# Case 2: a seeded new Date() call fails, naming the file and the right line.
cat > "$TMP/new-date.js" <<'EOF'
export const meta = { name: 'new-date-eval-seed' }
function buildEntry(id) {
  return { [id]: { attempted_at: new Date().toISOString() } }
}
return { ok: true }
EOF
if bash "$CHECK" "$TMP/new-date.js" > "$TMP/new-date.out" 2>&1; then
  note "checker passed a module with a seeded new Date() call"
  fail=1
else
  grep -q "new-date.js:3: forbidden call new Date(" "$TMP/new-date.out" \
    || { note "new Date() failure did not name the file at the correct line (3): $(cat "$TMP/new-date.out")"; fail=1; }
fi

# Case 3: a seeded Date.now() call fails.
cat > "$TMP/date-now.js" <<'EOF'
export const meta = { name: 'date-now-eval-seed' }
const stamp = Date.now()
return { ok: true, stamp }
EOF
if bash "$CHECK" "$TMP/date-now.js" > "$TMP/date-now.out" 2>&1; then
  note "checker passed a module with a seeded Date.now() call"
  fail=1
else
  grep -q "date-now.js:2: forbidden call Date.now(" "$TMP/date-now.out" \
    || { note "Date.now() failure did not name the file at the correct line (2): $(cat "$TMP/date-now.out")"; fail=1; }
fi

# Case 4: a seeded Math.random() call fails.
cat > "$TMP/math-random.js" <<'EOF'
export const meta = { name: 'math-random-eval-seed' }
const jitter = Math.random()
return { ok: true, jitter }
EOF
if bash "$CHECK" "$TMP/math-random.js" > "$TMP/math-random.out" 2>&1; then
  note "checker passed a module with a seeded Math.random() call"
  fail=1
else
  grep -q "math-random.js:2: forbidden call Math.random(" "$TMP/math-random.out" \
    || { note "Math.random() failure did not name the file at the correct line (2): $(cat "$TMP/math-random.out")"; fail=1; }
fi

# Case 5: the same three forbidden strings, but ONLY inside a // comment, a
# /* */ block comment, and a template literal — must all PASS. A bare
# textual grep would false-positive here; this proves the checker doesn't.
cat > "$TMP/comments-only.js" <<'EOF'
export const meta = { name: 'comments-only-eval-seed' }
// prose mentioning new Date() and Date.now() and Math.random() — not a call
/* a block comment that also says new Date(), Date.now(), Math.random() */
const msg = `a template literal that says new Date() and Date.now() and Math.random() as plain text`
return { ok: true, msg }
EOF
if ! bash "$CHECK" "$TMP/comments-only.js" > "$TMP/comments-only.out" 2>&1; then
  note "checker false-positived on forbidden strings that appear only in comments/a template literal: $(cat "$TMP/comments-only.out")"
  fail=1
fi

# Case 6: a minimal valid module (no forbidden calls) passes.
cat > "$TMP/valid.js" <<'EOF'
export const meta = { name: 'valid-eval-seed' }
const stamp = (args && args.runDate) || null
return { ok: true, stamp }
EOF
if ! bash "$CHECK" "$TMP/valid.js" > "$TMP/valid.out" 2>&1; then
  note "checker rejected a minimal valid module with no forbidden calls: $(cat "$TMP/valid.out")"
  fail=1
fi

# Case 7: the gate itself is green on the shipped tree via the verify
# surface, and names the #618 gate.
if ! out="$(bash scripts/verify.sh --gates 'gate_workflows$' 2>&1)"; then
  note "scoped verify.sh run of gate_workflows failed: $(printf '%s' "$out" | tail -5)"
  fail=1
else
  grep -q '#618' <<<"$out" \
    || { note "gate_workflows output no longer names #618 for the forbidden-globals check"; fail=1; }
fi

[ "$fail" -eq 0 ] && note "the forbidden-globals gate is real: the shipped tree is clean, seeded new Date()/Date.now()/Math.random() calls are all caught by name and line, the same strings inside comments/a template literal never false-positive, and the verify surface covers it"
exit "$fail"
