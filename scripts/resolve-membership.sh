#!/usr/bin/env bash
# resolve-membership.sh — the deterministic scope-resolution pass (SPEC §11).
#
# For a goal version, classify the topic's existing findings against that version's
# contract and emit the authoritative per-version members file
# reports/<topic>/goals/goal-<version>.members.json:
#
#   { version, generated, members[], stale[], gap_dimensions[] }
#
#   members        — findings IN SCOPE for this version (dimension is one of the
#                    goal's dimensions AND verdict is not "falsified").
#   stale          — in-scope findings whose verification has decayed under
#                    source-type decay (re_verify_by = attempted_at + TTL, where
#                    TTL is the MIN over the finding's citations' citationType
#                    windows from harness.config freshness; a finding with no
#                    attempted_at is freshness-unknown -> stale).
#   gap_dimensions — goal dimensions with no in-scope finding (must be researched).
#
# This is the DETERMINISTIC floor. Ambiguous in/out-of-scope judgement (against the
# goal's out_of_scope/non_goals prose) is layered on top by the goal-writer command,
# which calls this and then refines the members file. The result is a re-derivable
# projection; build-index.sh mirrors goal_versions[] onto each finding from it.
#
# Since research-harness-template#276 (Story #293, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: resolve-membership.sh <topic> [<goal-version>]
#        version defaults to the content hash of reports/<topic>/goal.json.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

# Anchor to the repo root (the script lives in <root>/scripts) when not told
# otherwise, so the script is runnable from any working directory.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$ROOT}"

TOPIC="${1:?usage: resolve-membership.sh <topic> [<goal-version>]}"
GOAL="$PROJECT_DIR/reports/$TOPIC/goal.json"
[ -f "$GOAL" ] || { echo "resolve-membership: no goal for topic \"$TOPIC\": $GOAL" >&2; exit 2; }

if [ -n "${2:-}" ]; then
  exec "$ENGINE" harness resolve-membership "$TOPIC" "$2" --root "$PROJECT_DIR"
fi
exec "$ENGINE" harness resolve-membership "$TOPIC" --root "$PROJECT_DIR"
