#!/usr/bin/env bash
# Fetch mif-docs-plugin at the SHA pinned in harness.config.json marketplaces[]
# (ADR-0018) into a local cache, so scripts/verify.sh's mif-docs conformance
# gate (gate_m32) can invoke its mif-validate.mjs without requiring every
# contributor to keep a separate sibling checkout.
#
# Usage: fetch-mif-docs-plugin.sh [--dest <dir>]
# Destination precedence: --dest, then $MIF_DOCS_PLUGIN_ROOT (the same env var
# gate_m32 in verify.sh reads), then the default cache path. Keeping these two
# in agreement matters: a MIF_DOCS_PLUGIN_ROOT override that only one of the
# two scripts honors makes fetch succeed and verify fail (or vice versa).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${MIF_DOCS_PLUGIN_ROOT:-${repo_root}/.mif-docs-plugin-cache}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest) DEST="$2"; shift 2;;
    *) echo "fetch-mif-docs-plugin: unknown argument $1" >&2; exit 2;;
  esac
done

MARKETPLACE_URL="$(jq -r '.marketplaces[] | select(.name=="mif-docs") | .url' "$repo_root/harness.config.json")"
PINNED_REF="$(jq -r '.marketplaces[] | select(.name=="mif-docs") | .ref' "$repo_root/harness.config.json")"

if [ -z "$MARKETPLACE_URL" ] || [ "$MARKETPLACE_URL" = "null" ]; then
  echo "fetch-mif-docs-plugin: no 'mif-docs' entry in harness.config.json marketplaces[]" >&2
  exit 1
fi
if [ -z "$PINNED_REF" ] || [ "$PINNED_REF" = "null" ]; then
  echo "fetch-mif-docs-plugin: mif-docs marketplace entry has no pinned ref" >&2
  exit 1
fi

# Completion sentinel (#677): the checkout landing at the pinned ref is NOT
# proof the cache is usable — `npm ci` / `npm run hydrate-schema` run *after*
# the checkout and can fail, leaving $DEST at the correct ref with no
# node_modules and no hydrated schema. The sentinel is written only after
# both post-checkout steps succeed, so cache reuse requires ref AND sentinel
# to agree; a partially-provisioned cache re-runs install/hydration instead
# of short-circuiting to a false success.
STAMP="$DEST/.provisioned-ref"

if [ -d "$DEST/.git" ]; then
  resolved="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || true)"
  if [ "$resolved" = "$PINNED_REF" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$PINNED_REF" ]; then
    echo "fetch-mif-docs-plugin: cache at $DEST already provisioned at pinned ref $PINNED_REF"
    exit 0
  fi
  if [ "$resolved" = "$PINNED_REF" ]; then
    echo "fetch-mif-docs-plugin: cache at $DEST is at pinned ref $PINNED_REF but provisioning never completed — re-running install/hydration"
  else
    rm -rf "$DEST"
  fi
fi

if [ ! -d "$DEST/.git" ]; then
  echo "fetch-mif-docs-plugin: cloning $MARKETPLACE_URL @ $PINNED_REF -> $DEST"
  git clone --quiet "$MARKETPLACE_URL" "$DEST"
  git -C "$DEST" checkout --quiet "$PINNED_REF"

  resolved="$(git -C "$DEST" rev-parse HEAD)"
  if [ "$resolved" != "$PINNED_REF" ]; then
    echo "fetch-mif-docs-plugin: FAIL-CLOSED — checked-out HEAD ($resolved) does not match the pinned ref ($PINNED_REF)" >&2
    rm -rf "$DEST"
    exit 1
  fi
fi

# Drop any stale sentinel before (re-)provisioning so an interrupted run can
# never be mistaken for a completed one.
rm -f "$STAMP"

# mif-validate.mjs imports ajv/ajv-formats/js-yaml as real npm deps — a bare
# clone has no node_modules. Install them (package-manager installs are
# integrity-verified against the registry by npm itself, same posture as
# this repo's own toolchain installs in ci.yml).
if [ -f "$DEST/package-lock.json" ]; then
  (cd "$DEST" && npm ci --omit=dev --quiet)
else
  echo "fetch-mif-docs-plugin: FAIL-CLOSED — no package-lock.json at the pinned ref, cannot reproducibly install deps" >&2
  rm -rf "$DEST"
  exit 1
fi

# mif-validate needs the canonical MIF schema cached locally (its own
# CLAUDE.md: "REQUIRED FIRST: caches the canonical schema into schema/.cache").
(cd "$DEST" && npm run --silent hydrate-schema)

# Both post-checkout steps succeeded — record completion so the next run's
# cache-reuse check can trust the cache (#677).
printf '%s\n' "$PINNED_REF" > "$STAMP"

echo "fetch-mif-docs-plugin: verified at pinned ref $PINNED_REF, dependencies installed, schema hydrated"
