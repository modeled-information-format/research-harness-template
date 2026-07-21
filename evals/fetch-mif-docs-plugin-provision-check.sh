#!/usr/bin/env bash
# fetch-mif-docs-plugin-provision-check.sh — contract test for the cache-reuse
# check in scripts/fetch-mif-docs-plugin.sh (issue #677).
#
# The defect this pins: the script's clone+checkout lands the pinned ref BEFORE
# `npm ci` / `npm run hydrate-schema` run, so a failed install leaves $DEST at
# the correct ref but unprovisioned. The old reuse check compared only the git
# ref, so the very next run printed "already at pinned ref" and exited 0 with
# no node_modules and no hydrated schema — a false success the downstream
# gate_m32 consumer then failed on with an unrelated-looking module error.
# The fix records a completion sentinel only after both post-checkout steps
# succeed, and reuse requires ref AND sentinel to agree. This eval proves:
#   1. a run whose `npm ci` fails exits non-zero and writes NO sentinel,
#      even though the checkout already landed the pinned ref;
#   2. the NEXT run does not short-circuit — it re-runs npm ci and
#      hydrate-schema and only then succeeds (the #677 regression case);
#   3. a fully-provisioned cache IS reused: third run exits 0 without
#      invoking npm at all.
#
# npm is stubbed with a PATH shim (no network, no real installs); the
# marketplace is a local fixture git repo cloned by path.
#
# Exit 0 = the contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
repo_root="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fetch-plugin-provision: %s\n' "$1"; }

# --- Fixture marketplace repo (stands in for mif-docs-plugin) ---------------
FIXTURE="$TMP/plugin-src"
mkdir -p "$FIXTURE"
git -C "$FIXTURE" init --quiet
git -C "$FIXTURE" config user.email "eval@example.invalid"
git -C "$FIXTURE" config user.name "eval"
git -C "$FIXTURE" config core.hooksPath "$TMP/no-hooks"   # keep any global hook manager out of the fixture
printf '{"name":"fixture","scripts":{"hydrate-schema":"true"}}\n' > "$FIXTURE/package.json"
printf '{}\n' > "$FIXTURE/package-lock.json"
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit --quiet -m "fixture"
PIN="$(git -C "$FIXTURE" rev-parse HEAD)"

# --- Sandbox harness root with its own harness.config.json ------------------
SANDBOX="$TMP/harness"
mkdir -p "$SANDBOX/scripts"
cp "$repo_root/scripts/fetch-mif-docs-plugin.sh" "$SANDBOX/scripts/"
jq -n --arg url "$FIXTURE" --arg ref "$PIN" \
  '{marketplaces:[{name:"mif-docs",url:$url,ref:$ref}]}' \
  > "$SANDBOX/harness.config.json"

# --- npm shim: logs invocations; `ci` fails while $TMP/fail-ci exists --------
mkdir -p "$TMP/shim"
cat > "$TMP/shim/npm" <<SHIM
#!/usr/bin/env bash
echo "\$*" >> "$TMP/npm.log"
if [ "\$1" = "ci" ] && [ -e "$TMP/fail-ci" ]; then
  echo "shim: simulated npm ci failure" >&2
  exit 1
fi
exit 0
SHIM
chmod +x "$TMP/shim/npm"
export PATH="$TMP/shim:$PATH"

CACHE="$TMP/cache"
: > "$TMP/npm.log"

# 1. First run: checkout succeeds, npm ci fails -> non-zero exit, ref landed,
#    NO completion sentinel left behind.
touch "$TMP/fail-ci"
out1="$(bash "$SANDBOX/scripts/fetch-mif-docs-plugin.sh" --dest "$CACHE" 2>&1)"; rc1=$?
if [ "$rc1" -ne 0 ] && [ "$(git -C "$CACHE" rev-parse HEAD 2>/dev/null)" = "$PIN" ] \
   && [ ! -f "$CACHE/.provisioned-ref" ]; then
  note "failed npm ci exits non-zero, leaves ref checked out, writes no sentinel"
else
  note "FAIL: case 1 — rc=$rc1 sentinel=$([ -f "$CACHE/.provisioned-ref" ] && echo present || echo absent)"
  printf '%s\n' "$out1" | sed 's/^/    /'
  fail=1
fi

# 2. THE #677 REGRESSION CASE: next run must NOT short-circuit on the ref
#    alone — it must re-run npm ci and hydrate-schema, then succeed.
rm -f "$TMP/fail-ci"
: > "$TMP/npm.log"
out2="$(bash "$SANDBOX/scripts/fetch-mif-docs-plugin.sh" --dest "$CACHE" 2>&1)"; rc2=$?
if [ "$rc2" -eq 0 ] && grep -q '^ci ' "$TMP/npm.log" && grep -q 'hydrate-schema' "$TMP/npm.log" \
   && [ "$(cat "$CACHE/.provisioned-ref" 2>/dev/null)" = "$PIN" ]; then
  note "partially-provisioned cache re-runs install/hydration instead of false success"
else
  note "FAIL: case 2 — rc=$rc2, npm invocations: [$(tr '\n' ';' < "$TMP/npm.log")]"
  printf '%s\n' "$out2" | sed 's/^/    /'
  fail=1
fi

# 3. Fully-provisioned cache IS reused: third run exits 0, reports reuse, and
#    never invokes npm.
: > "$TMP/npm.log"
out3="$(bash "$SANDBOX/scripts/fetch-mif-docs-plugin.sh" --dest "$CACHE" 2>&1)"; rc3=$?
if [ "$rc3" -eq 0 ] && printf '%s' "$out3" | grep -q 'already provisioned' \
   && [ ! -s "$TMP/npm.log" ]; then
  note "fully-provisioned cache short-circuits without invoking npm"
else
  note "FAIL: case 3 — rc=$rc3, npm invocations: [$(tr '\n' ';' < "$TMP/npm.log")]"
  printf '%s\n' "$out3" | sed 's/^/    /'
  fail=1
fi

exit "$fail"
