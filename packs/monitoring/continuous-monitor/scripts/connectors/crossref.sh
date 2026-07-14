#!/usr/bin/env bash
# crossref.sh — Crossref Source Connector (research-harness-template#418, #451).
#
# Free, keyless REST API (NFR2): https://api.crossref.org/works. Crossref's
# "polite pool" is opted into the same way as OpenAlex's, via a `mailto`
# query param — faster and still free/keyless.
#
# Usage: crossref.sh <query> [max_results]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: crossref.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="https://api.crossref.org/works?query=${ENC_QUERY}&rows=${MAX}&sort=published&order=desc&mailto=research-harness-template@modeled-information-format.dev"

JSON="$(connector_fetch "$URL")" || exit 1

connector_emit "crossref" '
  [ .message.items[]?
    | {
        source: "crossref",
        id: (.DOI // ""),
        title: ((.title // [""])[0]),
        summary: (.abstract // ""),
        url: (.URL // (if .DOI != null then "https://doi.org/" + .DOI else "" end)),
        published: (
          (.published."date-parts"[0] // [])
          | map(tostring)
          | join("-")
        ),
        authors: [ (.author // [])[]? | ((.given // "") + " " + (.family // "")) | ltrimstr(" ") | rtrimstr(" ") ],
        raw: .
      }
    | select(.id != "" and .title != "") ]
' - <<<"$JSON"
