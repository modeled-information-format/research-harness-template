#!/usr/bin/env bash
# recommend.sh — Recommendation Engine (research-harness-template#420).
#
# Two modes:
#   interest-match <scored-candidates.json> [threshold]
#     Rank Interest-Inference-scored candidates (research-harness-template#419)
#     above a threshold (default 0.02).
#   gap-detect [harness.config.json] [research-index.json]
#     Reuse .claude/skills/discover's own coverage-gap heuristic rather than
#     reimplementing knowledge-graph traversal.
#
# Every recommendation carries at least one MIF citation (NFR5) -- enforced
# as a hard invariant in scripts/monitoring/lib/recommend.py, not a
# convention: a citation-less recommendation raises rather than being
# produced.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

MODE="${1:?usage: recommend.sh interest-match <scored.json> [threshold] | recommend.sh gap-detect [config.json] [index.json]}"
shift

case "$MODE" in
  interest-match)
    SCORED="${1:?usage: recommend.sh interest-match <scored-candidates.json> [threshold]}"
    THRESHOLD="${2:-0.02}"
    python3 "$ROOT/scripts/monitoring/lib/recommend.py" interest-match "$SCORED" "$THRESHOLD"
    ;;
  gap-detect)
    CONFIG="${1:-$ROOT/harness.config.json}"
    INDEX="${2:-$ROOT/reports/_meta/sample-session/research-index.json}"
    python3 "$ROOT/scripts/monitoring/lib/recommend.py" gap-detect "$CONFIG" "$INDEX"
    ;;
  *)
    echo "recommend.sh: unknown mode '$MODE' (expected interest-match or gap-detect)" >&2
    exit 2
    ;;
esac
