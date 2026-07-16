#!/usr/bin/env bash
# interest-inference.sh — Interest-Inference Engine (research-harness-template#419).
#
# Scores candidates against reports/concordance.json (AD-2) with a TF-IDF
# fallback for topics the concordance doesn't cover yet (NFR4). Per AD-2's
# consequence, a monitoring run must rebuild (or verifiably freshen) the
# concordance before scoring against it — this script refuses to run
# against a stale one rather than silently scoring against outdated data.
#
# Usage: interest-inference.sh <candidates.json> [concordance.json] [--topic <id>] [-- <query-terms...>]
#   default concordance.json: reports/concordance.json
#   --topic scopes concordance scoring to nodes tagged with that topic
#     (#514) -- omit it only for a concordance already scoped to one topic
#     (e.g. an eval fixture).
#   default query-terms: none (concordance scoring only; pass the topic's
#     queryTerms for the first-class query-term signal and TF-IDF fallback
#     to have something to score against)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

CANDIDATES="${1:?usage: interest-inference.sh <candidates.json> [concordance.json] [--topic <id>] [-- <query-terms...>]}"
shift
CONCORDANCE="$ROOT/reports/concordance.json"
if [ $# -gt 0 ] && [ "$1" != "--" ] && [ "$1" != "--topic" ]; then
  CONCORDANCE="$1"
  shift
fi
TOPIC_ARGS=()
if [ "${1:-}" = "--topic" ]; then
  [ -n "${2:-}" ] || { echo "interest-inference: --topic requires a topic id" >&2; exit 2; }
  TOPIC_ARGS=(--topic "$2")
  shift 2
fi
[ "${1:-}" = "--" ] && shift
QUERY_TERMS=("$@")

[ -f "$CANDIDATES" ] || { echo "interest-inference: candidates file not found: $CANDIDATES" >&2; exit 2; }
[ -f "$CONCORDANCE" ] || {
  echo "interest-inference: concordance not found: $CONCORDANCE — run scripts/build-concordance.sh first" >&2
  exit 5
}

# AD-2 ordering guard: refuse a concordance that predates the findings it's
# supposed to summarize (fail closed rather than score against stale data).
# Compares GIT COMMIT history, not filesystem mtimes: a fresh checkout (every
# CI run, per Story #424's scheduled workflow) stamps every file with the
# same checkout-time mtime, which makes mtime-based staleness checks produce
# false positives right after a clone. Git's own commit timestamps are
# stable regardless of checkout. Known scoping limit: this only sees
# COMMITTED changes -- locally edited, uncommitted findings are invisible to
# it, the same caveat CLAUDE.md already documents for verify.sh vs a
# corpus's real reports/ (rebuild explicitly after uncommitted edits).
# Only meaningful for a git-TRACKED concordance -- a fixture/throwaway
# concordance (e.g. an eval's own test data, evals/monitoring-pipeline.sh)
# has no commit history to compare, and "not yet committed" must never
# read as "infinitely stale". Skip the check entirely for an untracked
# file rather than always failing it closed.
CONCORDANCE_RELPATH="$(python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$CONCORDANCE" "$ROOT")"
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
   && git -C "$ROOT" ls-files --error-unmatch "$CONCORDANCE_RELPATH" >/dev/null 2>&1; then
  FINDINGS_TS="$(git -C "$ROOT" log -1 --format=%ct -- 'reports/*/findings/*.json' 2>/dev/null || echo 0)"
  CONCORDANCE_TS="$(git -C "$ROOT" log -1 --format=%ct -- "$CONCORDANCE_RELPATH" 2>/dev/null || echo 0)"
  FINDINGS_TS="${FINDINGS_TS:-0}"; CONCORDANCE_TS="${CONCORDANCE_TS:-0}"
  if [ -n "$FINDINGS_TS" ] && [ -n "$CONCORDANCE_TS" ] && [ "$FINDINGS_TS" -gt "$CONCORDANCE_TS" ] 2>/dev/null; then
    echo "interest-inference: concordance predates the latest committed finding — run scripts/build-concordance.sh before scoring" >&2
    exit 5
  fi
fi

python3 "$SCRIPT_DIR/lib/interest_inference.py" "$CANDIDATES" "$CONCORDANCE" "${TOPIC_ARGS[@]+"${TOPIC_ARGS[@]}"}" -- "${QUERY_TERMS[@]+"${QUERY_TERMS[@]}"}"
