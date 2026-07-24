#!/usr/bin/env bash
# import-arg-parse-check.sh — regression eval for
# research-harness-template#746: a mistyped or unrecognized flag (e.g.
# --dryrun, -dry-run) used to fall through scripts/mif-container-import.sh's
# arg-parsing loop's wildcard branch into POSITIONAL[] like an ordinary
# positional argument. DRY_RUN silently stayed 0 (its default) and, since
# the old count check only required "at least 2" positionals, the script
# proceeded straight through step 4's real write with zero error or
# warning — directly contradicting its own documented --dry-run contract
# ("report the outcome without writing anything to reports/").
#
# Hermetic: every case below exits during arg-parsing, before the script
# ever resolves $CONTAINER_DIR/$MANIFEST or touches reports/ — so a
# nonexistent container-dir/topic pair is sufficient fixture, no real
# container/topic/corpus mutation needed (distinct from import-check.sh's
# own end-to-end Dry-Run/Review/Apply fixture, which this eval does not
# duplicate).
#
# Covers:
#   A. A mistyped flag (--dryrun, missing a hyphen) is REJECTED with a
#      message naming the unrecognized option, not silently absorbed as a
#      3rd positional argument — the exact #746 failure scenario.
#   B. The rejection happens at arg-parsing time (before any directory/
#      manifest resolution): the error text is the "unrecognized option"
#      message, never "not a directory"/"manifest not found", proving this
#      is caught early and not by coincidence further down the script.
#   C. A genuinely extra bare positional argument (3rd positional, no
#      leading '-') is also rejected now that the count check is exact
#      (-eq 2, not -ge 2) — the adjacent instance of the same
#      silent-acceptance defect class.
#   D. The real --dry-run flag still parses correctly and reaches the
#      directory-resolution step exactly as before (proven by getting the
#      "not a directory" error, not an "unrecognized option" one) — the fix
#      must not regress the documented, working case.
#   E. Ordinary 2-positional-arg usage with no flags is unaffected — same
#      "not a directory" outcome as case D, confirming the exact-count
#      check didn't tighten the baseline 2-arg case.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool/fixture is missing.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

IMPORT_SCRIPT="scripts/mif-container-import.sh"
[ -f "$IMPORT_SCRIPT" ] || { echo "  import-arg-parse-check: $IMPORT_SCRIPT not found" >&2; exit 2; }

fail=0
note() { printf '  import-arg-parse-check: %s\n' "$1"; }

NONEXISTENT_DIR="/tmp/import-arg-parse-check-does-not-exist-$$"
TOPIC="import-arg-parse-check-nonexistent-topic"

run_case() { # run_case <name> <expect_exit> <expect_grep> <forbid_grep> <args...>
  local name="$1" expect_exit="$2" expect_grep="$3" forbid_grep="$4"; shift 4
  local out rc
  out="$(bash "$IMPORT_SCRIPT" "$@" 2>&1)"
  rc=$?
  if [ "$rc" -eq "$expect_exit" ]; then
    note "  ok  $name: exit=$rc as expected"
  else
    note "FAIL $name: expected exit $expect_exit, got $rc -- output: $out"
    fail=1
    return
  fi
  if [ -n "$expect_grep" ] && ! grep -qF "$expect_grep" <<<"$out"; then
    note "FAIL $name: expected output to contain '$expect_grep' -- got: $out"
    fail=1
  fi
  if [ -n "$forbid_grep" ] && grep -qF "$forbid_grep" <<<"$out"; then
    note "FAIL $name: output must NOT contain '$forbid_grep' (would mean the typo reached directory resolution instead of being caught at arg-parsing) -- got: $out"
    fail=1
  fi
}

# A + B: the exact #746 failure scenario -- a missing-hyphen typo of
# --dry-run, given otherwise-well-formed positional args. Must be rejected
# with the "unrecognized option" message (naming the exact bad arg), never
# fall through to "not a directory" (which would mean it was silently
# accepted as a 3rd positional and DRY_RUN stayed 0).
run_case "A+B: mistyped --dryrun rejected at arg-parsing, not silently absorbed" \
  2 "unrecognized option: --dryrun" "not a directory" \
  "$NONEXISTENT_DIR" "$TOPIC" --dryrun

# Same scenario, a different plausible typo shape (missing leading dash).
run_case "A+B: mistyped -dry-run rejected at arg-parsing, not silently absorbed" \
  2 "unrecognized option: -dry-run" "not a directory" \
  "$NONEXISTENT_DIR" "$TOPIC" -dry-run

# C: a genuinely extra bare positional (no leading '-') is also rejected now
# (-eq 2, not -ge 2) -- the adjacent instance of the same defect class.
run_case "C: a 3rd bare positional argument is rejected (exact count, not >=2)" \
  2 "usage: mif-container-import.sh" "" \
  "$NONEXISTENT_DIR" "$TOPIC" extra-positional-arg

# D: the real, correctly-spelled --dry-run flag must still parse and reach
# directory resolution exactly as before the fix -- proven by getting the
# "not a directory" error (never "unrecognized option").
run_case "D: real --dry-run still parses correctly (reaches dir resolution)" \
  2 "not a directory" "unrecognized option" \
  "$NONEXISTENT_DIR" "$TOPIC" --dry-run

# E: ordinary 2-positional usage, no flags at all, is unaffected by the
# count check tightening from -ge 2 to -eq 2.
run_case "E: ordinary 2-arg usage (no flags) still reaches dir resolution" \
  2 "not a directory" "unrecognized option" \
  "$NONEXISTENT_DIR" "$TOPIC"

if [ "$fail" -eq 0 ]; then
  note "a mistyped/unrecognized flag is rejected at arg-parsing with a message naming the bad option, never silently absorbed as an extra positional argument that leaves DRY_RUN=0 and proceeds to a real write (#746); an extra bare positional is rejected too (exact count, not >=2); and the real --dry-run flag plus ordinary 2-arg usage are unaffected by the fix."
else
  echo "import-arg-parse-check: FAILED (see notes above)"
fi
exit "$fail"
