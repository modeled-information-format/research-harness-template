#!/usr/bin/env bash
# monitoring-domains.sh — domain-based monitoring model eval
# (research-harness-template#521: Tasks #522 monitoringDomains schema +
# resolution, #523 momentum ranking + prior-coverage memory, #524 digest,
# #525 dual-runtime parity/determinism). Recorded fixtures via the
# CONNECTOR_FETCH_OVERRIDE seam -- no live network; a throwaway domain under
# the real reports/_monitoring tree, cleaned by the EXIT trap.
#
# Covers:
#   1. #522: a monitoringDomains[] config validates against
#      harness.config.schema.json, and run-monitoring.sh resolves a domain
#      id (domain-first), writing its run under reports/_monitoring/<id>/.
#   2. #522: topic fallback still works -- an unknown subject id fails with
#      the neither-domain-nor-topic error.
#   3. #523: cross-source merge + momentum ranking -- the same item from two
#      sources becomes ONE recommendation with source_count 2, ranked above
#      a single-source item with higher engagement below it; ranking factors
#      recorded on each recommendation.
#   4. #523: prior-coverage -- coverage-append (gate-accept path) is
#      idempotent, and a re-run with --memory suppresses the accepted item.
#   5. #524: the digest carries the versioned format marker, momentum
#      evidence, and source URLs; a domain gate round-trips accept
#      (memory written, Output Router skipped for a standalone domain) and
#      reject (memory NOT written).
#   6. #525: identical fixture inputs produce byte-identical
#      recommendations.json across two runs (dual-runtime parity rests on
#      both runtimes calling exactly these scripts).
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PACK="packs/monitoring/continuous-monitor"
QFX="$ROOT/evals/fixtures/monitoring-query-construction"
TMP="$(mktemp -d)"
DOMAIN="eval-domain-monitoring"
DOMAIN_DIR="$ROOT/reports/_monitoring/$DOMAIN"
trap 'rm -rf "$TMP" "$DOMAIN_DIR"' EXIT
fail=0
note() { printf '  monitoring-domains: %s\n' "$1"; }

# --- Case 1: schema + domain resolution ------------------------------------
cat > "$TMP/config.json" <<EOF
{
  "version": "0.0.0",
  "topics": [],
  "dimensions": [ { "id": "eval-dimension" } ],
  "packs": [
    { "name": "continuous-monitor", "enabled": true, "source": "bundled" }
  ],
  "monitoringDomains": [
    {
      "id": "$DOMAIN",
      "name": "Eval Domain",
      "weight": 0.7,
      "queryTerms": ["git notes", "AI provenance"],
      "sources": ["hn"],
      "recommendationThreshold": 0.02
    }
  ]
}
EOF
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s harness.config.schema.json -d "$TMP/config.json" >/dev/null 2>&1; then
  note "monitoringDomains config does not validate against harness.config.schema.json"
  fail=1
fi

export HARNESS_CONFIG="$TMP/config.json"
export CONNECTOR_FETCH_OVERRIDE="$QFX/fetch-stub.sh"
export EVAL_FIXTURE_DIR="$QFX"
export FETCH_URL_LOG="$TMP/urls.log"
export MONITOR_PRIOR_COVERAGE="$TMP/memory.jsonl"
: > "$FETCH_URL_LOG"

RUN1="run-eval-domains-1"
if ! bash "$PACK/scripts/run-monitoring.sh" "$DOMAIN" "$RUN1" 2> "$TMP/run1.err"; then
  note "domain run failed: $(tail -3 "$TMP/run1.err")"
  fail=1
fi
RUN_DIR="$DOMAIN_DIR/runs/$RUN1"
[ -f "$RUN_DIR/recommendations.json" ] || { note "domain run wrote no recommendations under reports/_monitoring"; fail=1; }
[ -f "$RUN_DIR/digest.md" ] || { note "domain run wrote no digest"; fail=1; }
[ "$fail" -eq 0 ] || exit 1

jq -e --arg d "$DOMAIN" 'all(.[]; .domain == $d and .weight == 0.7 and (.momentum | has("source_count")))' \
  "$RUN_DIR/recommendations.json" >/dev/null || {
  note "recommendations lack domain/weight/momentum annotations"
  fail=1
}

# --- Case 2: unknown subject fails loudly -----------------------------------
if bash "$PACK/scripts/run-monitoring.sh" "no-such-subject" "$RUN1" >/dev/null 2>"$TMP/unknown.err"; then
  note "unknown subject id should fail"
  fail=1
elif ! grep -q "neither a monitoringDomains" "$TMP/unknown.err"; then
  note "unknown-subject error does not name both resolution paths"
  fail=1
fi

# --- Case 3: cross-source merge + momentum ranking --------------------------
cat > "$TMP/scored.json" <<'EOF'
[
  {"source": "arxiv", "id": "arxiv-1", "title": "Provenance Anchors for Generated Commits",
   "url": "https://example.org/abs/1", "published": "2026-07-10T00:00:00Z", "authors": [], "raw": {},
   "inference": {"method": "query-terms", "score": 0.5, "matched_nodes": [], "matched_terms": ["AI provenance"]}},
  {"source": "hn", "id": "hn-9", "title": "Provenance Anchors for Generated Commits",
   "url": "https://example.org/story/9", "published": "2026-07-11T00:00:00Z", "authors": [],
   "raw": {"points": 5, "num_comments": 2},
   "inference": {"method": "query-terms", "score": 0.4, "matched_nodes": [], "matched_terms": ["AI provenance"]}},
  {"source": "hn", "id": "hn-8", "title": "Git Notes Review Metadata Substrate",
   "url": "https://example.org/story/8", "published": "2026-07-12T00:00:00Z", "authors": [],
   "raw": {"points": 400, "num_comments": 200},
   "inference": {"method": "query-terms", "score": 0.9, "matched_nodes": [], "matched_terms": ["git notes"]}}
]
EOF
bash "$PACK/scripts/recommend.sh" interest-match "$TMP/scored.json" 0.02 \
  --domain "$DOMAIN" --weight 0.7 > "$TMP/recs.json" 2>/dev/null || { note "recommend momentum run failed"; fail=1; }
if ! jq -e 'length == 2' "$TMP/recs.json" >/dev/null; then
  note "cross-source merge wrong: expected 2 recommendations, got $(jq length "$TMP/recs.json")"
  fail=1
fi
# The two-source item outranks the single-source item despite the latter's
# far higher engagement: independent source count is momentum's FIRST factor.
if ! jq -e '.[0].momentum.source_count == 2 and .[0].momentum.engagement == 7 and (.[0].momentum.sources == ["arxiv","hn"]) and .[1].momentum.source_count == 1' "$TMP/recs.json" >/dev/null; then
  note "momentum ranking wrong: $(jq -c '[.[] | {id, momentum}]' "$TMP/recs.json")"
  fail=1
fi

# Recency tie-break (Copilot finding on PR #529): equal source count,
# engagement, score, and weight must order NEWEST first, not oldest.
cat > "$TMP/scored-ties.json" <<'EOF'
[
  {"source": "arxiv", "id": "older", "title": "Older Provenance Ledger Design",
   "url": "https://example.org/abs/older", "published": "2026-07-01T00:00:00Z", "authors": [], "raw": {},
   "inference": {"method": "query-terms", "score": 0.5, "matched_nodes": [], "matched_terms": ["AI provenance"]}},
  {"source": "arxiv", "id": "newer", "title": "Newer Provenance Ledger Design",
   "url": "https://example.org/abs/newer", "published": "2026-07-14T00:00:00Z", "authors": [], "raw": {},
   "inference": {"method": "query-terms", "score": 0.5, "matched_nodes": [], "matched_terms": ["AI provenance"]}}
]
EOF
bash "$PACK/scripts/recommend.sh" interest-match "$TMP/scored-ties.json" 0.02 > "$TMP/recs-ties.json" 2>/dev/null || { note "tie-break run failed"; fail=1; }
if ! jq -e '[.[].id] == ["newer", "older"]' "$TMP/recs-ties.json" >/dev/null; then
  note "recency tie-break wrong: $(jq -c '[.[].id]' "$TMP/recs-ties.json") (expected newest first)"
  fail=1
fi

# --- Case 4: prior-coverage append is idempotent and suppresses -------------
jq '[.[0]]' "$TMP/recs.json" > "$TMP/accepted.json"
python3 "$PACK/scripts/lib/recommend.py" coverage-append "$TMP/accepted.json" "$TMP/mem2.jsonl" run-A 2>/dev/null
python3 "$PACK/scripts/lib/recommend.py" coverage-append "$TMP/accepted.json" "$TMP/mem2.jsonl" run-B 2>/dev/null
[ "$(wc -l < "$TMP/mem2.jsonl")" -eq 1 ] || { note "coverage-append is not idempotent"; fail=1; }
bash "$PACK/scripts/recommend.sh" interest-match "$TMP/scored.json" 0.02 \
  --memory "$TMP/mem2.jsonl" > "$TMP/recs-suppressed.json" 2>"$TMP/suppress.err" || { note "suppression run failed"; fail=1; }
if ! jq -e 'length == 1 and .[0].momentum.source_count == 1' "$TMP/recs-suppressed.json" >/dev/null; then
  note "prior-covered item was not suppressed: $(jq -c '[.[].id]' "$TMP/recs-suppressed.json")"
  fail=1
fi
grep -q "suppressed prior-covered candidate" "$TMP/suppress.err" || { note "suppression was silent"; fail=1; }

# --- Case 5: digest format + domain gate round-trip -------------------------
head -1 "$RUN_DIR/digest.md" | grep -q '<!-- Digest format: v1 -->' || { note "digest lacks the v1 format marker"; fail=1; }
grep -q '\*\*Momentum:\*\*' "$RUN_DIR/digest.md" || { note "digest lacks momentum evidence"; fail=1; }
grep -q '\*\*Prior coverage:\*\*' "$RUN_DIR/digest.md" || { note "digest lacks prior-coverage status"; fail=1; }

# Reject path first: memory must NOT be written.
: > "$TMP/memory.jsonl"
bash "$PACK/scripts/run-gate-and-publish.sh" "$DOMAIN" "$RUN1" "$RUN_DIR/recommendations.json" false >/dev/null 2>&1 || { note "gate reject run failed"; fail=1; }
[ -s "$TMP/memory.jsonl" ] && { note "reject path wrote prior-coverage memory (must be accept-only)"; fail=1; }
# Accept path: memory written, Output Router skipped for a standalone domain.
bash "$PACK/scripts/run-gate-and-publish.sh" "$DOMAIN" "$RUN1" "$RUN_DIR/recommendations.json" true >/dev/null 2>"$TMP/gate.err" || { note "gate accept run failed: $(tail -3 "$TMP/gate.err")"; fail=1; }
[ -s "$TMP/memory.jsonl" ] || { note "accept path did not write prior-coverage memory"; fail=1; }
grep -q "standalone domain" "$TMP/gate.err" || { note "standalone domain did not skip the Output Router by design"; fail=1; }

# --- Case 6: determinism / parity (#525) ------------------------------------
# Case 5's gate-accept legitimately wrote the memory; parity must compare
# runs under identical inputs, so give this run a fresh (empty) memory.
: > "$FETCH_URL_LOG"
RUN2="run-eval-domains-2"
MONITOR_PRIOR_COVERAGE="$TMP/memory-parity.jsonl" \
  bash "$PACK/scripts/run-monitoring.sh" "$DOMAIN" "$RUN2" >/dev/null 2>&1 || { note "second domain run failed"; fail=1; }
if ! diff -q "$RUN_DIR/recommendations.json" "$DOMAIN_DIR/runs/$RUN2/recommendations.json" >/dev/null 2>&1; then
  note "identical inputs produced different recommendations.json across runs"
  fail=1
fi

[ "$fail" -eq 0 ] && note "domain resolution, momentum, memory, digest, gate round-trip, and determinism all hold"
exit "$fail"
