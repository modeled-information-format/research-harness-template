#!/usr/bin/env bash
# biorxiv.sh — bioRxiv/medRxiv Source Connector (research-harness-template#418, #452).
#
# Free, keyless REST API (NFR2): https://api.biorxiv.org/details/<server>/...
# Unlike the other paper connectors this API has no free-text search — it
# lists preprints by posting-date interval, which is exactly the "scan
# what's new" shape this Epic's monitoring workload needs (Epic goal: "scan
# ... new academic/preprint papers"). Query-based filtering (does this
# preprint match the topic?) happens downstream in the Interest-Inference
# Engine (research-harness-template#419), not in this connector.
#
# Usage: biorxiv.sh <days-back> [max_results] [server: biorxiv|medrxiv]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/connector-common.sh
. "$ROOT/scripts/monitoring/lib/connector-common.sh"

DAYS_BACK="${1:?usage: biorxiv.sh <days-back> [max_results] [server]}"
MAX="${2:-20}"
SERVER="${3:-biorxiv}"

# Defense in depth: run-monitoring.sh always passes a real day count
# (harness.config.json's biorxivDaysBack), but this connector's usage
# contract is exactly the arg shape every other connector's ISN'T
# (<query> [max_results]) -- if it's ever invoked with a non-numeric arg1,
# `date` would silently fail on some platforms rather than erroring
# loudly. Fall back to a sane default instead.
case "$DAYS_BACK" in
  ''|*[!0-9]*)
    echo "biorxiv: '$DAYS_BACK' is not a day count, defaulting to 7" >&2
    DAYS_BACK=7
    ;;
esac

START_DATE="$(date -u -v-"${DAYS_BACK}"d +%Y-%m-%d 2>/dev/null || date -u -d "${DAYS_BACK} days ago" +%Y-%m-%d)"
END_DATE="$(date -u +%Y-%m-%d)"

URL="https://api.biorxiv.org/details/${SERVER}/${START_DATE}/${END_DATE}/0"
JSON="$(connector_fetch "$URL")" || exit 1

connector_emit "biorxiv" '
  [ (.collection // [])[]?
    | {
        source: "biorxiv",
        id: ("doi:" + (.doi // "")),
        title: (.title // ""),
        summary: (.abstract // ""),
        url: (if .doi != null and .doi != "" then "https://doi.org/" + .doi else "" end),
        published: (.date // ""),
        authors: ((.authors // "") | split("; ") | map(select(. != ""))),
        raw: .
      }
    | select(.id != "doi:" and .title != "" and .url != "") ]
' - <<<"$JSON" | jq -c --arg max "$MAX" '.[0:($max | tonumber)]'
