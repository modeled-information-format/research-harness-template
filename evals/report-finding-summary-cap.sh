#!/usr/bin/env bash
# report-finding-summary-cap.sh — regression eval for research-harness-template#629:
# research-projection.js's Report phase step 2 constructs report-finding.json's
# `summary` field FROM SCRATCH off the artifact's title/sections/sources, and a
# naturally-written summary over a substantial multi-finding synthesis can run well
# past the schema's 500-char cap (schemas/mif/mif.schema.json) -- observed 3937
# chars against a real topic, surfaced only after the fact by the pipeline's own
# problems[] rather than caught before the file was written.
#
# The fix documents a bounded-construction algorithm (a Python snippet under
# ".claude/workflows/research-projection.js"'s "BOUNDED SUMMARY CONSTRUCTION"
# comment heading) rather than executable code -- like research-projection.js's
# other Report/Index/Verify steps, the module drives a prompt-based agent, not a
# script, so there is nothing else to unit-test directly (the same shape as the
# existing bounded-summary-qualifier eval for falsification-analyst.md's WEAKENED-
# remediation qualifier append, research-harness-template#503/#504 -- this module
# hits the same 500-char cap from the opposite direction: a bounded CONSTRUCTION
# from scratch, not a bounded APPEND onto an existing summary).
#
# This eval extracts that EXACT snippet from the module at eval time (not a
# hand-copied reimplementation, which would drift silently if the documented
# algorithm changes without the eval being updated) and exercises it against a
# matrix of summary lengths, including the real observed overrun (3937 chars),
# asserting the 500-char invariant holds and a summary already under the cap is
# never altered.
#
# Exit 0 = the documented algorithm holds its own invariant. Exit 1 = a case failed
# or the snippet could not be extracted (the comment fencing changed shape).

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/.claude/workflows/research-projection.js"
fail=0
note() { printf '  report-finding-summary-cap: %s\n' "$1"; }

# Extract the python fence immediately following the "BOUNDED SUMMARY
# CONSTRUCTION" heading. research-projection.js is a `//`-commented JS module,
# not a raw markdown file, so each fence/body line carries a "// " comment
# prefix that must be stripped before the snippet is valid Python.
SNIPPET="$(awk '
  /^\/\/ BOUNDED SUMMARY CONSTRUCTION/ { seen_heading = 1 }
  seen_heading && /^\/\/ ```python$/ && !in_fence { in_fence = 1; next }
  in_fence && /^\/\/ ```$/ { exit }
  in_fence { sub(/^\/\/ ?/, ""); print }
' "$DOC")"

if [ -z "$SNIPPET" ]; then
  note "could not extract the bounded-summary python snippet from $DOC -- comment fencing may have changed shape"
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

# check <case-name> <summary-len>
# Builds a synthetic summary of the given length, execs the EXTRACTED snippet's
# bound_summary() against it, and asserts the invariant + non-destructive behavior
# for summaries already under the cap.
check() {
  local case_name="$1" summary_len="$2"
  python3 - "$summary_len" "$SNIPPET_FILE" <<'PYEOF'
import sys
summary_len, snippet_file = int(sys.argv[1]), sys.argv[2]
summary = "s" * summary_len

with open(snippet_file) as f:
    exec(compile(f.read(), snippet_file, "exec"))

bounded = bound_summary(summary)
assert len(bounded) <= 500, f"summary exceeded 500 chars: {len(bounded)}"
if summary_len <= 500:
    assert bounded == summary, "a summary already under the cap must not be altered"
else:
    assert bounded.endswith("…"), "a truncated summary must carry the ellipsis marker"
    assert bounded[:-1] == summary[: len(bounded) - 1], "truncation must preserve the summary's leading content"
PYEOF
  if [ $? -eq 0 ]; then
    printf '  ok    %s (summary=%d)\n' "$case_name" "$summary_len"
  else
    printf '  FAIL  %s (summary=%d)\n' "$case_name" "$summary_len"
    fail=1
  fi
}

check "empty-summary" 0
check "short-summary" 50
check "summary-at-schema-limit" 500
check "summary-just-past-schema-limit" 501
check "summary-well-past-schema-limit" 2000
check "summary-matching-the-real-observed-overrun" 3937

if [ "$fail" -eq 0 ]; then
  note "the documented bound_summary algorithm holds the 500-char invariant and never alters an already-conformant summary"
fi
exit "$fail"
