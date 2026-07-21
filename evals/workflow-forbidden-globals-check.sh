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
#   8. a forbidden call written INSIDE a template literal's `${...}`
#      expression (e.g. `` `stamp=${Date.now()}` ``) still fails — proving
#      the checker scans expression code rather than treating the whole
#      template literal as inert text (a real Copilot-review finding on
#      this PR: template literals are common in these modules, and a bare
#      "strip everything between backticks" tokenizer would silently miss
#      this);
#   9. a forbidden call separated from its own name by a `/* */` block
#      comment (`new/*x*/Date()`) still fails — proving comment/string
#      removal doesn't fuse adjacent tokens together into a non-match (a
#      second real Copilot-review finding: naive delimiter stripping can
#      turn `new/*x*/Date(` into `newDate(`, which never matches
#      `\bnew\s+Date\s*\(`).
#  10. a regex literal containing `\/*` (e.g. `/^a\/*b$/`) followed by a
#      real `Date.now()` call still fails at the right line — the #680
#      regression: a tokenizer with no regex-literal state misreads the
#      `/*` inside the literal as a block-comment opener and silently
#      strips the rest of the file, hiding the forbidden call;
#  11. forbidden-call TEXT inside a regex literal (`/Date.now()/`) never
#      false-positives — proving regex contents are stripped like string
#      contents, not scanned as code;
#  12. a division operator is not misread as a regex opener: real `/`
#      division on earlier lines must not swallow a later `Date.now()`
#      call or shift its reported line number.
#  13. division after a postfix `++` (`i++ / 2`) is not misread as a regex
#      opener — a `Date.now()` later on the SAME line must still fail (a
#      real Copilot-review finding on the #680 PR: `++`/`--` can end an
#      expression, so `/` after one is division);
#  14. the ASI counterpart of 13: `i++` followed by a NEWLINE then a regex
#      literal containing `\/*` is still a regex (ASI terminates the
#      restricted `++` production), so the literal's `/*` must not open a
#      phantom block comment that hides a later `Date.now()`.
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

# Case 8: a forbidden call inside a template literal's ${...} expression
# still fails, naming the correct line — proves expressions are scanned as
# real code, not stripped away as inert template text.
cat > "$TMP/tmpl-expr.js" <<'EOF'
export const meta = { name: 'tmpl-expr-eval-seed' }
const msg = `attempted_at=${Date.now()}`
return { ok: true, msg }
EOF
if bash "$CHECK" "$TMP/tmpl-expr.js" > "$TMP/tmpl-expr.out" 2>&1; then
  note "checker passed a module with Date.now() inside a template literal's \${...} expression"
  fail=1
else
  grep -q "tmpl-expr.js:2: forbidden call Date.now(" "$TMP/tmpl-expr.out" \
    || { note "template-expression Date.now() failure did not name the file at the correct line (2): $(cat "$TMP/tmpl-expr.out")"; fail=1; }
fi

# Case 9: a forbidden call with a block comment spliced between its two
# halves still fails — proves comment stripping doesn't fuse `new` and
# `Date(` into a non-matching `newDate(`.
cat > "$TMP/split-call.js" <<'EOF'
export const meta = { name: 'split-call-eval-seed' }
const stamp = new/*inline*/Date().toISOString()
return { ok: true, stamp }
EOF
if bash "$CHECK" "$TMP/split-call.js" > "$TMP/split-call.out" 2>&1; then
  note "checker passed a module with new/*comment*/Date() (delimiter-stripping token fusion)"
  fail=1
else
  grep -q "split-call.js:2: forbidden call new Date(" "$TMP/split-call.out" \
    || { note "comment-split new Date() failure did not name the file at the correct line (2): $(cat "$TMP/split-call.out")"; fail=1; }
fi

# Case 10 (#680): a regex literal whose source contains `\/*` must not be
# misread as a block-comment opener that swallows the rest of the file — a
# real Date.now() after it must still fail, at the right line.
cat > "$TMP/regex-escape.js" <<'EOF'
export const meta = { name: 'regex-escape-eval-seed' }
const re = /^a\/*b$/
const stamp = Date.now()
return { ok: true, stamp, re }
EOF
if bash "$CHECK" "$TMP/regex-escape.js" > "$TMP/regex-escape.out" 2>&1; then
  note "checker passed a module where a regex literal containing \\/* hid a Date.now() call (#680)"
  fail=1
else
  grep -q "regex-escape.js:3: forbidden call Date.now(" "$TMP/regex-escape.out" \
    || { note "regex-literal-hidden Date.now() failure did not name the file at the correct line (3): $(cat "$TMP/regex-escape.out")"; fail=1; }
fi

# Case 11 (#680): forbidden-call text appearing only inside a regex
# literal's source is not code — must PASS, proving regex contents are
# stripped rather than scanned.
cat > "$TMP/regex-text.js" <<'EOF'
export const meta = { name: 'regex-text-eval-seed' }
const dateRe = /Date.now()/
const randRe = /Math.random()/g
return { ok: true, dateRe, randRe }
EOF
if ! bash "$CHECK" "$TMP/regex-text.js" > "$TMP/regex-text.out" 2>&1; then
  note "checker false-positived on forbidden-call text inside a regex literal: $(cat "$TMP/regex-text.out")"
  fail=1
fi

# Case 12 (#680): division is not misread as a regex opener — a later real
# Date.now() call must still be caught at its own line, not swallowed or
# shifted by the `/` operators before it.
cat > "$TMP/division.js" <<'EOF'
export const meta = { name: 'division-eval-seed' }
const half = total / 2
const ratio = a / b / c
const stamp = Date.now()
return { ok: true, half, ratio, stamp }
EOF
if bash "$CHECK" "$TMP/division.js" > "$TMP/division.out" 2>&1; then
  note "checker passed a module where division operators preceded a Date.now() call"
  fail=1
else
  grep -q "division.js:4: forbidden call Date.now(" "$TMP/division.out" \
    || { note "post-division Date.now() failure did not name the file at the correct line (4): $(cat "$TMP/division.out")"; fail=1; }
fi

# Case 13: division right after a postfix increment (`i++ / 2`) — the `/`
# must be read as division, not a regex opener that strips the rest of the
# line and hides the Date.now() after the `;`.
cat > "$TMP/postfix-division.js" <<'EOF'
export const meta = { name: 'postfix-division-eval-seed' }
let i = 0
const half = i++ / 2; const stamp = Date.now()
return { ok: true, half, stamp }
EOF
if bash "$CHECK" "$TMP/postfix-division.js" > "$TMP/postfix-division.out" 2>&1; then
  note "checker passed a module where division after a postfix ++ hid a same-line Date.now() call"
  fail=1
else
  grep -q "postfix-division.js:3: forbidden call Date.now(" "$TMP/postfix-division.out" \
    || { note "postfix-division Date.now() failure did not name the file at the correct line (3): $(cat "$TMP/postfix-division.out")"; fail=1; }
fi

# Case 14: the ASI counterpart — after `i++` and a NEWLINE, a `/` starts a
# regex literal (ASI ends the restricted `++` production), so a `\/*` inside
# it must not open a phantom block comment that swallows the later Date.now().
cat > "$TMP/postfix-asi.js" <<'EOF'
export const meta = { name: 'postfix-asi-eval-seed' }
let i = 0
const n = i++
const matched = /a\/*b/.test('a//b')
const stamp = Date.now()
return { ok: true, n, matched, stamp }
EOF
if bash "$CHECK" "$TMP/postfix-asi.js" > "$TMP/postfix-asi.out" 2>&1; then
  note "checker passed a module where a regex after i++ and a newline hid a Date.now() call (ASI case)"
  fail=1
else
  grep -q "postfix-asi.js:5: forbidden call Date.now(" "$TMP/postfix-asi.out" \
    || { note "postfix-ASI Date.now() failure did not name the file at the correct line (5): $(cat "$TMP/postfix-asi.out")"; fail=1; }
fi

[ "$fail" -eq 0 ] && note "the forbidden-globals gate is real: the shipped tree is clean, seeded new Date()/Date.now()/Math.random() calls are all caught by name and line (including inside a template literal's \${...} expression, even when comment-stripping would otherwise fuse tokens together, and even when a regex literal containing \\/* would otherwise be misread as a block comment, #680), the same strings inside comments/a template literal's static text/a regex literal never false-positive, division is never misread as a regex opener, and the verify surface covers it"
exit "$fail"
