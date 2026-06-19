#!/usr/bin/env bash
# Engine smoke test (Milestone 3 acceptance gate, SPEC §6b).
#
# Exercises the deterministic substrate the engine agents drive: it runs the
# orchestrator pipeline toward the sample session goal on a fixture, runs the
# adversarial falsification gate EXACTLY ONCE, and emits a finding that validates
# against the MIF-backed findings schema. The agent .md files document the
# LLM-driven behaviour; this test pins the contracts and gate scripts they rely
# on, so the engine is verifiable offline and in CI.
#
# Exit 0 = the engine pipeline is sound. Exit 1 = a stage failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

GOAL="reports/_meta/sample-session/goal.json"
RAW="evals/fixtures/raw-finding.json"
EVID="evals/fixtures/evidence.json"
fail=0
note() { printf '  smoke: %s\n' "$1"; }

ajv_mif() {
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s "$1" -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json -d "$2" >/dev/null 2>&1
}

# Phase 0 — the session goal is well-formed (goal-driven execution, #19).
if ajv validate --spec=draft2020 --strict=false -c ajv-formats \
     -s schemas/goal.schema.json -d "$GOAL" >/dev/null 2>&1; then
  note "session goal validates against goal.schema.json"
else
  note "FAIL: session goal does not validate"; fail=1
fi

# Phase 1 — dimension analysis: a candidate (pre-falsification) finding exists.
# Before the gate runs it must NOT yet be schema-valid (no verification verdict).
if ajv_mif schemas/findings.schema.json "$RAW"; then
  note "FAIL: raw finding validated before falsification (verification must be required)"; fail=1
else
  note "raw finding is not yet schema-valid (verification pending) — as expected"
fi

# Phase 2 — the SINGLE adversarial falsification gate. Run once; capture the run
# count from stderr to assert exactly-one.
ERRLOG="$TMP/falsify.err"
scripts/falsify.sh "$RAW" "$EVID" > "$TMP/finding.json" 2> "$ERRLOG"
RUNS=$(grep -c 'falsification-gate: run' "$ERRLOG")
if [ "$RUNS" -eq 1 ]; then
  note "falsification gate ran exactly once (run count = $RUNS)"
else
  note "FAIL: falsification gate ran $RUNS times (expected exactly 1)"; fail=1
fi

VERDICT=$(jq -r '.extensions.harness.verification.verdict // "none"' "$TMP/finding.json")
note "verdict assigned: $VERDICT"

# Phase 3 — the emitted finding validates against the MIF-backed schema (#13/#16).
if ajv_mif schemas/findings.schema.json "$TMP/finding.json"; then
  note "emitted finding validates against MIF-backed findings schema"
else
  note "FAIL: emitted finding does not validate against findings schema"; fail=1
fi

# Phase 4 — citation integrity holds for the emitted finding.
if scripts/check-citation-integrity.sh "$TMP/finding.json" >/dev/null 2>&1; then
  note "emitted finding passes the citation-integrity gate"
else
  note "FAIL: emitted finding fails citation integrity"; fail=1
fi

# Phase 5 — the goal's completion checks hold (goal gates 'done').
if [ "$VERDICT" = "survived" ] || [ "$VERDICT" = "weakened" ] || [ "$VERDICT" = "inconclusive" ]; then
  note "goal completion: a non-falsified finding survived the gate"
else
  note "FAIL: emitted finding was falsified; goal not satisfied"; fail=1
fi

# Phase 6 — one-round rule: re-running the gate on an already-falsified finding
# does NOT run the gate again (no infinite recursion).
scripts/falsify.sh "$TMP/finding.json" "$EVID" > /dev/null 2> "$TMP/falsify2.err"
RERUN=$(grep -c 'falsification-gate: run' "$TMP/falsify2.err")
if [ "$RERUN" -eq 0 ]; then
  note "one-round rule holds: gate is not re-run on an already-falsified finding"
else
  note "FAIL: gate re-ran on an already-falsified finding ($RERUN)"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "smoke-test: PASS"
  exit 0
fi
echo "smoke-test: FAIL"
exit 1
