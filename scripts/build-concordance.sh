#!/usr/bin/env bash
# build-concordance.sh — the ontological spine: ONE unified, cross-topic "concordance"
# (SPEC §8d). Merges every topic's findings into a single MIF-native graph typed by
# the ontology: concept nodes (one per finding) stamped with their resolved ontology
# entity_type (from reports/<topic>/ontology-map.json) AND falsification verdict;
# entity nodes merged across topics by urn:mif: @id (one node spanning every topic
# that references it). ALL findings are nodes; falsified are FLAGGED, not excluded.
# Deterministic/idempotent (sorted, no wall-clock) — "living" = on-demand rebuild.
#
# Since research-harness-template#276 (Story #282, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: build-concordance.sh [<reports-dir>] [<out.json>]
#   default reports-dir: reports/ ; default out: <reports-dir>/concordance.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

RD="${1:-$ROOT/reports}"; case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
[ -d "$RD" ] || { echo "build-concordance: reports dir not found: $RD" >&2; exit 2; }

if [ -n "${2:-}" ]; then
  exec "$ENGINE" harness build-concordance "$RD" "$2"
fi
exec "$ENGINE" harness build-concordance "$RD"
