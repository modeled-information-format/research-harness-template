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

# Zero-dependency short-circuit, preserved from before the engine cutover:
# a harness instance that has never adopted on-demand vendoring at all
# (documented as the common case — no ontologies.lock.json exists) must be
# able to answer "nothing to check" with nothing more than bash, not by
# requiring a compiled, attested engine binary just to notice the file is
# absent.
if [ ! -f "$ROOT/ontologies.lock.json" ]; then
  echo "check-ontology-lock: no ontologies.lock.json — on-demand vendoring not adopted; nothing to verify"
  exit 0
fi

# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" ontology lock-check --root "$ROOT" --config "$ROOT/harness.config.json"
