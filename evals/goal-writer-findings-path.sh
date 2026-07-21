#!/usr/bin/env bash
# goal-writer-findings-path.sh — regression eval for the goal-writer command
# manual's finding-file paths (research-harness-template#676).
#
# Findings live at reports/<topic>/findings/*.json — one MIF unit per file,
# one level below the topic directory (goal.json/state.json/ontology-map.json
# live at the top level and carry no extensions.harness.dimension). Before
# #676, .claude/commands/goal-writer.md modeled coverage `verify` commands as
# globbing reports/<topic>/*.json directly (evidence-surface table + worked
# example), so any goal.json authored from it had a permanently unsatisfiable
# coverage_per_dimension check. This eval keeps every finding-path reference
# in the manual pointed at the findings/ subdirectory:
#
#   1. no bare topic-level finding glob (reports/<topic>/*.json or
#      reports/template-distribution/*.json) or topic-level <finding>.json
#      placeholder survives anywhere in the manual;
#   2. the evidence-surface "Coverage for a dimension" row counts files in
#      reports/<topic>/findings/;
#   3. the worked example's coverage_per_dimension verify globs
#      reports/template-distribution/findings/*.json;
#   4. the worked example's finding_valid verify validates
#      reports/template-distribution/findings/<finding>.json;
#   5. every prose line stating where finding MIF units live ("per finding
#      under" / "MIF units under") names the findings/ subdirectory.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  goal-writer-findings-path: %s\n' "$1"; }

CMD=.claude/commands/goal-writer.md

if [ ! -f "$CMD" ]; then
  note "missing $CMD"
  exit 1
fi

# Case 1: no bare topic-level finding glob or placeholder remains.
if grep -nE 'reports/(<topic>|template-distribution)/(\*\.json|<finding>\.json)' "$CMD"; then
  note "bare topic-level finding path found (findings live under reports/<topic>/findings/)"
  fail=1
fi

# Case 2: the evidence-surface coverage row counts the findings/ subdirectory.
if ! grep -E '^\| Coverage for a dimension' "$CMD" | grep -q 'reports/<topic>/findings/'; then
  note "evidence-surface 'Coverage for a dimension' row does not count reports/<topic>/findings/"
  fail=1
fi

# Case 3: the worked example's coverage verify globs findings/*.json.
if ! grep -q 'ls reports/template-distribution/findings/\*\.json' "$CMD"; then
  note "worked example coverage_per_dimension verify does not glob reports/template-distribution/findings/*.json"
  fail=1
fi

# Case 4: the worked example's finding_valid verify targets findings/<finding>.json.
if ! grep -q "reports/template-distribution/findings/<finding>\.json" "$CMD"; then
  note "worked example finding_valid verify does not validate reports/template-distribution/findings/<finding>.json"
  fail=1
fi

# Case 5: every finding-location prose statement names the findings/
# subdirectory. The path may wrap onto the next line, so judge each matched
# line joined with the line that follows it.
while IFS= read -r n; do
  pair="$(sed -n "${n},$((n + 1))p" "$CMD" | tr '\n' ' ')"
  case "$pair" in
    *findings/*) : ;;
    *)
      note "finding-location prose omits the findings/ segment (line $n): $pair"
      fail=1
      ;;
  esac
done < <(grep -nE 'per finding under|MIF (memory )?units under' "$CMD" | cut -d: -f1)

exit "$fail"
