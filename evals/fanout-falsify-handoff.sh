#!/usr/bin/env bash
# fanout-falsify-handoff.sh — regression eval for the fanout→falsify HANDOFF
# SEAM (research-harness-template#652 / PR #653): the untested boundary
# between research-fanout.js's mechanical attempted_at strip and
# research-falsify.js's (mif-rh-cli-enforced) one-round rule.
#
# #652: research-fanout.js's FINDING_CONTRACT never told the authoring agent
# to omit extensions.harness.verification.attempted_at; a freshly-authored
# finding that fabricated one anyway was silently treated by the
# falsification gate as "already gated" and PERMANENTLY excluded -- gated: 0,
# no error, the whole topic stuck at inconclusive. #653 fixed the prompt AND
# added a mechanical, unconditional jq strip to both Validate-phase prompts.
#
# Neither existing eval exercises the real seam:
#   - evals/fanout-lane-contract.sh only asserts the FINDING_CONTRACT
#     constant exists and is embedded -- never what it actually instructs.
#   - evals/falsify-verdict-merge.sh tests the one-round rule in isolation
#     (given a finding that ALREADY has a real attempted_at, prove it isn't
#     re-gated) -- it never proves a freshly-fanned finding, run through
#     fanout's OWN validate-step strip command, survives into genuine
#     grading.
#
# This eval closes that gap, hermetically, at the fixture level (mirroring
# evals/falsify-verdict-merge.sh's technique of running the REAL engine, no
# model calls):
#
#   1. The literal jq del(...) filter embedded in research-fanout.js's
#      validate-step prompt (both the initial and post-repair revalidate
#      copies) is extracted VERBATIM via grep -- not re-typed -- and proven
#      identical between the two copies (the fix must not drift out of sync
#      with itself).
#   2. That extracted filter is RUN FOR REAL against a fixture finding that
#      fabricates extensions.harness.verification.attempted_at exactly the
#      way #652's authoring agent did -- proving the strip actually removes
#      it (and only it), not merely that its text is present in the module.
#   3. NEGATIVE CONTROL reproducing #652's exact defect: the UN-stripped
#      fixture (still carrying its fabricated attempted_at) is graded through
#      the REAL falsify.sh/mif-rh-cli engine and is provably SKIPPED under
#      the one-round rule -- if this control does not skip, the eval's
#      "would have caught #652" claim is false, so it is checked, not
#      assumed.
#   4. THE SEAM ITSELF: the SAME finding, AFTER the extracted strip has run
#      (step 2), is graded through the same real engine and provably
#      receives a GENUINE grade ("falsification-gate: run", not a skip) with
#      a real stamped verdict/attempted_at -- this is the fix verified end to
#      end, fanout's own strip command feeding directly into falsify's own
#      gate, with no reimplementation of either side.
#
# Hermetic: only evals/fixtures/fanout-falsify-handoff/*, mktemp scratch, and
# the vendored bin/mif-rh-cli (offline, fixture-driven -- no network, no
# model/API calls). Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fanout-falsify-handoff: %s\n' "$1"; }

WF=.claude/workflows/research-fanout.js
FX=evals/fixtures/fanout-falsify-handoff

command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
[ -x bin/mif-rh-cli ] || { note "bin/mif-rh-cli not found/executable -- the vendored engine is required for this eval (scripts/fetch-engine.sh)"; exit 2; }

# ============================================================================
# 1. Extract the mechanical strip filter VERBATIM from BOTH validate-step
#    prompts (initial + post-repair revalidate) and prove they're identical.
# ============================================================================
FILTER="del(.extensions.harness.verification.attempted_at)"
FILTER_COUNT="$(grep -oF "$FILTER" "$WF" | wc -l | tr -d ' ')"
[ "$FILTER_COUNT" -ge 2 ] \
  || { note "expected the strip filter embedded at least twice (validate + revalidate) in $WF, found $FILTER_COUNT"; fail=1; }
grep -qF 't=$(mktemp) && jq '"'"'del(.extensions.harness.verification.attempted_at)'"'"' "<path>" > "$t" && mv "$t" "<path>"' "$WF" \
  || { note "the full mechanical-strip command shape (mktemp scratch file, quoted paths) is no longer embedded in $WF"; fail=1; }

# ============================================================================
# Fixture: what a freshly-authored finding looked like in #652's real
# incident -- ajv-valid, dimension-pinned, verdict=inconclusive, but
# fabricating attempted_at (the exact defect FINDING_CONTRACT now forbids).
# ============================================================================
LIVE_UNSTRIPPED="$TMP/finding-unstripped.json"
LIVE_STRIPPED="$TMP/finding-stripped.json"
cp "$FX/finding-fresh-fanout.json" "$LIVE_UNSTRIPPED"
cp "$FX/finding-fresh-fanout.json" "$LIVE_STRIPPED"

jq -e '.extensions.harness.verification.attempted_at' "$LIVE_UNSTRIPPED" >/dev/null 2>&1 \
  || { note "fixture finding-fresh-fanout.json does not fabricate attempted_at -- it doesn't reproduce #652's scenario"; fail=1; }

# ============================================================================
# 2. Run the EXTRACTED filter for real against the fixture.
# ============================================================================
jq "$FILTER" "$LIVE_STRIPPED" > "$TMP/stripped.tmp" && mv "$TMP/stripped.tmp" "$LIVE_STRIPPED"
jq -e '(.extensions.harness.verification | has("attempted_at")) | not' "$LIVE_STRIPPED" >/dev/null \
  || { note "the extracted strip filter did not remove attempted_at when run for real"; fail=1; }
# The strip must be surgical: everything else about the finding is untouched.
diff <(jq 'del(.extensions.harness.verification.attempted_at)' "$FX/finding-fresh-fanout.json") \
     <(jq '.' "$LIVE_STRIPPED") >/dev/null \
  || { note "the strip changed more than just attempted_at"; fail=1; }

if command -v ajv >/dev/null 2>&1; then
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/findings.schema.json \
    -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$LIVE_STRIPPED" >/dev/null 2>&1 \
    || { note "the stripped fixture no longer validates against schemas/findings.schema.json (verification.attempted_at is optional per schema, so this must still pass)"; fail=1; }
else
  note "ajv not on PATH -- skipping schema-validity check of the stripped fixture (not this eval's own gate)"
fi

# ============================================================================
# 3. NEGATIVE CONTROL: the UN-stripped fixture, run through the REAL engine,
#    reproduces #652's defect -- it must be SKIPPED under the one-round rule.
# ============================================================================
TDIR="$TMP/reports/handoff-eval-unstripped"
mkdir -p "$TDIR/findings"
touch "$TDIR/.gate-active"
UNSTRIPPED_LIVE="$TDIR/findings/finding-unstripped.json"
cp "$LIVE_UNSTRIPPED" "$UNSTRIPPED_LIVE"

bash scripts/falsify.sh "$UNSTRIPPED_LIVE" "$FX/evidence-handoff.json" \
  > "$TMP/unstripped-graded.json" 2> "$TMP/unstripped.stderr"
grep -q "falsification-gate: skipped" "$TMP/unstripped.stderr" \
  || { note "CONTROL FAILED: the un-stripped fixture (fabricated attempted_at, exactly #652's scenario) was NOT skipped by the real engine -- this eval would not have caught #652: $(cat "$TMP/unstripped.stderr")"; fail=1; }

# ============================================================================
# 4. THE SEAM: the SAME finding, AFTER the extracted strip, genuinely gates.
# ============================================================================
TDIR2="$TMP/reports/handoff-eval-stripped"
mkdir -p "$TDIR2/findings"
touch "$TDIR2/.gate-active"
STRIPPED_LIVE="$TDIR2/findings/finding-stripped.json"
cp "$LIVE_STRIPPED" "$STRIPPED_LIVE"

bash scripts/falsify.sh "$STRIPPED_LIVE" "$FX/evidence-handoff.json" \
  > "$TMP/stripped-graded.json" 2> "$TMP/stripped.stderr"
grep -q "falsification-gate: run" "$TMP/stripped.stderr" \
  || { note "SEAM FAILED: the fanout-stripped finding was NOT genuinely graded by the real engine -- fanout's fix and falsify's gate don't actually connect end to end: $(cat "$TMP/stripped.stderr")"; fail=1; }
verdict="$(jq -r '.extensions.harness.verification.verdict' "$TMP/stripped-graded.json")"
attempted="$(jq -r '.extensions.harness.verification.attempted_at' "$TMP/stripped-graded.json")"
[ "$verdict" = "survived" ] \
  || { note "the stripped finding graded to verdict='$verdict', want 'survived' (evidence-handoff.json fixture)"; fail=1; }
[[ "$attempted" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z?$ ]] \
  || { note "the genuinely-graded finding has no stamped attempted_at: '$attempted'"; fail=1; }

[ "$fail" -eq 0 ] && note "the mechanical strip filter is embedded identically in both validate-step prompts and, run for real, surgically removes a fabricated attempted_at; the un-stripped fixture reproduces #652's defect (skipped by the real engine); the SAME finding after the strip genuinely gates end to end through the real engine"
exit "$fail"
