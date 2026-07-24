#!/usr/bin/env bash
# container-lock-test.sh — contract test for scripts/lib/container-lock.sh,
# the shared mkdir-based mutual-exclusion lock for reports/<topic>/.container.lock
# sourced by mif-container-export.sh / mif-container-import.sh (feature-spec AC12).
#
# Mirrors evals/run-lock-test.sh's structure for its sibling lock, plus the
# research-harness-template#739 regression: the stale-lock steal path must
# serialize its destructive rm-rf+re-mkdir reclaim so two concurrent
# stealers can never both end up believing they hold the lock (the
# previously-reproducible TOCTOU: racer A's freshly re-created live lock
# silently deleted and overwritten by racer B's own rm -rf, with BOTH
# acquire calls returning rc=0).
#
# Exit 0 = the lock contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
LOCKLIB="$(pwd)/scripts/lib/container-lock.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  container-lock: %s\n' "$1"; }

# Portable file/dir mtime as an epoch integer — GNU `stat -c %Y` vs BSD/macOS
# `stat -f %m` (mirrors evals/run-lock-test.sh's own helper).
mtime_epoch() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# do_acquire <dir> <label> -- run one container_lock_acquire call in a FRESH
# subshell (the lib is sourced into the caller's shell, not a CLI) and print
# its exit code on line 1, its ownership token on line 2.
do_acquire() {
  local dir="$1" label="$2" rc
  (
    . "$LOCKLIB"
    container_lock_acquire "$dir" "$label" >/dev/null 2>&1
    rc=$?
    printf '%s\n%s\n' "$rc" "${CONTAINER_LOCK_TOKEN:-}"
  )
}

D="$TMP/reports/topic-a/.container.lock"
mkdir -p "$(dirname "$D")"   # container_lock_acquire assumes the parent dir exists

# 1. First acquire on a clean lock succeeds and yields a non-empty token.
out=$(do_acquire "$D" "runA")
rc1=$(printf '%s' "$out" | sed -n 1p); tok1=$(printf '%s' "$out" | sed -n 2p)
if [ "$rc1" -eq 0 ] 2>/dev/null && [ -n "$tok1" ]; then
  note "first acquire succeeds on a clean lock and yields an ownership token"
else
  note "FAIL: first acquire rc=$rc1 token='$tok1'"; fail=1
fi

# 2. A second concurrent acquire on the still-fresh lock is DENIED (exit 3).
out=$(do_acquire "$D" "runB")
rc2=$(printf '%s' "$out" | sed -n 1p)
if [ "$rc2" -eq 3 ] 2>/dev/null; then
  note "second concurrent acquire denied (exit 3) — mutual exclusion holds"
else
  note "FAIL: second acquire returned $rc2 (expected 3)"; fail=1
fi

# 3. Refresh with the CORRECT token touches the lock's mtime; a WRONG token
#    is refused and leaves the mtime untouched.
touch -t 202001010000 "$D"
before3=$(mtime_epoch "$D")
( . "$LOCKLIB"; container_lock_refresh "$D" "$tok1" ) >/dev/null 2>&1
rc3=$?
after3=$(mtime_epoch "$D")
if [ "$rc3" -eq 0 ] && [ "$after3" != "$before3" ]; then
  note "refresh with the correct token touches the lock"
else
  note "FAIL: refresh(correct token) rc=$rc3 before=$before3 after=$after3"; fail=1
fi
( . "$LOCKLIB"; container_lock_refresh "$D" "not-the-real-token" ) >/dev/null 2>&1
rc3b=$?
if [ "$rc3b" -ne 0 ]; then
  note "refresh with a wrong token is refused"
else
  note "FAIL: refresh with a wrong token succeeded"; fail=1
fi

# 4. Release with a MISMATCHED token skips removal; the CORRECT token removes it.
( . "$LOCKLIB"; container_lock_release "$D" "not-the-real-token" ) >/dev/null 2>&1
if [ -d "$D" ]; then
  note "release with a mismatched token skips removal — does not delete another run's lock"
else
  note "FAIL: release with a mismatched token removed the lock"; fail=1
fi
( . "$LOCKLIB"; container_lock_release "$D" "$tok1" ) >/dev/null 2>&1
if [ ! -d "$D" ]; then
  note "release with the correct token removes the lock"
else
  note "FAIL: release with the correct token left the lock behind"; fail=1
fi

# 5. Staleness discriminates by age: a genuinely OLD (backdated) lock is
#    stolen; the just-stolen (now fresh) lock is NOT stolen again.
out=$(do_acquire "$D" "crashed")
rc5=$(printf '%s' "$out" | sed -n 1p)
[ "$rc5" -eq 0 ] 2>/dev/null || { note "FAIL: setup acquire for staleness test rc=$rc5"; fail=1; }
touch -t 202001010000 "$D"
out=$(do_acquire "$D" "recovery")
rc5b=$(printf '%s' "$out" | sed -n 1p); tok5b=$(printf '%s' "$out" | sed -n 2p)
if [ "$rc5b" -eq 0 ] 2>/dev/null && [ -n "$tok5b" ]; then
  note "an OLD (backdated) lock is stolen under the default window"
else
  note "FAIL: a genuinely-stale lock was not stolen (rc=$rc5b)"; fail=1
fi
out=$(do_acquire "$D" "interloper")
rc5c=$(printf '%s' "$out" | sed -n 1p)
if [ "$rc5c" -eq 3 ] 2>/dev/null; then
  note "the just-stolen (now fresh) lock is NOT stolen again"
else
  note "FAIL: a fresh lock was stolen (rc=$rc5c) — staleness ignores age"; fail=1
fi
( . "$LOCKLIB"; container_lock_release "$D" "$tok5b" ) >/dev/null 2>&1

# --- research-harness-template#739 regression: the steal path must be
# serialized, never racy ---

# 6. Deterministic proof of serialization: while the steal-mutex is HELD
#    (simulating a concurrent stealer mid-reclaim), a second acquire on the
#    SAME stale lock must NOT touch the lock at all — it must wait. Only
#    once the mutex is released may it proceed. Pre-create a stale lock,
#    pre-hold the mutex by hand, launch a second acquire in the background,
#    confirm the original lock is UNTOUCHED while the mutex is held, then
#    release the mutex and confirm the background acquire completes.
out=$(do_acquire "$D" "stale-owner")
rc6=$(printf '%s' "$out" | sed -n 1p)
[ "$rc6" -eq 0 ] 2>/dev/null || { note "FAIL: setup acquire for mutex test rc=$rc6"; fail=1; }
touch -t 202001010000 "$D"
orig_token=$(cat "$D/.owner-token" 2>/dev/null)
mutex="${D}.steal-mutex"
mkdir "$mutex"   # simulate racer A already mid-steal, holding the mutex
(
  . "$LOCKLIB"
  container_lock_acquire "$D" "racerB" >/dev/null 2>&1
  echo "$?" > "$TMP/racerB.rc"
  echo "${CONTAINER_LOCK_TOKEN:-}" > "$TMP/racerB.tok"
) &
bg_pid=$!
sleep 0.3   # give racerB time to be in its retry loop, contending on the mutex
if [ -d "$D" ] && [ "$(cat "$D/.owner-token" 2>/dev/null)" = "$orig_token" ]; then
  note "a waiting racer does NOT touch the lock while another racer holds the steal-mutex"
else
  note "FAIL: the lock was mutated while a different racer held the steal-mutex — serialization broken"; fail=1
fi
rm -rf "$mutex"   # release the simulated mutex
wait "$bg_pid"
bg_rc=$(cat "$TMP/racerB.rc" 2>/dev/null)
if [ "$bg_rc" = "0" ] && [ -d "$D" ]; then
  note "after the mutex is released, the waiting racer completes its steal successfully"
else
  note "FAIL: the waiting racer did not complete its steal after the mutex was released (rc=$bg_rc)"; fail=1
fi
( . "$LOCKLIB"; container_lock_release "$D" "$(cat "$TMP/racerB.tok" 2>/dev/null)" ) >/dev/null 2>&1

# 7. Real concurrent race (the issue's own reproduction, evaluated end to
#    end): two full processes race to steal the SAME stale lock at once,
#    with no pre-held mutex staging the timing. Mutual exclusion holds iff
#    whichever racer(s) report rc=0 actually own what is stamped at $D
#    afterward — the exact property the pre-fix code violated (both racers
#    could report rc=0 while only one's files were actually present).
out=$(do_acquire "$D" "setup7")
rc7setup=$(printf '%s' "$out" | sed -n 1p)
[ "$rc7setup" -eq 0 ] 2>/dev/null || { note "FAIL: setup acquire for race test rc=$rc7setup"; fail=1; }
touch -t 202001010000 "$D"
(
  . "$LOCKLIB"
  container_lock_acquire "$D" "racerX" >/dev/null 2>&1
  echo "$?" > "$TMP/racerX.rc"
  echo "${CONTAINER_LOCK_TOKEN:-}" > "$TMP/racerX.tok"
) &
pidX=$!
(
  . "$LOCKLIB"
  container_lock_acquire "$D" "racerY" >/dev/null 2>&1
  echo "$?" > "$TMP/racerY.rc"
  echo "${CONTAINER_LOCK_TOKEN:-}" > "$TMP/racerY.tok"
) &
pidY=$!
wait "$pidX" "$pidY"
rcX=$(cat "$TMP/racerX.rc" 2>/dev/null); tokX=$(cat "$TMP/racerX.tok" 2>/dev/null)
rcY=$(cat "$TMP/racerY.rc" 2>/dev/null); tokY=$(cat "$TMP/racerY.tok" 2>/dev/null)
final_token=$(cat "$D/.owner-token" 2>/dev/null)
race_ok=1
[ "$rcX" = "0" ] && [ "$tokX" != "$final_token" ] && race_ok=0
[ "$rcY" = "0" ] && [ "$tokY" != "$final_token" ] && race_ok=0
[ "$rcX" = "0" ] && [ "$rcY" = "0" ] && [ "$tokX" = "$tokY" ] && race_ok=0
if [ "$race_ok" -eq 1 ]; then
  note "concurrent steal race: whichever racer(s) report rc=0 actually own the final stamped lock — mutual exclusion holds under real concurrency"
else
  note "FAIL: concurrent steal race broke mutual exclusion (rcX=$rcX tokX=$tokX rcY=$rcY tokY=$tokY final=$final_token)"; fail=1
fi
( . "$LOCKLIB"; container_lock_release "$D" ) >/dev/null 2>&1

if [ "$fail" -eq 0 ]; then
  echo "container-lock-test: PASS"
  exit 0
fi
echo "container-lock-test: FAIL"
exit 1
