#!/usr/bin/env bash
# gate-engine-lazy-gating-trap-restore.sh — regression test for
# research-harness-template#745: gate_engine_lazy_gating renamed
# bin/mif-rh-cli aside with a bare `if`/`mv` sequence and no trap-based
# restore, unlike gate_m29/gate_m30/gate_m31's `trap ... RETURN EXIT`
# pattern. If verify.sh was interrupted (Ctrl-C, CI job timeout/SIGTERM)
# while this gate's nested
# `bash scripts/verify.sh --gates 'gate_workflows$'` subprocess was running,
# bin/mif-rh-cli was left permanently renamed to
# bin/mif-rh-cli.gate_engine_lazy_gating.bak -- every subsequent
# verify.sh/ontology-review.sh run then spuriously failed every
# engine-dependent gate with "engine: mif-rh-cli not found" until someone
# noticed and renamed it back by hand.
#
# Reproduces the interruption window against the REAL gate: starts
# `verify.sh --gates 'gate_engine_lazy_gating$'` in the background, polls for
# the .bak rename marker to confirm the window is open (the gate's nested
# subprocess spawns node several times via check-workflow-syntax.sh /
# check-workflow-forbidden-globals.sh, which reliably keeps this window open
# well past the poll interval below), sends SIGTERM, and asserts:
#   - bin/mif-rh-cli.gate_engine_lazy_gating.bak no longer exists afterward;
#   - bin/mif-rh-cli exists again (restored), not left renamed aside.
#
# Installs a throwaway bin/mif-rh-cli stub first if the real engine isn't
# installed in this checkout (the common case for a dev/CI checkout that
# hasn't run scripts/fetch-engine.sh) -- gate_engine_lazy_gating only renames
# anything if bin/mif-rh-cli exists and is executable. Removed again
# afterward, along with bin/ itself, if this eval is the one that created it.
#
# Exit 0 = the engine binary is restored even when interrupted mid-gate (the
# #745 fix holds). Exit 1 = the #745 regression (binary left permanently
# renamed) is back.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

note() { printf '  gate-engine-lazy-gating-trap-restore: %s\n' "$1"; }

BAK="bin/mif-rh-cli.gate_engine_lazy_gating.bak"
BIN_PRE_EXISTED=0
[ -e bin/mif-rh-cli ] && BIN_PRE_EXISTED=1
BIN_DIR_PRE_EXISTED=0
[ -d bin ] && BIN_DIR_PRE_EXISTED=1

cleanup() {
  # Belt-and-suspenders: whatever this eval's own assertions find, never
  # leave the real checkout in a state where a later gate/eval in the same
  # run spuriously fails with "engine: mif-rh-cli not found" because of THIS
  # test, and never leave a stub behind that didn't exist before it ran.
  if [ -e "$BAK" ]; then
    mv -f "$BAK" bin/mif-rh-cli 2>/dev/null
  fi
  if [ "$BIN_PRE_EXISTED" -eq 0 ] && [ -e bin/mif-rh-cli ]; then
    rm -f bin/mif-rh-cli
  fi
  if [ "$BIN_DIR_PRE_EXISTED" -eq 0 ] && [ -d bin ]; then
    rmdir bin 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [ "$BIN_PRE_EXISTED" -eq 0 ]; then
  mkdir -p bin
  cat > bin/mif-rh-cli <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in
  --version) echo "0.99.0" ;;
  *) exit 0 ;;
esac
STUB
  chmod +x bin/mif-rh-cli
fi

fail=0

bash scripts/verify.sh --gates 'gate_engine_lazy_gating$' >/dev/null 2>&1 &
pid=$!

waited=0
while [ ! -e "$BAK" ]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep 0.02
  waited=$((waited + 1))
  if [ "$waited" -gt 500 ]; then
    break
  fi
done

if [ ! -e "$BAK" ]; then
  note "FAIL: $BAK never appeared -- gate_engine_lazy_gating did not rename bin/mif-rh-cli aside (cannot exercise the interruption window)"
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  exit 1
fi

kill -TERM "$pid" 2>/dev/null
wait "$pid" 2>/dev/null

if [ -e "$BAK" ]; then
  note "FAIL: $BAK still exists after SIGTERM -- the #745 regression (no trap-based restore) is back"
  fail=1
else
  note "OK: $BAK was cleaned up after interruption"
fi

if [ ! -x bin/mif-rh-cli ]; then
  note "FAIL: bin/mif-rh-cli was not restored after interruption"
  fail=1
else
  note "OK: bin/mif-rh-cli was restored after interruption"
fi

exit "$fail"
