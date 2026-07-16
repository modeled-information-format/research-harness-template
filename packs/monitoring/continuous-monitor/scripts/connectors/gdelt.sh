#!/usr/bin/env bash
# gdelt.sh — GDELT DOC 2.0 Source Connector (research-harness-template#418, #453).
#
# Free, keyless REST API (NFR2): https://api.gdeltproject.org/api/v2/doc/doc.
# Current-events signal per the architecture doc's Source Connectors building
# block (GDELT DOC 2.0/GKG). No API key, no SDK — a single JSON GET.
#
# Usage: gdelt.sh <query> [max_results]
#   <query> is a JSON array of atomic terms/phrases or a plain string treated
#   as one term. GDELT's query grammar supports quoted phrases and OR inside
#   parentheses, so terms dispatch as `("term1" OR "term2")` in one request
#   (#513).
#
# Rate limiting (#515): GDELT enforces its one-request-per-5-seconds limit by
# returning HTTP 200 with a PLAINTEXT notice. connector_guard_json detects
# that (instead of letting jq fail with a misleading parse error), and this
# connector retries once after GDELT_RETRY_DELAY_SECONDS (default 6) before
# failing closed with the true cause in the Continuity Log.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: gdelt.sh <query> [max_results]}"
MAX="${2:-20}"

TERMS=()
while IFS= read -r _t; do TERMS+=("$_t"); done < <(connector_parse_terms "$QUERY")
[ "${#TERMS[@]}" -gt 0 ] || { echo "gdelt: no usable query terms" >&2; exit 2; }

GDELT_QUERY="$(connector_query_quoted_or '' "${TERMS[@]+"${TERMS[@]}"}")"
if [ "${#TERMS[@]}" -gt 1 ]; then
  GDELT_QUERY="(${GDELT_QUERY})"
fi

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$GDELT_QUERY")"
URL="https://api.gdeltproject.org/api/v2/doc/doc?query=${ENC_QUERY}&mode=artlist&maxrecords=${MAX}&sort=datedesc&format=json"

JSON="$(connector_fetch "$URL")" || exit 1
GUARD_RC=0
connector_guard_json "gdelt" "$JSON" || GUARD_RC=$?
if [ "$GUARD_RC" -ne 0 ]; then
  [ "$GUARD_RC" -eq 75 ] || exit 1
  sleep "${GDELT_RETRY_DELAY_SECONDS:-6}"
  JSON="$(connector_fetch "$URL")" || exit 1
  connector_guard_json "gdelt" "$JSON" || {
    echo "gdelt: still rate limited after one spaced retry -- failing closed" >&2
    exit 1
  }
fi

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
