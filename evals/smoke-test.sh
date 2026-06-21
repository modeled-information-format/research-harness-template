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

# Phase 0b — inbound boundary (SPEC §10): a raw source is normalized into a MIF
# source-envelope and validated at L3 before any analyst consumes it; an invalid
# source (empty content) is refused.
if scripts/wrap-source.sh --url "https://example.com/doc" --content-type "text/html" \
     --namespace "harness/smoke" --slug "smoke-source" --out "$TMP/source.json" \
     --content "A primary-source excerpt the analyst read." >/dev/null 2>&1 \
   && ajv_mif schemas/mif/source-envelope.schema.json "$TMP/source.json"; then
  note "inbound source normalized + validated as a MIF source-envelope"
else
  note "FAIL: inbound source did not normalize/validate at the boundary"; fail=1
fi
if scripts/wrap-source.sh --url "https://example.com/doc" --content-type "text/html" \
     --namespace "harness/smoke" --slug "empty" --out "$TMP/empty.json" --content "" >/dev/null 2>&1; then
  note "FAIL: empty-content source was accepted (should be refused)"; fail=1
else
  note "empty-content source refused at the boundary — as expected"
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

# Phase 7 — the topic README reconcile (orchestrator Phase 4 / report-synthesizer
# Step 4c). The gate ENFORCES synthesis: a freshly built skeleton (Key Findings =
# the deterministic draft) must be REFUSED; the same README must PASS once the Key
# Findings are synthesized. This is the floor that protects against shipping the
# skeleton.
RM="$TMP/README.md"
SF="reports/_meta/sample-session/findings"
bash scripts/build-topic-readme.sh example-topic --findings "$SF" --out "$RM" >/dev/null 2>&1
if bash scripts/build-topic-readme.sh example-topic --findings "$SF" --out "$RM" --check >/dev/null 2>&1; then
  note "FAIL: gate accepted the un-synthesized skeleton"; fail=1
else
  note "README gate refuses the un-synthesized skeleton (synthesis enforced)"
fi

# Simulate synthesis: replace the Key Findings draft with a cross-finding bullet.
awk '
  /^## Key Findings$/ { print; print ""; print "- Synthesized cross-finding insight with specifics."; print ""; skip=1; next }
  skip && /^## / { skip=0; print; next }
  skip { next }
  { print }
' "$RM" > "$RM.tmp" && mv "$RM.tmp" "$RM"
if bash scripts/build-topic-readme.sh example-topic --findings "$SF" --out "$RM" --check >/dev/null 2>&1; then
  note "README gate passes once Key Findings are synthesized"
else
  note "FAIL: gate rejected a synthesized README"; fail=1
fi

# The 'created' trigger: a zero-findings topic yields a valid README (synthesis
# gate is exempt — there is nothing to synthesize) and passes --check.
mkdir -p "$TMP/empty"
if bash scripts/build-topic-readme.sh example-topic --findings "$TMP/empty" \
      --out "$TMP/empty-README.md" >/dev/null 2>&1 \
   && grep -qF '**Findings:** 0' "$TMP/empty-README.md" \
   && bash scripts/build-topic-readme.sh example-topic --findings "$TMP/empty" \
      --out "$TMP/empty-README.md" --check >/dev/null 2>&1; then
  note "created-but-unstarted topic gets a valid zero-findings README (gate passes)"
else
  note "FAIL: zero-findings README not produced/validated"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "smoke-test: PASS"
  exit 0
fi
echo "smoke-test: FAIL"
exit 1
