#!/usr/bin/env bash
# render-digest.sh — per-run monitoring digest (research-harness-template#524).
#
# Thin wrapper over lib/render_digest.py: renders a run's
# recommendations.json into the versioned, human-reviewable digest the
# Editorial Gate reviews. The same digest serves both runtimes (#525):
# monitor.yml uses it as the review PR's body; an in-session operator
# renders it to read before invoking the gate.
#
# Usage: render-digest.sh <recommendations.json> <subject> <run-id>
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RECOMMENDATIONS="${1:?usage: render-digest.sh <recommendations.json> <subject> <run-id>}"
SUBJECT="${2:?missing subject (domain or topic id)}"
RUN_ID="${3:?missing run-id}"

[ -f "$RECOMMENDATIONS" ] || { echo "render-digest: recommendations file not found: $RECOMMENDATIONS" >&2; exit 2; }

python3 "$SCRIPT_DIR/lib/render_digest.py" "$RECOMMENDATIONS" "$SUBJECT" "$RUN_ID"
