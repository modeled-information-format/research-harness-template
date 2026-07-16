#!/usr/bin/env bash
# hn.sh — Hacker News (Algolia) Source Connector (research-harness-template#418, #454).
#
# Free, keyless REST API (NFR2): https://hn.algolia.com/api/v1. Current-events
# signal per the architecture doc's Source Connectors building block. No key,
# no SDK.
#
# Usage: hn.sh <query> [max_results]
#   <query> is a JSON array of atomic terms/phrases or a plain string treated
#   as one term. Algolia's `query` parameter has no OR operator and applies
#   AND-of-all-words to a multi-word blob (0 hits for any real term list,
#   #513) -- so this connector dispatches one request per atomic term and
#   merges the results, deduplicated by objectID, newest first, capped at
#   max_results.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: hn.sh <query> [max_results]}"
MAX="${2:-20}"

TERMS=()
while IFS= read -r _t; do TERMS+=("$_t"); done < <(connector_parse_terms "$QUERY")
[ "${#TERMS[@]}" -gt 0 ] || { echo "hn: no usable query terms" >&2; exit 2; }

PART_FILES=()
trap 'rm -f "${PART_FILES[@]+"${PART_FILES[@]}"}"' EXIT

for term in "${TERMS[@]+"${TERMS[@]}"}"; do
  ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$term")"
  URL="https://hn.algolia.com/api/v1/search_by_date?query=${ENC_QUERY}&tags=story&hitsPerPage=${MAX}"

  JSON="$(connector_fetch "$URL")" || exit 1

  PART="$(mktemp)"
  PART_FILES+=("$PART")
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
  ' - <<<"$JSON" > "$PART" || exit 1
done

connector_merge_candidates "$MAX" "${PART_FILES[@]+"${PART_FILES[@]}"}"
