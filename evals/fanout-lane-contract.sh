#!/usr/bin/env bash
# fanout-lane-contract.sh — regression eval for the research-fanout lane
# contract (research-harness-template#558, Epic #540).
#
# The vendored workflow module (.claude/workflows/research-fanout.js) fans a
# research round out across goal dimensions; each lane's findings gate through
# ajv against schemas/findings.schema.json (with the vendored schemas/mif/
# closure registered), a dimension-pin check, a repair pass that must never
# delete a finding or weaken its claim, and a cross-corpus relate pass that
# only ever ANNOTATES. CI cannot run the model-driven lanes, so this eval
# exercises the contract deterministically at the fixture level (mirroring
# evals/goal-lint-repair.sh, #554):
#
#   1. the seeded-invalid finding fixture FAILS the ajv gate, and the failure
#      names both seeded issue classes (empty citations; missing
#      extensions.harness.verification) — if the gate would accept the
#      seeded-invalid finding, this eval fails;
#   2. the wrong-dimension-pin fixture is ajv-VALID but pinned to a dimension
#      other than its lane's — the lane's pin gate (the module's validate
#      step: extensions.harness.dimension != lane => invalid) must reject it;
#      proves pin enforcement catches what the schema gate alone cannot. The
#      correctly-pinned fixture passes the same gate (positive control);
#   3. relate/dedup is non-destructive: annotating the newer of a valid
#      duplicate pair with a typed MIF relationship (the relate pass's one
#      sanctioned edit) preserves the findings-file count, leaves the older
#      file byte-identical, leaves the newer file's claim content (title,
#      content, summary) untouched, and keeps the annotated file ajv-valid;
#   4. structural contract of the workflow module itself: FINDING_CONTRACT is
#      defined once and embedded in the analyst brief, crossDimensionLeads is
#      REQUIRED in RESEARCH_SCHEMA, the validate step enforces the dimension
#      pin, the repair prompt forbids deleting findings or weakening claims
#      and only runs when the validate step reported invalid files
#      (fail-closed routing), and the relate prompt forbids deletion.
#
# Hermetic: only evals/fixtures/fanout-lane/* and mktemp scratch; no real
# topic, no network, no model APIs.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fanout-lane-contract: %s\n' "$1"; }

FX=evals/fixtures/fanout-lane
WF=.claude/workflows/research-fanout.js
LANE=landscape

# The ajv gate exactly as the module's contract states it: draft2020 +
# ajv-formats, schemas/findings.schema.json with the vendored schemas/mif/
# closure registered. --all-errors so every violated issue class is named.
GATE() {
  ajv validate --spec=draft2020 --strict=false -c ajv-formats --all-errors \
    -s schemas/findings.schema.json \
    -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$1"
}

# The lane gate as the module's validate step describes it: ajv-valid AND
# extensions.harness.dimension == the lane's dimension.
LANE_GATE() { # LANE_GATE <file> <lane>
  GATE "$1" >/dev/null 2>&1 || { echo "schema-invalid"; return 1; }
  local pin
  pin="$(jq -r '.extensions.harness.dimension' "$1")"
  [ "$pin" = "$2" ] || { echo "dimension pin '$pin' != lane '$2'"; return 1; }
}

# Case 1: the seeded-invalid fixture is rejected, naming both issue classes.
if GATE "$FX/finding-seeded-invalid.json" > "$TMP/seeded.out" 2>&1; then
  note "ajv gate ACCEPTED the seeded-invalid finding — the gate has no teeth"
  fail=1
else
  grep -q "citations" "$TMP/seeded.out" && grep -q "minItems" "$TMP/seeded.out" \
    || { note "seeded empty-citations violation not named by the gate"; fail=1; }
  grep -q "verification" "$TMP/seeded.out" \
    || { note "seeded missing-verification violation not named by the gate"; fail=1; }
fi

# Case 2: the wrong-dimension fixture is ajv-valid (the schema gate cannot see
# lanes) but the lane's pin gate rejects it; the correctly-pinned fixture
# passes the same gate.
if ! GATE "$FX/finding-wrong-dimension.json" > "$TMP/ajv-wrongdim.out" 2>&1; then
  note "wrong-dimension fixture is schema-broken — it must be ajv-valid so the eval proves the PIN gate, not the schema gate: $(tail -2 "$TMP/ajv-wrongdim.out")"
  fail=1
fi
if LANE_GATE "$FX/finding-wrong-dimension.json" "$LANE" > "$TMP/pin.out" 2>&1; then
  note "lane gate PASSED a finding pinned to another dimension — pin enforcement has no teeth"
  fail=1
else
  grep -q "dimension pin 'governance' != lane '$LANE'" "$TMP/pin.out" \
    || { note "wrong-dimension rejection did not name the pin mismatch"; fail=1; }
fi
LANE_GATE "$FX/finding-pair-old.json" "$LANE" >/dev/null 2>&1 \
  || { note "lane gate rejected the correctly-pinned control finding"; fail=1; }

# Case 3: relate/dedup annotation is additive — never a delete or rewrite.
FDIR="$TMP/findings"
mkdir -p "$FDIR"
cp "$FX/finding-pair-old.json" "$FX/finding-pair-new.json" "$FDIR/"
before_count=$(ls "$FDIR" | wc -l | tr -d ' ')
jq '{title, content, summary}' "$FDIR/finding-pair-new.json" > "$TMP/new-claim-before.json"
old_id="$(jq -r '."@id"' "$FDIR/finding-pair-old.json")"

# The relate pass's one sanctioned edit: annotate the NEWER finding with a
# typed MIF relationship to the older (duplicates semantics).
jq --arg t "$old_id" \
  '.relationships = ((.relationships // []) + [{type: "duplicates", target: $t, strength: 0.9}])' \
  "$FDIR/finding-pair-new.json" > "$TMP/annotated.json" \
  && mv "$TMP/annotated.json" "$FDIR/finding-pair-new.json"

after_count=$(ls "$FDIR" | wc -l | tr -d ' ')
[ "$before_count" = "$after_count" ] \
  || { note "relate annotation changed the findings-file count ($before_count -> $after_count)"; fail=1; }
cmp -s "$FX/finding-pair-old.json" "$FDIR/finding-pair-old.json" \
  || { note "relate annotation modified the OLDER finding — it must be byte-identical"; fail=1; }
jq '{title, content, summary}' "$FDIR/finding-pair-new.json" > "$TMP/new-claim-after.json"
cmp -s "$TMP/new-claim-before.json" "$TMP/new-claim-after.json" \
  || { note "relate annotation rewrote the newer finding's claim content"; fail=1; }
GATE "$FDIR/finding-pair-new.json" >/dev/null 2>&1 \
  || { note "annotated finding no longer validates against schemas/findings.schema.json"; fail=1; }
jq -e --arg t "$old_id" \
  '.relationships | map(select(.type == "duplicates" and .target == $t)) | length == 1' \
  "$FDIR/finding-pair-new.json" >/dev/null \
  || { note "typed duplicates relationship to the older finding was not added"; fail=1; }

# Case 4: the workflow module encodes the same contract.
grep -q 'const FINDING_CONTRACT' "$WF" \
  || { note "$WF lost the FINDING_CONTRACT constant"; fail=1; }
grep -qF 'CONTRACT — ${FINDING_CONTRACT}' "$WF" \
  || { note "$WF analyst brief no longer embeds FINDING_CONTRACT"; fail=1; }
grep -q "required:.*'crossDimensionLeads'" "$WF" \
  || { note "$WF RESEARCH_SCHEMA no longer requires crossDimensionLeads"; fail=1; }
grep -qF 'extensions.harness.dimension != "${d}"' "$WF" \
  || { note "$WF validate step lost the dimension-pin enforcement"; fail=1; }
grep -qF 'never delete a finding or weaken its claim' "$WF" \
  || { note "$WF repair prompt lost the never-delete/never-weaken constraint"; fail=1; }
grep -qF 'v.validation.invalid.length' "$WF" \
  || { note "$WF repair pass no longer routes on the validate step's invalid list (fail-closed routing lost)"; fail=1; }
grep -qF 'never delete either' "$WF" \
  || { note "$WF relate prompt lost the never-delete constraint"; fail=1; }

[ "$fail" -eq 0 ] && note "ajv gate rejects the seeded-invalid finding naming both issue classes, the lane pin gate rejects an off-lane (ajv-valid) pin, relate annotation is purely additive, and the module keeps the contract text"
exit "$fail"
