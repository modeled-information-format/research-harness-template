#!/usr/bin/env bash
# goal-lint-repair.sh — regression eval for the research-goal draft→lint→repair
# contract (research-harness-template#554, Epic #539).
#
# The vendored workflow module (.claude/workflows/research-goal.js) gates a
# drafted goal through a verifiability lint with a bounded (max 2 rounds)
# repair loop. CI cannot run the model-driven loop, so this eval exercises the
# contract deterministically at the fixture level:
#
#   1. the seeded-invalid fixture (a step-shaped check assertion + an
#      off-config dimension) FAILS scripts/lint-goal.sh, and the failure
#      names both issue classes — if the lint gate would pass the
#      seeded-invalid goal, this eval fails;
#   2. the same seeded-invalid fixture is ajv-VALID against
#      schemas/goal.schema.json — proves the lint catches what the schema
#      gate alone cannot (the fixture is invalid at the lint level, not
#      trivially schema-broken);
#   3. a schema-invalid fixture fails closed at the ajv gate, before the
#      content lint;
#   4. the repaired fixture passes ajv AND the lint gate reports green;
#   5. the bounded repair loop, driven with scripted fixture "repairs"
#      mirroring the workflow's arithmetic (while invalid && repairs < 2):
#      a converging sequence ends valid at repairs=2; a never-converging
#      sequence exhausts the bound and fails CLOSED (still invalid after 2);
#   6. structural contract of the workflow module itself: the 2-round bound,
#      the fail-closed ok gate on lint validity, and the Gate phase routing
#      through scripts/lint-goal.sh are all present in research-goal.js;
#   7. a --config pointing at malformed JSON is rejected early with a clear
#      error (exit 2), never a confusing downstream jq failure.
#
# Hermetic: only evals/fixtures/goal-lint/* and mktemp scratch; no real topic,
# no harness.config.json mutation, no model APIs.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  goal-lint-repair: %s\n' "$1"; }

FX=evals/fixtures/goal-lint
CFG="$FX/config.json"
WF=.claude/workflows/research-goal.js
LINT() { bash scripts/lint-goal.sh "$@"; }

# Case 1: the seeded-invalid fixture is genuinely invalid before repair —
# the lint gate must FAIL it and name both seeded issue classes.
if LINT "$FX/goal-seeded-invalid.json" --config "$CFG" > "$TMP/seeded.out" 2>&1; then
  note "lint gate PASSED the seeded-invalid goal — the gate has no teeth"
  fail=1
else
  grep -q "step-shaped assertion" "$TMP/seeded.out" \
    || { note "seeded step-shaped check assertion not flagged"; fail=1; }
  grep -q "dimension 'adoption_momentum' is not config-declared" "$TMP/seeded.out" \
    || { note "seeded off-config dimension not flagged"; fail=1; }
fi

# Case 2: the seeded-invalid fixture is schema-VALID — the lint catches what
# ajv alone cannot.
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/goal.schema.json -d "$FX/goal-seeded-invalid.json" > "$TMP/ajv-seeded.out" 2>&1; then
  note "seeded-invalid fixture is schema-broken — it must be ajv-valid so the eval proves the LINT gate, not the schema gate: $(tail -2 "$TMP/ajv-seeded.out")"
  fail=1
fi

# Case 3: a schema-invalid goal fails closed at the ajv gate.
if LINT "$FX/goal-schema-invalid.json" --config "$CFG" > "$TMP/schema.out" 2>&1; then
  note "lint gate passed a schema-invalid goal"
  fail=1
else
  grep -q "schema gate, content lint not reached" "$TMP/schema.out" \
    || { note "schema-invalid goal did not fail via the fail-closed ajv gate"; fail=1; }
fi

# Case 4: the repaired fixture is ajv-valid and lint-green.
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/goal.schema.json -d "$FX/goal-repaired.json" >/dev/null 2>&1; then
  note "repaired fixture does not validate against schemas/goal.schema.json"
  fail=1
fi
if ! LINT "$FX/goal-repaired.json" --config "$CFG" > "$TMP/repaired.out" 2>&1; then
  note "lint gate rejected the repaired goal: $(tail -3 "$TMP/repaired.out")"
  fail=1
fi

# Case 5: the bounded repair loop — same arithmetic as the workflow module
# (while invalid && repairs < 2), with fixtures standing in for the repair
# agent's output each round.
drive_loop() { # drive_loop <round1-fixture> <round2-fixture> -> "<valid> <repairs>"
  local goal="$TMP/goal.json" repairs=0 valid=0
  cp "$FX/goal-seeded-invalid.json" "$goal"
  LINT "$goal" --config "$CFG" >/dev/null 2>&1 && valid=1
  while [ "$valid" -eq 0 ] && [ "$repairs" -lt 2 ]; do
    repairs=$((repairs + 1))
    cp "$1" "$goal"; shift
    LINT "$goal" --config "$CFG" >/dev/null 2>&1 && valid=1
  done
  echo "$valid $repairs"
}

# 5a: converging sequence (round 1 fixes only the dimension, round 2 fixes the
# step-shaped assertion too) ends valid exactly at the bound.
got=$(drive_loop "$FX/goal-half-repaired.json" "$FX/goal-repaired.json")
[ "$got" = "1 2" ] || { note "converging repair sequence: expected 'valid=1 repairs=2', got '$got'"; fail=1; }

# 5b: a never-converging sequence exhausts the bound and fails CLOSED —
# still invalid after 2 rounds, never a silent pass.
got=$(drive_loop "$FX/goal-half-repaired.json" "$FX/goal-half-repaired.json")
[ "$got" = "0 2" ] || { note "exhausted repair sequence: expected 'valid=0 repairs=2' (fail closed), got '$got'"; fail=1; }

# Case 7: a malformed-JSON config fails closed, early and clearly (exit 2).
printf '{not json' > "$TMP/bad-config.json"
LINT "$FX/goal-repaired.json" --config "$TMP/bad-config.json" > "$TMP/badcfg.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] || { note "malformed config: expected exit 2, got $rc"; fail=1; }
grep -q "config is not valid JSON" "$TMP/badcfg.out" \
  || { note "malformed config not rejected with the clear early error"; fail=1; }

# Case 6: the workflow module encodes the same contract.
grep -q 'repairs < 2' "$WF" \
  || { note "$WF lost the 2-round repair bound (repairs < 2)"; fail=1; }
grep -qF 'ok: !!(lint && lint.valid)' "$WF" \
  || { note "$WF lost the fail-closed ok gate on lint validity"; fail=1; }
grep -q 'lint-goal\.sh' "$WF" \
  || { note "$WF Gate phase no longer routes through scripts/lint-goal.sh"; fail=1; }

[ "$fail" -eq 0 ] && note "lint gate rejects the seeded-invalid goal (ajv-valid, lint-invalid), repaired goal is green, and the 2-round repair bound converges or fails closed"
exit "$fail"
