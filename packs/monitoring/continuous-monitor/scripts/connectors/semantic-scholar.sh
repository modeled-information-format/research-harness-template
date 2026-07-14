#!/usr/bin/env bash
# semantic-scholar.sh — Semantic Scholar Source Connector
# (research-harness-template#418, #451).
#
# Free, keyless REST API (NFR2): https://api.semanticscholar.org/graph/v1.
# An API key raises the rate limit but is never required for the default
# path; if SEMANTIC_SCHOLAR_API_KEY is set it is used, otherwise the
# connector runs fully keyless (opt-in enhancement, never a hard
# dependency — see docs/reference/dependencies.md's "Continuous monitoring
# source APIs" section, #455).
#
# Usage: semantic-scholar.sh <query> [max_results]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: semantic-scholar.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
URL="https://api.semanticscholar.org/graph/v1/paper/search?query=${ENC_QUERY}&limit=${MAX}&fields=title,abstract,url,publicationDate,authors,externalIds"

EXTRA_ARGS=()
if [ -n "${SEMANTIC_SCHOLAR_API_KEY:-}" ]; then
  EXTRA_ARGS+=(-H "x-api-key: ${SEMANTIC_SCHOLAR_API_KEY}")
fi

JSON="$(connector_fetch "$URL" "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")" || exit 1

connector_emit "semantic-scholar" '
  [ .data[]?
    | {
        source: "semantic-scholar",
        id: (.externalIds.DOI // .paperId // ""),
        title: (.title // ""),
        summary: (.abstract // ""),
        # The API does not always populate .url; fall back to a DOI-derived
        # url rather than emitting an empty one -- a candidate with no
        # primary-source URL and no concordance match fails
        # recommend.py citation requirement downstream.
        url: (.url // (if .externalIds.DOI != null then "https://doi.org/" + .externalIds.DOI else "" end)),
        published: (.publicationDate // ""),
        authors: [ (.authors // [])[]?.name ],
        raw: .
      }
    | select(.id != "" and .title != "" and .url != "") ]
' - <<<"$JSON"
