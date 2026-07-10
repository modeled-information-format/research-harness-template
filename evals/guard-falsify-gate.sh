#!/usr/bin/env bash
# guard-falsify-gate.sh — contract test for .claude/hooks/guard-falsify-gate.sh
# (issue #356): its path-extraction regex used a greedy [^[:space:]]* prefix
# that did not stop at '=', so a command shaped like
#   F=reports/t/findings/f.json; bash scripts/falsify.sh "$F"
# had the extracted "finding" corrupted to "F=reports/t/findings/f.json",
# computing the wrong TOPIC_DIR and denying a legitimate call even though the
# topic's gate window was genuinely open.
#
# This invokes the REAL hook script (not a reimplementation — unlike
# dimension-analyst.md's prose algorithm, this is a directly executable Bash
# script) with synthetic PreToolUse JSON on stdin, and asserts:
#   - the var-assignment shape is ALLOWED when the gate window is open (the
#     exact bug this issue reports);
#   - the var-assignment shape is still correctly DENIED when the window is
#     closed (the fix must not defeat the guard itself);
#   - a normal literal-argument call is unaffected (no regression);
#   - a non-gate command (falsify.sh on a path outside reports/*/findings/)
#     is always allowed, regardless of any window;
#   - an absolute finding path still resolves its window correctly (the
#     positive path-character-class fix, rather than deleting the prefix
#     outright, preserves the case statement's absolute-path branch).
#
# Exit 0 = the guard's contract holds. Exit 1 = a case failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/guard-falsify-gate.sh"
fail=0
note() { printf '  guard-falsify-gate: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_hook <command-string> <CLAUDE_PROJECT_DIR>
# Prints the hook's stdout; caller inspects it for a deny payload.
run_hook() {
  local cmd="$1" project_dir="$2"
  jq -cn --arg cmd "$cmd" '{tool_input:{command:$cmd}}' \
    | CLAUDE_PROJECT_DIR="$project_dir" bash "$HOOK"
}

is_denied() {
  # $1 = hook stdout
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

# --- Case 1: var-assignment shape, gate window OPEN -> must ALLOW ---------
# This is the exact bug: the corrupted TOPIC_DIR ("F=reports/mytopic") never
# matches the real marker at "reports/mytopic/.gate-active", so the old regex
# denies a call it should allow.
PROJECT1="$TMP/proj1"
mkdir -p "$PROJECT1/reports/mytopic/findings"
touch "$PROJECT1/reports/mytopic/.gate-active"
OUT1=$(run_hook 'F=reports/mytopic/findings/foo.json; bash scripts/falsify.sh "$F"' "$PROJECT1")
if is_denied "$OUT1"; then
  note "FAIL: var-assignment shape denied even though the gate window is open (issue #356)"; fail=1
else
  note "var-assignment shape is allowed when the gate window is open"
fi

# --- Case 1b/1c: QUOTED var-assignment shapes, gate window OPEN -> ALLOW ---
# An earlier fix attempt excluded only '=' from the prefix (a negative
# character class), which closed the unquoted case above but left the
# quoted forms broken the identical way: the leading quote character gets
# swallowed into the "extracted" path, corrupting TOPIC_DIR the same way
# the bare "F=" prefix did. Quoted assignment is, if anything, the more
# idiomatic bash shape, so this is not an edge case to skip.
PROJECT1B="$TMP/proj1b"
mkdir -p "$PROJECT1B/reports/mytopic/findings"
touch "$PROJECT1B/reports/mytopic/.gate-active"
OUT1B=$(run_hook 'F="reports/mytopic/findings/foo.json"; bash scripts/falsify.sh "$F"' "$PROJECT1B")
if is_denied "$OUT1B"; then
  note "FAIL: double-quoted var-assignment shape denied even though the gate window is open"; fail=1
else
  note "double-quoted var-assignment shape is allowed when the gate window is open"
fi

PROJECT1C="$TMP/proj1c"
mkdir -p "$PROJECT1C/reports/mytopic/findings"
touch "$PROJECT1C/reports/mytopic/.gate-active"
OUT1C=$(run_hook "F='reports/mytopic/findings/foo.json'; bash scripts/falsify.sh \"\$F\"" "$PROJECT1C")
if is_denied "$OUT1C"; then
  note "FAIL: single-quoted var-assignment shape denied even though the gate window is open"; fail=1
else
  note "single-quoted var-assignment shape is allowed when the gate window is open"
fi

# --- Case 2: var-assignment shape, gate window CLOSED -> must still DENY ---
# The fix must not defeat the guard itself -- a real closed window is still
# a real denial, corrupted-path bug or not.
PROJECT2="$TMP/proj2"
mkdir -p "$PROJECT2/reports/mytopic/findings"
# No .gate-active marker created -- window is closed.
OUT2=$(run_hook 'F=reports/mytopic/findings/foo.json; bash scripts/falsify.sh "$F"' "$PROJECT2")
if is_denied "$OUT2"; then
  note "var-assignment shape is still denied when the gate window is genuinely closed"
else
  note "FAIL: var-assignment shape was allowed with no open gate window (guard defeated)"; fail=1
fi

# --- Case 3: normal literal-argument call, gate window OPEN -> must ALLOW --
PROJECT3="$TMP/proj3"
mkdir -p "$PROJECT3/reports/mytopic/findings"
touch "$PROJECT3/reports/mytopic/.gate-active"
OUT3=$(run_hook 'bash scripts/falsify.sh reports/mytopic/findings/foo.json fixture.json' "$PROJECT3")
if is_denied "$OUT3"; then
  note "FAIL: a normal literal-argument call regressed to denied"; fail=1
else
  note "normal literal-argument call is unaffected (no regression)"
fi

# --- Case 4: non-gate use (no reports/*/findings/ path) -> always ALLOW ---
OUT4=$(run_hook 'bash scripts/falsify.sh /tmp/some/other/f.json fixture.json' "$TMP/proj4-unused")
if is_denied "$OUT4"; then
  note "FAIL: a non-gate falsify.sh call (no reports/*/findings/ path) was denied"; fail=1
else
  note "a non-gate falsify.sh call is always allowed"
fi

# --- Case 5: absolute finding path, gate window OPEN -> must ALLOW --------
# Confirms the positive path-character-class fix, not deleting the prefix
# outright, still lets an absolute path's leading directories match,
# preserving the hook's case "/*") branch for an absolute TOPIC_DIR.
ABS_TOPIC="$TMP/elsewhere/reports/mytopic"
mkdir -p "$ABS_TOPIC/findings"
touch "$ABS_TOPIC/.gate-active"
OUT5=$(run_hook "bash scripts/falsify.sh $ABS_TOPIC/findings/foo.json" "$TMP/proj5-unused")
if is_denied "$OUT5"; then
  note "FAIL: an absolute finding path with an open window was denied (absolute-path branch broken)"; fail=1
else
  note "absolute finding path with an open window is allowed (absolute-path branch preserved)"
fi

if [ "$fail" -eq 0 ]; then
  echo "guard-falsify-gate: PASS"
  exit 0
fi
echo "guard-falsify-gate: FAIL"
exit 1
