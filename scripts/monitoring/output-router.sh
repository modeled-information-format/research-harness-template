#!/usr/bin/env bash
# output-router.sh — Output Router (research-harness-template#423).
#
# Hands Editorial-Gate-accepted recommendations to the harness's EXISTING
# publish surfaces -- no bespoke publish path, no new schema:
#
#   interest-match  -> projected to a MIF finding (schemas/findings.schema.json,
#                      verdict "inconclusive" pending a full /falsify pass),
#                      gated on scripts/check-citation-integrity.sh, then
#                      written via scripts/write-finding.sh into
#                      reports/<topic>/findings/ -- from there,
#                      .claude/skills/publish-report and publish-blog pick
#                      it up completely unmodified, exactly like any
#                      human-authored finding.
#   gap-detect      -> NOT projected to a finding: a coverage gap is a
#                      meta-observation about the corpus, not a sourced
#                      claim, and has no real citation to gate on.
#                      Surfaced instead as an actionable suggestion in
#                      reports/<topic>/monitoring/recommended-research-areas.jsonl.
#
# HARD REQUIREMENT (NFR6, no exceptions): every recommendation passed in
# must already carry a valid Editorial Gate stamp (gate.passed === true).
# assert_all_gated() enforces this before anything else runs.
#
# Usage: output-router.sh <topic> <run-id> <accepted.json>
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=scripts/monitoring/lib/continuity-log.sh
. "$ROOT/scripts/monitoring/lib/continuity-log.sh"

TOPIC="${1:?usage: output-router.sh <topic> <run-id> <accepted.json>}"
RUN_ID="${2:?missing run-id}"
ACCEPTED="${3:?missing accepted.json}"
[ -f "$ACCEPTED" ] || { echo "output-router: accepted file not found: $ACCEPTED" >&2; exit 2; }

NAMESPACE="harness/$TOPIC"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FINDINGS_DIR="$ROOT/reports/$TOPIC/findings"
GAP_LOG="$ROOT/reports/$TOPIC/monitoring/recommended-research-areas.jsonl"

# The one gate that matters: refuse to run at all if ANYTHING here lacks a
# valid Editorial Gate stamp. This is the actual NFR6 enforcement point.
python3 - "$ACCEPTED" "$ROOT/scripts/monitoring/lib" <<'PYEOF' || exit 5
import json, sys
sys.path.insert(0, sys.argv[2])
from editorial_gate import assert_all_gated
with open(sys.argv[1], encoding="utf-8") as fh:
    recs = json.load(fh)
assert_all_gated(recs)
PYEOF

jq -c '.[] | select(.mode == "interest-match")' "$ACCEPTED" | while IFS= read -r rec; do
  TMP_REC="$(mktemp).json"
  printf '%s' "$rec" > "$TMP_REC"
  TITLE="$(printf '%s' "$rec" | jq -r '.title')"

  FINDING="$(python3 "$ROOT/scripts/monitoring/lib/recommendation_to_finding.py" "$TMP_REC" "$TOPIC" "$NAMESPACE" "$NOW")" || {
    echo "output-router: failed to project recommendation to a finding: $TITLE" >&2
    rm -f "$TMP_REC"
    continue
  }
  TMP_FINDING="$(mktemp).json"
  printf '%s' "$FINDING" > "$TMP_FINDING"

  # mktemp, not a predictable /tmp/name.$$ path (symlink/clobber attack on
  # a shared multi-user /tmp).
  CITATION_CHECK_OUT="$(mktemp)"
  if ! bash "$ROOT/scripts/check-citation-integrity.sh" "$TMP_FINDING" >"$CITATION_CHECK_OUT" 2>&1; then
    REASON="citation-integrity check failed: $(cat "$CITATION_CHECK_OUT")"
    continuity_log_append "$ROOT" "$TOPIC" "$RUN_ID" "ingestion_failure" "output-router" \
      "$TITLE: blocked, not published with a warning" \
      "$(jq -nc --arg reason "$REASON" '{reason: $reason}')"
    echo "output-router: BLOCKED (citation-integrity failed): $TITLE" >&2
    rm -f "$TMP_REC" "$TMP_FINDING" "$CITATION_CHECK_OUT"
    continue
  fi
  rm -f "$CITATION_CHECK_OUT"

  SLUG="$(printf '%s' "$FINDING" | jq -r '."@id" | split(":") | last').json"
  if bash "$ROOT/scripts/write-finding.sh" "$TMP_FINDING" "$FINDINGS_DIR" "$SLUG"; then
    echo "output-router: published finding $SLUG ($TITLE)" >&2
  else
    continuity_log_append "$ROOT" "$TOPIC" "$RUN_ID" "ingestion_failure" "output-router" \
      "$TITLE: write-finding.sh refused the projected finding" "{}"
    echo "output-router: BLOCKED (write-finding refused): $TITLE" >&2
  fi
  rm -f "$TMP_REC" "$TMP_FINDING"
done

jq -c '.[] | select(.mode == "gap-detect")' "$ACCEPTED" | while IFS= read -r rec; do
  mkdir -p "$(dirname "$GAP_LOG")"
  printf '%s\n' "$(printf '%s' "$rec" | jq -c --arg run_id "$RUN_ID" --arg now "$NOW" '. + {run_id: $run_id, surfaced_at: $now}')" >> "$GAP_LOG"
  echo "output-router: surfaced research-gap suggestion: $(printf '%s' "$rec" | jq -r '.dimension')" >&2
done

echo "output-router[$TOPIC]: done" >&2
