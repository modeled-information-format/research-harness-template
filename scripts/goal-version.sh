#!/usr/bin/env bash
# goal-version.sh — compute the content-hash identity of a goal version (SPEC §11).
#
# The id is gv-<sha256(normalized goal)[:12]>, where "normalized" is the goal JSON
# with the lineage fields (version, supersedes, revision) removed and all keys
# sorted, compact. Removing the lineage fields makes the hash a stable
# function of the goal's *content* — minting a new version (which sets version/
# supersedes/revision) never perturbs the hash of the content it describes. The id
# is self-verifying (recompute and compare) and independent of git commit timing.
#
# Since research-harness-template#276 (Story #298, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: goal-version.sh <goal.json>
#        prints e.g. gv-9f3c1a2b4d5e
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

GOAL="${1:?usage: goal-version.sh <goal.json>}"
[ -f "$GOAL" ] || { echo "goal-version: not a file: $GOAL" >&2; exit 2; }

exec "$ENGINE" harness goal-version "$GOAL"
