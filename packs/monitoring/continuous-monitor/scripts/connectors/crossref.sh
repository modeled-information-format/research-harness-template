#!/usr/bin/env bash
# crossref.sh — Crossref Source Connector (research-harness-template#418, #451).
#
# Free, keyless REST API (NFR2): https://api.crossref.org/works. Crossref's
# "polite pool" is opted into the same way as OpenAlex's, via a `mailto`
# query param — faster and still free/keyless.
#
# Usage: crossref.sh <query> [max_results]
#   <query> is a JSON array of atomic terms/phrases or a plain string treated
#   as one term. Crossref's `query` parameter applies its own fuzzy
#   relevance blending to a multi-word blob (no phrase-exact OR grammar), so
#   this connector dispatches one request per atomic term and merges the
#   results, deduplicated by DOI, newest first, capped at max_results (#513).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: crossref.sh <query> [max_results]}"
MAX="${2:-20}"

TERMS=()
while IFS= read -r _t; do TERMS+=("$_t"); done < <(connector_parse_terms "$QUERY")
[ "${#TERMS[@]}" -gt 0 ] || { echo "crossref: no usable query terms" >&2; exit 2; }

PART_FILES=()
trap 'rm -f "${PART_FILES[@]+"${PART_FILES[@]}"}"' EXIT

for term in "${TERMS[@]+"${TERMS[@]}"}"; do
  ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$term")"
  URL="https://api.crossref.org/works?query=${ENC_QUERY}&rows=${MAX}&sort=published&order=desc&mailto=research-harness-template@modeled-information-format.dev"

  JSON="$(connector_fetch "$URL")" || exit 1

  PART="$(mktemp)"
  PART_FILES+=("$PART")
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
  ' - <<<"$JSON" > "$PART" || exit 1
done

connector_merge_candidates "$MAX" "${PART_FILES[@]+"${PART_FILES[@]}"}"
