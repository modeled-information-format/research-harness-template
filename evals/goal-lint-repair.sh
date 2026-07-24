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

# Case 8 (research-harness-template#626): the optional `deliverables` field.
# (a) a goal WITH a valid deliverables:{genres,channels} block passes both the
#     schema gate and the content lint (deliverables carries no step-shaped
#     assertions or dimension ids, so it never trips the lint's own checks).
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/goal.schema.json -d "$FX/goal-deliverables-valid.json" >"$TMP/deliv-valid-ajv.out" 2>&1; then
  note "goal-deliverables-valid.json (deliverables present, valid) unexpectedly failed ajv: $(tail -3 "$TMP/deliv-valid-ajv.out")"
  fail=1
fi
if ! LINT "$FX/goal-deliverables-valid.json" --config "$CFG" >"$TMP/deliv-valid-lint.out" 2>&1; then
  note "lint gate rejected a goal with a valid deliverables block: $(tail -3 "$TMP/deliv-valid-lint.out")"
  fail=1
fi
# (b) `deliverables` is genuinely OPTIONAL — a goal that omits it entirely
#     (goal-repaired.json, already exercised by Case 4 above) must still
#     pass both gates; a regression here would mean adding the field made it
#     retroactively required.
jq -e '.deliverables == null' "$FX/goal-repaired.json" >/dev/null 2>&1 \
  || { note "test-fixture assumption broke: goal-repaired.json now carries a deliverables field — Case 8b no longer proves the field is optional"; fail=1; }
if ! LINT "$FX/goal-repaired.json" --config "$CFG" >"$TMP/deliv-omitted-lint.out" 2>&1; then
  note "lint gate rejected the deliverables-omitting goal-repaired.json fixture — deliverables must be optional, not required: $(tail -3 "$TMP/deliv-omitted-lint.out")"
  fail=1
fi
# (c) an unknown key inside deliverables fails schema validation closed
#     (deliverables is additionalProperties:false, same as every other goal
#     sub-object) — the lint gate's own fail-closed schema step must catch
#     it before the content lint ever runs.
if LINT "$FX/goal-deliverables-invalid-key.json" --config "$CFG" >"$TMP/deliv-invalid-key.out" 2>&1; then
  note "lint gate PASSED a goal with an unrecognized key inside deliverables — deliverables' additionalProperties:false is not actually enforced"
  fail=1
else
  grep -q "schema gate, content lint not reached" "$TMP/deliv-invalid-key.out" \
    || { note "goal with an unknown deliverables key did not fail via the fail-closed ajv schema gate"; fail=1; }
fi

# Case 10 (research-harness-template#760): --config with no path after it
# (or an empty path) is a usage mistake and must exit 2 via usage(), never
# bash's own ${2:?msg} parameter-expansion error (which exits 1 and makes a
# usage mistake indistinguishable by exit code from a real lint failure).
LINT "$FX/goal-repaired.json" --config > "$TMP/noconfigpath.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] || { note "--config with no path: expected exit 2, got $rc"; fail=1; }
grep -q '^usage: lint-goal.sh' "$TMP/noconfigpath.out" \
  || { note "--config with no path did not print the usage message"; fail=1; }

LINT "$FX/goal-repaired.json" --config "" > "$TMP/emptyconfigpath.out" 2>&1
rc=$?
[ "$rc" -eq 2 ] || { note "--config with an empty path: expected exit 2, got $rc"; fail=1; }
grep -q '^usage: lint-goal.sh' "$TMP/emptyconfigpath.out" \
  || { note "--config with an empty path did not print the usage message"; fail=1; }

# Case 6: the workflow module encodes the same contract.
grep -q 'repairs < 2' "$WF" \
  || { note "$WF lost the 2-round repair bound (repairs < 2)"; fail=1; }
grep -qF 'ok: !!(lint && lint.valid)' "$WF" \
  || { note "$WF lost the fail-closed ok gate on lint validity"; fail=1; }
grep -q 'lint-goal\.sh' "$WF" \
  || { note "$WF Gate phase no longer routes through scripts/lint-goal.sh"; fail=1; }

# Case 9 (research-harness-template#626): the engine path never elicits
# `deliverables` itself — it only preserves an existing value verbatim on
# reshape, or leaves it absent on a fresh author. Structural proof against
# the real module source (the elicitation UX itself is /goal-writer.md's
# job, exercised interactively, not by this hermetic eval).
grep -qF 'deliverables: {' "$WF" \
  || { note "$WF's DRAFT_SCHEMA no longer declares a deliverables property — the draft result can no longer surface it to the Gate phase/caller"; fail=1; }
grep -qF 'deliverables: draft.deliverables' "$WF" \
  || { note "$WF's final return no longer forwards draft.deliverables — the Draft phase's preserved-or-absent fact would be silently dropped"; fail=1; }
grep -qF 'PRESERVE OR LEAVE ABSENT, NEVER ELICIT' "$WF" \
  || { note "$WF's Draft prompt lost the preserve-or-leave-absent-never-elicit carve-out for deliverables (research-harness-template#626)"; fail=1; }
grep -qF 'CANNOT pause for user input' "$WF" \
  || { note "$WF's Draft prompt no longer states the engine path cannot pause for AskUserQuestion — a future edit could silently reintroduce elicitation on this path"; fail=1; }

[ "$fail" -eq 0 ] && note "lint gate rejects the seeded-invalid goal (ajv-valid, lint-invalid), repaired goal is green, the 2-round repair bound converges or fails closed, the optional deliverables field validates when present/omitted and fails closed on an unrecognized key, and research-goal.js's Draft prompt never elicits deliverables itself"
exit "$fail"
