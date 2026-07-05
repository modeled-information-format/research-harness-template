#!/usr/bin/env bash
# ontology-review.sh — rebuild ontology-map.json per topic and aggregate coverage.
#
# Re-resolves every finding in each configured topic (or one --topic), rewrites
# that topic's reports/<topic>/ontology-map.json atomically, and prints the
# corpus coverage table (TOPIC BOUND FIND STAMPED DISCOVERY UNTYPED INVALID).
# STAMPED requires a durable (declared/resolved) type on disk; DISCOVERY is a
# content-pattern guess never written back. Also runs
# check-relationship-targets.sh once, corpus-wide, after the per-topic loop.
#
# Since ADR-0016 this script delegates to the mif-rh engine (mif-rh-cli),
# whose byte-level output and exit-code parity with the retired bash
# implementation is enforced fail-closed in mif-rs CI. The engine is hard
# required: install it with scripts/fetch-engine.sh, put mif-rh-cli on
# PATH, or set MIF_RH_CLI.
#
# Usage: ontology-review.sh [--topic <id>] [--strict] [--reports-dir <p>]
#                           [--config <p>] [--catalog <p>] [--followup <path>]
#   exit 0 = reviewed; with --strict, non-zero if any finding is unresolved/invalid
#            or any relationships[].target is orphaned. --strict does NOT fail on
#            DISCOVERY or UNTYPED findings — those are backlog, not corruption; use
#            --followup to track them.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

CONFIG="$ROOT/harness.config.json"
CATALOG="$ROOT/.claude/enabled-packs.json"
RD="$ROOT/reports"
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --topic) args+=(--topic "$2"); shift 2 ;;
    --strict) args+=(--strict); shift ;;
    --reports-dir) RD="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --followup) args+=(--followup "$2"); shift 2 ;;
    *) echo "ontology-review: unknown argument $1" >&2; exit 2 ;;
  esac
done
exec "$ENGINE" review --reports-dir "$RD" --config "$CONFIG" --catalog "$CATALOG" \
  --root "$ROOT" --relationship-script "$ROOT/scripts/check-relationship-targets.sh" \
  "${args[@]}"
