#!/usr/bin/env bash
# pubmed.sh — PubMed Source Connector (research-harness-template#418, #452).
#
# Free, keyless NCBI E-utilities REST API (NFR2):
# https://eutils.ncbi.nlm.nih.gov/entrez/eutils/. Two-step per NCBI's own
# contract: esearch resolves the query to a PMID list, esummary fetches the
# per-record metadata for those ids. No API key required for the default
# path (an NCBI_API_KEY raises the rate limit but is optional, same
# opt-in-only posture as semantic-scholar.sh).
#
# Usage: pubmed.sh <query> [max_results]
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$SCRIPT_DIR/../lib/connector-common.sh"

QUERY="${1:?usage: pubmed.sh <query> [max_results]}"
MAX="${2:-20}"

ENC_QUERY="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"
API_KEY_PARAM=""
[ -n "${NCBI_API_KEY:-}" ] && API_KEY_PARAM="&api_key=${NCBI_API_KEY}"

SEARCH_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=${ENC_QUERY}&retmax=${MAX}&sort=date&retmode=json${API_KEY_PARAM}"
SEARCH_JSON="$(connector_fetch "$SEARCH_URL")" || exit 1

IDS="$(printf '%s' "$SEARCH_JSON" | jq -r '.esearchresult.idlist // [] | join(",")')"
if [ -z "$IDS" ]; then
  echo "[]"
  exit 0
fi

SUMMARY_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=${IDS}&retmode=json${API_KEY_PARAM}"
SUMMARY_JSON="$(connector_fetch "$SUMMARY_URL")" || exit 1

connector_emit "pubmed" '
  .result
  | to_entries
  | map(select(.key != "uids"))
  | [ .[]
      | {
          source: "pubmed",
          id: ("pmid:" + .key),
          title: (.value.title // ""),
          summary: "",
          url: ("https://pubmed.ncbi.nlm.nih.gov/" + .key + "/"),
          published: (.value.pubdate // .value.sortpubdate // ""),
          authors: [ (.value.authors // [])[]?.name ],
          raw: .value
        }
      | select(.title != "") ]
' - <<<"$SUMMARY_JSON"
