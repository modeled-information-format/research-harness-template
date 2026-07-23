#!/usr/bin/env bash
# engine-version-mismatch-source-check.sh — regression eval for
# research-harness-template#767.
#
# scripts/lib/engine.sh's engine_bin() resolves a candidate mif-rh-cli in
# priority order ($MIF_RH_CLI override -> PATH -> <root>/bin/mif-rh-cli, the
# only location scripts/fetch-engine.sh ever writes to). Before this fix, a
# version-mismatch failure ALWAYS told the user to "re-run
# scripts/fetch-engine.sh" regardless of which of the three paths actually
# supplied the stale candidate. For the override and PATH cases that advice
# is a guaranteed no-op: fetch-engine.sh only touches the repo-local install,
# so a stale override or a stale PATH binary keeps winning on every
# subsequent run, with no diagnostic ever naming the real cause.
#
# This eval builds a fake, deliberately-stale mif-rh-cli (reports a version
# below ENGINE_MIN_VERSION) and drives engine_bin() through all three
# resolution paths, asserting each failure:
#   - still exits 5 (ADR-0016: hard failure, never a silent fallback);
#   - names the ACTUAL source of the stale candidate; and
#   - gives the remedy that actually fixes THAT source, not a blanket
#     "re-run fetch-engine.sh" when that would be a no-op.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  engine-version-mismatch-source-check: %s\n' "$1"; }

# A fake mif-rh-cli that only answers --version, with a version well below
# whatever ENGINE_MIN_VERSION is (0.1.0 stays below any realistic future
# minimum without hardcoding today's value).
STALE="$TMP/stale-mif-rh-cli"
cat > "$STALE" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "mif-rh-cli 0.1.0"
  exit 0
fi
exit 1
FAKE
chmod +x "$STALE"

run_engine_bin() { # run_engine_bin <fake-root>
  (
    cd "$ROOT" || exit 2
    # shellcheck source=scripts/lib/engine.sh
    . "$ROOT/scripts/lib/engine.sh"
    engine_bin "$1"
  )
}

# Case 1: stale candidate via $MIF_RH_CLI override.
out=$(MIF_RH_CLI="$STALE" run_engine_bin "$TMP/unused-root" 2>&1); rc=$?
if [ "$rc" -ne 5 ]; then
  note "override case: expected exit 5, got $rc"
  fail=1
elif ! printf '%s' "$out" | grep -q "MIF_RH_CLI=${STALE}"; then
  note "override case: message did not name \$MIF_RH_CLI as the source: $out"
  fail=1
elif ! printf '%s' "$out" | grep -qi "unset MIF_RH_CLI"; then
  note "override case: message did not give the override-specific remedy: $out"
  fail=1
else
  note "override case OK: names \$MIF_RH_CLI as the source and gives the real remedy"
fi

# Case 2: stale candidate found first on PATH (no override, no repo-local
# binary needed — PATH wins over a nonexistent repo-local file too, but we
# point "root" at a directory with no bin/mif-rh-cli to keep the case clean).
FAKE_PATH_DIR="$TMP/fakepath"
mkdir -p "$FAKE_PATH_DIR"
cp "$STALE" "$FAKE_PATH_DIR/mif-rh-cli"
chmod +x "$FAKE_PATH_DIR/mif-rh-cli"
out=$(env -u MIF_RH_CLI PATH="$FAKE_PATH_DIR:$PATH" bash -c '
  cd "'"$ROOT"'" || exit 2
  . "'"$ROOT"'/scripts/lib/engine.sh"
  engine_bin "'"$TMP"'/no-repo-local-root"
' 2>&1); rc=$?
if [ "$rc" -ne 5 ]; then
  note "PATH case: expected exit 5, got $rc"
  fail=1
elif ! printf '%s' "$out" | grep -q "came from PATH"; then
  note "PATH case: message did not name PATH as the source: $out"
  fail=1
elif ! printf '%s' "$out" | tr '\n' ' ' | grep -qi "NOT fix this by itself"; then
  note "PATH case: message did not warn that fetch-engine.sh alone won't fix a PATH shadow: $out"
  fail=1
else
  note "PATH case OK: names PATH as the source and warns fetch-engine.sh alone is a no-op here"
fi

# Case 3: stale candidate at the repo-local <root>/bin/mif-rh-cli — the ONE
# case where "re-run scripts/fetch-engine.sh" is actually the correct fix.
FAKE_ROOT="$TMP/fake-root"
mkdir -p "$FAKE_ROOT/bin"
cp "$STALE" "$FAKE_ROOT/bin/mif-rh-cli"
chmod +x "$FAKE_ROOT/bin/mif-rh-cli"
out=$(env -u MIF_RH_CLI bash -c '
  cd "'"$ROOT"'" || exit 2
  . "'"$ROOT"'/scripts/lib/engine.sh"
  # Strip any real mif-rh-cli off PATH so the repo-local fake is what resolves.
  clean_path=""
  IFS=: read -ra dirs <<< "$PATH"
  for d in "${dirs[@]}"; do
    [ -x "$d/mif-rh-cli" ] && continue
    clean_path="${clean_path:+$clean_path:}$d"
  done
  PATH="$clean_path" engine_bin "'"$FAKE_ROOT"'"
' 2>&1); rc=$?
if [ "$rc" -ne 5 ]; then
  note "repo-local case: expected exit 5, got $rc"
  fail=1
elif ! printf '%s' "$out" | grep -q "${FAKE_ROOT}/bin/mif-rh-cli"; then
  note "repo-local case: message did not name the repo-local install path: $out"
  fail=1
elif ! printf '%s' "$out" | grep -q "re-run scripts/fetch-engine.sh"; then
  note "repo-local case: message did not tell the user to re-run fetch-engine.sh (the correct fix here): $out"
  fail=1
else
  note "repo-local case OK: names the repo-local install as the source and re-run fetch-engine.sh as the (correct) remedy"
fi

[ "$fail" -eq 0 ] && note "engine_bin's version-mismatch message correctly identifies which of the three resolution paths (override, PATH, repo-local) supplied the stale candidate, and gives the remedy that actually fixes that source"
exit "$fail"
