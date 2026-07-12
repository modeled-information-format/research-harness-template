#!/usr/bin/env bash
# Fetch mif-docs-plugin at the SHA pinned in harness.config.json marketplaces[]
# (ADR-0018) into a local cache, so scripts/verify.sh's mif-docs conformance
# gate (gate_m32) can invoke its mif-validate.mjs without requiring every
# contributor to keep a separate sibling checkout.
#
# Usage: fetch-mif-docs-plugin.sh [--dest <dir>]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${repo_root}/.mif-docs-plugin-cache"

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

if [ -d "$DEST/.git" ]; then
  resolved="$(git -C "$DEST" rev-parse HEAD 2>/dev/null || true)"
  if [ "$resolved" = "$PINNED_REF" ]; then
    echo "fetch-mif-docs-plugin: cache at $DEST already at pinned ref $PINNED_REF"
    exit 0
  fi
  rm -rf "$DEST"
fi

echo "fetch-mif-docs-plugin: cloning $MARKETPLACE_URL @ $PINNED_REF -> $DEST"
git clone --quiet "$MARKETPLACE_URL" "$DEST"
git -C "$DEST" checkout --quiet "$PINNED_REF"

resolved="$(git -C "$DEST" rev-parse HEAD)"
if [ "$resolved" != "$PINNED_REF" ]; then
  echo "fetch-mif-docs-plugin: FAIL-CLOSED — checked-out HEAD ($resolved) does not match the pinned ref ($PINNED_REF)" >&2
  rm -rf "$DEST"
  exit 1
fi

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

echo "fetch-mif-docs-plugin: verified at pinned ref $PINNED_REF, dependencies installed, schema hydrated"
