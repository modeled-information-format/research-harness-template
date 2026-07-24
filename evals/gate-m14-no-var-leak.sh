#!/usr/bin/env bash
# gate-m14-no-var-leak.sh — regression eval for research-harness-template#780
# (gate_m14's bypass-cmds loop variable `c` was not declared `local`, so it
# leaked into the caller's global namespace once gate_m14 returned -- verify.sh
# calls every gate as `"$gate"`, in-process, not in a subshell, so a bare loop
# var here becomes a real global visible to every later gate).
#
# Loads only the gate function DEFINITIONS from verify.sh (every line strictly
# before its `GATES=(...)` runner line) into this process, calls gate_m14
# directly, and asserts `c` is unset afterwards -- proving the loop variable
# stayed function-scoped instead of leaking. This mirrors the exact mechanism
# the bug report describes: verify.sh's runner calls each gate as `"$gate"`
# (never in a subshell), so any leak here is observable from this same shell.
#
# Exit 0 = no leak. Exit 1 = c leaked (or gate_m14 itself failed to run).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

DEFS_LINE="$(grep -n '^GATES=(' scripts/verify.sh | head -1 | cut -d: -f1)"
if [ -z "$DEFS_LINE" ]; then
  echo "gate-m14-no-var-leak: could not find GATES=(...) line in verify.sh" >&2
  exit 2
fi

# Source only the function definitions (everything strictly before the
# GATES=(...) runner) so gate_m14 becomes callable in THIS process without
# also running the full gate sequence / --gates selector logic at the bottom
# of the file.
TMP_DEFS="$(mktemp)"
trap 'rm -f "$TMP_DEFS"' EXIT
head -n "$((DEFS_LINE - 1))" scripts/verify.sh > "$TMP_DEFS"

# shellcheck source=/dev/null
. "$TMP_DEFS"

unset c 2>/dev/null || true
gate_m14 >/dev/null 2>&1
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "gate-m14-no-var-leak: gate_m14 itself exited non-zero ($RC)" >&2
  exit 1
fi

if [ -n "${c+x}" ]; then
  echo "gate-m14-no-var-leak: 'c' leaked into the caller's scope after gate_m14 returned (c=$c) -- the bypass_cmds loop variable must be declared 'local'" >&2
  exit 1
fi

echo "gate-m14-no-var-leak: gate_m14's loop variable 'c' stayed function-scoped, no global leak (#780)"
exit 0
