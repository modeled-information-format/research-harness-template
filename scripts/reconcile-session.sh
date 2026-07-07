#!/usr/bin/env bash
# reconcile-session.sh — derive a durable session checkpoint
# (reports/<topic>/state.json) purely from disk and print the remaining-work plan.
# Crash-safe resume (SPEC §6b): a finding is DONE iff it validates against
# schemas/findings.schema.json — which REQUIRES extensions.harness.verification
# (verdict + verdict_basis), so a valid finding has already been through the
# falsification gate. Raw/partial/invalid findings and *.tmp / hidden partial
# writes are EXCLUDED from done-counts, so /resume never reworks a completed
# finding (re-running burns expensive web research + falsification budget).
#
# A finding is found WHEREVER it lives: the canonical reports/<topic>/findings/
# subdir AND, defensively, a flat reports/<topic>/finding-*.json — a real finding
# must never be missed, or its dimension would be re-run from scratch.
#
# Idempotent and byte-deterministic: no wall-clock field, sorted records, jq -S.
#
# Since research-harness-template#276 (Story #282, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: reconcile-session.sh <reports-dir>
#   writes <reports-dir>/state.json; prints the remaining plan to stdout; exit 0.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

RD="${1:?usage: reconcile-session.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
[ -d "$RD" ] || { echo "reconcile: not a directory: $RD" >&2; exit 2; }

exec "$ENGINE" harness reconcile-session "$RD" \
  --schema "$ROOT/schemas/findings.schema.json" \
  --ref "$ROOT/schemas/mif/mif.schema.json" \
  --ref "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
  --sample "$ROOT/schemas/samples/finding.sample.json"
