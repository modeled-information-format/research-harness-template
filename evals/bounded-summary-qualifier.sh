#!/usr/bin/env bash
# bounded-summary-qualifier.sh — regression eval for research-harness-template#503/#504:
# the falsification-analyst's `weakened`-remediation step appends a qualifier to a
# finding's `summary`, and that field inherits `maxLength: 500` from the canonical
# MIF schema (schemas/mif/mif.schema.json). Before #504, the append was unbounded,
# so a verbose qualifier could push `summary` past 500 chars (observed up to 723
# chars, 5 of 19 weakened findings in one real gate run) -- a schema-invalid finding
# that `ajv validate` would reject.
#
# #504 fixed this by documenting a bounded-qualifier algorithm (a Python snippet
# under ".claude/agents/falsification-analyst.md"'s "Bounded summary qualifier"
# heading) rather than executable code -- the falsification-analyst is a prose
# agent, not a script, so there is nothing else to unit-test directly. This eval
# extracts that EXACT snippet from the doc at eval time (not a hand-copied
# reimplementation, which would drift silently if the doc's algorithm changes
# without the eval being updated) and exercises it against a matrix of summary/
# verdict_basis lengths, asserting the 500-char invariant holds and the qualifier
# is never silently dropped.
#
# Exit 0 = the documented algorithm holds its own invariant. Exit 1 = a case failed
# or the snippet could not be extracted (the doc's fencing changed shape).

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/.claude/agents/falsification-analyst.md"
fail=0
note() { printf '  bounded-summary-qualifier: %s\n' "$1"; }

# Extract the python fence immediately following the "Bounded summary qualifier"
# heading -- not just the first ```python fence in the doc (Step 6 has an
# unrelated bash fence; a future doc edit could add other python fences too).
SNIPPET="$(awk '
  /^\*\*Bounded summary qualifier/ { seen_heading = 1 }
  seen_heading && /^```python$/ && !in_fence { in_fence = 1; next }
  in_fence && /^```$/ { exit }
  in_fence { print }
' "$DOC")"

if [ -z "$SNIPPET" ]; then
  note "could not extract the bounded-summary python snippet from $DOC -- doc fencing may have changed shape"
  exit 1
fi

# Write the extracted snippet to disk and have Python read it back at run time,
# rather than interpolating $SNIPPET into an unquoted here-doc -- an unquoted
# here-doc lets Bash expand any `$`, backticks, or other shell metacharacters
# in the doc's own prose/code before Python ever sees it, which would silently
# corrupt the "exact snippet" this eval exists to test verbatim.
SNIPPET_FILE="$(mktemp)"
trap 'rm -f "$SNIPPET_FILE"' EXIT
printf '%s\n' "$SNIPPET" > "$SNIPPET_FILE"

# check <case-name> <summary-len> <verdict-basis-len>
# Builds a synthetic finding + verdict_basis of the given lengths, execs the
# EXTRACTED snippet against them, and asserts the invariant + qualifier presence.
check() {
  local case_name="$1" summary_len="$2" basis_len="$3"
  python3 - "$summary_len" "$basis_len" "$SNIPPET_FILE" <<'PYEOF'
import sys
summary_len, basis_len, snippet_file = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
finding = {"summary": "s" * summary_len}
verdict_basis = "b" * basis_len

with open(snippet_file) as f:
    exec(compile(f.read(), snippet_file, "exec"))

assert len(finding["summary"]) <= 500, f"summary exceeded 500 chars: {len(finding['summary'])}"
assert "[Falsification note:" in finding["summary"], "qualifier was dropped, not just truncated"
PYEOF
  if [ $? -eq 0 ]; then
    printf '  ok    %s (summary=%d, verdict_basis=%d)\n' "$case_name" "$summary_len" "$basis_len"
  else
    printf '  FAIL  %s (summary=%d, verdict_basis=%d)\n' "$case_name" "$summary_len" "$basis_len"
    fail=1
  fi
}

check "short-summary-short-basis" 50 20
check "summary-at-schema-limit" 500 20
check "summary-well-past-schema-limit" 2000 20
check "long-verdict-basis-alone" 50 300
check "both-summary-and-basis-long" 2000 300
check "empty-summary" 0 20
check "empty-verdict-basis" 50 0

if [ "$fail" -eq 0 ]; then
  note "all cases hold the 500-char invariant and never drop the qualifier"
fi
exit "$fail"
