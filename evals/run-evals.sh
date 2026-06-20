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

# 5d. Exemptions are declared (blog + book first-class, channel packs via mif.exempt).
run "exempt-channels-declared" bash -c '
  jq -e "[.outputs[]|select(.channel==\"blog\" or .channel==\"book\")|select(.mifExempt==true)]|length==2" harness.config.json >/dev/null &&
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

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%srun-evals: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%srun-evals: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
