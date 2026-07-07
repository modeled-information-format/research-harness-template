#!/usr/bin/env bash
# site-toggle.sh — flip the Astro/Starlight site-projection controls in a harness
# manifest (`.site`, the control plane read by astro.config.mjs at build time).
# This is the one-line manifest edit a clone makes to choose which surface leads
# (reports vs docs) or to turn an optional site plugin on/off. Unlike pack-toggle,
# there is no re-materialize step: astro.config.mjs reads `.site` directly, so the
# change takes effect on the next `npm run build`.
#
# Since research-harness-template#276 (Story #302, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage:
#   site-toggle.sh primary <reports|docs|auto> [<harness.config.json>]
#   site-toggle.sh plugin  <llmsTxt|mermaid|imageZoom|linksValidator> <on|off> [<harness.config.json>]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

SUB="${1:?usage: site-toggle.sh primary <reports|docs|auto> | plugin <name> <on|off> [config]}"

case "$SUB" in
  primary)
    VALUE="${2:?usage: site-toggle.sh primary <reports|docs|auto> [config]}"
    CFG="${3:-$ROOT/harness.config.json}"
    "$ENGINE" harness site-toggle-primary "$VALUE" --config "$CFG" || exit 1
    ;;
  plugin)
    NAME="${2:?usage: site-toggle.sh plugin <llmsTxt|mermaid|imageZoom|linksValidator> <on|off> [config]}"
    STATE="${3:?usage: site-toggle.sh plugin <name> <on|off> [config]}"
    CFG="${4:-$ROOT/harness.config.json}"
    "$ENGINE" harness site-toggle-plugin "$NAME" "$STATE" --config "$CFG" || exit 1
    ;;
  *)
    echo "site-toggle: unknown subcommand '$SUB' (primary|plugin)" >&2
    exit 2
    ;;
esac

echo "site-toggle: rebuild with 'npm run build' (or 'npm run dev') to apply."
