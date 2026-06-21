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
"$LOCK" acquire "$D" "crashed" 2>/dev/null
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

if [ "$fail" -eq 0 ]; then
  echo "run-lock-test: PASS"
  exit 0
fi
echo "run-lock-test: FAIL"
exit 1
