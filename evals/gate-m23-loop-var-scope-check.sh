#!/usr/bin/env bash
# gate-m23-loop-var-scope-check.sh — regression eval for research-harness-template#781.
#
# gate_m23's 23d deliverable-title loop (`for d in "$edir"/synthesis-*.md ...`)
# declared the neighboring locals (`edir`, `all_titled`) but never declared `d`
# itself with `local`, leaking it into the global scope once gate_m23 returned.
# Any later gate (or a future edit to an existing one) reusing an unscoped `for
# d in ...`/`while read d` loop would silently inherit gate_m23's leaked value
# instead of starting from an unset variable.
#
# This runs gate_m23 in isolation (via verify.sh --gates, so no other gate's own
# `d` usage can interfere) and asserts `d` does NOT survive as a global once
# gate_m23 returns. An EXIT trap captures the leak state right as verify.sh's
# own `exit 0`/`exit 1` fires (source never returns control to a line after
# it), then overrides the process exit code to report the leak check itself —
# deliberately independent of whether gate_m23's own checks pass today, since
# this eval is scoped to the scoping bug, not gate_m23's content.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
# Gate scripts never read stdin (research-harness-template#531).
exec </dev/null

trap '
  if [ -n "${d+x}" ]; then
    echo "gate-m23-loop-var-scope-check: d leaked into the global scope after gate_m23 returned (research-harness-template#781 regressed)" >&2
    exit 1
  else
    exit 0
  fi
' EXIT
source scripts/verify.sh --gates "gate_m23\$" >/dev/null 2>&1
