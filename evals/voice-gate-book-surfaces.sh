#!/usr/bin/env bash
# voice-gate-book-surfaces.sh — regression test for .claude/hooks/check-voice.sh's
# is_authored_surface() classification of book-channel prose (issue #672): the
# generic `reports/*/*.md` clause used to sit ABOVE the dedicated
# `reports/*/book/{chapters,appendices,front-matter}/*.md` clause. Bash `case`
# patterns match top-down and `*` crosses `/` (fnmatch, not pathname expansion),
# so a path like reports/<slug>/book/chapters/ch1.md resolved at the generic
# clause, failed its basename==dirname canonical-report check, and was classified
# NOT an authored surface — making the book clause dead code and book prose
# invisible to both the post tier and the stop tier of the gate. The fix orders
# the book clause before the generic one.
#
# This invokes the REAL hook (like evals/voice-gate-line-numbers.sh) and asserts:
#   1. post mode flags an em dash in a book chapter file;
#   2. post mode flags book appendices and front-matter files too;
#   3. post mode still flags the canonical report (generic clause intact);
#   4. post mode still ignores a non-canonical, non-book reports file;
#   5. stop mode blocks (decision:block) on a dirty book chapter carrying a
#      mechanical violation.
#
# Exit 0 = the contract holds. Exit 1 = a case failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/check-voice.sh"
fail=0
note() { printf '  voice-gate-book-surfaces: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_post <file_path> — feeds PostToolUse JSON to the real hook in post mode;
# prints the hook's stdout.
run_post() {
  jq -cn --arg fp "$1" '{tool_input:{file_path:$fp}}' \
    | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" post
}

# has_mech <hook_output> — true when the output carries a mechanical hit.
has_mech() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null \
    | grep -q 'char: '
}

DIRTY_LINE='This prose line carries a real em dash — the gate must flag it.'

# --- Cases 1-2: book-channel surfaces are authored prose and get flagged.
for sub in chapters appendices front-matter; do
  mkdir -p "$TMP/reports/demo/book/$sub"
  BF="$TMP/reports/demo/book/$sub/sample.md"
  printf '# Book %s\n\n%s\n' "$sub" "$DIRTY_LINE" > "$BF"
  OUT=$(run_post "$BF")
  if has_mech "$OUT"; then
    note "PASS: book $sub file flagged as authored surface"
  else
    note "FAIL: book $sub file NOT flagged (is_authored_surface shadowed?); output: ${OUT:-<none>}"
    fail=1
  fi
done

# --- Case 3: the canonical report path still resolves through the generic clause.
mkdir -p "$TMP/reports/demo"
CANON="$TMP/reports/demo/demo.md"
printf '# Canonical report\n\n%s\n' "$DIRTY_LINE" > "$CANON"
OUT=$(run_post "$CANON")
if has_mech "$OUT"; then
  note "PASS: canonical report still flagged"
else
  note "FAIL: canonical report no longer flagged; output: ${OUT:-<none>}"
  fail=1
fi

# --- Case 4: a non-canonical, non-book reports file is still NOT authored prose.
SCRATCH="$TMP/reports/demo/notes.md"
printf '# Scratch notes\n\n%s\n' "$DIRTY_LINE" > "$SCRATCH"
OUT=$(run_post "$SCRATCH")
if [ -z "$OUT" ]; then
  note "PASS: non-canonical reports file still ignored"
else
  note "FAIL: expected no output for reports/demo/notes.md, got: $OUT"
  fail=1
fi

# --- Case 5: stop mode blocks on a dirty book chapter with a mechanical hit.
GITTMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$GITTMP"' EXIT
git -C "$GITTMP" init -q
mkdir -p "$GITTMP/reports/demo/book/chapters"
printf '# Chapter one\n\n%s\n' "$DIRTY_LINE" > "$GITTMP/reports/demo/book/chapters/ch1.md"
STOP_OUT=$(printf '{}' | CLAUDE_PROJECT_DIR="$GITTMP" bash "$HOOK" stop)
DECISION=$(printf '%s' "$STOP_OUT" | jq -r '.decision // empty' 2>/dev/null)
if [ "$DECISION" = "block" ] \
  && printf '%s' "$STOP_OUT" | jq -r '.reason' 2>/dev/null | grep -q 'reports/demo/book/chapters/ch1.md'; then
  note "PASS: stop mode blocks on dirty book chapter with mechanical violation"
else
  note "FAIL: expected decision:block naming the book chapter, got: ${STOP_OUT:-<none>}"
  fail=1
fi

exit "$fail"
