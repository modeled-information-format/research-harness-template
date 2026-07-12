#!/usr/bin/env bash
# arxiv.sh — arXiv Source Connector (research-harness-template#418, #450).
#
# Free, keyless export API (NFR2): http://export.arxiv.org/api/query. No
# auth, no rate-limit tier to opt into — arXiv asks only for a reasonable
# request rate, which connector-common.sh's timeout/retry bounds already
# respect. RSS/Atom-first (NFR3): this is arXiv's own public Atom feed, no
# SDK.
#
# Usage: arxiv.sh <query> [max_results]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/connector-common.sh
. "$ROOT/scripts/monitoring/lib/connector-common.sh"

QUERY="${1:?usage: arxiv.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="http://export.arxiv.org/api/query?search_query=all:${ENC_QUERY}&start=0&max_results=${MAX}&sortBy=submittedDate&sortOrder=descending"

XML="$(connector_fetch "$URL")" || exit 1
JSON="$(printf '%s' "$XML" | connector_xml_to_json)" || {
  echo "arxiv: failed to parse Atom response" >&2
  exit 1
}

connector_emit "arxiv" '
  [ .entries[]?
    | {
        source: "arxiv",
        id: (.id._text // ""),
        title: ((.title._text // "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")),
        summary: ((.summary._text // "") | gsub("\\s+"; " ")),
        url: (.id._text // ""),
        published: (.published._text // .updated._text // ""),
        authors: (
          (.author // [])
          | (if type == "array" then . else [.] end)
          | map(.name._text // empty)
        ),
        raw: .
      }
    | select(.id != "" and .title != "") ]
' - <<<"$JSON"
