#!/usr/bin/env bash
# pack-toggle.sh — flip a pack's enabled flag in a harness manifest (the control
# plane, SPEC §7b), then re-materialize the enablement set. This is the one-line
# manifest edit a clone makes to enable or disable a pack.
#
# Usage: pack-toggle.sh <pack-name> <on|off> [<harness.config.json>]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

PACK="${1:?usage: pack-toggle.sh <pack> <on|off> [config]}"
STATE="${2:?usage: pack-toggle.sh <pack> <on|off> [config]}"
CFG="${3:-harness.config.json}"
[ -f "$CFG" ] || { echo "pack-toggle: config not found: $CFG" >&2; exit 2; }

case "$STATE" in
  on)  EN=true ;;
  off) EN=false ;;
  *)   echo "pack-toggle: state must be on|off" >&2; exit 2 ;;
esac

# The pack must already be declared in packs[] (with its source); we only flip
# enabled. A pack absent from the manifest is an error — declare it first.
if [ "$(jq -r --arg p "$PACK" '[.packs[] | select(.name==$p)] | length' "$CFG")" = "0" ]; then
  echo "pack-toggle: pack '$PACK' is not declared in $CFG packs[]" >&2
  exit 2
fi

tmp=$(mktemp)
jq --arg p "$PACK" --argjson en "$EN" \
  '(.packs[] | select(.name==$p) | .enabled) |= $en' "$CFG" > "$tmp" && mv "$tmp" "$CFG"

echo "pack-toggle: $PACK -> enabled=$EN in $CFG"
scripts/sync-packs.sh "$CFG"
