#!/usr/bin/env bash
# goal-version.sh — compute the content-hash identity of a goal version (SPEC §11).
#
# The id is gv-<sha256(normalized goal)[:12]>, where "normalized" is the goal JSON
# with the lineage fields (version, supersedes, revision) removed and all keys
# sorted (jq -S, compact). Removing the lineage fields makes the hash a stable
# function of the goal's *content* — minting a new version (which sets version/
# supersedes/revision) never perturbs the hash of the content it describes. The id
# is self-verifying (recompute and compare) and independent of git commit timing.
#
# Usage: goal-version.sh <goal.json>
#        prints e.g. gv-9f3c1a2b4d5e

set -uo pipefail

die() { echo "goal-version: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"

GOAL="${1:?usage: goal-version.sh <goal.json>}"
[ -f "$GOAL" ] || die "not a file: $GOAL"

# Portable sha256 → hex on stdout (first field).
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 | awk '{print $NF}'
  else die "no sha256 tool (need sha256sum, shasum, or openssl)"; fi
}

NORM=$(jq -cS 'del(.version, .supersedes, .revision)' "$GOAL") \
  || die "invalid goal JSON: $GOAL"

HASH=$(printf '%s' "$NORM" | sha256_hex)
printf 'gv-%s\n' "${HASH:0:12}"
