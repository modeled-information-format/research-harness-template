#!/usr/bin/env bash
# conformance-sweep-depth.sh — regression eval for the check-output-conformance
# sweep pathspec depth (research-harness-template#687). A bare git pathspec
# 'reports/*/*.md' is fnmatch() without FNM_PATHNAME, so `*` crosses `/` and the
# sweep used to pick up arbitrarily nested channel files (e.g.
# reports/<topic>/book/chapters/ch1.md) that the hook's own header declares
# exempt — mif-project.sh then failed against ordinary book prose and the Stop
# hook emitted a spurious "MIF output-conformance gate" systemMessage on every
# session that left a book-pack chapter git-dirty. The fix qualifies the sweep
# with `:(glob)` so `*` stops at `/`.
#
# Runs the REAL hook against a scratch git repo (stub mif-project.sh that always
# refuses, so anything swept lands in $BAD) and asserts:
#   1. A git-dirty nested book chapter alone produces NO gate message
#      (fails without the :(glob) qualifier — the #687 regression).
#   2. A git-dirty flat generic report still produces the gate message
#      (the fix must not weaken the gate's teeth).
#   3. Exempt flat files (README.md, *.blog.md, *-build-spec.md, _meta/,
#      _corpus/) still produce NO gate message.
#
# Exit 0 = all hold. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  conformance-sweep-depth: %s\n' "$1"; }

HOOK="$ROOT/.claude/hooks/check-output-conformance.sh"
[ -f "$HOOK" ] || { note "hook not found at $HOOK"; exit 1; }

# Scratch harness: a git repo with a stub mif-project.sh that refuses every
# file, so any path the sweep picks up is guaranteed to land in $BAD.
HARNESS="$TMP/harness"
mkdir -p "$HARNESS/scripts" "$HARNESS/.claude/hooks"
git -C "$HARNESS" init -q
printf '#!/usr/bin/env bash\nexit 1\n' > "$HARNESS/scripts/mif-project.sh"
chmod +x "$HARNESS/scripts/mif-project.sh"
cp "$HOOK" "$HARNESS/.claude/hooks/check-output-conformance.sh"

# run_hook <label> — runs the hook against the scratch harness, prints stdout.
run_hook() {
  CLAUDE_PROJECT_DIR="$HARNESS" bash "$HARNESS/.claude/hooks/check-output-conformance.sh" </dev/null 2>/dev/null
}
reset_tree() { rm -rf "$HARNESS/reports"; }

# Case 1: nested book chapter alone — must NOT be swept (#687).
reset_tree
mkdir -p "$HARNESS/reports/mytopic/book/chapters"
printf 'ordinary book prose, no MIF frontmatter\n' \
  > "$HARNESS/reports/mytopic/book/chapters/ch1.md"
OUT="$(run_hook)"
if [ -n "$OUT" ]; then
  note "nested book chapter tripped the gate (pathspec crossed '/') — #687 regression: $OUT"
  fail=1
fi

# Case 2: flat non-conformant generic report — the gate must still fire.
reset_tree
mkdir -p "$HARNESS/reports/mytopic"
printf 'a generic report that does not project\n' \
  > "$HARNESS/reports/mytopic/finding.md"
OUT="$(run_hook)"
if ! printf '%s' "$OUT" | grep -q 'reports/mytopic/finding.md'; then
  note "flat non-conformant report no longer trips the gate (teeth lost)"
  fail=1
fi

# Case 3: exempt flat files — still skipped by the case exemptions.
reset_tree
mkdir -p "$HARNESS/reports/mytopic" "$HARNESS/reports/_meta" "$HARNESS/reports/_corpus"
printf 'nav index\n'    > "$HARNESS/reports/mytopic/README.md"
printf 'blog post\n'    > "$HARNESS/reports/mytopic/post.blog.md"
printf 'ai spec\n'      > "$HARNESS/reports/mytopic/foo-build-spec.md"
printf 'scaffolding\n'  > "$HARNESS/reports/_meta/notes.md"
printf 'atlas\n'        > "$HARNESS/reports/_corpus/corpus-synthesis.md"
OUT="$(run_hook)"
if [ -n "$OUT" ]; then
  note "an exempt flat file tripped the gate: $OUT"
  fail=1
fi

[ "$fail" -eq 0 ] && note "sweep matches only depth-2 generic reports; gate teeth intact"
exit "$fail"
