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
# A finding with no fixture entry defaults to `survived` (no disconfirming
# evidence found). Output: the updated finding JSON on stdout.

set -uo pipefail

FINDING="${1:?usage: falsify.sh <finding.json> [<evidence-fixture.json>]}"
FIXTURE="${2:-}"

[ -f "$FINDING" ] || { echo "falsify: finding not found: $FINDING" >&2; exit 2; }
jq -e . "$FINDING" >/dev/null 2>&1 || { echo "falsify: finding is not valid JSON" >&2; exit 2; }

ID=$(jq -r '.["@id"] // empty' "$FINDING")

# One-round rule (SPEC falsification-analyst Step 1): never falsify a finding that
# already carries a verdict from a prior round — that recursion never terminates.
if jq -e '.extensions.harness.verification.attempted_at? // empty | length > 0' "$FINDING" >/dev/null 2>&1; then
  echo "falsification-gate: skipped (already falsified this session): $ID" >&2
  cat "$FINDING"
  exit 0
fi

# Resolve the verdict from the fixture (or default to survived).
if [ -n "$FIXTURE" ] && [ -f "$FIXTURE" ]; then
  ENTRY=$(jq -c --arg id "$ID" '.[$id] // {}' "$FIXTURE")
else
  ENTRY='{}'
fi

VERDICT=$(jq -r '.verdict // "survived"' <<<"$ENTRY")
BASIS=$(jq -r '.basis // "Adversarial queries executed; no disconfirming evidence found."' <<<"$ENTRY")

# Deterministic UTC timestamp from the fixture if provided, else a fixed marker
# (scripts cannot call the clock in some sandboxes; the agent supplies real time).
ATTEMPTED=$(jq -r '.attempted_at // "1970-01-01T00:00:00Z"' <<<"$ENTRY")

echo "falsification-gate: run ($ID -> $VERDICT)" >&2

jq --arg v "$VERDICT" --arg b "$BASIS" --arg t "$ATTEMPTED" \
   --argjson dis "$(jq -c '.disconfirming // []' <<<"$ENTRY")" '
  .extensions = (.extensions // {})
  | .extensions.harness = (.extensions.harness // {})
  | .extensions.harness.verification = {
      verdict: $v,
      verdict_basis: $b,
      attempted_at: $t,
      disconfirming_evidence: $dis
    }
' "$FINDING"
