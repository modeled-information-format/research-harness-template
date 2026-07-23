#!/usr/bin/env bash
# gate-m28-timeout-path-check.sh — regression eval for
# research-harness-template#774: gate_m28's 28h hang-regression check used to
# hard-fail (`bad`) whenever neither `timeout` nor `gtimeout` was on PATH,
# even though the resolver script itself was completely correct and CI
# (ubuntu-latest, which always ships GNU coreutils `timeout`) would pass
# cleanly. A contributor on stock macOS with no Homebrew coreutils on PATH
# saw a real-looking FAIL from a CI-parity gate for a change that would
# actually pass CI. Fixed to match 27a's sha256sum/shasum precedent: degrade
# gracefully (skip, via `info`) instead of hard-failing when the optional
# tool is unavailable -- the same fallback scripts/write-finding.sh already
# uses for this exact pair of binaries.
#
# This eval hides BOTH `timeout` and `gtimeout` from PATH (whichever the
# ambient environment happens to have -- this workspace's own dev machines
# have both via Homebrew coreutils) and asserts gate_m28 still passes the
# gate overall (no hard FAIL) and explicitly reports the check as skipped,
# rather than emitting the old "requires 'timeout' on PATH ... cannot
# verify" failure message.
#
# Exit 0 = the gate degrades gracefully. Exit 1 = it still hard-fails (the
# original #774 defect). Exit 2 = test setup itself could not construct a
# PATH lacking both binaries (environment problem, not a verify.sh defect).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  gate-m28-timeout-path-check: %s\n' "$1"; }

# Build a PATH with every directory that supplies a `timeout` or `gtimeout`
# binary removed, but every OTHER command those directories provide restored
# via a scratch directory of symlinks -- so nothing except the two timing
# wrappers themselves goes missing, regardless of platform layout (Homebrew
# gnubin on macOS colocates `gtimeout`/`timeout` next to `jq`; a from-scratch
# PATH entry on Linux could equally colocate `timeout` next to other
# essentials). This keeps the eval portable instead of hardcoding one
# platform's directory layout.
SCRATCH="$(mktemp -d)" || { note "FAIL: could not create scratch dir"; exit 2; }
trap 'rm -rf "$SCRATCH"' EXIT

NEWPATH=""
IFS=':' read -r -a DIRS <<< "$PATH"
for d in "${DIRS[@]}"; do
  [ -n "$d" ] && [ -d "$d" ] || continue
  if [ -e "$d/timeout" ] || [ -e "$d/gtimeout" ]; then
    for f in "$d"/*; do
      [ -e "$f" ] || continue
      base="$(basename "$f")"
      case "$base" in
        timeout|gtimeout) continue ;;
      esac
      [ -e "$SCRATCH/$base" ] || ln -s "$f" "$SCRATCH/$base" 2>/dev/null
    done
    continue
  fi
  NEWPATH="${NEWPATH:+$NEWPATH:}$d"
done
NEWPATH="$SCRATCH:$NEWPATH"

# Sanity: the constructed PATH truly lacks both binaries before trusting
# anything the gate reports under it.
if PATH="$NEWPATH" command -v timeout >/dev/null 2>&1; then
  note "FAIL: test setup could not hide 'timeout' from PATH -- eval environment problem, not a verify.sh defect"
  exit 2
fi
if PATH="$NEWPATH" command -v gtimeout >/dev/null 2>&1; then
  note "FAIL: test setup could not hide 'gtimeout' from PATH -- eval environment problem, not a verify.sh defect"
  exit 2
fi

OUT="$(PATH="$NEWPATH" bash scripts/verify.sh --gates 'gate_m28$' 2>&1)"
RC=$?

if [ "$RC" -ne 0 ]; then
  note "gate_m28 hard-failed with neither timeout nor gtimeout on PATH (rc=$RC) -- expected a graceful skip, not a gate failure"
  printf '%s\n' "$OUT" | tail -20 | sed 's/^/    /'
  fail=1
fi
if printf '%s' "$OUT" | grep -qi "requires 'timeout' on PATH"; then
  note "gate_m28 still emits the old hard-fail message when timeout is absent -- issue #774 regressed"
  fail=1
fi
if ! printf '%s' "$OUT" | grep -q "resolver hang-regression check skipped"; then
  note "gate_m28 did not report the hang-regression check as skipped when neither timeout nor gtimeout is on PATH"
  fail=1
fi

[ "$fail" -eq 0 ] && note "gate_m28 degrades gracefully (skips 28h, does not hard-fail the gate) when neither timeout nor gtimeout is on PATH"
exit "$fail"
