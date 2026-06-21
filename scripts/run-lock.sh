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
# Usage:
#   run-lock.sh acquire <reports_dir> [label]   # exit 0 acquired (or stole stale); 3 held by live run / lost steal race; 2 usage
#   run-lock.sh refresh <reports_dir>           # touch a HELD lock; no-op if it is already gone (never resurrects)
#   run-lock.sh release <reports_dir>           # drop the lock
#   run-lock.sh steal   <reports_dir> [label]   # force re-acquire (recovery; e.g. operator-driven /resume)
set -uo pipefail
STALE_MIN="${RUN_LOCK_STALE_MIN:-240}"

CMD="${1:?usage: run-lock.sh acquire|refresh|release|steal <reports_dir> [label]}"
DIR="${2:?usage: run-lock.sh <cmd> <reports_dir> [label]}"
LABEL="${3:-run}"
LOCK="$DIR/.run-lock"

# A lock is FRESH if its directory mtime is within the staleness window.
fresh() { [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin "-$STALE_MIN" 2>/dev/null)" ]; }
write_owner() { printf '%s\n' "$LABEL" > "$LOCK/owner" 2>/dev/null || true; }

case "$CMD" in
  acquire)
    mkdir -p "$DIR" 2>/dev/null || true
    if mkdir "$LOCK" 2>/dev/null; then   # atomic: succeeds only if no holder existed
      write_owner
      echo "run-lock: acquired ($DIR)" >&2
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
      write_owner
      echo "run-lock: stole STALE lock on $DIR (previous holder left it >${STALE_MIN}m ago)" >&2
      exit 0
    fi
    echo "run-lock: DENIED — lost the steal race for a stale lock on $DIR (another run is recovering it)." >&2
    exit 3
    ;;
  refresh)
    # Touch a HELD lock so it does not age out mid-run. Do NOT recreate a missing
    # lock: if it is gone, this run released it or another run already stole it, and
    # resurrecting it would forge a phantom second owner. A run that still legitimately
    # owns the topic always has the dir present (it acquired it and has not released).
    [ -d "$LOCK" ] && touch "$LOCK"
    exit 0
    ;;
  release)
    rm -rf "$LOCK"
    exit 0
    ;;
  steal)
    rm -rf "$LOCK"
    mkdir -p "$LOCK" 2>/dev/null || true
    touch "$LOCK"; write_owner
    echo "run-lock: stole lock on $DIR (forced)" >&2
    exit 0
    ;;
  *)
    echo "run-lock: unknown command '$CMD' (acquire|refresh|release|steal)" >&2
    exit 2
    ;;
esac
