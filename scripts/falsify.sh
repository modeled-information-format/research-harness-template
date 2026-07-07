#!/usr/bin/env bash
# Falsification gate (SPEC §6b) — the SINGLE adversarial verification pass the
# harness runs. The falsification-analyst agent drives this against live web
# search; this script is the deterministic substrate it writes through, and the
# offline gate the smoke test exercises.
#
# It treats a finding as a hypothesis, consults an (offline, fixture-supplied)
# body of disconfirming evidence, assigns an ordinal verdict, and writes the
# verdict back into extensions.harness.verification. It logs exactly one
# "falsification-gate: run" line to stderr per invocation so a caller can assert
# the gate ran exactly once.
#
# Verdict model (SPEC §6b / falsification-analyst Step 5):
#   falsified  >=1 credible source directly contradicts the claim
#   weakened   >=1 credible source qualifies/narrows the claim
#   survived   adversarial queries ran; no disconfirming evidence found
#   inconclusive  could not test (budget, vague claim, already falsified)
#
# Usage:
#   falsify.sh <finding.json> [<evidence-fixture.json>]
#
# Evidence fixture: a JSON object keyed by finding @id, each value
#   { "verdict": "...", "basis": "...", "disconfirming": ["url", ...] }.
# A finding with no fixture entry is recorded as a PLACEHOLDER `inconclusive` (it was not
# adversarially tested) WITHOUT `attempted_at`, so a later real gate run can still overwrite
# it. Output: the updated finding JSON on stdout.
#
# Since research-harness-template#276 (Story #287, Category B cutover), verdict
# resolution (fixture lookup, the one-round rule, the merge into
# extensions.harness.verification) delegates to the mif-rh engine (mif-rh-cli),
# hard required: install it with scripts/fetch-engine.sh, put mif-rh-cli on
# PATH, or set MIF_RH_CLI.

set -uo pipefail

FINDING="${1:?usage: falsify.sh <finding.json> [<evidence-fixture.json>]}"
FIXTURE="${2:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

if [ -n "$FIXTURE" ]; then
  exec "$ENGINE" harness falsify "$FINDING" "$FIXTURE"
else
  exec "$ENGINE" harness falsify "$FINDING"
fi
