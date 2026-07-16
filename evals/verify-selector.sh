#!/usr/bin/env bash
# verify-selector.sh — regression eval for verify.sh's gate selector and
# profiling instrumentation (research-harness-template#531). The pre-push
# gate is only as valuable as it is runnable: --gates gives local iteration
# a scoped fast path (loudly marked, so a scoped run can never pass itself
# off as the full suite), and VERIFY_PROFILE=1 keeps the suite's runtime
# measurable instead of anecdotal.
#
# Covers:
#   1. --gates 'gate_m1$' runs exactly one gate, exits 0, and the summary
#      carries the SCOPED RUN marker with the 1/N count.
#   2. VERIFY_PROFILE=1 emits a per-gate time line and the slowest-gates
#      footer.
#   3. A pattern matching no gate fails loudly (exit 2, names the flag).
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  verify-selector: %s\n' "$1"; }

# Case 1 + 2 in one scoped run (VERIFY_PROFILE exercises both paths).
if ! VERIFY_PROFILE=1 bash scripts/verify.sh --gates 'gate_m1$' > "$TMP/scoped.out" 2>&1; then
  note "scoped run failed: $(tail -3 "$TMP/scoped.out")"
  fail=1
fi
grep -q 'SCOPED RUN' "$TMP/scoped.out" || { note "summary lacks the SCOPED RUN marker"; fail=1; }
grep -qE "matched 1/[0-9]+ gates" "$TMP/scoped.out" || { note "summary lacks the matched-count"; fail=1; }
grep -qE '^  time +[0-9]+s gate_m1$' "$TMP/scoped.out" || { note "per-gate time line missing"; fail=1; }
grep -q -- '--- slowest gates ---' "$TMP/scoped.out" || { note "slowest-gates footer missing"; fail=1; }
if grep -q 'Milestone 2 ' "$TMP/scoped.out"; then
  note "scoped run executed an unselected gate"
  fail=1
fi

# Case 3: unmatched pattern fails loudly.
bash scripts/verify.sh --gates 'no-such-gate-zzz' > "$TMP/none.out" 2>&1
RC=$?
[ "$RC" -eq 2 ] || { note "unmatched pattern should exit 2 (got $RC)"; fail=1; }
grep -q "matches no gate" "$TMP/none.out" || { note "unmatched-pattern error lacks the explanation"; fail=1; }

# Case 4: --gates with no argument fails with exit 2 and a usage message.
bash scripts/verify.sh --gates > "$TMP/noarg.out" 2>&1
RC=$?
[ "$RC" -eq 2 ] || { note "--gates with no argument should exit 2 (got $RC)"; fail=1; }
grep -q "requires a pattern argument" "$TMP/noarg.out" || { note "missing-argument error lacks the usage message"; fail=1; }

# Case 5: an invalid ERE gets its own message, not "matches no gate".
bash scripts/verify.sh --gates '(' > "$TMP/badere.out" 2>&1
RC=$?
[ "$RC" -eq 2 ] || { note "invalid ERE should exit 2 (got $RC)"; fail=1; }
grep -q "not a valid extended regular expression" "$TMP/badere.out" || { note "invalid-ERE error lacks its dedicated message"; fail=1; }

[ "$fail" -eq 0 ] && note "gate selector is scoped-and-loud; profiling emits per-gate and slowest-gate timings"
exit "$fail"
