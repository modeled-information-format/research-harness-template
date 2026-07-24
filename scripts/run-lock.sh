#!/usr/bin/env bash
# run-lock.sh — topic-level mutual-exclusion lock for a research run.
#
# WHY: a topic's findings live in one shared directory (reports/<topic>/findings/).
# Two pipelines running concurrently on the SAME topic corrupt each other — the
# documented CONCURRENCY INCIDENT stripped the verification block from 10 findings
# and DELETED 2 findings (no backup recoverable). The root cause was multiple
# independent runs writing one topic's findings/ at once. Every entry point that
# MUTATES a topic's findings — the orchestrator (any mode) and the standalone
# /falsify gate — acquires this lock first, so a second concurrent run on the same
# topic REFUSES to start rather than racing the live writer.
#
# This mirrors the .gate-active phase marker: an atomically-created marker whose
# freshness (mtime) ages out, so a CRASHED run does not wedge the topic forever —
# a later run steals a stale lock. A LIVE run refreshes the lock at each phase
# boundary so it never ages out underneath it.
#
# The lock is a DIRECTORY: `mkdir` is an atomic test-and-set across processes
# (`touch` is not — it always succeeds and cannot detect a prior holder). Freshness
# is the directory's mtime; an `owner` file inside records a human-readable label
# for the diagnostic message.
#
# Staleness window: RUN_LOCK_STALE_MIN (default 240 = 4h). 240 is chosen to match
# the gate window's fixed `-mmin -240` (.gate-active), but that hook window is NOT
# env-tunable — so if you raise RUN_LOCK_STALE_MIN, keep it >= 240; lowering it
# shortens crash self-heal but risks a long phase aging the lock out mid-run. A live
# run MUST refresh within this window at every phase boundary or risk being stolen.
#
# Ownership token (research-harness-template#798, same defect class #763 fixed in
# scripts/lib/container-lock.sh's container_lock_refresh): `acquire`/`steal` stamp
# each successful (re)acquisition with a unique per-acquisition token, written to
# `$LOCK/.owner-token` AND printed on stdout (diagnostics stay on stderr, unchanged).
# Unlike container-lock.sh (sourced into one long-lived shell, so an in-memory
# variable survives from acquire to refresh), this script runs as separate CLI
# process invocations with no shared shell state — the token has to persist on
# disk, and every caller MUST capture it from acquire/steal's stdout and pass it
# back on every later `refresh`/`release` call:
#   TOKEN=$(scripts/run-lock.sh acquire "$REPORTS_DIR" "label") || exit 3
#   scripts/run-lock.sh refresh "$REPORTS_DIR" "$TOKEN" || exit 1   # lost ownership -- STOP
#   scripts/run-lock.sh release "$REPORTS_DIR" "$TOKEN"
# `refresh` REFUSES (without touching the lock) if the token is missing or no
# longer matches what is currently stamped there — otherwise a refresh cannot
# distinguish "the lock I originally acquired" from "a different run's lock that
# has since replaced mine at this same path" (a stale-lock steal race, or a phase
# boundary far enough apart for RUN_LOCK_STALE_MIN to elapse between refreshes),
# and would silently extend whichever lock currently occupies the path. `release`'s
# token is optional (back-compat for a caller that never refreshes): when given
# and it does not match, release SKIPS removal rather than destroy a different
# run's live lock.
#
# Usage:
#   run-lock.sh acquire <reports_dir> [label]        # exit 0 acquired (or stole stale, prints TOKEN on stdout);
#                                                     # 3 held by live run / lost steal race; 2 usage
#   run-lock.sh refresh <reports_dir> <token>        # touch a HELD lock IF <token> still matches; exit 1 (fatal,
#                                                     # never resurrects) if the lock is already gone, OR if the
#                                                     # token is missing/mismatched — either way ownership is lost
#                                                     # and the caller MUST treat it as fatal, not log-and-continue
#   run-lock.sh release <reports_dir> [token]        # drop the lock; if [token] is given and mismatched, skip
#                                                     # removal (does not own it) instead of deleting another run's lock
#   run-lock.sh steal   <reports_dir> [label]        # force re-acquire (recovery; e.g. operator-driven /resume);
#                                                     # prints a NEW token on stdout on success
#                                                     # refuses (exit 3) if findings/ or research-progress.md
#                                                     # were written within RUN_LOCK_STEAL_GUARD_MIN (default 10,
#                                                     # matching start.md/resume.md's own "quiet is normal up to
#                                                     # ~10m" guidance) — override with FORCE=1 once you've
#                                                     # independently confirmed via disk state that the owner is
#                                                     # dead (issue #392)
set -uo pipefail

# Sanitize a minutes value: an empty/non-numeric/zero value would make `find -mmin`
# error and a freshness check mis-judge a LIVE target as stale (then act on it — the
# corruption this prevents). Fall back to the given default rather than fail open. The
# case pattern alone only rejects the exact literal "0" -- "00"/"0000" are all-digit and
# slip through, then `find -mmin -00` matches nothing (a file can't be modified "<0
# minutes ago"), silently defeating the same fail-safe intent. The arithmetic check
# catches every all-digit zero, not just the single-character form (issue #382 review).
sanitize_minutes() {
  local val="$1" default="$2"
  case "$val" in ''|*[!0-9]*) val="$default" ;; esac
  [ "$val" -eq 0 ] 2>/dev/null && val="$default"
  printf '%s' "$val"
}
STALE_MIN="$(sanitize_minutes "${RUN_LOCK_STALE_MIN:-240}" 240)"
GUARD_MIN="$(sanitize_minutes "${RUN_LOCK_STEAL_GUARD_MIN:-10}" 10)"

CMD="${1:?usage: run-lock.sh acquire|refresh|release|steal <reports_dir> [label]}"
DIR="${2:?usage: run-lock.sh <cmd> <reports_dir> [label]}"
LABEL="${3:-run}"
LOCK="$DIR/.run-lock"

# A lock is FRESH if its directory mtime is within the staleness window. Fail SAFE: if
# `find` errors, treat the lock as fresh/owned (return 0) so acquire DENIES, never steals.
fresh() {
  [ -d "$LOCK" ] || return 1
  local hit
  hit=$(find "$LOCK" -maxdepth 0 -mmin "-$STALE_MIN" 2>/dev/null) || return 0
  [ -n "$hit" ]
}
# A PATH shows recent activity if it, or (for a directory) anything directly inside
# it, has an mtime within the guard window. `-maxdepth 1` checks both the directory's
# OWN mtime (catches a file being created/renamed/deleted — e.g. falsify.sh's documented
# temp+mv verdict write, which IS a rename and so bumps it) AND every individual file's
# own mtime one level down (catches an in-place content-only write to an EXISTING file,
# which does NOT bump the parent directory's mtime — a plain `> existing_file` truncate
# leaves the directory entry itself untouched). Checking the directory's mtime alone
# would miss that second case and let `steal` race a writer doing in-place updates.
# `-maxdepth 1` bounds this to one level (findings/ is a flat directory of *.json per
# convention), not an unbounded recursive walk. Fail SAFE like `fresh()`: if `find`
# errors, treat it as recent (return 0) so `steal` refuses rather than racing a writer
# it couldn't inspect.
recent_activity() {
  [ -e "$1" ] || return 1
  local hit
  hit=$(find "$1" -maxdepth 1 -mmin "-$GUARD_MIN" 2>/dev/null) || return 0
  [ -n "$hit" ]
}
# stamp_owner — write the human-readable `owner` label (unchanged, used only for the
# DENIED diagnostic) plus a NEW `.owner-token`: a value unique to THIS acquisition
# (label + PID + wall-clock + two $RANDOM draws — good enough to tell one acquisition
# apart from another; not a security credential, this lock has no adversarial holder).
# Sets RUN_LOCK_TOKEN and prints it on stdout so the caller can capture it immediately
# after a successful acquire/steal and pass it to every later refresh/release call
# (research-harness-template#798).
stamp_owner() {
  printf '%s\n' "$LABEL" > "$LOCK/owner" 2>/dev/null || true
  RUN_LOCK_TOKEN="${LABEL}:$$:$(date +%s%N 2>/dev/null || date +%s):${RANDOM}${RANDOM}"
  # Fail CLOSED if the token can't be persisted (disk full, read-only filesystem):
  # a token that only ever existed in this shell's memory can never be matched by
  # a later refresh/release CLI invocation (separate process, no shared shell
  # state — see file header), so an un-persisted "success" here would silently
  # produce a lock that can never again be safely refreshed or released. Return
  # non-zero and print nothing; every caller below MUST treat that as acquisition
  # failure and release the lock it just created rather than leave a stuck,
  # unusable acquisition behind.
  if ! printf '%s\n' "$RUN_LOCK_TOKEN" > "$LOCK/.owner-token" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$RUN_LOCK_TOKEN"
}

case "$CMD" in
  acquire)
    mkdir -p "$DIR" || { echo "run-lock: cannot create $DIR — lock protocol inactive, refusing to proceed." >&2; exit 2; }
    if mkdir "$LOCK" 2>/dev/null; then   # atomic: succeeds only if no holder existed
      echo "run-lock: acquired ($DIR)" >&2
      if ! stamp_owner; then
        echo "run-lock: FAILED to persist ownership token for $DIR (disk full or read-only filesystem?) — releasing the lock rather than leave an un-refreshable/un-releasable acquisition behind." >&2
        rm -rf "$LOCK"
        exit 2
      fi
      exit 0
    fi
    if fresh; then
      echo "run-lock: DENIED — a live run owns $DIR (held by '$(cat "$LOCK/owner" 2>/dev/null || echo unknown)'; lock fresh within ${STALE_MIN}m). Refusing to start a second concurrent run on this topic — it would corrupt the shared findings/. Wait for that run to finish; if it is dead, the lock ages out after ${STALE_MIN}m, or run: scripts/run-lock.sh steal '$DIR'." >&2
      exit 3
    fi
    # Stale marker from a crashed run — steal it, but keep mutual exclusion: remove it
    # and re-acquire through the SAME atomic mkdir, so two runs that both see it stale
    # cannot both win (only one mkdir succeeds; the loser is denied).
    rm -rf "$LOCK"
    if mkdir "$LOCK" 2>/dev/null; then
      echo "run-lock: stole STALE lock on $DIR (previous holder left it >${STALE_MIN}m ago)" >&2
      if ! stamp_owner; then
        echo "run-lock: FAILED to persist ownership token for $DIR (disk full or read-only filesystem?) — releasing the lock rather than leave an un-refreshable/un-releasable acquisition behind." >&2
        rm -rf "$LOCK"
        exit 2
      fi
      exit 0
    fi
    echo "run-lock: DENIED — lost the steal race for a stale lock on $DIR (another run is recovering it)." >&2
    exit 3
    ;;
  refresh)
    # Touch a HELD lock so it does not age out mid-run — but ONLY if <token> (arg 3)
    # still matches what is currently stamped in $LOCK/.owner-token. Without this check
    # (the pre-#798 behavior), touching $LOCK unconditionally cannot tell "the lock this
    # run originally acquired" from "a DIFFERENT run's lock that has since replaced it at
    # this same path" (a stale-lock steal race, or a phase boundary far enough apart for
    # RUN_LOCK_STALE_MIN to elapse between refreshes) — it would silently extend
    # whichever lock happens to occupy $DIR, regardless of who actually holds it (the
    # same defect class #763 fixed in container_lock_refresh). A missing/mismatched
    # token means this run LOST ownership; the caller MUST treat that as fatal (STOP),
    # not a warning to log and keep going.
    #
    # Does NOT recreate a missing lock: if it is gone, this run released it or another
    # run already stole it, and resurrecting it would forge a phantom second owner. A
    # run that still legitimately owns the topic always has the dir present.
    TOKEN="${3:-}"
    if [ -z "$TOKEN" ]; then
      echo "run-lock: REFUSED to refresh $DIR — no ownership token supplied. Callers must capture the token acquire/steal printed on stdout and pass it to every refresh call; refreshing without one cannot distinguish this run's lock from a different run's." >&2
      exit 1
    fi
    if [ ! -d "$LOCK" ]; then
      echo "run-lock: LOST ownership of $DIR — the lock is gone (released, or reclaimed by another run); refusing to refresh." >&2
      exit 1
    fi
    CURRENT="$(cat "$LOCK/.owner-token" 2>/dev/null || true)"
    if [ "$CURRENT" != "$TOKEN" ]; then
      echo "run-lock: LOST ownership of $DIR — it is now held by a different run (this run's token: '$TOKEN'; currently stamped: '${CURRENT:-<none>}'). Another run stole this lock; refusing to refresh or keep writing under a false assumption of exclusive access." >&2
      exit 1
    fi
    # Retry a transient touch failure before treating it as fatal (mirrors
    # container_lock_refresh's identical fix, PR #796 review): only a PERSISTENT
    # failure (permissions, read-only filesystem, disk full) should abort a run.
    attempt=1
    while [ "$attempt" -le 3 ]; do
      touch "$LOCK" 2>/dev/null && exit 0
      [ "$attempt" -lt 3 ] && sleep 0.05
      attempt=$((attempt+1))
    done
    echo "run-lock: FAILED to refresh $DIR after 3 attempts — touch failed (permissions or read-only filesystem?); the lock's mtime was NOT extended and it may now be judged stale by a concurrent acquirer. Treat this as loss of ownership." >&2
    exit 1
    ;;
  release)
    TOKEN="${3:-}"
    if [ -n "$TOKEN" ] && [ -d "$LOCK" ]; then
      CURRENT="$(cat "$LOCK/.owner-token" 2>/dev/null || true)"
      if [ "$CURRENT" != "$TOKEN" ]; then
        echo "run-lock: SKIPPED release of $DIR — it is currently held by a different run than the one that acquired it (stamped token: '${CURRENT:-<missing>}'); not removing another run's lock." >&2
        exit 0
      fi
    fi
    rm -rf "$LOCK"
    exit 0
    ;;
  steal)
    # Guard against a steal driven by a misread liveness signal rather than a
    # genuinely dead owner (issue #392: a supervisor read an orchestrator's
    # `TaskOutput(block: false)` status of "completed" as proof of death while
    # it was, in fact, still actively working — then stole its lock, producing
    # two concurrent writers on one topic's findings/). The lock's own mtime is
    # NOT a reliable "still alive right now" signal here: it only refreshes at
    # phase boundaries (which can be many minutes apart), so a live run can look
    # lock-stale-adjacent between refreshes. Recent writes under findings/ or to
    # research-progress.md are a much tighter, independent signal of real
    # activity — refuse the steal if either was touched within the guard
    # window, unless explicitly forced. GUARD_MIN and its sanitization are set once,
    # above, alongside STALE_MIN.
    if [ -z "${FORCE:-}" ]; then
      if recent_activity "$DIR/findings" || recent_activity "$DIR/research-progress.md"; then
        echo "run-lock: REFUSED — $DIR shows write activity within the last ${GUARD_MIN}m, which looks ALIVE regardless of the lock's own age. Forcing a steal here would race a genuinely-live writer. An agent-status signal (e.g. TaskOutput reporting \"completed\") is NOT sufficient evidence the owner is dead — confirm via disk state instead: the finding count must be STATIC and no new research-progress.md phase entry must appear for the SAME window before you override. To proceed anyway: FORCE=1 scripts/run-lock.sh steal '$DIR'." >&2
        exit 3
      fi
    fi
    # Forced recovery. Verify each step — if we cannot (re)create the lock the topic is
    # left UNLOCKED, so fail non-zero rather than claim success and let callers proceed.
    # (mkdir alone already stamps a current mtime; no extra touch needed.)
    rm -rf "$LOCK" 2>/dev/null
    if mkdir "$LOCK" 2>/dev/null; then
      echo "run-lock: stole lock on $DIR (forced)" >&2
      if ! stamp_owner; then
        echo "run-lock: FAILED to persist ownership token for $DIR (disk full or read-only filesystem?) — releasing the lock rather than leave an un-refreshable/un-releasable acquisition behind." >&2
        rm -rf "$LOCK"
        exit 3
      fi
      exit 0
    fi
    echo "run-lock: steal FAILED on $DIR — could not (re)create the lock; topic is NOT locked, do not proceed." >&2
    exit 3
    ;;
  *)
    echo "run-lock: unknown command '$CMD' (acquire|refresh|release|steal)" >&2
    exit 2
    ;;
esac
