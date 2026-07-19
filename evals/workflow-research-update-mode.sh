#!/usr/bin/env bash
# workflow-research-update-mode.sh — structural eval for update-mode
# membership-aware fan-out in .claude/workflows/research.js
# (research-harness#19), complementing workflow-research-parses.sh and
# workflow-research-structure.sh. No live agent spawning -- purely static
# checks, fast and free to run in CI:
#
#   1. The script recognizes args.mode === 'update' (a MODE constant/branch
#      keyed off A.mode, not just full mode hardcoded).
#   2. Update mode resolves membership via resolve-membership.sh (SPEC §11)
#      instead of always fanning out every goal dimension.
#   3. Update mode ALSO runs a tag-aware gap check sourced from the goal's
#      completion_condition.checks[] -- the specific blind spot the issue
#      calls out: resolve-membership.sh's gap_dimensions[] is dimension-level
#      only, so a dimension with baseline coverage but an unanswered NEW
#      tagged sub-question must still be picked up, not silently skipped.
#   4. Stale carried findings (SPEC §11) are re-verified via the gate, not
#      dropped, when update mode has nothing new to research this round --
#      the round loop must not require workDims to be non-empty when there
#      are stale ids waiting on re-verification (the same "skip straight to
#      synthesis on stale content" bug class the issue describes for the
#      orchestrator, guarded against here too).
#
# Exit 0 = all four hold. Exit 1 = any fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SCRIPT="$ROOT/.claude/workflows/research.js"
fail=0
note() { printf '  workflow-research-update-mode: %s\n' "$1"; }

if [ ! -f "$SCRIPT" ]; then
  note "$SCRIPT does not exist"
  exit 1
fi

# --- 1. args.mode === 'update' is recognized --------------------------------
# Accept either the raw arg comparison (A.mode === 'update') or a check
# against a single resolved MODE constant (MODE === 'update', where MODE
# itself derives from A.mode once, near the top of the file) -- the latter
# is the correct shape when full/augment/update share one resolution point
# instead of each mode re-deriving its own MODE constant independently (that
# duplication is exactly what caused a real duplicate `const MODE` SyntaxError
# when research-harness#19 and #20 were merged separately, 2026-07-17 --
# fixed by consolidating to one resolution point, which this check must not
# then penalize for no longer repeating "A.mode" downstream).
if grep -qE "(A\.mode|MODE)\s*===\s*'update'" "$SCRIPT"; then
  note "recognizes args.mode === 'update'"
else
  note "no branch keys off A.mode === 'update' (or a MODE constant derived from it) -- update mode is not wired in"
  fail=1
fi

# --- 2. update mode resolves membership via resolve-membership.sh -----------
if grep -q 'resolve-membership.sh' "$SCRIPT" && grep -qE "gap_dimensions|gapDimensions" "$SCRIPT"; then
  note "update mode resolves gap_dimensions via resolve-membership.sh"
else
  note "update mode does not resolve membership (resolve-membership.sh / gap_dimensions) -- would blindly re-research everything"
  fail=1
fi

# --- 3. a tag-aware gap check exists on top of dimension-level membership ---
if grep -qE 'tags\s*\|\s*index\(' "$SCRIPT" && grep -qiE 'tagGap|tag-aware|tagged sub-question' "$SCRIPT"; then
  note "a tag-aware gap check (completion_condition.checks[] tag membership) is present"
else
  note "no tag-aware gap check found -- a dimension with baseline coverage but an unanswered new tagged sub-question would be silently skipped (the exact production blind spot research-harness#19 exists to close)"
  fail=1
fi

# --- 4. stale findings can still be re-verified when workDims is empty ------
# The round loop condition must not gate solely on workDims.length > 0 --
# otherwise a stale-only update (gap_dimensions empty, stale non-empty) never
# runs a round at all and the stale findings are reused with a decayed
# verdict instead of being re-gated.
LOOP_LOG="$(mktemp "${TMPDIR:-/tmp}/workflow-research-update-mode.loop.XXXXXX.log")"
trap 'rm -f "$LOOP_LOG"' EXIT
if node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  const m = src.match(/for\s*\(\s*let\s+round\s*=\s*1\s*;\s*round\s*<=\s*MAX_ROUNDS\s*&&\s*([\s\S]*?)\s*;\s*round\+\+\s*\)/);
  if (!m) { console.error('could not locate the round for-loop header'); process.exit(1); }
  const cond = m[1];
  const gatesOnlyOnWorkDims = /^workDims\.length\s*>\s*0$/.test(cond.trim());
  if (gatesOnlyOnWorkDims) { console.error('round loop condition is exactly workDims.length > 0 -- a stale-only update round never runs'); process.exit(1); }
  if (!/STALE_IDS/.test(cond)) { console.error('round loop condition does not reference STALE_IDS at all: ' + cond); process.exit(1); }
" "$SCRIPT" 2>"$LOOP_LOG"; then
  note "round loop still runs a stale-only round (condition accounts for STALE_IDS, not just workDims)"
else
  sed 's/^/    /' "$LOOP_LOG"
  fail=1
fi

exit "$fail"
