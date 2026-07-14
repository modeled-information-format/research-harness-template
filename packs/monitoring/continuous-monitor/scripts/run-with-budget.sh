#!/usr/bin/env bash
# run-with-budget.sh — per-run budget/timeout enforcement (research-harness-template#421, NFR1).
#
# Wraps one ingestion step (a Source Connector, typically) in a hard wall-
# clock budget. On success, passes the wrapped command's stdout through
# unchanged. On timeout OR any non-zero exit, fails closed for THIS
# connector: it does NOT partial-succeed silently -- it records the
# specific failure (which source, why) in the topic's Continuity Log and
# exits non-zero, rather than returning incomplete/truncated data as if it
# were complete. Whether one connector's failure stops the WHOLE monitoring
# run is the orchestrator's call (run-monitoring.sh continues with the
# remaining sources), not this wrapper's.
#
# Usage: run-with-budget.sh <topic> <source-name> <budget-seconds> <run-id> -- <command...>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/continuity-log.sh
. "$SCRIPT_DIR/lib/continuity-log.sh"

TOPIC="${1:?usage: run-with-budget.sh <topic> <source-name> <budget-seconds> <run-id> -- <command...>}"
SOURCE_NAME="${2:?missing source-name}"
BUDGET_SECONDS="${3:?missing budget-seconds}"
RUN_ID="${4:?missing run-id}"
shift 4
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "run-with-budget: no command given after --" >&2; exit 2; }

if ! command -v timeout >/dev/null 2>&1; then
  echo "run-with-budget: 'timeout' is required on PATH and was not found" >&2
  exit 2
fi

OUT_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
timeout "$BUDGET_SECONDS" "$@" >"$OUT_FILE" 2>"$ERR_FILE"
RC=$?

if [ "$RC" -eq 0 ]; then
  cat "$OUT_FILE"
  rm -f "$OUT_FILE" "$ERR_FILE"
  exit 0
fi

STDERR_TAIL="$(tail -c 500 "$ERR_FILE" 2>/dev/null)"
rm -f "$OUT_FILE" "$ERR_FILE"

if [ "$RC" -eq 124 ]; then
  continuity_log_append "$ROOT" "$TOPIC" "$RUN_ID" "budget_exceeded" "$SOURCE_NAME" \
    "exceeded ${BUDGET_SECONDS}s per-run budget" \
    "$(jq -nc --arg budget "$BUDGET_SECONDS" '{budget_seconds: ($budget | tonumber)}')"
else
  DETAILS_JSON="$(jq -nc --arg rc "$RC" --arg stderr "$STDERR_TAIL" '{exit_code: ($rc | tonumber), stderr_tail: $stderr}')"
  continuity_log_append "$ROOT" "$TOPIC" "$RUN_ID" "ingestion_failure" "$SOURCE_NAME" \
    "command exited $RC" "$DETAILS_JSON"
fi

echo "run-with-budget[$SOURCE_NAME]: fail-closed (rc=$RC), see Continuity Log" >&2
exit "$RC"
