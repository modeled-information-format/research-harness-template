#!/usr/bin/env bash
# gate-m5-mktemp-guard.sh — regression test for
# research-harness-template#778: gate_m5's `mktemp -d` calls (5c/5d/5d2/5d3/
# 5d4) had no failure guard, unlike gate_m29/30/31's
# `T="$(mktemp -d)" || { bad ...; return 1; }` pattern. If `mktemp -d` failed,
# `T` silently became an empty string and was never checked, so every
# subsequent "$T/..." path collapsed to a filesystem-root path (e.g.
# "/settings-on.json"), and the matching `rm -rf "$T"` cleanup became the
# silent no-op `rm -rf ""` instead of a loud signal.
#
# Reproduces the failure deterministically by shadowing `mktemp` on PATH with
# a stub that always fails, then running gate_m5 in isolation
# (`verify.sh --gates 'gate_m5$'`). Asserts:
#   - gate_m5 exits non-zero (verify.sh reports at least one FAIL) instead of
#     limping through with misleading "bad" results for unrelated reasons;
#   - the failure message names the scratch-directory creation itself as the
#     cause (the #778 fix's guard message), not a downstream cp/jq/sync-packs
#     failure that would misattribute the break to pack-toggle logic;
#   - NO file is ever written at filesystem root (e.g. /settings-on.json,
#     /settings-mkt.json, /settings-typo.json, /settings-ghost.json) — the
#     exact "$T/..." -> "/..." collapse #778 describes;
#   - the repo's real harness.config.json is byte-identical before and after
#     (a SEVERER, previously-undocumented consequence found while verifying
#     this fix: 5d3's `Path(sys.argv[1])` receives T="" on an unguarded
#     mktemp failure, and Python's `Path("")` resolves to `.` -- the repo
#     root, since verify.sh cd's there -- so `(T / "harness.config.json")
#     .write_text(...)` silently OVERWRITES the real, tracked
#     harness.config.json with synthetic fixture content, not merely a
#     confusing test failure. Reproduced empirically against the pre-fix
#     code while developing this test).
#
# Exit 0 = gate_m5 fails closed on a broken mktemp, with no root-path
# collapse and no corpus-file corruption. Exit 1 = the #778 regression (or
# its more severe harness.config.json-clobbering variant) is back.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  gate-m5-mktemp-guard: %s\n' "$1"; }

# Track any root-level settings-*.json fallout from a previous run of this
# same check (belt-and-suspenders — should never exist, but don't let a
# leftover from an interrupted run produce a false negative on a later run,
# and don't ever silently rm anything outside our own stub/marker prefix).
ROOT_MARKERS=(/settings-on.json /settings-off.json /settings-mkt.json /settings-typo.json /settings-ghost.json)

no_root_collapse() {
  local m
  for m in "${ROOT_MARKERS[@]}"; do
    [ -e "$m" ] && return 1
  done
  return 0
}

# Shadow mktemp with a stub that always fails (mimics a full/unwritable
# /tmp, or a sandboxed CI runner with a misconfigured TMPDIR — #778's
# named failure scenario), while leaving every other tool (jq, cp, ajv,
# python3, scripts/sync-packs.sh) untouched.
STUB="$TMP/stub-bin"
mkdir -p "$STUB"
printf '#!/bin/sh\nexit 1\n' > "$STUB/mktemp"
chmod +x "$STUB/mktemp"

# Snapshot the real harness.config.json so we can detect the corruption
# variant above, and restore it unconditionally on exit no matter what the
# gate does to it (belt-and-suspenders on top of the fix itself).
CFG_BACKUP="$TMP/harness.config.json.orig"
cp harness.config.json "$CFG_BACKUP"
trap 'cp "$CFG_BACKUP" harness.config.json 2>/dev/null || true; rm -rf "$TMP"' EXIT

OUT="$TMP/gate-m5.out"
PATH="$STUB:$PATH" bash scripts/verify.sh --gates 'gate_m5$' >"$OUT" 2>&1
rc=$?

if [ "$rc" -ne 0 ]; then
  note "gate_m5 fails closed when mktemp -d fails (rc=$rc)"
else
  note "FAIL: gate_m5 reported success despite mktemp -d failing (rc=$rc)"; fail=1
fi

if grep -q 'failed to create a scratch directory' "$OUT"; then
  note "failure is attributed to scratch-directory creation, not a downstream symptom"
else
  note "FAIL: no scratch-directory guard message found; failure likely misattributed to pack-toggle logic"
  fail=1
fi

if no_root_collapse; then
  note "no settings-*.json ever collapsed to filesystem root (#778)"
else
  note "FAIL: a settings-*.json file was written at filesystem root -- the #778 collapse recurred"
  fail=1
fi

if cmp -s "$CFG_BACKUP" harness.config.json; then
  note "harness.config.json is untouched (the T='' -> Path('') -> cwd clobber did not recur)"
else
  note "FAIL: harness.config.json was overwritten by the gate -- the T='' -> Path('.') clobber recurred"
  fail=1
  cp "$CFG_BACKUP" harness.config.json
fi

if [ "$fail" -eq 0 ]; then
  echo "gate-m5-mktemp-guard: PASS"
  exit 0
fi
echo "gate-m5-mktemp-guard: FAIL"
exit 1
