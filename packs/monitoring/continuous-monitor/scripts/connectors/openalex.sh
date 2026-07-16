#!/usr/bin/env bash
# openalex.sh — OpenAlex Source Connector (research-harness-template#418, #451).
#
# Free, keyless REST API (NFR2): https://api.openalex.org/works. OpenAlex asks
# API consumers to identify themselves via a `mailto` query param for its
# "polite pool" (faster, still free, still keyless) — connector-common.sh's
# User-Agent plus this param satisfy that without any auth.
#
# Usage: openalex.sh <query> [max_results]
#   <query> is a JSON array of atomic terms/phrases or a plain string treated
#   as one term. OpenAlex's `search` parameter has no documented boolean OR
#   for mixed phrase/word term lists, so this connector dispatches one
#   request per atomic term and merges the results, deduplicated by work id,
#   newest first, capped at max_results (#513).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: openalex.sh <query> [max_results]}"
MAX="${2:-20}"

TERMS=()
while IFS= read -r _t; do TERMS+=("$_t"); done < <(connector_parse_terms "$QUERY")
[ "${#TERMS[@]}" -gt 0 ] || { echo "openalex: no usable query terms" >&2; exit 2; }

PART_FILES=()
trap 'rm -f "${PART_FILES[@]+"${PART_FILES[@]}"}"' EXIT

for term in "${TERMS[@]+"${TERMS[@]}"}"; do
  ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$term")"
  URL="https://api.openalex.org/works?search=${ENC_QUERY}&per-page=${MAX}&sort=publication_date:desc&mailto=research-harness-template@modeled-information-format.dev"

  JSON="$(connector_fetch "$URL")" || exit 1

  PART="$(mktemp)"
  PART_FILES+=("$PART")
  connector_emit "openalex" '
    [ .results[]?
      | {
          source: "openalex",
          id: (.id // ""),
          title: (.title // .display_name // ""),
          summary: (.abstract_inverted_index // {} | keys | join(" ")),
          url: (.primary_location.landing_page_url // .id // ""),
          published: (.publication_date // (.publication_year | tostring) // ""),
          authors: [ (.authorships // [])[]?.author.display_name ],
          raw: .
        }
      | select(.id != "" and .title != "") ]
  ' - <<<"$JSON" > "$PART" || exit 1
done

connector_merge_candidates "$MAX" "${PART_FILES[@]+"${PART_FILES[@]}"}"
