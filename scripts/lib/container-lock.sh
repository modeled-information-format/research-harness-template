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
# Usage (sourced, not executed):
#   . "$ROOT/scripts/lib/container-lock.sh"
#   container_lock_acquire "$LOCK_DIR" "export" || fail "another export/import is in progress for topic '$TOPIC' (lock held: $LOCK_DIR)"
#   trap 'container_lock_release "$LOCK_DIR"' EXIT
#   ...
#   container_lock_release "$LOCK_DIR"

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
    printf '%s\n' "$label" > "$lock_dir/owner" 2>/dev/null || true
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
      printf '%s\n' "$label" > "$lock_dir/owner" 2>/dev/null || true
      echo "container-lock: stole STALE lock (previous holder left it >${CONTAINER_LOCK_STALE_MIN}m ago): $lock_dir" >&2
      return 0
    fi
    # rm confirmed the directory gone, but mkdir still failed -- a
    # concurrent racer's own mkdir must have won in between. A genuine lost
    # race, not our own error.
    echo "container-lock: DENIED -- lost the steal race for a stale lock: $lock_dir" >&2
    return 3
  fi
  CONTAINER_LOCK_LAST_ERROR="${lock_err:-mkdir failed for an unknown reason}"
  echo "container-lock: failed to create lock at $lock_dir: $CONTAINER_LOCK_LAST_ERROR" >&2
  return 1
}

# container_lock_refresh <lock_dir> -- touch a HELD lock so it does not age
# out mid-run, mirroring run-lock.sh's own `refresh` verb (which the
# orchestrator's long-running Phase 2 loop calls at phase boundaries for the
# identical reason). Without this, an export/import that genuinely runs
# longer than CONTAINER_LOCK_STALE_MIN would have its own still-live lock
# misjudged as stale and stolen by a second, concurrent invocation --
# review caught this gap: staleness alone, with no refresh anywhere in the
# two callers' long-running per-resource loops, meant "long-running" and
# "stale" were indistinguishable. Does NOT recreate a missing lock (mirrors
# run-lock.sh's own refresh: resurrecting a released/stolen lock would forge
# a phantom second owner) -- a run that still legitimately owns the topic
# always has the dir present.
container_lock_refresh() { [ -d "$1" ] && touch "$1" 2>/dev/null || true; }

# container_lock_release <lock_dir> -- drop the lock. rm -rf, not rmdir: the
# lock dir is not empty (container_lock_acquire writes an `owner` file
# inside it), so a plain rmdir would silently fail to remove it, leaving a
# non-stale-looking lock behind forever (the exact wedge this file exists to
# prevent -- mirrors run-lock.sh's own `release` command). No-op if it is
# already gone (this run released it, or another run already stole it) --
# never resurrects a lock this process no longer owns.
container_lock_release() { rm -rf "$1" 2>/dev/null || true; }
