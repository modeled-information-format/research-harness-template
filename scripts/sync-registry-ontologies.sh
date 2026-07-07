#!/usr/bin/env bash
# sync-registry-ontologies.sh — discovers domain ontologies published to the
# canonical registry that this harness's harness.config.json has never heard
# of (not merely disabled — absent from `.ontologies[]` entirely), adds each
# one with `enabled: true` (this harness's default posture: every registry
# ontology is available unless a harness owner explicitly opts it out), then
# vendors and catalogs everything currently enabled.
#
# The registry can grow at any time — a new ontology domain published to
# mif-spec.dev/ontologies gives no push notification to any harness instance.
# This script is the pull side of that: run it whenever you want this harness
# to catch up with what the registry currently offers.
#
# Since research-harness-template#276 (Story #277, Category A cutover),
# this delegates entirely to the mif-rh engine (mif-rh-cli): discovery,
# config update, vendoring, and cataloging all happen inside one engine call.
# The engine is hard required: install it with scripts/fetch-engine.sh, put
# mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: sync-registry-ontologies.sh
#   exit 0 = synced (0 or more new ontologies discovered and enabled, then
#            vendored + cataloged)
#   non-zero = registry index unreachable/malformed, a malformed registry id,
#              or a downstream vendor/catalog step failed
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" ontology sync-registry \
  --root "$ROOT" \
  --config "$ROOT/harness.config.json" \
  --catalog "$ROOT/.claude/enabled-packs.json"
