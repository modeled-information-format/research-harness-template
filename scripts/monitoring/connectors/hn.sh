#!/usr/bin/env bash
# hn.sh — Hacker News (Algolia) Source Connector (research-harness-template#418, #454).
#
# Free, keyless REST API (NFR2): https://hn.algolia.com/api/v1. Current-events
# signal per the architecture doc's Source Connectors building block. No key,
# no SDK.
#
# Usage: hn.sh <query> [max_results]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/connector-common.sh
. "$ROOT/scripts/monitoring/lib/connector-common.sh"

QUERY="${1:?usage: hn.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="https://hn.algolia.com/api/v1/search_by_date?query=${ENC_QUERY}&tags=story&hitsPerPage=${MAX}"

JSON="$(connector_fetch "$URL")" || exit 1

connector_emit "hn" '
  [ (.hits // [])[]?
    | {
        source: "hn",
        id: (.objectID // ""),
        title: (.title // ""),
        summary: (.story_text // ""),
        url: (.url // ("https://news.ycombinator.com/item?id=" + (.objectID // ""))),
        published: (.created_at // ""),
        authors: (if .author != null then [.author] else [] end),
        raw: .
      }
    | select(.id != "" and .title != "") ]
' - <<<"$JSON"
