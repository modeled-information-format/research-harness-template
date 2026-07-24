#!/usr/bin/env bash
# run-lock-test.sh — contract test for the topic run lock (scripts/run-lock.sh).
#
# The lock is the mutual-exclusion guard that prevents two concurrent runs from
# corrupting one topic's shared findings/ (the documented CONCURRENCY INCIDENT:
# 10 verification blocks stripped, 2 findings deleted). This pins its contract:
#   - a second concurrent acquire on a held topic is DENIED (exit 3);
#   - release frees the topic for the next run;
#   - a STALE lock (crashed run) is stolen so the topic never wedges;
#   - refresh keeps a held lock alive, but ONLY for the run that still owns the
#     ownership token acquire/steal stamped (research-harness-template#798).
#
# Exit 0 = the lock contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
LOCK=scripts/run-lock.sh
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  run-lock: %s\n' "$1"; }

D="$TMP/reports/topic-a"

# 1. First acquire on a clean topic succeeds and prints a non-empty token on stdout.
TOKA=$("$LOCK" acquire "$D" "runA" 2>/dev/null)
if [ -n "$TOKA" ]; then
  note "first acquire succeeds on a clean topic and prints an ownership token"
else
  note "FAIL: first acquire did not succeed / printed no token"; fail=1
fi

# 2. A second concurrent acquire is DENIED with exit 3 (the core invariant).
"$LOCK" acquire "$D" "runB" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  note "second concurrent acquire denied (exit 3) — mutual exclusion holds"
else
  note "FAIL: second acquire returned $rc (expected 3)"; fail=1
fi

# 3. Refresh with the CORRECT token keeps the held lock present, exclusive, and
#    actually advances its mtime (proving the touch, not just non-removal).
touch -t 202001010000 "$D/.run-lock"   # backdate so a real touch is observable
"$LOCK" refresh "$D" "$TOKA" >/dev/null 2>&1; rc=$?
mtime_year=$(date -r "$D/.run-lock" +%Y 2>/dev/null || echo "?")
"$LOCK" acquire "$D" "runB" >/dev/null 2>&1; acq_rc=$?
if [ "$rc" -eq 0 ] && [ "$mtime_year" != "2020" ] && [ "$acq_rc" -eq 3 ]; then
  note "refresh with the correct token touches the lock and keeps it exclusive"
else
  note "FAIL: refresh(correct token) rc=$rc mtime_year=$mtime_year acquire_rc=$acq_rc"; fail=1
fi

# 4. Release with the CORRECT token frees the topic; a fresh acquire then succeeds.
"$LOCK" release "$D" "$TOKA" 2>/dev/null
if [ ! -d "$D/.run-lock" ] && "$LOCK" acquire "$D" "runC" >/dev/null 2>&1; then
  note "release(correct token) frees the topic; next acquire succeeds"
else
  note "FAIL: release(correct token) did not free the topic"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 5. Staleness discriminates by AGE under the DEFAULT window — a genuinely OLD lock
#    is stolen, a FRESH one is not (proves age-based staleness, not blanket-steal).
#    Backdate the lock dir mtime to 2020 (far past 240m) to simulate a crashed run.
if ! "$LOCK" acquire "$D" "crashed" >/dev/null 2>&1 || [ ! -d "$D/.run-lock" ]; then
  note "FAIL: setup — acquire did not create the .run-lock DIRECTORY (test can't validate staleness)"; fail=1
fi
touch -t 202001010000 "$D/.run-lock"
if "$LOCK" acquire "$D" "recovery" >/dev/null 2>&1; then
  note "an OLD (backdated) lock is stolen under the default window"
else
  note "FAIL: a genuinely-stale lock was not stolen"; fail=1
fi
# The just-stolen lock is now FRESH, so the next concurrent acquire must be DENIED
# (if staleness ignored age and always stole, this would wrongly succeed).
"$LOCK" acquire "$D" "interloper" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  note "a FRESH lock is NOT stolen (age, not blanket-steal)"
else
  note "FAIL: a fresh lock was stolen (rc=$rc) — staleness ignores age"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 6. `steal` forces re-acquire over a held, FRESH lock (operator recovery path), and
#    prints a fresh ownership token on stdout.
"$LOCK" acquire "$D" "stuck" >/dev/null 2>&1     # a live, fresh holder
"$LOCK" acquire "$D" "blocked" >/dev/null 2>&1; rc=$?
TOKSTEAL=$("$LOCK" steal "$D" "operator" 2>/dev/null)
if [ "$rc" -eq 3 ] && [ -n "$TOKSTEAL" ] && [ -d "$D/.run-lock" ]; then
  note "steal forces re-acquire over a fresh lock acquire would refuse, and prints a new token"
else
  note "FAIL: steal did not force re-acquire (deny rc=$rc, token='$TOKSTEAL')"; fail=1
fi
"$LOCK" release "$D" "$TOKSTEAL" 2>/dev/null

# 7. refresh does NOT resurrect a released/stolen lock (no phantom second owner).
TOK7=$("$LOCK" acquire "$D" "owner" 2>/dev/null)
"$LOCK" release "$D" "$TOK7" 2>/dev/null
"$LOCK" refresh "$D" "$TOK7" >/dev/null 2>&1
if [ ! -d "$D/.run-lock" ]; then
  note "refresh on a released lock is a no-op (does not resurrect a phantom owner)"
else
  note "FAIL: refresh resurrected a released lock"; fail=1
fi

# 8. Two DIFFERENT topics never block each other.
DB="$TMP/reports/topic-b"
"$LOCK" acquire "$D"  "runA" >/dev/null 2>&1
if "$LOCK" acquire "$DB" "runB" >/dev/null 2>&1; then
  note "distinct topics lock independently"
else
  note "FAIL: a lock on one topic blocked another"; fail=1
fi

# 9. Regression test for #382 review: RUN_LOCK_STALE_MIN="00" (all-digit but
#    numerically zero) must fall back to the safe default, same as an empty or
#    non-numeric value -- the original `case ... in ''|*[!0-9]*|0)` validation
#    only rejected the exact literal "0", so "00"/"0000" slipped through as
#    non-empty, non-"0" strings and made `find -mmin -00` match nothing (a file
#    can't be modified "<0 minutes ago"), silently defeating the fail-safe
#    intent (a fresh lock would misjudge as stale and get stolen).
"$LOCK" release "$D" 2>/dev/null
"$LOCK" acquire "$D" "live" >/dev/null 2>&1
RUN_LOCK_STALE_MIN="00" "$LOCK" acquire "$D" "interloper" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  note "RUN_LOCK_STALE_MIN=\"00\" falls back to the safe default (fresh lock still denies, not mis-stolen)"
else
  note "FAIL: RUN_LOCK_STALE_MIN=\"00\" did not fall back to the safe default (rc=$rc, expected 3)"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 10. Regression test for #392's corrected root cause: a steal against a topic
#     with WRITE ACTIVITY inside the guard window (a findings/ file just
#     written, simulating a genuinely-alive owner) is REFUSED without FORCE,
#     and the lock is left untouched -- proving a misread liveness signal
#     (e.g. a stale-looking TaskOutput message) can't alone force a steal past
#     a live writer. FORCE=1 still overrides for a confirmed-dead recovery.
"$LOCK" release "$D" 2>/dev/null
"$LOCK" acquire "$D" "alive-owner" >/dev/null 2>&1
mkdir -p "$D/findings"
echo '{}' > "$D/findings/f1.json"
"$LOCK" steal "$D" "operator" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ] && [ -d "$D/.run-lock" ]; then
  note "steal refused (rc=3) against recent findings/ activity, lock left intact"
else
  note "FAIL: steal against recent write activity was not refused (rc=$rc, lock present=$([ -d "$D/.run-lock" ] && echo y || echo n))"; fail=1
fi
if FORCE=1 "$LOCK" steal "$D" "operator" >/dev/null 2>&1 && [ -d "$D/.run-lock" ]; then
  note "FORCE=1 still overrides the guard for a confirmed-dead recovery"
else
  note "FAIL: FORCE=1 did not override the write-activity guard"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 11. Regression test (Copilot review, PR #398): an IN-PLACE update to an
#     EXISTING finding file (content overwritten via a plain truncate, same
#     path, no rename) must still count as activity -- only the file's own
#     mtime changes in this case, not the findings/ directory's mtime, so a
#     directory-mtime-only check would miss it. Backdate the directory itself
#     to look old, then touch only the existing file in place.
"$LOCK" release "$D" 2>/dev/null
"$LOCK" acquire "$D" "alive-owner" >/dev/null 2>&1
mkdir -p "$D/findings"
echo '{}' > "$D/findings/f1.json"
touch -t 202001010000 "$D/findings"   # directory itself looks old/stale
printf '{"v":2}' > "$D/findings/f1.json"   # in-place rewrite of the EXISTING file, no rename
"$LOCK" steal "$D" "operator" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ] && [ -d "$D/.run-lock" ]; then
  note "steal refused (rc=3) against an in-place file update, even with an old directory mtime"
else
  note "FAIL: an in-place existing-file update was not detected as activity (rc=$rc) -- directory-mtime-only check regression"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 12. A steal against a topic with NO recent write activity (the ordinary
#     crashed-run recovery case) proceeds without needing FORCE.
rm -rf "$D/findings"
"$LOCK" acquire "$D" "stale-owner" >/dev/null 2>&1
if "$LOCK" steal "$D" "operator" >/dev/null 2>&1 && [ -d "$D/.run-lock" ]; then
  note "steal with no recent write activity proceeds without FORCE"
else
  note "FAIL: steal was refused despite no recent write activity"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 13. The steal guard fails SAFE (refuses) if it cannot inspect activity at all,
#     matching fresh()'s existing fail-safe convention -- an unreadable findings/
#     dir must not be silently treated as "no activity, safe to steal". Skipped
#     when running as root, since root bypasses directory permission bits and
#     the simulated unreadable-directory condition can't be produced.
if [ "$(id -u)" -ne 0 ]; then
  "$LOCK" acquire "$D" "alive-owner" >/dev/null 2>&1
  mkdir -p "$D/findings"
  echo '{}' > "$D/findings/f1.json"
  chmod 000 "$D/findings"
  "$LOCK" steal "$D" "operator" >/dev/null 2>&1; rc=$?
  chmod 755 "$D/findings"
  if [ "$rc" -eq 3 ] && [ -d "$D/.run-lock" ]; then
    note "steal fails SAFE (refused) when findings/ can't be inspected, not treated as no-activity"
  else
    note "FAIL: steal against an uninspectable findings/ was not refused (rc=$rc) -- fails OPEN, not safe"; fail=1
  fi
  "$LOCK" release "$D" 2>/dev/null
else
  note "skipped: fail-safe-on-uninspectable-dir case (running as root, permission bits bypassed)"
fi

# --- research-harness-template#798 regression tests: refresh/release ownership ---
# Same defect class research-harness-template#763 fixed in
# scripts/lib/container-lock.sh's container_lock_refresh: run-lock.sh's `refresh`
# used to touch $LOCK unconditionally, with no way to tell "the lock this run
# originally acquired" from "a different run's lock that has since replaced it
# at this same path". Unlike container-lock.sh (sourced into one long-lived
# shell, so an in-memory token survives from acquire to refresh), run-lock.sh
# runs as SEPARATE CLI invocations -- the fix persists the token on disk
# (`.owner-token`) and prints it on stdout, so these tests exercise it exactly
# as a real caller would: capture the token from acquire/steal's stdout, then
# pass it back on every later refresh/release call.

# 14. The exact steal scenario the issue describes: run A acquires (token A),
#     a stale-lock steal (or a live operator steal) hands the lock to run B
#     (token B) at the SAME path, and run A's next refresh -- still holding
#     only its OLD token A -- must be REFUSED (rc=1) and must NOT touch the
#     lock's mtime, while run B's refresh with token B succeeds.
"$LOCK" release "$D" 2>/dev/null
TOKA14=$("$LOCK" acquire "$D" "runA" 2>/dev/null)
TOKB14=$(FORCE=1 "$LOCK" steal "$D" "runB" 2>/dev/null)   # simulates a second run stealing the same path
touch -t 202001010000 "$D/.run-lock"   # backdate so a wrongful touch would be observable
"$LOCK" refresh "$D" "$TOKA14" >/dev/null 2>&1; rc_stale=$?
mtime_year_stale=$(date -r "$D/.run-lock" +%Y 2>/dev/null || echo "?")
"$LOCK" refresh "$D" "$TOKB14" >/dev/null 2>&1; rc_live=$?
if [ "$rc_stale" -eq 1 ] && [ "$mtime_year_stale" = "2020" ] && [ "$rc_live" -eq 0 ]; then
  note "refresh with a STOLEN run's old token is refused (rc=1) and does not touch the lock; the new owner's refresh succeeds"
else
  note "FAIL: stolen-token refresh rc=$rc_stale (expected 1) mtime_year=$mtime_year_stale live_refresh_rc=$rc_live (expected 0)"; fail=1
fi
"$LOCK" release "$D" "$TOKB14" 2>/dev/null

# 15. release with a MISMATCHED token SKIPS removal (never destroys a different
#     run's live lock); release with the CORRECT token still removes it.
TOKA15=$("$LOCK" acquire "$D" "runA" 2>/dev/null)
TOKB15=$(FORCE=1 "$LOCK" steal "$D" "runB" 2>/dev/null)
"$LOCK" release "$D" "$TOKA15" >/dev/null 2>&1   # old token — must be a no-op, not a deletion
if [ -d "$D/.run-lock" ]; then
  note "release with a mismatched (stolen) token skips removal — does not delete another run's live lock"
else
  note "FAIL: release with a mismatched token deleted a different run's live lock"; fail=1
fi
"$LOCK" release "$D" "$TOKB15" >/dev/null 2>&1   # correct token — must remove it
if [ ! -d "$D/.run-lock" ]; then
  note "release with the correct token removes the lock"
else
  note "FAIL: release with the correct token did not remove the lock"; fail=1
fi

# 16. refresh with NO token argument is refused (rc=1) rather than silently
#     touching whatever lock currently occupies the path — a caller that
#     forgot to thread the token through must fail loudly, not corrupt.
TOK16=$("$LOCK" acquire "$D" "runA" 2>/dev/null)
touch -t 202001010000 "$D/.run-lock"
"$LOCK" refresh "$D" >/dev/null 2>&1; rc=$?
mtime_year16=$(date -r "$D/.run-lock" +%Y 2>/dev/null || echo "?")
if [ "$rc" -eq 1 ] && [ "$mtime_year16" = "2020" ]; then
  note "refresh with no token argument is refused (rc=1) and does not touch the lock"
else
  note "FAIL: refresh with no token rc=$rc (expected 1) mtime_year=$mtime_year16 (expected 2020)"; fail=1
fi
"$LOCK" release "$D" "$TOK16" 2>/dev/null

if [ "$fail" -eq 0 ]; then
  echo "run-lock-test: PASS"
  exit 0
fi
echo "run-lock-test: FAIL"
exit 1
