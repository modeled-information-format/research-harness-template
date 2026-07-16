#!/usr/bin/env bash
# monitoring-relevance.sh — golden-query-set relevance eval for continuous
# monitoring (research-harness-template#516). The pre-existing monitoring
# eval exercises the pipeline's MECHANICS (schemas, budgets, gate
# fail-safety); nothing asserted the recommendations were topically
# RELEVANT, which is how two critical scoring defects (#513 query
# flattening, #514 corpus-global scoring) shipped green: their output was
# schema-valid, citation-bearing, threshold-clearing, and useless.
#
# Recorded fixtures, no live network (CI must stay deterministic): a golden
# topic ("eval-golden-topic", queryTerms: "git notes" / "AI provenance" /
# "commit attestation"), five known-relevant candidates, five
# known-irrelevant candidates lifted from the real 2026-07-16 diagnostic run
# (Hopf-conjecture mathematics, neutron-star physics, ...), and a
# concordance carrying both the topic's own nodes and cross-topic decoy
# nodes that the irrelevant candidates DO token-overlap.
#
# Asserts, at the production default threshold (0.02):
#   1. Zero known-irrelevant fixtures are recommended.
#   2. At least 80% (4/5) of known-relevant fixtures are recommended.
#   3. Topic scoping holds: the Hopf sentinel, which shares >= 2 tokens with
#      a DIFFERENT topic's concordance node, matches no concordance node
#      (corpus-global scoring -- the #514 defect -- would match it).
#   4. Every emitted recommendation validates against
#      schemas/monitoring-recommendation.schema.json.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PACK="packs/monitoring/continuous-monitor"
FX="evals/fixtures/monitoring-relevance"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  monitoring-relevance: %s\n' "$1"; }

bash "$PACK/scripts/interest-inference.sh" "$FX/candidates.json" "$FX/concordance.json" \
  --topic eval-golden-topic -- "git notes" "AI provenance" "commit attestation" \
  > "$TMP/scored.json" 2>"$TMP/scored.err" || {
  note "interest-inference failed: $(cat "$TMP/scored.err")"
  exit 1
}
bash "$PACK/scripts/recommend.sh" interest-match "$TMP/scored.json" 0.02 \
  > "$TMP/recs.json" 2>"$TMP/recs.err" || {
  note "recommend failed: $(cat "$TMP/recs.err")"
  exit 1
}

REC_IDS="$(jq -r '[.[].id] | sort | join(",")' "$TMP/recs.json")"

# 1. Zero known-irrelevant recommended.
# I6-fieldnotes shares exactly ONE query token ("notes") -- the
# tfidf-fallback noise floor (live-acceptance finding on Epic #518) must
# keep it below the default threshold.
for bad in I1-hopf I2-neutron I3-earthquake I4-farm I5-poetry I6-fieldnotes; do
  if jq -e --arg id "$bad" 'any(.[]; .id == $id)' "$TMP/recs.json" >/dev/null; then
    note "known-irrelevant candidate '$bad' was recommended (recommended: $REC_IDS)"
    fail=1
  fi
done

# 2. >= 80% of known-relevant recommended.
REL_COUNT="$(jq '[.[] | select(.id | startswith("R"))] | length' "$TMP/recs.json")"
if [ "$REL_COUNT" -lt 4 ]; then
  note "only $REL_COUNT/5 known-relevant fixtures recommended, need >= 4 (recommended: $REC_IDS)"
  fail=1
fi

# 3. Topic scoping (regression sentinel for #514).
if jq -e '.[] | select(.id == "I1-hopf") | .inference.matched_nodes | length > 0' \
    "$TMP/scored.json" >/dev/null 2>&1; then
  note "I1-hopf matched concordance nodes despite --topic scoping (#514 regression)"
  fail=1
fi

# 4. Every recommendation is schema-valid (covers the query-terms
#    inference_method addition).
COUNT="$(jq 'length' "$TMP/recs.json")"
for ((i = 0; i < COUNT; i++)); do
  jq -c ".[$i]" "$TMP/recs.json" > "$TMP/rec.json"
  if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/monitoring-recommendation.schema.json -d "$TMP/rec.json" >/dev/null 2>&1; then
    note "recommendation $i failed monitoring-recommendation.schema.json"
    fail=1
  fi
done

[ "$fail" -eq 0 ] && note "golden set holds: zero irrelevant, $REL_COUNT/5 relevant recommended"
exit "$fail"
