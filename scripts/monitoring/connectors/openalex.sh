#!/usr/bin/env bash
# openalex.sh — OpenAlex Source Connector (research-harness-template#418, #451).
#
# Free, keyless REST API (NFR2): https://api.openalex.org/works. OpenAlex asks
# API consumers to identify themselves via a `mailto` query param for its
# "polite pool" (faster, still free, still keyless) — connector-common.sh's
# User-Agent plus this param satisfy that without any auth.
#
# Usage: openalex.sh <query> [max_results]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/connector-common.sh
. "$ROOT/scripts/monitoring/lib/connector-common.sh"

QUERY="${1:?usage: openalex.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="https://api.openalex.org/works?search=${ENC_QUERY}&per-page=${MAX}&sort=publication_date:desc&mailto=research-harness-template@modeled-information-format.dev"

JSON="$(connector_fetch "$URL")" || exit 1

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
' - <<<"$JSON"
