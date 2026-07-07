#!/usr/bin/env bash
# check-ontology-lock.sh — prove vendored domain ontologies match the pinned lock.
#
# Fail-closed integrity gate (wired into verify.sh). Two checks:
#   (a) COVERAGE — every ENABLED domain ontology is pinned in ontologies.lock.json
#       and present as packs/ontologies/<id>/<id>.ontology.yaml.
#   (b) INTEGRITY — every PINNED ontology that is present on disk hashes to its
#       pinned sha256 (catches local drift even for a disabled-but-vendored pack;
#       fixes belong UPSTREAM in the ontologies repo, not here).
# Base layers under schemas/ontologies/ are committed, not vendored, and skipped.
#
# When there is no lock, on-demand vendoring has not been adopted in this clone —
# there is nothing to verify, so the gate passes cleanly.
#
# Since research-harness-template#276 (Story #277, Category A cutover),
# this delegates to the mif-rh engine (mif-rh-cli), hard required: install it
# with scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: check-ontology-lock.sh        (exit 1 on any drift/missing pin/file)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" ontology lock-check --root "$ROOT" --config "$ROOT/harness.config.json"
