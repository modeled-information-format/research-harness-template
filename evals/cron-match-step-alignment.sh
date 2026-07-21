#!/usr/bin/env bash
# cron-match-step-alignment.sh — regression eval for cron_match.py's step
# semantics (research-harness-template#689). Two defects this pins down:
#
#   1. 'a-b/step' used to align step offsets to the FIELD's absolute lower
#      bound (lo) instead of the range's own start: parse_field('9-17/4', 0, 23)
#      returned {12, 16} — none of the intended hours — instead of the
#      vixie-cron {9, 13, 17}.
#   2. Bare 'N/step' used to collapse to the single value {N} (the step was
#      silently ignored) instead of the open-ended sequence N, N+step, ...
#      up to the field's upper bound.
#
# Each case fails on the pre-#689 code and passes on the fix; the '*/step',
# plain value, plain range, and list forms are asserted unchanged, and the
# end-to-end matches() gate is exercised through the CLI exit code exactly
# as monitor.yml consumes it.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

LIB="packs/monitoring/continuous-monitor/scripts/lib"
fail=0
note() { printf '  cron-match-step-alignment: %s\n' "$1"; }

# --- parse_field() unit cases -------------------------------------------------
# expect <label> <field> <lo> <hi> <expected python set literal>
expect() {
  local label="$1" field="$2" lo="$3" hi="$4" want="$5"
  if python3 - "$field" "$lo" "$hi" "$want" <<PY
import ast
import sys
sys.path.insert(0, "$LIB")
from cron_match import parse_field
field, lo, hi, want = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
got = parse_field(field, lo, hi)
expected = ast.literal_eval(want)
if got != expected:
    print(f"parse_field({field!r}, {lo}, {hi}) = {sorted(got)}, want {sorted(expected)}", file=sys.stderr)
    sys.exit(1)
PY
  then
    note "PASS $label"
  else
    note "FAIL $label"
    fail=1
  fi
}

# Defect 1 (#689): range-with-step must step from the range's own start.
expect "range-step-aligns-to-range-start" "9-17/4" 0 23 "{9, 13, 17}"
# Range start on the field's own lo bound still works (degenerate alignment).
expect "range-step-from-lo" "0-20/5" 0 59 "{0, 5, 10, 15, 20}"
# Defect 2 (#689): bare N/step is open-ended to the field's hi bound.
expect "bare-value-step-open-ended" "10/5" 0 59 "{10, 15, 20, 25, 30, 35, 40, 45, 50, 55}"
expect "bare-value-step-hours" "9/4" 0 23 "{9, 13, 17, 21}"
# Unchanged forms must keep their pre-#689 behaviour.
expect "star-step" "*/15" 0 59 "{0, 15, 30, 45}"
expect "star" "*" 0 5 "{0, 1, 2, 3, 4, 5}"
expect "plain-value" "30" 0 59 "{30}"
expect "plain-range" "1-5" 0 23 "{1, 2, 3, 4, 5}"
expect "list-with-step-part" "0,30-40/5" 0 59 "{0, 30, 35, 40}"

# --- end-to-end via the CLI, as monitor.yml calls it --------------------------
# '0 9-17/4 * * *' means hours {9, 13, 17}. Pre-#689 it wrongly matched
# hour 12 and missed hour 13.
if python3 "$LIB/cron_match.py" "0 9-17/4 * * *" "2026-07-20T13:00:00Z"; then
  note "PASS cli-range-step-fires-at-intended-hour"
else
  note "FAIL cli-range-step-fires-at-intended-hour (13:00 should match 9-17/4)"
  fail=1
fi
if python3 "$LIB/cron_match.py" "0 9-17/4 * * *" "2026-07-20T12:00:00Z"; then
  note "FAIL cli-range-step-skips-off-step-hour (12:00 must NOT match 9-17/4)"
  fail=1
else
  note "PASS cli-range-step-skips-off-step-hour"
fi
# '10/15 * * * *' means minutes {10, 25, 40, 55}. Pre-#689 only minute 10 matched.
if python3 "$LIB/cron_match.py" "10/15 * * * *" "2026-07-20T13:25:00Z"; then
  note "PASS cli-bare-step-fires-past-first-value"
else
  note "FAIL cli-bare-step-fires-past-first-value (minute 25 should match 10/15)"
  fail=1
fi

exit "$fail"
