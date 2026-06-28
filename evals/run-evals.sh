#!/usr/bin/env bash
# run-evals.sh — the harness eval suite (SPEC §4a "Evals — KEEP → first-class";
# shipped and run in template CI). Each eval exercises a harness behaviour
# end-to-end against the sample corpus and asserts the expected outcome. Quality
# is a first-class concern, not optional.
#
#   bash evals/run-evals.sh
#
# Exit 0 iff every eval passes.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

PASS=0; FAIL=0
GREEN=$'\033[32m'; RED=$'\033[31m'; RST=$'\033[0m'
run() { # run <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf '%s  PASS %s %s\n' "$GREEN" "$RST" "$name"
  else
    FAIL=$((FAIL+1)); printf '%s  FAIL %s %s\n' "$RED" "$RST" "$name"
  fi
}
# An eval that must FAIL the underlying command (negative case).
run_neg() { # run_neg <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    FAIL=$((FAIL+1)); printf '%s  FAIL %s %s (expected failure)\n' "$RED" "$RST" "$name"
  else
    PASS=$((PASS+1)); printf '%s  PASS %s %s\n' "$GREEN" "$RST" "$name"
  fi
}

SF="reports/_meta/sample-session/findings"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. Engine pipeline smoke test (orchestrator → one falsification gate → MIF finding).
run "engine-smoke" bash evals/smoke-test.sh

# 1b. Topic run lock: two concurrent runs on one topic are mutually exclusive
#     (prevents the shared-findings/ corruption vector).
run "run-lock-mutual-exclusion" bash evals/run-lock-test.sh

# 1c. Update-channel provenance gate: scripts/update.sh refuses to invoke copier on a
#     verification miss (fail-closed), pins copier to the verified SHA on a pass, and
#     refuses a dirty tree (issue #94).
run "update-provenance-gate" bash evals/update-provenance.sh

# 2. Citation-integrity: a clean finding passes; a bad one is flagged.
run     "citation-integrity-good" scripts/check-citation-integrity.sh schemas/samples/citation-good.sample.json
run_neg "citation-integrity-bad"  scripts/check-citation-integrity.sh schemas/samples/citation-bad.sample.json

# 3. Knowledge graph derives from MIF ids, not tags.
run "kg-from-mif" bash -c 'scripts/build-graph.sh "'"$SF"'" "'"$TMP"'/kg.json" && scripts/assert-graph-mif.sh "'"$TMP"'/kg.json"'

# 4. Output contract: findings render to both blog and book via one artifact.
run "outputs-blog-and-book" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/a.json" &&
  scripts/render-artifact.sh "'"$TMP"'/a.json" blog "'"$TMP"'/post.md" &&
  scripts/render-artifact.sh "'"$TMP"'/a.json" book "'"$TMP"'/chapter.md" &&
  [ -s "'"$TMP"'/post.md" ] && [ -s "'"$TMP"'/chapter.md" ]'

# 4b. Diagram policy: a Mermaid figure in a section body survives rendering intact
#     (the render pass leaves fenced code blocks verbatim) and validates.
run "mermaid-render-preserves-fences" bash evals/mermaid-render.sh

# 5. MIF I/O conformance (SPEC §10).
# 5a. A compliant report projects to a valid MIF L3 finding; bad ones are rejected.
run     "report-mif-good"           scripts/mif-project.sh schemas/samples/report.sample.md
run_neg "report-mif-bad"            scripts/mif-project.sh evals/fixtures/report-bad.md
run_neg "report-falsified-rejected" scripts/mif-project.sh evals/fixtures/report-falsified.md

# 5b. The report channel emits a valid L3 report end-to-end (write-then-validate).
run "report-channel-e2e" bash -c '
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/r.json" &&
  scripts/render-artifact.sh "'"$TMP"'/r.json" report "'"$TMP"'/report.md" evals/fixtures/report-verification.json &&
  scripts/mif-project.sh "'"$TMP"'/report.md"'

# 5b-2. The documented verdict path is real: a verdict PRODUCED by falsify.sh (not
#       hand-authored) flows through extraction into a valid L3 report. Proves the
#       falsify.sh -> verification-block -> report channel seam the agent doc uses.
run "report-verdict-from-falsify" bash -c '
  scripts/falsify.sh evals/fixtures/raw-finding.json evals/fixtures/evidence.json > "'"$TMP"'/ff.json" &&
  jq ".extensions.harness.verification" "'"$TMP"'/ff.json" > "'"$TMP"'/vf.json" &&
  scripts/synthesize-artifact.sh "'"$SF"'" general "'"$TMP"'/ra.json" &&
  scripts/render-artifact.sh "'"$TMP"'/ra.json" report "'"$TMP"'/rr.md" "'"$TMP"'/vf.json" &&
  scripts/mif-project.sh "'"$TMP"'/rr.md"'

# 5c. Inbound source-envelope: a valid envelope passes; an invalid one is refused.
run     "source-envelope-good" ajv validate --spec=draft2020 --strict=false -c ajv-formats \
          -s schemas/mif/source-envelope.schema.json -r schemas/mif/mif.schema.json \
          -r schemas/mif/definitions/entity-reference.schema.json -d schemas/samples/source-envelope.sample.json
run_neg "source-envelope-bad"  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
          -s schemas/mif/source-envelope.schema.json -r schemas/mif/mif.schema.json \
          -r schemas/mif/definitions/entity-reference.schema.json -d evals/fixtures/source-envelope-bad.json

# 5d. Exemptions are declared (blog is the always-on exempt output; book/pdf channel packs
#     declare mif.exempt in their plugin.json).
run "exempt-channels-declared" bash -c '
  jq -e "[.outputs[]|select(.channel==\"blog\")|select(.mifExempt==true)]|length==1" harness.config.json >/dev/null &&
  jq -e ".mif.exempt==true" packs/channels/book/.claude-plugin/plugin.json >/dev/null &&
  jq -e ".mif.exempt==true" packs/channels/pdf/.claude-plugin/plugin.json >/dev/null'

# 5d. Ontology resolution (SPEC §8c): a finding's entity_type resolves to exactly one
#     of its topic's bound ontologies and its entity validates (additive); undeclared,
#     missing-required, and unbound-for-topic fail; untyped and generic-core pass.
OC="--catalog evals/fixtures/ontology/catalog.json --config evals/fixtures/ontology/config.json"
run     "ontology-resolve-good"     bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/good.json    --topic edu  $OC --map \"$TMP/o1.json\""
run     "ontology-extra-field-ok"   bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/extra.json   --topic edu  $OC --map \"$TMP/o2.json\""
run     "ontology-generic-core"     bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/generic.json --topic bare $OC --map \"$TMP/o3.json\""
run     "ontology-untyped-ok"       bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/untyped.json --topic edu  $OC --map \"$TMP/o4.json\""
run_neg "ontology-undeclared-type"  bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/undecl.json  --topic edu  $OC --map \"$TMP/o5.json\""
run_neg "ontology-missing-required" bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/missing.json --topic edu  $OC --map \"$TMP/o6.json\""
run_neg "ontology-unbound-for-topic" bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/good.json   --topic bare $OC --map \"$TMP/o7.json\""
run_neg "ontology-ambiguous"        bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/ambiguous.json --topic eng $OC --map \"$TMP/o8.json\""
run     "ontology-disambiguated"    bash -c "scripts/resolve-ontology.sh evals/fixtures/ontology/disambig.json  --topic eng $OC --map \"$TMP/o9.json\""
run     "ontology-review-coverage"  bash -c "mkdir -p \"$TMP/rep/edu/findings\" && cp evals/fixtures/ontology/good.json \"$TMP/rep/edu/findings/\" && scripts/ontology-review.sh --topic edu --strict --reports-dir \"$TMP/rep\" $OC"

# 5e. Ontological spine (concordance, SPEC §8d): build over a topic corpus and validate
#     ontology conformance; an undeclared entityType or a from/to domain violation fails.
WC="--config evals/fixtures/concordance/config.json --catalog evals/fixtures/concordance/catalog.json"
run     "concordance-build-and-validate" bash -c "scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w.json\" >/dev/null && scripts/validate-concordance.sh \"$TMP/w.json\" $WC"
run     "concordance-conformant"         scripts/validate-concordance.sh evals/fixtures/concordance/good.concordance.json $WC
run_neg "concordance-undeclared-type"    scripts/validate-concordance.sh evals/fixtures/concordance/undeclared-type.concordance.json $WC
run_neg "concordance-domain-violation"   scripts/validate-concordance.sh evals/fixtures/concordance/domain-violation.concordance.json $WC
run     "concordance-idempotent"         bash -c "scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w1.json\" >/dev/null && scripts/build-concordance.sh evals/fixtures/concordance/reports \"$TMP/w2.json\" >/dev/null && diff -q \"$TMP/w1.json\" \"$TMP/w2.json\""

# 6. Model-authoring layer (lib/harness_models): every authored schema emits
#    deterministic, schema-valid contract JSON from a typed dict — replacing the
#    hand-composed shell JSON (`jq -n`) that broke under the Bash `eval` wrapper.
run "models-authoring" python3 evals/test_models.py

# 7. Progress-log markdownlint conformance (issue #85 Defect 2): a multi-session
#    research-progress.md built per orchestrator.md's template — one H1 (file
#    creation only) + date-qualified per-session H2s — lints clean, while each old
#    buggy form fails on its SPECIFIC rule: a re-emitted top-level H1 trips MD025,
#    and a repeated fixed `## Findings Summary` sub-heading (single H1) trips MD024
#    and not MD025. Proves the lint config has teeth for both defect forms.
#    markdownlint-cli2 is always present in CI (installed in this job); a local run
#    without it shows a visible SKIP rather than a silent pass.
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  run "progress-log-multisession-lint" bash -c '
    d=$(mktemp -d); trap '\''rm -rf "$d"'\'' EXIT
    cat > "$d/good.md" <<EOF
# Research Progress: demo

## 2026-06-01 — Session Initialized

- Goal: x

## 2026-06-01 — Session Summary

- **Status:** complete

## 2026-06-02 — Session Initialized

- Goal: x

## 2026-06-02 — Session Summary

- **Status:** complete
EOF
    # D2 form (a): the H1 re-emitted each session -> MD025 (multiple top-level headings).
    cat > "$d/bad_h1.md" <<EOF
# Research Progress: demo

## 2026-06-01 — Session Initialized

- Goal: x

# Research Progress: demo

## 2026-06-02 — Session Initialized

- Goal: y
EOF
    # D2 form (b): a fixed sub-heading repeated across sessions under a single H1 ->
    #             MD024 (duplicate sibling heading), and specifically NOT MD025.
    cat > "$d/bad_sub.md" <<EOF
# Research Progress: demo

## Findings Summary

- a

## Findings Summary

- b
EOF
    markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/good.md" >/dev/null 2>&1 || { echo "conformant log not clean"; exit 1; }
    h1=$(markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/bad_h1.md" 2>&1); [ $? -ne 0 ] || { echo "bad_h1 unexpectedly clean"; exit 1; }
    echo "$h1" | grep -q MD025 || { echo "re-emitted H1 did not trip MD025"; exit 1; }
    sub=$(markdownlint-cli2 --config .markdownlint-cli2.jsonc "$d/bad_sub.md" 2>&1); [ $? -ne 0 ] || { echo "bad_sub unexpectedly clean"; exit 1; }
    echo "$sub" | grep -q MD024 || { echo "repeated sub-heading did not trip MD024"; exit 1; }
    echo "$sub" | grep -q MD025 && { echo "bad_sub tripped MD025 (must isolate MD024)"; exit 1; }
    exit 0'
else
  printf '  SKIP  progress-log-multisession-lint (markdownlint-cli2 not installed)\n'
fi

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%srun-evals: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%srun-evals: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
