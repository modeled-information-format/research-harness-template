#!/usr/bin/env bash
# gate-m11-engine-bin-hard-exit.sh — regression test for
# research-harness-template#748: gate_m11's 11j fail-safe check did
# `BAD_ENGINE="$(engine_bin "$(pwd)")" || exit 5` directly in verify.sh's own
# process (gates run as `"$g"`, not a subshell), so an engine_bin failure at
# that point terminated the ENTIRE verify.sh run instead of just failing
# gate_m11 -- silently skipping every gate after it (gate_m12 through
# gate_workflows) with no `bad` message for 11j itself and no final
# "N passed, M FAILED" summary. Two sibling gates (gate_m20, gate_m22) hit the
# identical engine_bin call and correctly `bad ...; return` instead, which is
# the pattern gate_m11 was missing.
#
# Reproduces the failure deterministically by pointing MIF_RH_CLI at a path
# that does not exist -- engine_bin's override branch takes MIF_RH_CLI
# unconditionally, so this forces engine_bin to fail regardless of whether a
# real mif-rh-cli is reachable on PATH or at <repo>/bin/mif-rh-cli in the
# environment actually running this eval. Runs verify.sh scoped to
# `gate_m11$|gate_m12$` (gate_m12 does not itself need the engine) via
# `--gates`, so a hard-exit vs. fail-and-continue is unambiguous from a single
# fast, isolated invocation. Asserts:
#   - verify.sh does NOT abort with exit 5 (engine_bin's own raw return code);
#   - gate_m12 actually ran (its "Milestone 12" info line is present) --
#     the concrete "~29 gates silently skipped" symptom, pinned narrowly to
#     the very next gate;
#   - the final "verify.sh: N passed, M FAILED"-shaped summary line is
#     printed (proves the scoped run reached its normal end, not a hard
#     process exit mid-gate);
#   - gate_m11 itself reports a `bad` (FAIL) line naming the engine as the
#     cause of the 11j check specifically, rather than silently vanishing.
#
# Exit 0 = gate_m11 fails closed on a broken engine (verify.sh's own process
# survives, gate_m12 runs, the summary prints). Exit 1 = the #748 regression
# (verify.sh hard-exits and gate_m12 never runs) is back.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)" || {
  printf 'gate-m11-engine-bin-hard-exit: FATAL: mktemp -d failed while setting up this eval'"'"'s own scratch directory\n' >&2
  exit 2
}
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  gate-m11-engine-bin-hard-exit: %s\n' "$1"; }

OUT="$TMP/gate-m11.out"
MIF_RH_CLI=/nonexistent/mif-rh-cli-748-eval bash scripts/verify.sh --gates 'gate_m11$|gate_m12$' >"$OUT" 2>&1
rc=$?

if [ "$rc" -ne 5 ]; then
  note "verify.sh did not hard-exit with rc=5 on the engine_bin failure (rc=$rc)"
else
  note "FAIL: verify.sh exited with rc=5 -- the #748 hard-exit recurred (gate_m11's engine_bin failure escaped as a raw process exit)"
  fail=1
fi

if grep -q 'Milestone 12' "$OUT"; then
  note "gate_m12 ran after gate_m11's engine_bin failure (not silently skipped)"
else
  note "FAIL: gate_m12 never ran -- the #748 '~29 gates silently skipped' symptom recurred"
  fail=1
fi

if grep -qE 'verify\.sh: [0-9]+ passed, [0-9]+ (FAILED|failed)' "$OUT"; then
  note "the final PASS/FAILED summary line was printed"
else
  note "FAIL: no final summary line found -- verify.sh did not reach its normal end"
  fail=1
fi

if grep -q 'gate_m11 needs the mif-rh-cli engine' "$OUT"; then
  note "gate_m11's 11j check reported its own FAIL naming the engine as the cause"
else
  note "FAIL: no gate_m11 engine-failure message found -- the 11j check's own failure went unreported"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "gate-m11-engine-bin-hard-exit: PASS"
  exit 0
fi
echo "gate-m11-engine-bin-hard-exit: FAIL"
exit 1
