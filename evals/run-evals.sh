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

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%srun-evals: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%srun-evals: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
