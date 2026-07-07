#!/usr/bin/env bash
# pack-toggle.sh — flip a pack's enabled flag in a harness manifest (the control
# plane, SPEC §7b), then re-materialize the enablement set. This is the one-line
# manifest edit a clone makes to enable or disable a pack.
#
# Since research-harness-template#276 (Story #302, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: pack-toggle.sh <pack-name> <on|off> [<harness.config.json>]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

PACK="${1:?usage: pack-toggle.sh <pack> <on|off> [config]}"
STATE="${2:?usage: pack-toggle.sh <pack> <on|off> [config]}"
CFG="${3:-$ROOT/harness.config.json}"

"$ENGINE" harness pack-toggle "$PACK" "$STATE" --config "$CFG" || exit 1
"$ROOT/scripts/sync-packs.sh" "$CFG"
