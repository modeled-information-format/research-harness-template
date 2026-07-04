#!/usr/bin/env bash
# sync-registry-ontologies.sh — discovers domain ontologies published to the
# canonical registry that this harness's harness.config.json has never heard
# of (not merely disabled — absent from `.ontologies[]` entirely), adds each
# one with `enabled: true` (this harness's default posture: every registry
# ontology is available unless a harness owner explicitly opts it out), then
# vendors and catalogs everything currently enabled.
#
# The registry can grow at any time — a new ontology domain published to
# mif-spec.dev/ontologies gives no push notification to any harness instance.
# This script is the pull side of that: run it whenever you want this harness
# to catch up with what the registry currently offers. It does not vendor
# anything itself; it delegates to fetch-ontology.sh (which independently
# verifies the registry's trust-pinned index and every file's sha256) and
# sync-packs.sh (which rebuilds the catalog).
#
# Usage: sync-registry-ontologies.sh
#   exit 0 = synced (0 or more new ontologies discovered and enabled, then
#            vendored + cataloged)
#   non-zero = registry index unreachable/malformed, or a downstream vendor/
#              catalog step failed

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"
CFG="$ROOT/harness.config.json"

die() { echo "sync-registry-ontologies: $*" >&2; exit 1; }
command -v jq >/dev/null || die "jq is required"
[ -f "$CFG" ] || die "config not found: $CFG"

# Source resolution mirrors fetch-ontology.sh's own precedence, so a fixture
# override (MIF_ONTOLOGY_SOURCE) used for discovery here also governs the
# fetch-ontology.sh call below.
SRC="${MIF_ONTOLOGY_SOURCE:-}"
[ -z "$SRC" ] && [ -f "$ROOT/.ontologies.source" ] && SRC="$(head -n1 "$ROOT/.ontologies.source")"
[ -z "$SRC" ] && SRC="https://mif-spec.dev/ontologies"
SRC="${SRC%/}"

INDEX_FILE="$(mktemp)" || die "mktemp failed"
trap 'rm -f "$INDEX_FILE"' EXIT
case "$SRC" in
  http://*|https://*)
    command -v curl >/dev/null || die "curl is required for an http(s) source"
    curl -fsSL "$SRC/index.json" -o "$INDEX_FILE" || die "cannot read index at $SRC/index.json"
    ;;
  file://*) cp "${SRC#file://}/index.json" "$INDEX_FILE" 2>/dev/null || die "cannot read index at $SRC/index.json" ;;
  *) cp "$SRC/index.json" "$INDEX_FILE" 2>/dev/null || die "cannot read index at $SRC/index.json" ;;
esac
jq -e '.ontologies' "$INDEX_FILE" >/dev/null 2>&1 || die "index at $SRC is malformed (no .ontologies)"

# This is a plain, unauthenticated read purely for discovery/diffing — the
# actual vendoring below (fetch-ontology.sh) independently re-fetches and
# verifies the index against its own trust-pinned sha256 (ADR-0012's TOFU
# scheme), so no trust decision is made by this read.
#
# A registry id satisfied by a committed base layer under schemas/ontologies/
# (mirrors fetch-ontology.sh's own is_committed_base() check) is always
# available regardless of harness.config.json's ontologies[] toggle — adding
# it there is not just redundant, it is actively wrong: check-pack-docs.py
# treats every ontologies[] id as a component requiring its own documented
# section (scripts/check-pack-docs.py:45-46), so toggling a base layer would
# spuriously demand doc coverage for infrastructure this harness never
# curates per-instance.
is_committed_base() { [ -d "$ROOT/schemas/ontologies/$1" ]; }

new_ids=""
for id in $(jq -r '.ontologies | keys[]' "$INDEX_FILE"); do
  is_committed_base "$id" && continue
  jq -e --arg id "$id" '.ontologies[]? | select(.id==$id)' "$CFG" >/dev/null 2>&1 || new_ids="$new_ids$id "
done

if [ -z "${new_ids// /}" ]; then
  echo "sync-registry-ontologies: no new ontologies in the registry — $(jq '.ontologies | length' "$CFG") already known"
else
  count=0
  # Read-modify-write on $CFG is atomic per invocation (temp file + mv) but not
  # across concurrent invocations racing on the same file — accepted, since this
  # is a manually-run sync script, not a concurrent service.
  for id in $new_ids; do
    jq --arg id "$id" '.ontologies += [{id: $id, enabled: true}]' "$CFG" > "$CFG.tmp" \
      && mv "$CFG.tmp" "$CFG" \
      || { rm -f "$CFG.tmp"; die "failed to add '$id' to $CFG"; }
    echo "sync-registry-ontologies: discovered new ontology '$id' — added, enabled by default"
    count=$((count + 1))
  done
  echo "sync-registry-ontologies: $count new ontology(ies) added to $CFG"
fi

"$ROOT/scripts/fetch-ontology.sh" --all-enabled || die "fetch-ontology.sh failed"
"$ROOT/scripts/sync-packs.sh" || die "sync-packs.sh failed"
