# container-lock.sh — shared mkdir-based mutual-exclusion lock for
# reports/<topic>/.container.lock (feature-spec AC12, issue #375).
#
# scripts/mif-container-export.sh and scripts/mif-container-import.sh both
# source this instead of each carrying their own near-verbatim mkdir/trap
# block, so a future change to the lock's behavior (e.g. this file's own
# staleness fix, issue #382) applies to both at once instead of being easy
# to apply to one copy and silently miss the other.
#
# Mirrors scripts/run-lock.sh's staleness/steal semantics (same documented
# CONCURRENCY INCIDENT motivates both -- see run-lock.sh's header): a plain
# mkdir/rmdir pair with only an EXIT-trap release has no staleness
# detection, so a killed export/import (SIGKILL, OOM, container eviction)
# before its trap fires left $LOCK_DIR behind FOREVER, wedging every later
# export/import on that topic until an operator manually found and rmdir'd
# it. A lock older than the staleness window is now treated as abandoned and
# safely stolen via the same race-safe re-mkdir-after-rm-rf pattern
# run-lock.sh uses (only one racer's mkdir can win).
#
# CONTAINER_LOCK_STALE_MIN (default 240 = 4h) intentionally matches
# run-lock.sh's RUN_LOCK_STALE_MIN default, though the two locks are
# independent namespaces (reports/<topic>/.container.lock vs
# reports/<topic>/.run-lock) -- merging them is explicitly out of scope
# (issue #375's own "Out of scope" note: matching import's pre-existing
# SEPARATE lock exactly, staleness gap included, was the correct minimal
# scope for that issue; this file only closes the staleness gap, in place).
#
# Ownership token (research-harness-template#763): container_lock_acquire
# stamps each acquisition with a unique token (CONTAINER_LOCK_TOKEN) inside
# $lock_dir/.owner-token. container_lock_refresh requires that token and
# refuses to touch the lock if it no longer matches -- otherwise a refresh
# cannot distinguish "the lock I originally acquired" from "a different run's
# lock that has since replaced mine at this path" and would silently extend
# whichever lock currently occupies it. container_lock_release's token
# parameter is optional (back-compat for a caller that never refreshes).
#
# Steal-mutex (research-harness-template#739): the ownership token above
# lets a REFRESHING caller detect that it lost the lock, but it does nothing
# for the steal itself -- the rm-rf-then-re-mkdir reclaim of a stale lock is
# NOT atomic. Two racers can both observe the SAME stale $lock_dir and both
# run rm-rf+mkdir; if racer A's sequence completes (rm-rf, mkdir, stamp)
# before racer B's own rm-rf runs, B's rm-rf deletes A's brand-new LIVE lock
# out from under it and B's mkdir then recreates it as B's own -- both
# acquire calls return rc=0, both callers believe they hold exclusive
# access, and both write concurrently. container_lock_acquire's steal path
# now serializes the whole check-stale+rm-rf+mkdir sequence behind a
# separate mutex directory (`$lock_dir.steal-mutex`, created via `mkdir`,
# which IS atomic): only the racer that wins the mutex performs the
# destructive reclaim; every other racer either fails to grab the mutex and
# waits, or -- once the winner has finished and released it -- re-observes
# $lock_dir as freshly held and correctly reports "lost the race" instead of
# stealing it a second time. See _container_lock_steal below.
#
# Usage (sourced, not executed):
#   . "$ROOT/scripts/lib/container-lock.sh"
#   container_lock_acquire "$LOCK_DIR" "export" || fail "another export/import is in progress for topic '$TOPIC' (lock held: $LOCK_DIR)"
#   LOCK_TOKEN="$CONTAINER_LOCK_TOKEN"
#   trap 'container_lock_release "$LOCK_DIR" "$LOCK_TOKEN"' EXIT
#   ...
#   container_lock_refresh "$LOCK_DIR" "$LOCK_TOKEN" || fail "lost the lock mid-run"
#   ...
#   container_lock_release "$LOCK_DIR" "$LOCK_TOKEN"

CONTAINER_LOCK_STALE_MIN="${CONTAINER_LOCK_STALE_MIN:-240}"
# Validate: an empty/non-numeric/zero value would make `find -mmin` error and
# container_lock_fresh mis-judge a LIVE lock as stale (then steal it -- the
# corruption this file exists to prevent). Fall back to the safe default
# rather than fail open. The case pattern alone only rejects the exact
# literal "0" -- "00"/"0000" are all-digit and would slip through as a
# non-empty, non-'0' string, then `find -mmin -00` matches nothing (a file
# can't be modified "<0 minutes ago"), silently defeating the same
# fail-safe intent. The arithmetic check below catches every all-digit
# zero, not just the single-character form.
case "$CONTAINER_LOCK_STALE_MIN" in ''|*[!0-9]*) CONTAINER_LOCK_STALE_MIN=240 ;; esac
[ "$CONTAINER_LOCK_STALE_MIN" -eq 0 ] 2>/dev/null && CONTAINER_LOCK_STALE_MIN=240

# CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC (default 30, seconds not minutes) --
# staleness window for the steal-mutex itself (research-harness-template#739;
# see _container_lock_steal). The mutex's critical section is a handful of
# filesystem calls, normally sub-second; a holder still present after this
# many seconds was killed mid-steal (an astronomically small window) and is
# safe to reclaim the same way container/run locks reclaim their own stale
# holder -- self-healing, one level down, so a crashed stealer cannot wedge
# every future acquire on this topic forever.
CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC="${CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC:-30}"
case "$CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC" in ''|*[!0-9]*) CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC=30 ;; esac
[ "$CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC" -eq 0 ] 2>/dev/null && CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC=30

# container_lock_fresh <lock_dir> -- true if $lock_dir exists and its
# directory mtime is within the staleness window. Fails SAFE: if `find`
# errors, treat the lock as fresh (never mis-steal a live lock because of a
# `find` hiccup).
container_lock_fresh() {
  local lock_dir="$1" hit
  [ -d "$lock_dir" ] || return 1
  hit=$(find "$lock_dir" -maxdepth 0 -mmin "-$CONTAINER_LOCK_STALE_MIN" 2>/dev/null) || return 0
  [ -n "$hit" ]
}

# container_lock_acquire <lock_dir> [label] -- mkdir-atomic acquire; a STALE
# lock (mtime older than the window) is reclaimed via _container_lock_steal,
# which serializes the reclaim behind a mutex so two concurrent stealers can
# never both win (research-harness-template#739 -- see that function and the
# file header for why the naive rm-rf-then-re-mkdir sequence alone is NOT
# race-safe). Writes an `owner` file inside the lock for the diagnostic
# message. Prints an error to stderr and returns nonzero (3 = held by a live
# holder/lost the steal race, 1 = an unrelated filesystem failure e.g.
# missing parent dir or a read-only FS) on denial/failure; the caller
# decides how to fail (this repo's convention is `fail "$msg"`). On a rc=1
# failure, also sets CONTAINER_LOCK_LAST_ERROR to the underlying error text
# so the caller's own fail() message can include it (the pre-refactor
# per-script messages embedded this detail inline; this global preserves
# that without the library needing to know each caller's fail() shape).
container_lock_acquire() {
  local lock_dir="$1" label="${2:-run}" lock_err
  CONTAINER_LOCK_LAST_ERROR=""
  if lock_err="$(mkdir "$lock_dir" 2>&1)"; then
    _container_lock_stamp "$lock_dir" "$label"
    return 0
  fi
  if [ -d "$lock_dir" ]; then
    if container_lock_fresh "$lock_dir"; then
      echo "container-lock: DENIED -- another export/import is in progress for this topic (lock held: $lock_dir, held by '$(cat "$lock_dir/owner" 2>/dev/null || echo unknown)'; fresh within ${CONTAINER_LOCK_STALE_MIN}m)." >&2
      return 3
    fi
    _container_lock_steal "$lock_dir" "$label"
    return $?
  fi
  CONTAINER_LOCK_LAST_ERROR="${lock_err:-mkdir failed for an unknown reason}"
  echo "container-lock: failed to create lock at $lock_dir: $CONTAINER_LOCK_LAST_ERROR" >&2
  return 1
}

# _container_lock_mtime_epoch <path> -- portable mtime as an epoch integer
# (GNU `stat -c %Y` vs BSD/macOS `stat -f %m`), used only to age-check the
# steal-mutex below (seconds granularity; `find -mmin` is minutes-only and
# not reliably fractional across GNU/BSD, so this avoids that portability
# gap for the short mutex window).
_container_lock_mtime_epoch() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# _container_lock_steal <lock_dir> <label> -- reclaim a lock container_lock_acquire
# has already determined is STALE, with the destructive rm-rf+mkdir sequence
# serialized behind a separate mutex directory ("$lock_dir.steal-mutex") so
# two concurrent stealers can never both perform it (research-harness-
# template#739). `mkdir` is atomic: exactly one racer's `mkdir "$mutex"` can
# succeed at a time. The racer that wins it re-verifies staleness (time has
# passed since the caller's own check -- another racer may have already won
# and finished) and only then does the actual rm-rf+mkdir reclaim. A racer
# that loses the mutex either waits (bounded retries) or, if the mutex looks
# abandoned (older than CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC -- its holder
# was killed mid-steal), reclaims the MUTEX itself the same self-healing way
# the outer lock reclaims a stale holder, then retries.
#
# Returns the same contract container_lock_acquire's old inline steal did:
# 0 = stole it; 3 = DENIED (lost the race, or a live lock now occupies it);
# 1 = an unrelated filesystem failure (permissions, read-only FS, ENOSPC).
_container_lock_steal() {
  local lock_dir="$1" label="$2"
  # NB: a second `local` here, not folded into the line above -- within a
  # single `local` statement bash evaluates each RHS against the value the
  # name held BEFORE this `local` took effect, so `mutex="${lock_dir}..."`
  # on the same line would derive from the caller's dynamically-scoped
  # `lock_dir`, not this function's own parameter (SC2318). It happens to
  # match today only because the sole caller passes its identically-named
  # local; splitting the statement makes the derivation depend on `$1`, the
  # actual contract, so it stays correct under any future call site.
  local mutex="${lock_dir}.steal-mutex"
  local attempt mutex_err mutex_mtime now age
  for attempt in $(seq 1 20); do
    if mutex_err="$(mkdir "$mutex" 2>&1)"; then
      # Holding the mutex: re-verify staleness -- another racer may have
      # already won this exact steal and finished while we were retrying.
      if container_lock_fresh "$lock_dir"; then
        rm -rf "$mutex" 2>/dev/null
        echo "container-lock: DENIED -- lost the steal race for a stale lock: $lock_dir" >&2
        return 3
      fi
      # Distinguish a genuine rm/mkdir failure unrelated to any racer
      # (permissions, read-only FS) from a lost race below -- if rm didn't
      # actually clear the directory, a follow-up mkdir failure isn't "lost
      # the race", it's the same underlying error rm just hit, and
      # misreporting it as a race would hide a real filesystem problem from
      # the caller (review, carried over from the pre-mutex implementation).
      if ! rm -rf "$lock_dir" 2>/dev/null || [ -e "$lock_dir" ]; then
        CONTAINER_LOCK_LAST_ERROR="failed to remove stale lock at $lock_dir (permissions or read-only filesystem?)"
        echo "container-lock: DENIED -- $CONTAINER_LOCK_LAST_ERROR" >&2
        rm -rf "$mutex" 2>/dev/null
        return 1
      fi
      if mkdir "$lock_dir" 2>/dev/null; then
        _container_lock_stamp "$lock_dir" "$label"
        echo "container-lock: stole STALE lock (previous holder left it >${CONTAINER_LOCK_STALE_MIN}m ago): $lock_dir" >&2
        rm -rf "$mutex" 2>/dev/null
        return 0
      fi
      # rm confirmed the directory gone, but our own mkdir still failed --
      # under the mutex, no OTHER racer can be concurrently reclaiming this
      # same lock_dir, so this is never "lost the race": it is an unrelated
      # mkdir failure (ENOSPC, a transient I/O error, ...).
      CONTAINER_LOCK_LAST_ERROR="failed to re-create lock at $lock_dir after removing the stale one"
      echo "container-lock: DENIED -- $CONTAINER_LOCK_LAST_ERROR" >&2
      rm -rf "$mutex" 2>/dev/null
      return 1
    fi
    # Lost the mutex to another racer (or a real fs error creating it).
    if [ -d "$mutex" ]; then
      now=$(date +%s 2>/dev/null)
      mutex_mtime=$(_container_lock_mtime_epoch "$mutex")
      if [ -n "$now" ] && [ -n "$mutex_mtime" ]; then
        age=$(( now - mutex_mtime ))
        if [ "$age" -ge "$CONTAINER_LOCK_STEAL_MUTEX_STALE_SEC" ]; then
          # Abandoned mutex (its holder was killed mid-steal) -- reclaim it
          # and retry immediately. rm -rf here is safe even if another
          # waiter races us to it: mkdir right after is still the sole
          # atomic arbiter of who proceeds.
          rm -rf "$mutex" 2>/dev/null
          continue
        fi
      fi
      sleep 0.05
      continue
    fi
    # mkdir failed and the mutex path still doesn't exist -- not contention,
    # a real filesystem problem (permissions, read-only FS, missing parent).
    CONTAINER_LOCK_LAST_ERROR="failed to create steal mutex at $mutex: ${mutex_err:-unknown error}"
    echo "container-lock: DENIED -- $CONTAINER_LOCK_LAST_ERROR" >&2
    return 1
  done
  echo "container-lock: DENIED -- timed out waiting for the steal mutex on $lock_dir (contended by a concurrent stealer); try again." >&2
  return 3
}

# _container_lock_stamp <lock_dir> <label> -- internal helper shared by
# container_lock_acquire's fresh-acquire and steal paths. Writes the existing
# human-readable `owner` file (unchanged, used only for the DENIED diagnostic
# message above) plus a NEW `.owner-token` file: a value unique to THIS
# acquisition (label + PID + wall-clock + two $RANDOM draws -- good enough to
# tell one acquisition apart from another; not a security credential, this
# lock has no adversarial holder). Sets CONTAINER_LOCK_TOKEN so the caller can
# capture it (e.g. `LOCK_TOKEN="$CONTAINER_LOCK_TOKEN"`) immediately after a
# successful container_lock_acquire and pass it to every later
# container_lock_refresh call for this lock (research-harness-template#763).
_container_lock_stamp() {
  local lock_dir="$1" label="$2"
  CONTAINER_LOCK_TOKEN="${label}:$$:$(date +%s%N 2>/dev/null || date +%s):${RANDOM}${RANDOM}"
  printf '%s\n' "$label" > "$lock_dir/owner" 2>/dev/null || true
  printf '%s\n' "$CONTAINER_LOCK_TOKEN" > "$lock_dir/.owner-token" 2>/dev/null || true
}

# container_lock_refresh <lock_dir> <token> -- touch a HELD lock so it does
# not age out mid-run, mirroring run-lock.sh's own `refresh` verb (which the
# orchestrator's long-running Phase 2 loop calls at phase boundaries for the
# identical reason). Without this, an export/import that genuinely runs
# longer than CONTAINER_LOCK_STALE_MIN would have its own still-live lock
# misjudged as stale and stolen by a second, concurrent invocation.
#
# research-harness-template#763: touching $lock_dir's mtime unconditionally
# (the pre-fix behavior) cannot tell "the lock I originally acquired" from "a
# DIFFERENT run's lock that has since replaced mine at this same path" (e.g. a
# stale-lock steal race, or a phase boundary far enough apart that
# CONTAINER_LOCK_STALE_MIN elapsed between refresh calls) -- it silently
# extended whichever lock happened to occupy $lock_dir, regardless of who
# actually held it. `<token>` is the value container_lock_acquire wrote to
# `$lock_dir/.owner-token` via CONTAINER_LOCK_TOKEN at acquire time; refresh
# now only touches the directory when that token still matches what is
# currently stamped there.
#
# Returns nonzero and prints a diagnostic -- WITHOUT touching the lock -- when
# the token is missing, the lock is gone, or the stamped token no longer
# matches (this run lost ownership). The caller MUST treat a nonzero return as
# fatal (e.g. `container_lock_refresh "$LOCK_DIR" "$LOCK_TOKEN" || fail "..."`),
# not a warning to log and keep going: continuing to write believing you still
# hold exclusive access is exactly the corruption this lock exists to prevent.
# Does NOT recreate a missing lock (mirrors run-lock.sh's own refresh:
# resurrecting a released/stolen lock would forge a phantom second owner) -- a
# run that still legitimately owns the topic always has the dir present.
container_lock_refresh() {
  # token defaults to empty (not a bare "$2") so a call missing its second
  # argument, for whatever reason, hits this function's own graceful "no
  # ownership token supplied" refusal below instead of a hard `set -u`
  # unbound-variable abort -- observed reproducibly in a real CI import run
  # (research-harness-template PR #796 review) where every static call site
  # in this repo passes both arguments, yet the abort still occurred; the
  # exact call path was not pinned down, but this default is unconditionally
  # correct regardless of cause and mirrors container_lock_release's own
  # "${2:-}" default just below.
  local lock_dir="$1" token="${2:-}" current
  if [ -z "$token" ]; then
    echo "container-lock: REFUSED to refresh $lock_dir -- no ownership token supplied. Callers must pass the token container_lock_acquire set via CONTAINER_LOCK_TOKEN; refreshing without one cannot distinguish this run's lock from a different run's." >&2
    return 1
  fi
  if [ ! -d "$lock_dir" ]; then
    echo "container-lock: LOST ownership of $lock_dir -- the lock is gone (released, or reclaimed by another run); refusing to refresh." >&2
    return 1
  fi
  current="$(cat "$lock_dir/.owner-token" 2>/dev/null || true)"
  if [ "$current" != "$token" ]; then
    echo "container-lock: LOST ownership of $lock_dir -- it is now held by a different run (this run's token: '$token'; currently stamped: '${current:-<none>}'). Another run stole this lock; refusing to refresh or keep writing under a false assumption of exclusive access." >&2
    return 1
  fi
  # Retried up to 3x with a brief backoff (PR #796 review follow-up): this
  # call happens once per finding during a real import/export (up to
  # dozens of touches in well under a second), and a bare single-attempt
  # `touch` reproducibly hit a transient failure under that pattern on
  # GitHub Actions' runners (never on local disk) -- turning an otherwise
  # healthy, in-progress import into a hard failure on a one-off I/O blip.
  # Only a PERSISTENT touch failure (permissions, read-only filesystem,
  # disk full) is treated as fatal; a single transient hiccup is retried
  # rather than immediately propagated.
  local attempt
  for attempt in 1 2 3; do
    touch "$lock_dir" 2>/dev/null && return 0
    [ "$attempt" -lt 3 ] && sleep 0.05
  done
  echo "container-lock: FAILED to refresh $lock_dir after 3 attempts -- touch failed (permissions or read-only filesystem?); the lock's mtime was NOT extended and it may now be judged stale by a concurrent acquirer. Treat this as loss of ownership." >&2
  return 1
}

# container_lock_release <lock_dir> [token] -- drop the lock. rm -rf, not
# rmdir: the lock dir is not empty (container_lock_acquire writes `owner` and
# `.owner-token` files inside it), so a plain rmdir would silently fail to
# remove it, leaving a non-stale-looking lock behind forever (the exact wedge
# this file exists to prevent -- mirrors run-lock.sh's own `release`
# command). No-op if it is already gone (this run released it, or another run
# already stole it) -- never resurrects a lock this process no longer owns.
#
# `token` is optional (back-compat: an existing caller that only ever
# acquires/releases its own lock and never refreshes -- e.g.
# research-projection.js's .projection-lock -- need not change). When given
# and the lock is currently stamped with a DIFFERENT token, this process does
# not own it (already released and re-acquired by someone else, or stolen out
# from under it): skip the removal rather than destroy another run's live
# lock -- silently deleting a different run's mutual exclusion would be worse
# than the refresh bug research-harness-template#763 fixes, not better.
container_lock_release() {
  local lock_dir="$1" token="${2:-}" current
  if [ -n "$token" ] && [ -d "$lock_dir" ]; then
    current="$(cat "$lock_dir/.owner-token" 2>/dev/null || true)"
    if [ "$current" != "$token" ]; then
      echo "container-lock: SKIPPED release of $lock_dir -- it is currently held by a different run than the one that acquired it (stamped token: '${current:-<missing>}'); not removing another run's lock." >&2
      return 0
    fi
  fi
  rm -rf "$lock_dir" 2>/dev/null || true
}
