#!/usr/bin/env bash
# editorial-gate.sh — Editorial Gate (research-harness-template#422).
#
# Splits Recommendation Engine output into accepted/rejected per an explicit
# decisions map (in the real pipeline, derived from the review PR's actual
# merge/close state, per ADR-0019 -- Story: Scheduler/Trigger wiring,
# research-harness-template#424, is what produces decisions.json from that
# PR). Fail-safe default: a recommendation with no decision recorded is
# rejected, never accepted by omission. Every rejection is written to the
# topic's Continuity Log (research-harness-template#421), never dropped
# silently.
#
# Usage: editorial-gate.sh <topic> <run-id> <recommendations.json> <decisions.json> <accepted-out.json>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/continuity-log.sh
. "$SCRIPT_DIR/lib/continuity-log.sh"

TOPIC="${1:?usage: editorial-gate.sh <topic> <run-id> <recommendations.json> <decisions.json> <accepted-out.json>}"
RUN_ID="${2:?missing run-id}"
RECOMMENDATIONS="${3:?missing recommendations.json}"
DECISIONS="${4:?missing decisions.json}"
ACCEPTED_OUT="${5:?missing accepted-out.json}"

[ -f "$RECOMMENDATIONS" ] || { echo "editorial-gate: recommendations file not found: $RECOMMENDATIONS" >&2; exit 2; }
[ -f "$DECISIONS" ] || { echo "editorial-gate: decisions file not found: $DECISIONS" >&2; exit 2; }

# Every recommendation reaching the gate must already conform to
# schemas/monitoring-recommendation.schema.json -- a violation here means a
# real bug upstream in recommend.sh, so (unlike a connector's occasional
# malformed item) this fails the whole run rather than silently dropping
# one entry.
RECOMMENDATION_SCHEMA="$ROOT/schemas/monitoring-recommendation.schema.json"
if command -v ajv >/dev/null 2>&1 && [ -f "$RECOMMENDATION_SCHEMA" ]; then
  REC_COUNT="$(jq 'length' "$RECOMMENDATIONS")"
  for ((_i = 0; _i < REC_COUNT; _i++)); do
    _tmp_rec="$(mktemp).json"
    jq -c ".[$_i]" "$RECOMMENDATIONS" > "$_tmp_rec"
    if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats -s "$RECOMMENDATION_SCHEMA" -d "$_tmp_rec" >/dev/null 2>&1; then
      echo "editorial-gate: recommendation at index $_i does not conform to monitoring-recommendation.schema.json" >&2
      rm -f "$_tmp_rec"
      exit 1
    fi
    rm -f "$_tmp_rec"
  done
fi

DECIDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RESULT="$(python3 "$SCRIPT_DIR/lib/editorial_gate.py" "$RECOMMENDATIONS" "$DECISIONS" "editorial-gate" "$DECIDED_AT")" || {
  echo "editorial-gate: gate evaluation failed" >&2
  exit 1
}

mkdir -p "$(dirname "$ACCEPTED_OUT")"
printf '%s' "$RESULT" | jq '.accepted' > "$ACCEPTED_OUT"

REJECTED_COUNT="$(printf '%s' "$RESULT" | jq '.rejected | length')"
if [ "$REJECTED_COUNT" -gt 0 ]; then
  printf '%s' "$RESULT" | jq -c '.rejected[]' | while IFS= read -r rejected; do
    TITLE="$(printf '%s' "$rejected" | jq -r '.title // .dimension // "unknown"')"
    REASON="$(printf '%s' "$rejected" | jq -r '.reason')"
    continuity_log_append "$ROOT" "$TOPIC" "$RUN_ID" "gate_rejected" "editorial-gate" \
      "$TITLE: $REASON" "$(printf '%s' "$rejected" | jq -c '{recommendation: .}')"
  done
fi

ACCEPTED_COUNT="$(jq 'length' "$ACCEPTED_OUT")"
echo "editorial-gate[$TOPIC]: $ACCEPTED_COUNT accepted, $REJECTED_COUNT rejected" >&2
