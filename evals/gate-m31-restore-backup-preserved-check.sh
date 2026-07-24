#!/usr/bin/env bash
# gate-m31-restore-backup-preserved-check.sh — regression eval for
# research-harness-template#750: gate_m31's restore_state() unconditionally
# ran `rm -rf "$T"` (its own backup scratch dir) even when the preceding
# `cp "$T/harness.config.json.orig" harness.config.json` restore had just
# failed and was flagged with `bad`. That destroyed the only recoverable
# copy of the pre-run harness.config.json/concordance.json originals at the
# exact moment the real tracked files had already been left mutated by
# gate_m31's own synthetic-topic round-trip test — the identical defect
# class as gate_m30's restore_snapshot() (#754).
#
# This eval shims `cp` on PATH so that the ONE call restore_state() makes to
# restore harness.config.json from its ".orig" backup fails, while every
# other cp invocation (including gate_m31's own legitimate mutations of
# harness.config.json earlier in the same run, and gate_m29/gate_m30's own
# restores if they ever ran) passes straight through to the real `cp`. It
# then asserts gate_m31 reports the failure AND preserves the backup
# directory instead of deleting it, so the originals stay recoverable.
#
# Exit 0 = restore_state preserves the backup on a failed restore (the
# fixed behavior). Exit 1 = it still deletes it (the #750 defect). Exit 2 =
# test setup itself failed (environment problem, not a verify.sh defect).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  gate-m31-restore-backup-preserved-check: %s\n' "$1"; }

REAL_CP="$(command -v cp)" || { note "FAIL: no real 'cp' found on PATH"; exit 2; }

# Independent safety-net backup of the real tracked files this test's
# induced failure will leave mutated (the restore is INTENTIONALLY made to
# fail) -- separate from anything verify.sh's own $T does, so this eval can
# always put the working tree back regardless of what it's asserting.
SAFETY="$(mktemp -d)" || { note "FAIL: could not create safety-net scratch dir"; exit 2; }
cp harness.config.json "$SAFETY/harness.config.json.orig" \
  || { note "FAIL: could not back up harness.config.json before the test"; rm -rf "$SAFETY"; exit 2; }
cp reports/concordance.json "$SAFETY/concordance.json.orig" \
  || { note "FAIL: could not back up reports/concordance.json before the test"; rm -rf "$SAFETY"; exit 2; }
had_sameas=0
if [ -f reports/concordance-sameas-proposals.json ]; then
  had_sameas=1
  cp reports/concordance-sameas-proposals.json "$SAFETY/concordance-sameas-proposals.json.orig" \
    || { note "FAIL: could not back up reports/concordance-sameas-proposals.json before the test"; rm -rf "$SAFETY"; exit 2; }
fi

LEFTOVER_T=""
cleanup() {
  cp "$SAFETY/harness.config.json.orig" harness.config.json 2>/dev/null
  cp "$SAFETY/concordance.json.orig" reports/concordance.json 2>/dev/null
  if [ "$had_sameas" -eq 1 ]; then
    cp "$SAFETY/concordance-sameas-proposals.json.orig" reports/concordance-sameas-proposals.json 2>/dev/null
  else
    rm -f reports/concordance-sameas-proposals.json
  fi
  rm -rf "$SAFETY"
  rm -rf "reports/gate-m31-roundtrip-test" "reports/gate-m31-malformed-test"
  [ -n "$LEFTOVER_T" ] && rm -rf "$LEFTOVER_T"
}
trap cleanup EXIT

SCRATCH="$(mktemp -d)" || { note "FAIL: could not create PATH-shim scratch dir"; exit 2; }
cat > "$SCRATCH/cp" <<SHIM
#!/usr/bin/env bash
if [ "\$#" -eq 2 ] && [ "\$2" = "harness.config.json" ] && [[ "\$1" == *harness.config.json.orig ]]; then
  echo "cp: simulated failure restoring harness.config.json (gate-m31-restore-backup-preserved-check)" >&2
  exit 1
fi
exec "$REAL_CP" "\$@"
SHIM
chmod +x "$SCRATCH/cp"

OUT="$(PATH="$SCRATCH:$PATH" bash scripts/verify.sh --gates 'gate_m31$' 2>&1)"

if ! printf '%s' "$OUT" | grep -q "gate_m31 restore_state: failed to restore harness.config.json"; then
  note "the induced restore failure was never reported -- test setup did not actually intercept the restore cp"
  printf '%s\n' "$OUT" | tail -30 | sed 's/^/    /'
  fail=1
fi

PRESERVE_LINE="$(printf '%s' "$OUT" | grep "gate_m31 restore_state: a restore step failed above" || true)"
if [ -z "$PRESERVE_LINE" ]; then
  note "gate_m31 did not report preserving the backup after the restore failure -- #750 regressed (or the fix was never applied)"
  fail=1
else
  LEFTOVER_T="$(printf '%s' "$PRESERVE_LINE" | grep -oE '/[^ ]*$' || true)"
  if [ -z "$LEFTOVER_T" ] || [ ! -d "$LEFTOVER_T" ]; then
    note "gate_m31 reported preserving a backup dir, but it does not exist on disk -- reporting is out of sync with reality"
    fail=1
  elif [ ! -f "$LEFTOVER_T/harness.config.json.orig" ]; then
    note "preserved backup dir $LEFTOVER_T no longer contains harness.config.json.orig -- the recoverable original is gone anyway"
    fail=1
  else
    note "backup dir $LEFTOVER_T was preserved (not deleted) after the induced restore failure, with harness.config.json.orig still recoverable inside it"
  fi
fi

[ "$fail" -eq 0 ] && note "gate_m31 restore_state preserves its backup instead of deleting it when a restore step fails"
exit "$fail"
