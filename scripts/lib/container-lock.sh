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

# container_lock_acquire <lock_dir> [label] -- mkdir-atomic acquire; steals a
# STALE lock (mtime older than the window) via the same race-safe
# rm-rf-then-re-mkdir pattern run-lock.sh uses (only one racer's mkdir
# wins). Writes an `owner` file inside the lock for the diagnostic message.
# Prints an error to stderr and returns nonzero (3 = held by a live
# holder/lost the steal race, 1 = mkdir failed for an unrelated reason e.g.
# missing parent dir or a read-only FS) on denial/failure; the caller
# decides how to fail (this repo's convention is `fail "$msg"`). On a rc=1
# failure, also sets CONTAINER_LOCK_LAST_ERROR to the underlying mkdir error
# text so the caller's own fail() message can include it (the pre-refactor
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
    # Steal: rm -rf then re-mkdir, race-safe (only one racer's mkdir wins).
    # Distinguish that genuine race from an rm/mkdir failure unrelated to
    # any racer (permissions, read-only FS) -- if rm didn't actually clear
    # the directory, a follow-up mkdir failure isn't "lost the race", it's
    # the same underlying error rm just hit, and misreporting it as a race
    # would hide a real filesystem problem from the caller (review).
    if ! rm -rf "$lock_dir" 2>/dev/null || [ -e "$lock_dir" ]; then
      CONTAINER_LOCK_LAST_ERROR="failed to remove stale lock at $lock_dir (permissions or read-only filesystem?)"
      echo "container-lock: DENIED -- $CONTAINER_LOCK_LAST_ERROR" >&2
      return 1
    fi
    if mkdir "$lock_dir" 2>/dev/null; then
      _container_lock_stamp "$lock_dir" "$label"
      echo "container-lock: stole STALE lock (previous holder left it >${CONTAINER_LOCK_STALE_MIN}m ago): $lock_dir" >&2
      return 0
    fi
    # rm confirmed the directory gone, but mkdir still failed -- distinguish
    # a genuine lost race (a concurrent racer's own mkdir won in between, so
    # $lock_dir exists again) from an unrelated mkdir failure (ENOSPC, a
    # transient I/O error, ...) where $lock_dir is STILL absent -- the
    # latter isn't a race at all and misreporting it as one would hide the
    # real error from the caller (Copilot review, round 2).
    if [ -d "$lock_dir" ]; then
      echo "container-lock: DENIED -- lost the steal race for a stale lock: $lock_dir" >&2
      return 3
    fi
    CONTAINER_LOCK_LAST_ERROR="failed to re-create lock at $lock_dir after removing the stale one (not a race -- the directory is still absent)"
    echo "container-lock: DENIED -- $CONTAINER_LOCK_LAST_ERROR" >&2
    return 1
  fi
  CONTAINER_LOCK_LAST_ERROR="${lock_err:-mkdir failed for an unknown reason}"
  echo "container-lock: failed to create lock at $lock_dir: $CONTAINER_LOCK_LAST_ERROR" >&2
  return 1
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
  local lock_dir="$1" token="$2" current
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
  touch "$lock_dir" 2>/dev/null || true
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
    if [ -n "$current" ] && [ "$current" != "$token" ]; then
      echo "container-lock: SKIPPED release of $lock_dir -- it is currently held by a different run than the one that acquired it; not removing another run's lock." >&2
      return 0
    fi
  fi
  rm -rf "$lock_dir" 2>/dev/null || true
}
