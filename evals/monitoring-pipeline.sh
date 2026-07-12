#!/usr/bin/env bash
# monitoring-pipeline.sh — dry-run eval for continuous research monitoring
# (research-harness-template#416, Story #425). Fixture source responses
# (no live network calls -- CI must stay deterministic and not depend on,
# or get rate-limited by, real external APIs), real pipeline logic:
# Interest-Inference -> Recommendation Engine -> Editorial Gate ->
# Output Router, exercised against a throwaway topic under a tmpdir, never
# the real reports/ corpus.
#
# Covers three required paths (Story #425's own scope):
#   1. Fail-closed: a synthetic slow command trips run-with-budget.sh's
#      timeout path and lands a Continuity Log entry.
#   2. Editorial Gate block: assert_all_gated() refuses an ungated
#      recommendation; the whole no-decision-recorded fail-safe path also
#      rejects and logs.
#   3. Full accept-to-publish: a fixture candidate with a real citation
#      is scored, recommended, gate-accepted, and published as a real,
#      schema+citation-integrity-valid MIF finding.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
TOPIC="eval-monitoring-topic"
# run-with-budget.sh, editorial-gate.sh, and output-router.sh all resolve
# their own paths from the repo root, not a tmpdir, so every case below
# runs against a throwaway topic under the REAL reports/ tree. Cleaned up
# by the same EXIT trap as $TMP, not a trailing rm -rf -- a CI cancellation
# or timeout partway through must not leave residue in the tracked tree
# (CLAUDE.md: "Ephemeral artifacts go to mktemp outside the tree, never
# into reports/").
REAL_TOPIC_DIR="$ROOT/reports/$TOPIC"
trap 'rm -rf "$TMP" "$REAL_TOPIC_DIR"' EXIT
fail=0
note() { printf '  monitoring-pipeline: %s\n' "$1"; }

TOPIC_DIR="$TMP/reports/$TOPIC"
mkdir -p "$TOPIC_DIR/findings" "$TOPIC_DIR/monitoring"

# A minimal but real concordance -- one node whose label shares real
# tokens with the fixture candidate below, so a genuine (not stubbed)
# overlap match happens.
cat > "$TMP/concordance.json" <<'EOF'
{
  "@type": "Concordance",
  "nodes": [
    { "id": "urn:mif:concept:eval:knowledge-graph-provenance", "kind": "concept",
      "label": "Knowledge Graph Provenance Tracking", "topics": ["eval-monitoring-topic"],
      "entityType": "concept", "ontology": "mif-generic@1.0.0", "verdict": "survived", "flagged": false }
  ],
  "edges": []
}
EOF

# --- Case 1: fail-closed on timeout ---------------------------------------
mkdir -p "$REAL_TOPIC_DIR/monitoring"
rm -f "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl"
bash "$ROOT/scripts/monitoring/run-with-budget.sh" "$TOPIC" "eval-slow-source" 1 "eval-run-1" \
  -- sleep 5 >/dev/null 2>&1
if [ -f "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl" ] \
   && jq -e '.event_type == "budget_exceeded"' "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl" >/dev/null 2>&1; then
  note "fail-closed budget path logs budget_exceeded to the Continuity Log"
else
  note "FAIL: no budget_exceeded Continuity Log entry after a timeout"; fail=1
fi

# --- Case 2: Editorial Gate no-bypass + fail-safe default -----------------
BYPASS_CHECK="$(python3 -c "
import sys
sys.path.insert(0, '$ROOT/scripts/monitoring/lib')
from editorial_gate import assert_all_gated
try:
    assert_all_gated([{'mode': 'interest-match', 'title': 'x'}])
    print('FAIL')
except AssertionError:
    print('OK')
" 2>/dev/null)"
if [ "$BYPASS_CHECK" = "OK" ]; then
  note "assert_all_gated refuses an ungated recommendation"
else
  note "FAIL: assert_all_gated did not refuse an ungated recommendation"; fail=1
fi

cat > "$TMP/rec-no-decision.json" <<EOF
[{"mode":"interest-match","id":"eval-candidate-1","title":"Eval Candidate",
  "url":"https://example.org/eval-candidate-1","citations":[{"type":"primary-source","url":"https://example.org/eval-candidate-1"}]}]
EOF
echo '{}' > "$TMP/empty-decisions.json"
rm -f "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl"
bash "$ROOT/scripts/monitoring/editorial-gate.sh" "$TOPIC" "eval-run-2" \
  "$TMP/rec-no-decision.json" "$TMP/empty-decisions.json" "$TMP/accepted-none.json" >/dev/null 2>&1
if [ "$(jq 'length' "$TMP/accepted-none.json")" = "0" ] \
   && jq -e '.event_type == "gate_rejected"' "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl" >/dev/null 2>&1; then
  note "no-decision-recorded candidate is rejected by the fail-safe default and logged"
else
  note "FAIL: fail-safe default did not reject+log a no-decision candidate"; fail=1
fi

# --- Case 3: full accept-to-publish ----------------------------------------
cat > "$TMP/candidates.json" <<'EOF'
[{"source":"eval","id":"https://example.org/eval-candidate-2",
  "title":"Knowledge Graph Provenance Tracking In Practice",
  "summary":"A study of provenance tracking approaches for knowledge graph systems.",
  "url":"https://example.org/eval-candidate-2","published":"2026-01-01","authors":[],"raw":{}}]
EOF
if ! bash "$ROOT/scripts/monitoring/interest-inference.sh" "$TMP/candidates.json" "$TMP/concordance.json" \
     -- knowledge graph provenance > "$TMP/scored.json" 2>"$TMP/scored.err"; then
  note "FAIL: interest-inference.sh failed: $(cat "$TMP/scored.err")"; fail=1
fi
bash "$ROOT/scripts/monitoring/recommend.sh" interest-match "$TMP/scored.json" 0.0 > "$TMP/recs.json" 2>/dev/null
if [ "$(jq 'length' "$TMP/recs.json" 2>/dev/null)" != "1" ]; then
  note "FAIL: expected 1 recommendation, got: $(cat "$TMP/recs.json")"; fail=1
fi

DECISION_KEY="$(jq -r '.[0] | (.id // ("gap:" + .dimension))' "$TMP/recs.json")"
jq -n --arg k "$DECISION_KEY" '{($k): "accept"}' > "$TMP/decisions-accept.json"
rm -f "$REAL_TOPIC_DIR/monitoring/continuity-log.jsonl"
bash "$ROOT/scripts/monitoring/editorial-gate.sh" "$TOPIC" "eval-run-3" \
  "$TMP/recs.json" "$TMP/decisions-accept.json" "$TMP/accepted.json" >/dev/null 2>&1
if [ "$(jq 'length' "$TMP/accepted.json" 2>/dev/null)" != "1" ]; then
  note "FAIL: expected 1 accepted recommendation, got: $(cat "$TMP/accepted.json" 2>/dev/null)"; fail=1
else
  if bash "$ROOT/scripts/monitoring/output-router.sh" "$TOPIC" "eval-run-3" "$TMP/accepted.json" >/dev/null 2>&1; then
    PUBLISHED="$(find "$REAL_TOPIC_DIR/findings" -name '*.json' 2>/dev/null | head -1)"
    if [ -n "$PUBLISHED" ] && bash "$ROOT/scripts/check-citation-integrity.sh" "$PUBLISHED" >/dev/null 2>&1; then
      note "accept-to-publish: a real MIF finding was written and passes citation-integrity"
    else
      note "FAIL: output-router.sh ran but no valid finding was published"; fail=1
    fi
  else
    note "FAIL: output-router.sh failed on a fully gated, valid recommendation"; fail=1
  fi
fi

# $REAL_TOPIC_DIR cleanup happens in the EXIT trap above, not here -- it
# must fire even if this script is killed/cancelled before reaching this
# line.

if [ "$fail" -eq 0 ]; then
  echo "monitoring-pipeline: PASS"
  exit 0
fi
echo "monitoring-pipeline: FAIL"
exit 1
