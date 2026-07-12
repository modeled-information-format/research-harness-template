#!/usr/bin/env bash
# run-monitoring.sh — continuous-monitoring pipeline orchestrator, Phase 1
# (research-harness-template#424): Source Connectors -> concordance rebuild
# (AD-2 ordering) -> Interest-Inference -> Recommendation Engine. Stops
# there -- this script never calls editorial-gate.sh or output-router.sh.
# Per ADR-0019, the review PR the caller (the scheduled workflow) opens
# from this script's output IS the Editorial Gate; publishing happens in
# Phase 2 (run-gate-and-publish.sh), only after that PR is actually
# reviewed.
#
# Usage: run-monitoring.sh <topic-id> <run-id>
# Reads the topic's continuousMonitoring block from harness.config.json.
# Writes reports/<topic>/monitoring/runs/<run-id>/recommendations.json.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TOPIC="${1:?usage: run-monitoring.sh <topic-id> <run-id>}"
RUN_ID="${2:?missing run-id}"

CONFIG="${HARNESS_CONFIG:-$ROOT/harness.config.json}"
TOPIC_CFG="$(jq -c --arg t "$TOPIC" '.topics[] | select(.id == $t)' "$CONFIG")"
[ -n "$TOPIC_CFG" ] || { echo "run-monitoring: topic '$TOPIC' not found in harness.config.json" >&2; exit 2; }

MONITORING_CFG="$(printf '%s' "$TOPIC_CFG" | jq -c '.continuousMonitoring // {}')"
ENABLED="$(printf '%s' "$MONITORING_CFG" | jq -r '.enabled // false')"
if [ "$ENABLED" != "true" ]; then
  echo "run-monitoring: continuous monitoring is not enabled for topic '$TOPIC' -- nothing to do" >&2
  exit 0
fi

BUDGET="$(printf '%s' "$MONITORING_CFG" | jq -r '.budgetSeconds // 30')"
MAX_RESULTS="$(printf '%s' "$MONITORING_CFG" | jq -r '.maxResultsPerSource // 20')"
BIORXIV_DAYS_BACK="$(printf '%s' "$MONITORING_CFG" | jq -r '.biorxivDaysBack // 7')"
THRESHOLD="$(printf '%s' "$MONITORING_CFG" | jq -r '.recommendationThreshold // 0.02')"
# Not `mapfile`/`readarray` -- bash 4+ only, and this needs to run on
# stock macOS bash (3.2, verified locally) as well as GitHub Actions'
# bash 5 runners.
QUERY_TERMS=()
while IFS= read -r _line; do QUERY_TERMS+=("$_line"); done < <(printf '%s' "$MONITORING_CFG" | jq -r '.queryTerms // [] | .[]')
SOURCES=()
while IFS= read -r _line; do SOURCES+=("$_line"); done < <(printf '%s' "$MONITORING_CFG" | jq -r '.sources // ["arxiv","openalex","crossref","semantic-scholar","pubmed","biorxiv","gdelt","hn"] | .[]')

[ "${#QUERY_TERMS[@]}" -gt 0 ] || { echo "run-monitoring: topic '$TOPIC' has continuousMonitoring.enabled=true but no queryTerms" >&2; exit 2; }

RUN_DIR="$ROOT/reports/$TOPIC/monitoring/runs/$RUN_ID"
mkdir -p "$RUN_DIR"
QUERY_STRING="${QUERY_TERMS[*]}"

echo "run-monitoring[$TOPIC/$RUN_ID]: sources=${SOURCES[*]} budget=${BUDGET}s query='$QUERY_STRING'" >&2

CANDIDATE_FILES=()
for source in "${SOURCES[@]}"; do
  OUT_FILE="$RUN_DIR/candidates-$source.json"
  # biorxiv.sh has a different signature (<days-back> [max_results] [server])
  # -- bioRxiv/medRxiv's API has no free-text search, only date-range
  # listing (see the connector's own header comment) -- every other
  # connector takes (<query> [max_results]).
  if [ "$source" = "biorxiv" ]; then
    CONNECTOR_ARGS=("$BIORXIV_DAYS_BACK" "$MAX_RESULTS")
  else
    CONNECTOR_ARGS=("$QUERY_STRING" "$MAX_RESULTS")
  fi
  if bash "$ROOT/scripts/monitoring/run-with-budget.sh" "$TOPIC" "$source" "$BUDGET" "$RUN_ID" \
      -- bash "$ROOT/scripts/monitoring/connectors/$source.sh" "${CONNECTOR_ARGS[@]}" > "$OUT_FILE" 2>>"$RUN_DIR/run.log"; then
    CANDIDATE_FILES+=("$OUT_FILE")
    echo "run-monitoring[$TOPIC/$RUN_ID]: $source ok ($(jq 'length' "$OUT_FILE") candidates)" >&2
  else
    echo "run-monitoring[$TOPIC/$RUN_ID]: $source failed closed, continuing with remaining sources" >&2
    rm -f "$OUT_FILE"
  fi
done

if [ "${#CANDIDATE_FILES[@]}" -eq 0 ]; then
  echo "run-monitoring[$TOPIC/$RUN_ID]: every source failed -- no candidates to score" >&2
  echo "[]" > "$RUN_DIR/recommendations.json"
  exit 0
fi

ALL_CANDIDATES="$RUN_DIR/candidates-all.json"
jq -s 'add' "${CANDIDATE_FILES[@]}" > "$ALL_CANDIDATES"
echo "run-monitoring[$TOPIC/$RUN_ID]: $(jq 'length' "$ALL_CANDIDATES") total candidates across $(( ${#CANDIDATE_FILES[@]} )) source(s)" >&2

# AD-2 ordering: rebuild the concordance before scoring against it.
if ! bash "$ROOT/scripts/build-concordance.sh" >>"$RUN_DIR/run.log" 2>&1; then
  echo "run-monitoring[$TOPIC/$RUN_ID]: concordance rebuild failed, see $RUN_DIR/run.log" >&2
  exit 5
fi

SCORED="$RUN_DIR/candidates-scored.json"
if ! bash "$ROOT/scripts/monitoring/interest-inference.sh" "$ALL_CANDIDATES" "$ROOT/reports/concordance.json" -- "${QUERY_TERMS[@]}" > "$SCORED" 2>>"$RUN_DIR/run.log"; then
  echo "run-monitoring[$TOPIC/$RUN_ID]: interest-inference failed, see $RUN_DIR/run.log" >&2
  exit 5
fi

INTEREST_RECS="$RUN_DIR/recommendations-interest.json"
bash "$ROOT/scripts/monitoring/recommend.sh" interest-match "$SCORED" "$THRESHOLD" > "$INTEREST_RECS" 2>>"$RUN_DIR/run.log"

# Freshen the topic's own research-index.json before gap-detect -- same
# rebuild-before-scoring discipline as the concordance above.
if ! bash "$ROOT/scripts/build-index.sh" "$ROOT/reports/$TOPIC/findings" >>"$RUN_DIR/run.log" 2>&1; then
  echo "run-monitoring[$TOPIC/$RUN_ID]: research-index rebuild failed, see $RUN_DIR/run.log" >&2
  exit 5
fi

GAP_RECS="$RUN_DIR/recommendations-gap.json"
bash "$ROOT/scripts/monitoring/recommend.sh" gap-detect "$CONFIG" "$ROOT/reports/$TOPIC/research-index.json" > "$GAP_RECS" 2>>"$RUN_DIR/run.log"

jq -s 'add' "$INTEREST_RECS" "$GAP_RECS" > "$RUN_DIR/recommendations.json"
COUNT="$(jq 'length' "$RUN_DIR/recommendations.json")"
echo "run-monitoring[$TOPIC/$RUN_ID]: $COUNT recommendation(s) written to $RUN_DIR/recommendations.json -- awaiting Editorial Gate review" >&2
