#!/usr/bin/env bash
# gate-m27-root-safe-unreadable-check.sh — regression eval for
# research-harness-template#777: gate_m27's 27f "unreadable file fails
# closed" check used `chmod 000` to simulate a permission-denied read, but
# root (or any DAC_OVERRIDE-capable process, e.g. a root-uid Docker/
# devcontainer run) can still read a 000-mode file, silently invalidating
# the check's premise and turning a working, unmodified digest script into
# a false FAIL.
#
# scripts/lib/unreadable-probe.sh's m27_classify_unreadable_probe is pure
# classification logic (no filesystem access) precisely so this scenario is
# testable without needing to actually run as root: we feed it synthetic
# bypassed/rc/out inputs and check the verdict.
#
# Covers:
#   1. bypassed=1 (root/DAC-override read the "unreadable" file fine) ->
#      "skip", never "bad" -- the exact false-FAIL this issue reports.
#   2. bypassed=0 with a real permission-denied outcome (rc!=0) -> "ok".
#   3. bypassed=0 with the original swallow-bug outcome (rc=0, out="sha256:")
#      -> "bad" -- the real defect class 27f exists to catch is still caught.
#   4. End-to-end: `verify.sh --gates 'gate_m27$'` still passes when actually
#      run as the current (non-root) user -- no regression to the normal path.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
# shellcheck source=scripts/lib/unreadable-probe.sh
. scripts/lib/unreadable-probe.sh

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  gate-m27-root-safe-unreadable-check: %s\n' "$1"; }

# Case 1: the false-FAIL this issue reports -- root/DAC-override could still
# read the file (bypassed=1) despite chmod 000; rc/out are whatever a
# successful root read happened to produce (a real digest, rc=0).
got="$(m27_classify_unreadable_probe 1 0 "sha256:2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881")"
if [ "$got" != "skip" ]; then
  note "bypassed=1 should classify as 'skip' (got '$got') -- this is #777's false FAIL"
  fail=1
fi

# Case 2: genuinely denied, digest script correctly failed closed.
got="$(m27_classify_unreadable_probe 0 1 "")"
if [ "$got" != "ok" ]; then
  note "bypassed=0 rc=1 out='' should classify as 'ok' (got '$got')"
  fail=1
fi

# Case 3: genuinely denied, but the digest script produced the original
# swallow-bug's malformed empty digest at rc=0 -- must still be caught.
got="$(m27_classify_unreadable_probe 0 0 "sha256:")"
if [ "$got" != "bad" ]; then
  note "bypassed=0 rc=0 out='sha256:' should classify as 'bad' (got '$got')"
  fail=1
fi

# Case 4: end-to-end, run as whoever is actually running this eval (not
# root in CI) -- the real gate must still pass with no regression.
if [ "$(id -u)" != "0" ]; then
  if ! bash scripts/verify.sh --gates 'gate_m27$' >"$TMP/gate-m27.out" 2>&1; then
    note "verify.sh --gates 'gate_m27$' failed as a non-root user: $(tail -5 "$TMP/gate-m27.out")"
    fail=1
  fi
else
  note "running as root -- skipping the end-to-end non-root regression check (case 4)"
fi

[ "$fail" -eq 0 ] && note "27f classifies a chmod-000-bypassed read as SKIP, a real denial as ok/bad correctly, and the full gate still passes non-root"
exit "$fail"
