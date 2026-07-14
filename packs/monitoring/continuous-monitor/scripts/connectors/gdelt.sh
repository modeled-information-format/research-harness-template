#!/usr/bin/env bash
# gdelt.sh — GDELT DOC 2.0 Source Connector (research-harness-template#418, #453).
#
# Free, keyless REST API (NFR2): https://api.gdeltproject.org/api/v2/doc/doc.
# Current-events signal per the architecture doc's Source Connectors building
# block (GDELT DOC 2.0/GKG). No API key, no SDK — a single JSON GET.
#
# Usage: gdelt.sh <query> [max_results]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: gdelt.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="https://api.gdeltproject.org/api/v2/doc/doc?query=${ENC_QUERY}&mode=artlist&maxrecords=${MAX}&sort=datedesc&format=json"

JSON="$(connector_fetch "$URL")" || exit 1

connector_emit "gdelt" '
  [ (.articles // [])[]?
    | {
        source: "gdelt",
        id: (.url // ""),
        title: (.title // ""),
        summary: "",
        url: (.url // ""),
        published: (.seendate // ""),
        authors: (if .domain != null then [.domain] else [] end),
        raw: .
      }
    | select(.id != "" and .title != "") ]
' - <<<"$JSON"
