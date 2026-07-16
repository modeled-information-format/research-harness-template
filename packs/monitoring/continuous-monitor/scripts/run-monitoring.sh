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
# SCRIPT_DIR is this pack's own scripts/ dir (packs/monitoring/continuous-monitor/scripts) --
# every sibling script/connector/lib reference below is resolved relative to
# it, not a hardcoded depth, so this file doesn't need to know where the pack
# happens to live in the repo tree. ROOT is the repo root
# (research-harness-template#483: this pipeline moved from the core
# scripts/monitoring/** tree to packs/monitoring/continuous-monitor/scripts/**).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

SUBJECT="${1:?usage: run-monitoring.sh <domain-or-topic-id> <run-id>}"
RUN_ID="${2:?missing run-id}"

# Master gate (research-harness-template#483): continuous monitoring is now a
# pack (packs/monitoring/continuous-monitor), not a bespoke core capability --
# packs[] "continuous-monitor".enabled is the repo-wide switch that must be on
# before any per-topic continuousMonitoring block is even consulted. This is
# the fix for the exact architectural gap #483 flagged: a config flag that
# didn't route through the packs[] control plane at all.
CONFIG="${HARNESS_CONFIG:-$ROOT/harness.config.json}"
PACK_ENABLED="$(jq -r 'any(.packs[]?; .name == "continuous-monitor" and .enabled == true)' "$CONFIG")"
if [ "$PACK_ENABLED" != "true" ]; then
  echo "run-monitoring: the 'continuous-monitor' pack is not enabled in harness.config.json packs[] -- nothing to do" >&2
  exit 0
fi

# Subject resolution (#521, #522): a first-class monitoringDomains[] entry
# wins; a topic's continuousMonitoring block is the topic-bound fallback.
# A DOMAIN is a current-events monitoring subject in its own right (weighted,
# curated sources, momentum-ranked, digest output) -- it may optionally bind
# to a topic via projectToTopic, which scopes concordance scoring and is
# where gate-accepted candidates publish.
DOMAIN_CFG="$(jq -c --arg d "$SUBJECT" '(.monitoringDomains // [])[] | select(.id == $d)' "$CONFIG")"
if [ -n "$DOMAIN_CFG" ]; then
  MODE="domain"
  MONITORING_CFG="$DOMAIN_CFG"
  ENABLED="$(printf '%s' "$MONITORING_CFG" | jq -r 'if has("enabled") then .enabled else true end')"
  if [ "$ENABLED" != "true" ]; then
    echo "run-monitoring: monitoring domain '$SUBJECT' is disabled -- nothing to do" >&2
    exit 0
  fi
  # A domain's interest scoring is anchored to its own queryTerms; a
  # projectToTopic binding additionally scores against that topic's
  # concordance nodes (#514's topic scoping, reused unchanged).
  SCORE_TOPIC="$(printf '%s' "$MONITORING_CFG" | jq -r '.projectToTopic // empty')"
  DOMAIN_WEIGHT="$(printf '%s' "$MONITORING_CFG" | jq -r '.weight // 1')"
else
  MODE="topic"
  TOPIC_CFG="$(jq -c --arg t "$SUBJECT" '.topics[] | select(.id == $t)' "$CONFIG")"
  [ -n "$TOPIC_CFG" ] || { echo "run-monitoring: '$SUBJECT' is neither a monitoringDomains[] id nor a topic id in harness.config.json" >&2; exit 2; }

  MONITORING_CFG="$(printf '%s' "$TOPIC_CFG" | jq -c '.continuousMonitoring // {}')"
  ENABLED="$(printf '%s' "$MONITORING_CFG" | jq -r '.enabled // false')"
  if [ "$ENABLED" != "true" ]; then
    echo "run-monitoring: continuous monitoring is not enabled for topic '$SUBJECT' -- nothing to do" >&2
    exit 0
  fi
  SCORE_TOPIC="$SUBJECT"
  DOMAIN_WEIGHT="1"
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

[ "${#QUERY_TERMS[@]}" -gt 0 ] || { echo "run-monitoring: monitoring subject '$SUBJECT' is enabled but has no queryTerms" >&2; exit 2; }

# A domain's runs live under reports/_monitoring/<domain>/ -- a domain is
# not a topic and must not fabricate a topic directory; a topic-bound run
# keeps the original per-topic location.
if [ "$MODE" = "domain" ]; then
  RUN_DIR="$ROOT/reports/_monitoring/$SUBJECT/runs/$RUN_ID"
else
  RUN_DIR="$ROOT/reports/$SUBJECT/monitoring/runs/$RUN_ID"
fi
mkdir -p "$RUN_DIR"
# Connectors receive queryTerms as a JSON array, NOT a space-joined blob:
# each term is an atomic phrase the connector dispatches per its own API's
# query grammar (#513 -- the flattened blob was parsed as OR-of-single-words
# by arXiv and AND-of-all-words by Algolia, destroying relevance both ways).
QUERY_JSON="$(printf '%s' "$MONITORING_CFG" | jq -c '.queryTerms')"

echo "run-monitoring[$SUBJECT/$RUN_ID]: mode=$MODE sources=${SOURCES[*]} budget=${BUDGET}s queryTerms=${QUERY_JSON}" >&2

CANDIDATE_FILES=()
for source in "${SOURCES[@]+"${SOURCES[@]}"}"; do
  OUT_FILE="$RUN_DIR/candidates-$source.json"
  # biorxiv.sh has a different signature (<days-back> [max_results] [server])
  # -- bioRxiv/medRxiv's API has no free-text search, only date-range
  # listing (see the connector's own header comment) -- every other
  # connector takes (<query> [max_results]).
  if [ "$source" = "biorxiv" ]; then
    CONNECTOR_ARGS=("$BIORXIV_DAYS_BACK" "$MAX_RESULTS")
  else
    CONNECTOR_ARGS=("$QUERY_JSON" "$MAX_RESULTS")
  fi
  if bash "$SCRIPT_DIR/run-with-budget.sh" "$SUBJECT" "$source" "$BUDGET" "$RUN_ID" \
      -- bash "$SCRIPT_DIR/connectors/$source.sh" "${CONNECTOR_ARGS[@]+"${CONNECTOR_ARGS[@]}"}" > "$OUT_FILE" 2>>"$RUN_DIR/run.log"; then
    CANDIDATE_FILES+=("$OUT_FILE")
    echo "run-monitoring[$SUBJECT/$RUN_ID]: $source ok ($(jq 'length' "$OUT_FILE") candidates)" >&2
  else
    echo "run-monitoring[$SUBJECT/$RUN_ID]: $source failed closed, continuing with remaining sources" >&2
    rm -f "$OUT_FILE"
  fi
done

if [ "${#CANDIDATE_FILES[@]}" -eq 0 ]; then
  echo "run-monitoring[$SUBJECT/$RUN_ID]: every source failed -- no candidates to score" >&2
  echo "[]" > "$RUN_DIR/recommendations.json"
  exit 0
fi

ALL_CANDIDATES="$RUN_DIR/candidates-all.json"
jq -s 'add' "${CANDIDATE_FILES[@]+"${CANDIDATE_FILES[@]}"}" > "$ALL_CANDIDATES"
echo "run-monitoring[$SUBJECT/$RUN_ID]: $(jq 'length' "$ALL_CANDIDATES") total candidates across $(( ${#CANDIDATE_FILES[@]} )) source(s)" >&2

# AD-2 ordering: rebuild the concordance before scoring against it. A
# standalone domain (no projectToTopic) has no concordance stake at all --
# its relevance signal is its own queryTerms -- so skip the rebuild and pass
# an empty concordance instead of paying a corpus rebuild for nothing.
SCORED="$RUN_DIR/candidates-scored.json"
if [ -n "$SCORE_TOPIC" ]; then
  if ! bash "$ROOT/scripts/build-concordance.sh" >>"$RUN_DIR/run.log" 2>&1; then
    echo "run-monitoring[$SUBJECT/$RUN_ID]: concordance rebuild failed, see $RUN_DIR/run.log" >&2
    exit 5
  fi
  CONCORDANCE_FILE="$ROOT/reports/concordance.json"
else
  CONCORDANCE_FILE="$RUN_DIR/concordance-empty.json"
  printf '{"@type": "Concordance", "nodes": [], "edges": []}' > "$CONCORDANCE_FILE"
  SCORE_TOPIC="$SUBJECT"
fi

# --topic scopes concordance scoring to the bound topic's own nodes (#514):
# the corpus-global concordance made any candidate sharing two tokens with
# any label anywhere in a 55-topic corpus score as an "interest match".
if ! bash "$SCRIPT_DIR/interest-inference.sh" "$ALL_CANDIDATES" "$CONCORDANCE_FILE" --topic "$SCORE_TOPIC" -- "${QUERY_TERMS[@]+"${QUERY_TERMS[@]}"}" > "$SCORED" 2>>"$RUN_DIR/run.log"; then
  echo "run-monitoring[$SUBJECT/$RUN_ID]: interest-inference failed, see $RUN_DIR/run.log" >&2
  exit 5
fi

# Momentum ranking + prior-coverage suppression (#523): the memory is a
# single shared JSONL, written ONLY by the gate-accept path
# (run-gate-and-publish.sh) -- single-writer discipline per the
# weekly-research reference.
PRIOR_COVERAGE="${MONITOR_PRIOR_COVERAGE:-$ROOT/reports/_monitoring/prior-coverage.jsonl}"
INTEREST_RECS="$RUN_DIR/recommendations-interest.json"
bash "$SCRIPT_DIR/recommend.sh" interest-match "$SCORED" "$THRESHOLD" \
  --memory "$PRIOR_COVERAGE" --domain "$SUBJECT" --weight "$DOMAIN_WEIGHT" \
  > "$INTEREST_RECS" 2>>"$RUN_DIR/run.log"

if [ "$MODE" = "topic" ]; then
  # Freshen the topic's own research-index.json before gap-detect -- same
  # rebuild-before-scoring discipline as the concordance above. Gap
  # detection is inherently topic-bound (config-declared dimensions vs the
  # topic's findings); a standalone domain has neither.
  if ! bash "$ROOT/scripts/build-index.sh" "$ROOT/reports/$SUBJECT/findings" >>"$RUN_DIR/run.log" 2>&1; then
    echo "run-monitoring[$SUBJECT/$RUN_ID]: research-index rebuild failed, see $RUN_DIR/run.log" >&2
    exit 5
  fi

  GAP_RECS="$RUN_DIR/recommendations-gap.json"
  bash "$SCRIPT_DIR/recommend.sh" gap-detect "$CONFIG" "$ROOT/reports/$SUBJECT/research-index.json" > "$GAP_RECS" 2>>"$RUN_DIR/run.log"

  jq -s 'add' "$INTEREST_RECS" "$GAP_RECS" > "$RUN_DIR/recommendations.json"
else
  cp "$INTEREST_RECS" "$RUN_DIR/recommendations.json"
fi

# Per-run digest (#524): the Editorial Gate's human review surface, in both
# runtimes (review-PR body in Actions, rendered artifact in-session).
bash "$SCRIPT_DIR/render-digest.sh" "$RUN_DIR/recommendations.json" "$SUBJECT" "$RUN_ID" > "$RUN_DIR/digest.md" 2>>"$RUN_DIR/run.log" || {
  echo "run-monitoring[$SUBJECT/$RUN_ID]: digest rendering failed, see $RUN_DIR/run.log" >&2
  exit 5
}

COUNT="$(jq 'length' "$RUN_DIR/recommendations.json")"
echo "run-monitoring[$SUBJECT/$RUN_ID]: $COUNT recommendation(s) written to $RUN_DIR/recommendations.json (digest: $RUN_DIR/digest.md) -- awaiting Editorial Gate review" >&2
