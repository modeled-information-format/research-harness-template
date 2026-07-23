#!/usr/bin/env bash
# engine-version-precedence-check.sh — regression test for issue #779:
# engine_bin's version-extraction regex only ever captured the bare X.Y.Z
# digits and silently discarded any pre-release/build suffix (-rc1, -alpha,
# +build.5), so a semver-precedence-lower pre-release binary (e.g.
# "mif-rh-cli 0.7.0-rc1") compared as == ENGINE_MIN_VERSION and PASSED the
# `>= ENGINE_MIN_VERSION` gate it should have failed.
#
# This drives scripts/lib/engine.sh's engine_bin directly against a FAKE
# engine (the documented MIF_RH_CLI override) that reports a controlled
# --version string, and asserts semver precedence end to end:
#   - a pre-release of the exact required version (0.7.0-rc1 vs need 0.7.0)
#     must be REJECTED (exit 5) — the exact bug #779 describes;
#   - the exact required release (0.7.0) must still be ACCEPTED;
#   - a newer release (0.8.0) must still be ACCEPTED;
#   - an older release (0.6.0) must still be REJECTED;
#   - a pre-release of a newer release (0.8.0-rc1) must still be ACCEPTED,
#     since its X.Y.Z release triplet already clears the requirement.
#
# Exit 0 = every case matches expected precedence. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  engine-version-precedence-check: %s\n' "$1"; }

FAKE_ENGINE="$TMP/fake-mif-rh-cli"
cat > "$FAKE_ENGINE" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "mif-rh-cli ${FAKE_ENGINE_VERSION}"
  exit 0
fi
exit 0
FAKE
chmod +x "$FAKE_ENGINE"

# check_engine <label> <fake-version> <expect: accept|reject>
check_engine() {
  local label="$1" version="$2" expect="$3" out rc
  out=$(FAKE_ENGINE_VERSION="$version" MIF_RH_CLI="$FAKE_ENGINE" \
        bash -c '. scripts/lib/engine.sh; engine_bin "$(pwd)"' 2>&1)
  rc=$?
  if [ "$expect" = accept ]; then
    if [ "$rc" -eq 0 ] && [ "$out" = "$FAKE_ENGINE" ]; then
      return 0
    fi
    note "$label: expected ACCEPT (rc=0, path=$FAKE_ENGINE) but got rc=$rc out=$out"
    return 1
  else
    if [ "$rc" -eq 5 ] && printf '%s' "$out" | grep -q 'older than the required'; then
      return 0
    fi
    note "$label: expected REJECT (rc=5, 'older than the required') but got rc=$rc out=$out"
    return 1
  fi
}

# The exact bug: a pre-release of the exact minimum version must rank BELOW
# the release it names, not compare as equal to it.
check_engine "prerelease-of-min-version-rejected" "0.7.0-rc1" reject || fail=1
# The plain minimum release must still pass.
check_engine "exact-min-version-accepted"          "0.7.0"     accept || fail=1
# A newer release must still pass.
check_engine "newer-release-accepted"              "0.8.0"     accept || fail=1
# An older release must still fail (unrelated to the prerelease fix).
check_engine "older-release-rejected"               "0.6.0"     reject || fail=1
# A pre-release of a NEWER release still clears the requirement, since its
# X.Y.Z release triplet already exceeds ENGINE_MIN_VERSION.
check_engine "prerelease-of-newer-release-accepted" "0.8.0-rc1" accept || fail=1

if [ "$fail" -eq 0 ]; then
  note "all precedence cases matched"
  exit 0
fi
exit 1
