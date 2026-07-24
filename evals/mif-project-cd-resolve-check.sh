#!/usr/bin/env bash
# mif-project-cd-resolve-check.sh — regression eval for
# research-harness-template#762: scripts/mif-project.sh re-resolves the
# report's directory to an absolute path via
#   MD="$(cd "$(dirname "$MD")" && pwd)/$(basename "$MD")"
# without checking whether the `cd` subshell actually succeeded. If the
# containing directory is removed, renamed, or unmounted by a concurrent
# process between the earlier `[ -f "$MD" ]` existence check and this
# re-resolution (a TOCTOU window — e.g. a worktree/scratch dir being cleaned
# up mid-run), `cd` fails, the command substitution silently returns empty,
# and MD becomes "/$(basename "$MD")" — a bogus root-level path — with no
# error raised at that point (no `set -e`, no explicit check). The script
# then proceeds and only fails several lines later inside the engine call
# with a generic "not compliant" error, obscuring the real cause.
#
# This extracts the ACTUAL fixed re-resolution stanza VERBATIM from the live
# script (never re-typed, so a future edit that regresses the check is
# caught structurally, not just behaviorally) and drives it with two cases:
#
#   A. Good path: the directory genuinely exists -> resolves to the correct
#      canonical absolute path, exits 0.
#   B. Vanished path: the directory does not exist at resolution time
#      (the post-TOCTOU state) -> must exit non-zero with a clear
#      diagnostic naming the resolution failure, and must NOT silently
#      produce a bogus "/$(basename ...)" path and continue.
#
# Exit 0 = both cases hold. Exit 1 = a case failed. Exit 2 = the script's
# shape has changed enough that the verbatim extraction itself failed —
# this eval refuses to silently skip.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/mif-project.sh"
fail=0
note() { printf '  mif-project-cd-resolve-check: %s\n' "$1"; }

[ -f "$SCRIPT" ] || { note "$SCRIPT not found"; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ============================================================================
# Verbatim extraction: the MD_DIR=... re-resolution stanza, start marker
# through its closing brace, plus the final MD= assignment line that
# consumes MD_DIR.
# ============================================================================
START='MD_DIR="\$(cd "\$(dirname "\$MD")" && pwd)" ||'
END_LINE='^MD="\$MD_DIR/\$\(basename "\$MD"\)"$'

start_no="$(grep -n "$START" "$SCRIPT" | head -1 | cut -d: -f1)"
[ -n "${start_no:-}" ] || { note "could not locate the checked cd re-resolution ('MD_DIR=\"\$(cd ...) || {') in $SCRIPT — has the #762 fix been reverted or reshaped?"; exit 2; }

end_no="$(tail -n "+$start_no" "$SCRIPT" | grep -nE "$END_LINE" | head -1 | cut -d: -f1)"
[ -n "${end_no:-}" ] || { note "could not locate the closing 'MD=\"\$MD_DIR/...\"' line after line $start_no in $SCRIPT — has the fix's shape changed?"; exit 2; }
end_no=$((start_no + end_no - 1))

STANZA="$(sed -n "${start_no},${end_no}p" "$SCRIPT")"
[ -n "$STANZA" ] || { note "extracted stanza was empty (lines $start_no-$end_no)"; exit 2; }

# Structural guard: the extracted stanza must still check the cd's exit
# status (a bare `|| {` immediately following the command substitution) and
# must exit non-zero on failure — regression trap against silently dropping
# the check while leaving the surrounding lines untouched.
case "$STANZA" in
  *'|| {'*) : ;;
  *) note "FAIL: extracted stanza no longer checks the cd subshell's exit status (no '|| {' guard)"; fail=1 ;;
esac
case "$STANZA" in
  *'exit 2'*) : ;;
  *) note "FAIL: extracted stanza no longer exits non-zero on a resolution failure"; fail=1 ;;
esac

note "extracted stanza (lines $start_no-$end_no of scripts/mif-project.sh):"
printf '%s\n' "$STANZA" | sed 's/^/    /'

run_case() { # run_case <name> <MD-path> <want-exit-zero: 0|1>
  local name="$1" md="$2" want_zero="$3"
  local script out rc
  # Built with the final "echo" piece single-quoted (no expansion at
  # construction time) so "$MD" is left literal for the INNER bash -c to
  # evaluate after the extracted stanza runs — not expanded here, now, in
  # this outer eval's own shell.
  script="MD=$(printf '%q' "$md")"$'\n'"$STANZA"$'\n''echo "RESOLVED:$MD"'
  out="$(bash -c "$script" 2>&1)"
  rc=$?
  if [ "$want_zero" -eq 1 ]; then
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^RESOLVED:$(cd "$(dirname "$md")" && pwd)/$(basename "$md")$"; then
      note "PASS: $name (rc=0, resolved to the correct canonical absolute path)"
    else
      note "FAIL: $name (rc=$rc, output: $out)"; fail=1
    fi
  else
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'failed to resolve directory'; then
      note "PASS: $name (rc=$rc, clear diagnostic emitted, no silent continuation)"
    elif printf '%s' "$out" | grep -q '^RESOLVED:/'; then
      note "FAIL: $name — silently produced a bogus root-level path and continued: $out"; fail=1
    else
      note "FAIL: $name (rc=$rc, expected non-zero exit with a 'failed to resolve directory' diagnostic; output: $out)"; fail=1
    fi
  fi
}

# --- A: good path — the directory genuinely exists ------------------------
GOOD_DIR="$TMP/topic"
mkdir -p "$GOOD_DIR"
echo '# report' > "$GOOD_DIR/report.md"
run_case "good path resolves correctly" "$GOOD_DIR/report.md" 1

# --- B: vanished path — simulates the post-TOCTOU state -------------------
# The directory that would have passed the earlier [ -f "$MD" ] existence
# check no longer exists by the time re-resolution runs (removed, renamed,
# or unmounted by a concurrent process).
GONE_DIR="$TMP/gone-topic"
mkdir -p "$GONE_DIR"
GONE_MD="$GONE_DIR/report.md"
echo '# report' > "$GONE_MD"
[ -f "$GONE_MD" ] || { note "setup failed: $GONE_MD should exist before removal"; exit 2; }
rm -rf "$GONE_DIR"
run_case "vanished directory fails loudly, does not silently continue" "$GONE_MD" 0

if [ "$fail" -eq 0 ]; then
  echo "mif-project-cd-resolve-check: PASS"
  exit 0
fi
echo "mif-project-cd-resolve-check: FAIL"
exit 1
