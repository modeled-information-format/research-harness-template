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
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/continuity-log.sh
. "$ROOT/scripts/monitoring/lib/continuity-log.sh"

TOPIC="${1:?usage: editorial-gate.sh <topic> <run-id> <recommendations.json> <decisions.json> <accepted-out.json>}"
RUN_ID="${2:?missing run-id}"
RECOMMENDATIONS="${3:?missing recommendations.json}"
DECISIONS="${4:?missing decisions.json}"
ACCEPTED_OUT="${5:?missing accepted-out.json}"

[ -f "$RECOMMENDATIONS" ] || { echo "editorial-gate: recommendations file not found: $RECOMMENDATIONS" >&2; exit 2; }
[ -f "$DECISIONS" ] || { echo "editorial-gate: decisions file not found: $DECISIONS" >&2; exit 2; }

DECIDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RESULT="$(python3 "$ROOT/scripts/monitoring/lib/editorial_gate.py" "$RECOMMENDATIONS" "$DECISIONS" "editorial-gate" "$DECIDED_AT")" || {
  echo "editorial-gate: gate evaluation failed" >&2
  exit 1
}

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
