#!/usr/bin/env bash
# voice-gate-line-numbers.sh — regression test for .claude/hooks/check-voice.sh's
# reported line numbers (issue #688): `strip_links` used to DELETE exempt lines
# (link references, URL lines, structured citation fields) before the scanners
# ran `grep -n`, so every reported line number after the first exempt line was a
# position in the filtered stream, not in the real file — sending the author to
# fix the wrong line. The fix blanks exempt lines instead of deleting them, so
# line numbering is preserved.
#
# This invokes the REAL hook (like evals/md-guard-fix-lock.sh) in `post` mode
# with synthetic PostToolUse JSON on stdin and asserts:
#   1. a mechanical (em dash) violation BELOW exempt lines is reported at its
#      real file line number;
#   2. a buzzword warning below exempt lines is reported at its real line number;
#   3. the exempt lines themselves (whose verbatim titles carry em dashes) are
#      still not flagged;
#   4. a file whose only violations sit on exempt lines stays clean (no output).
#
# Exit 0 = the contract holds. Exit 1 = a case failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/check-voice.sh"
fail=0
note() { printf '  voice-gate-line-numbers: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_hook <file_path> — feeds PostToolUse JSON to the real hook in post mode;
# prints the hook's stdout.
run_hook() {
  jq -cn --arg fp "$1" '{tool_input:{file_path:$fp}}' \
    | CLAUDE_PROJECT_DIR="$TMP" bash "$HOOK" post
}

# --- Fixture: exempt lines interleaved ABOVE the real violations. Line map:
#   1  clean heading
#   2  blank
#   3  markdown link reference (exempt; verbatim title carries an em dash)
#   4  bare-URL line (exempt)
#   5  prose with an em dash        -> mechanical violation, must report 5
#   6  clean prose
#   7  prose with a buzzword        -> buzzword warning, must report 7
mkdir -p "$TMP/reports/demo"
F="$TMP/reports/demo/demo.md"
cat > "$F" <<'EOF'
# Demo report

[ref]: https://example.com/paper "A Cited Title — verbatim, exempt"
Source list: https://example.com/other
This prose line carries a real em dash — the gate must point here.
A clean line of prose.
Here the author chose to delve into filler.
EOF

OUT=$(run_hook "$F")
CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)

# Case 1: the em-dash violation is reported at its REAL line number (5).
if printf '%s\n' "$CTX" | grep -q 'char: 5:'; then
  note "PASS: mechanical violation reported at real file line 5"
else
  note "FAIL: expected 'char: 5:' in additionalContext, got: $(printf '%s' "$CTX" | grep 'char:' || echo '<none>')"
  fail=1
fi

# Case 2: the buzzword warning is reported at its REAL line number (7).
if printf '%s\n' "$CTX" | grep -q 'buzzword: 7:'; then
  note "PASS: buzzword warning reported at real file line 7"
else
  note "FAIL: expected 'buzzword: 7:' in additionalContext, got: $(printf '%s' "$CTX" | grep 'buzzword:' || echo '<none>')"
  fail=1
fi

# Case 3: the exempt link-reference line (3) is still exempt, and exactly one
# mechanical hit is reported (the filtered-stream bug reported it as 'char: 3:').
MECH_COUNT=$(printf '%s\n' "$CTX" | grep -c 'char: ' || true)
if [ "$MECH_COUNT" = "1" ] && ! printf '%s\n' "$CTX" | grep -q 'char: 3:'; then
  note "PASS: exempt citation line not flagged; exactly one mechanical hit"
else
  note "FAIL: expected exactly 1 mechanical hit and none at line 3, got $MECH_COUNT hit(s): $(printf '%s' "$CTX" | grep 'char:' || echo '<none>')"
  fail=1
fi

# Case 4: a file whose only em dashes sit on exempt lines stays clean.
mkdir -p "$TMP/reports/clean"
C="$TMP/reports/clean/clean.md"
cat > "$C" <<'EOF'
# Clean report

[a]: https://example.com/x "Title — dash in verbatim citation"
"title": "Another — dashed title"
All prose here is plainly voiced.
EOF
CLEAN_OUT=$(run_hook "$C")
if [ -z "$CLEAN_OUT" ]; then
  note "PASS: exempt-only violations produce no gate output"
else
  note "FAIL: expected no output for exempt-only file, got: $CLEAN_OUT"
  fail=1
fi

exit "$fail"
