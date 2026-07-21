#!/usr/bin/env bash
# start-error-handling-glob-check.sh — regression eval for /start's
# Error handling partial-findings check (research-harness-template#684).
#
# /start's Error handling section distinguishes "the orchestrator made
# partial progress" from "the orchestrator failed completely" by globbing
# for finding files. Findings are only ever written under
# reports/<topic>/findings/ (the orchestrator's dimension-analyst contract:
# "write findings into {REPORTS_DIR}/findings/"), but the check used to
# glob the flat reports/<topic>/*.json — which matches Phase 0 bookkeeping
# (goal.json, state.json, ontology-map.json) on essentially every run, so
# the "made progress, suggest /resume" branch fired even on a total
# failure with zero findings anywhere.
#
#   1. the Error handling section's partial-findings `ls` invocation globs
#      reports/<topic>/findings/*.json — the directory findings actually
#      land in;
#   2. no `ls reports/<topic>/*.json` invocation survives anywhere in
#      start.md (the flat glob may be MENTIONED as the anti-pattern, but
#      never invoked);
#   3. the findings path the check globs agrees with the path the
#      orchestrator names as the live progress signal
#      (reports/<topic>/findings/*.json in .claude/agents/orchestrator.md),
#      so the two surfaces cannot silently diverge again.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  start-error-handling-glob-check: %s\n' "$1"; }

CMD=.claude/commands/start.md
ORCH=.claude/agents/orchestrator.md

if [ ! -f "$CMD" ]; then
  note "missing $CMD"
  exit 1
fi

# Isolate the Error handling section (up to the next H2).
SECTION="$(awk '/^## Error handling$/{flag=1; next} /^## /{flag=0} flag' "$CMD")"
if [ -z "$SECTION" ]; then
  note "$CMD lost its '## Error handling' section"
  exit 1
fi

# Case 1: the partial-findings check globs the findings/ subdirectory.
if ! printf '%s\n' "$SECTION" | grep -qF 'ls reports/<topic>/findings/*.json'; then
  note "Error handling section does not glob reports/<topic>/findings/*.json for partial findings"
  fail=1
fi

# Case 2: the flat glob is never INVOKED (mentioning it as the anti-pattern
# is fine; an `ls` of it is the #684 defect).
if grep -qF 'ls reports/<topic>/*.json' "$CMD"; then
  note "$CMD still invokes the flat 'ls reports/<topic>/*.json' glob (#684)"
  fail=1
fi

# Case 3: the check's path agrees with the orchestrator's own live-progress
# signal path.
if [ -f "$ORCH" ]; then
  if ! grep -qF 'findings/*.json' "$ORCH"; then
    note "$ORCH no longer names findings/*.json as the progress signal — re-derive where findings land before trusting this eval"
    fail=1
  fi
else
  note "missing $ORCH"
  fail=1
fi

exit "$fail"
