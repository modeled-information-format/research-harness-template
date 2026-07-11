#!/usr/bin/env bash
# run-lock-test.sh — contract test for the topic run lock (scripts/run-lock.sh).
#
# The lock is the mutual-exclusion guard that prevents two concurrent runs from
# corrupting one topic's shared findings/ (the documented CONCURRENCY INCIDENT:
# 10 verification blocks stripped, 2 findings deleted). This pins its contract:
#   - a second concurrent acquire on a held topic is DENIED (exit 3);
#   - release frees the topic for the next run;
#   - a STALE lock (crashed run) is stolen so the topic never wedges;
#   - refresh keeps a held lock alive.
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

# 1. First acquire on a clean topic succeeds.
if "$LOCK" acquire "$D" "runA" 2>/dev/null; then
  note "first acquire succeeds on a clean topic"
else
  note "FAIL: first acquire did not succeed"; fail=1
fi

# 2. A second concurrent acquire is DENIED with exit 3 (the core invariant).
"$LOCK" acquire "$D" "runB" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then
  note "second concurrent acquire denied (exit 3) — mutual exclusion holds"
else
  note "FAIL: second acquire returned $rc (expected 3)"; fail=1
fi

# 3. Refresh keeps the held lock present and still exclusive.
"$LOCK" refresh "$D" 2>/dev/null
"$LOCK" acquire "$D" "runB" >/dev/null 2>&1; rc=$?
if [ -d "$D/.run-lock" ] && [ "$rc" -eq 3 ]; then
  note "refresh keeps the lock held and exclusive"
else
  note "FAIL: after refresh, lock present=$([ -d "$D/.run-lock" ] && echo y || echo n) acquire rc=$rc"; fail=1
fi

# 4. Release frees the topic; a fresh acquire then succeeds.
"$LOCK" release "$D" 2>/dev/null
if [ ! -d "$D/.run-lock" ] && "$LOCK" acquire "$D" "runC" 2>/dev/null; then
  note "release frees the topic; next acquire succeeds"
else
  note "FAIL: release did not free the topic"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 5. Staleness discriminates by AGE under the DEFAULT window — a genuinely OLD lock
#    is stolen, a FRESH one is not (proves age-based staleness, not blanket-steal).
#    Backdate the lock dir mtime to 2020 (far past 240m) to simulate a crashed run.
if ! "$LOCK" acquire "$D" "crashed" 2>/dev/null || [ ! -d "$D/.run-lock" ]; then
  note "FAIL: setup — acquire did not create the .run-lock DIRECTORY (test can't validate staleness)"; fail=1
fi
touch -t 202001010000 "$D/.run-lock"
if "$LOCK" acquire "$D" "recovery" 2>/dev/null; then
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

# 6. `steal` forces re-acquire over a held, FRESH lock (operator recovery path).
"$LOCK" acquire "$D" "stuck" >/dev/null 2>&1     # a live, fresh holder
"$LOCK" acquire "$D" "blocked" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ] && "$LOCK" steal "$D" "operator" 2>/dev/null && [ -d "$D/.run-lock" ]; then
  note "steal forces re-acquire over a fresh lock acquire would refuse"
else
  note "FAIL: steal did not force re-acquire (deny rc=$rc)"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 7. refresh does NOT resurrect a released/stolen lock (no phantom second owner).
"$LOCK" acquire "$D" "owner" >/dev/null 2>&1
"$LOCK" release "$D" 2>/dev/null
"$LOCK" refresh "$D" 2>/dev/null
if [ ! -d "$D/.run-lock" ]; then
  note "refresh on a released lock is a no-op (does not resurrect a phantom owner)"
else
  note "FAIL: refresh resurrected a released lock"; fail=1
fi

# 8. Two DIFFERENT topics never block each other.
DB="$TMP/reports/topic-b"
"$LOCK" acquire "$D"  "runA" >/dev/null 2>&1
if "$LOCK" acquire "$DB" "runB" 2>/dev/null; then
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
if FORCE=1 "$LOCK" steal "$D" "operator" 2>/dev/null && [ -d "$D/.run-lock" ]; then
  note "FORCE=1 still overrides the guard for a confirmed-dead recovery"
else
  note "FAIL: FORCE=1 did not override the write-activity guard"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 11. A steal against a topic with NO recent write activity (the ordinary
#     crashed-run recovery case) proceeds without needing FORCE.
rm -rf "$D/findings"
"$LOCK" acquire "$D" "stale-owner" >/dev/null 2>&1
if "$LOCK" steal "$D" "operator" 2>/dev/null && [ -d "$D/.run-lock" ]; then
  note "steal with no recent write activity proceeds without FORCE"
else
  note "FAIL: steal was refused despite no recent write activity"; fail=1
fi
"$LOCK" release "$D" 2>/dev/null

# 12. The steal guard fails SAFE (refuses) if it cannot inspect activity at all,
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

if [ "$fail" -eq 0 ]; then
  echo "run-lock-test: PASS"
  exit 0
fi
echo "run-lock-test: FAIL"
exit 1
