#!/usr/bin/env bash
# monitoring-query-construction.sh — regression evals for the connector query
# semantics (research-harness-template#513) and the GDELT HTTP-200 rate-limit
# notice handling (#515). Recorded fixtures via the CONNECTOR_FETCH_OVERRIDE
# seam in connector-common.sh -- no live network, CI stays deterministic.
#
# Covers:
#   1. connector_parse_terms: JSON-array query -> atomic terms; plain string
#      -> one atomic term (never a space-joined blob, the #513 defect).
#   2. connector_query_quoted_or: phrase-quoted boolean OR construction.
#   3. connector_guard_json: JSON body passes; the GDELT plaintext
#      rate-limit notice is identified as rate limiting (75), other non-JSON
#      as a data error (65) -- not a misleading jq parse error.
#   4. arxiv.sh sends ONE request whose search_query is per-term
#      phrase-quoted OR (`all:"t1" OR all:"t2"`), never the flattened blob
#      arXiv would explode into OR-of-single-words (151,074 hits in the
#      2026-07-16 live comparison, vs 2 for the correct query).
#   5. hn.sh sends one request PER term (Algolia has no OR operator;
#      AND-of-all-words returned 0 hits live) and merges/dedups by objectID.
#   6. gdelt.sh, fed the recorded rate-limit notice: retries exactly once
#      after GDELT_RETRY_DELAY_SECONDS, then fails closed reporting the TRUE
#      cause ("rate limited"), not a jq parse error.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PACK="packs/monitoring/continuous-monitor"
FX="$ROOT/evals/fixtures/monitoring-query-construction"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  monitoring-query-construction: %s\n' "$1"; }

# --- Cases 1-3: pure helpers, sourced directly -----------------------------
# shellcheck source=packs/monitoring/continuous-monitor/scripts/lib/connector-common.sh
. "$PACK/scripts/lib/connector-common.sh"

EXPECTED_TERMS=$'git notes\nAI provenance\ncommit attestation'
GOT_TERMS="$(connector_parse_terms '["git notes","AI provenance","commit attestation"]')"
if [ "$GOT_TERMS" != "$EXPECTED_TERMS" ]; then
  note "parse_terms(JSON array) wrong: got $(printf '%s' "$GOT_TERMS" | tr '\n' '|')"
  fail=1
fi
if [ "$(connector_parse_terms 'git notes')" != "git notes" ]; then
  note "parse_terms(plain string) must yield the string as ONE atomic term"
  fail=1
fi

GOT_EXPR="$(connector_query_quoted_or 'all:' 'git notes' 'AI provenance')"
if [ "$GOT_EXPR" != 'all:"git notes" OR all:"AI provenance"' ]; then
  note "quoted_or wrong: got $GOT_EXPR"
  fail=1
fi

connector_guard_json eval '{"ok": true}' 2>/dev/null
[ $? -eq 0 ] || { note "guard_json rejected a JSON body"; fail=1; }
connector_guard_json eval "$(cat "$FX/gdelt-rate-limit-notice.txt")" 2>/dev/null
[ $? -eq 75 ] || { note "guard_json did not classify the GDELT notice as rate limiting (75)"; fail=1; }
connector_guard_json eval '<html>maintenance page</html>' 2>/dev/null
[ $? -eq 65 ] || { note "guard_json did not classify non-JSON junk as a data error (65)"; fail=1; }

# --- Cases 4-6: connectors against recorded fixtures -----------------------
export CONNECTOR_FETCH_OVERRIDE="$FX/fetch-stub.sh"
export EVAL_FIXTURE_DIR="$FX"
export FETCH_URL_LOG="$TMP/urls.log"

# Case 4: arXiv phrase-quoted OR in a single request.
: > "$FETCH_URL_LOG"
if ! bash "$PACK/scripts/connectors/arxiv.sh" '["git notes","AI provenance"]' 5 > "$TMP/arxiv.json" 2>"$TMP/arxiv.err"; then
  note "arxiv.sh failed: $(cat "$TMP/arxiv.err")"
  fail=1
else
  if ! grep -q 'search_query=all%3A%22git%20notes%22%20OR%20all%3A%22AI%20provenance%22' "$FETCH_URL_LOG"; then
    note "arxiv query is not per-term phrase-quoted OR: $(cat "$FETCH_URL_LOG")"
    fail=1
  fi
  [ "$(wc -l < "$FETCH_URL_LOG")" -eq 1 ] || { note "arxiv should send exactly one request"; fail=1; }
  jq -e 'type == "array" and length >= 1' "$TMP/arxiv.json" >/dev/null || { note "arxiv emitted no candidates from the fixture"; fail=1; }
fi

# Case 5: HN one-request-per-term, merged and deduplicated.
: > "$FETCH_URL_LOG"
if ! bash "$PACK/scripts/connectors/hn.sh" '["git notes","AI provenance"]' 5 > "$TMP/hn.json" 2>"$TMP/hn.err"; then
  note "hn.sh failed: $(cat "$TMP/hn.err")"
  fail=1
else
  [ "$(grep -c 'hn.algolia.com' "$FETCH_URL_LOG")" -eq 2 ] || { note "hn should send one request per term (got: $(cat "$FETCH_URL_LOG"))"; fail=1; }
  if ! jq -e '[.[].id] | sort == ["hn-1", "hn-2", "hn-3"]' "$TMP/hn.json" >/dev/null; then
    note "hn merge/dedup wrong: $(jq -c '[.[].id]' "$TMP/hn.json")"
    fail=1
  fi
fi

# Case 6: GDELT rate-limit notice -> true cause + exactly one spaced retry.
: > "$FETCH_URL_LOG"
GDELT_RETRY_DELAY_SECONDS=0 bash "$PACK/scripts/connectors/gdelt.sh" '["AI provenance"]' 5 > "$TMP/gdelt.json" 2>"$TMP/gdelt.err"
RC=$?
[ "$RC" -ne 0 ] || { note "gdelt.sh must fail closed on persistent rate limiting"; fail=1; }
grep -q 'rate limited' "$TMP/gdelt.err" || { note "gdelt stderr lacks the true cause: $(cat "$TMP/gdelt.err")"; fail=1; }
if grep -q 'jq parse error' "$TMP/gdelt.err"; then
  note "gdelt still reports the misleading jq parse error (#515 regression)"
  fail=1
fi
[ "$(grep -c 'gdeltproject.org' "$FETCH_URL_LOG")" -eq 2 ] || { note "gdelt should retry exactly once (got: $(cat "$FETCH_URL_LOG"))"; fail=1; }

[ "$fail" -eq 0 ] && note "query construction, merge/dedup, and rate-limit handling all hold"
exit "$fail"
