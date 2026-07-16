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
#   <query> is a JSON array of atomic terms/phrases (what run-monitoring.sh
#   passes from continuousMonitoring.queryTerms[]) or a plain string treated
#   as one term. Terms are dispatched per arXiv's own query grammar as
#   `all:"term1" OR all:"term2" ...` -- an unquoted multi-word blob would be
#   exploded by arXiv into OR-of-single-words, matching essentially the
#   whole archive (#513).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: arxiv.sh <query> [max_results]}"
MAX="${2:-20}"

TERMS=()
while IFS= read -r _t; do TERMS+=("$_t"); done < <(connector_parse_terms "$QUERY")
[ "${#TERMS[@]}" -gt 0 ] || { echo "arxiv: no usable query terms" >&2; exit 2; }

SEARCH_EXPR="$(connector_query_quoted_or 'all:' "${TERMS[@]+"${TERMS[@]}"}")"
ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$SEARCH_EXPR")"
URL="http://export.arxiv.org/api/query?search_query=${ENC_QUERY}&start=0&max_results=${MAX}&sortBy=submittedDate&sortOrder=descending"

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
