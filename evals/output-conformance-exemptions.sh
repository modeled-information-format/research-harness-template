#!/usr/bin/env bash
# output-conformance-exemptions.sh — contract test for
# .claude/hooks/check-output-conformance.sh's exemption case statement
# (issue #691): the Stop-hook's MIF-exemption glob whitelisted only
# *-build-spec.md and *.blog.md under reports/*/*.md, while the ai-spec
# channel's SKILL.md documents three more equally MIF-exempt (Level-1)
# default output filenames — <topic>-kiro-requirements.md,
# <topic>-kiro-design.md, <topic>-kiro-tasks.md — matching the complete
# four-suffix exclusion list scripts/verify.sh already carries in its
# reports-binding checks. A git-dirty kiro spec fell through to
# scripts/mif-project.sh, failed (it is not a Level-3 finding-backed
# report), and produced a misleading "must be fixed" systemMessage.
#
# This invokes the REAL hook script against a synthetic git project whose
# scripts/mif-project.sh is a stub that always fails and records every
# path it is handed, and asserts:
#   - the three kiro genre outputs are exempt: never handed to
#     mif-project.sh, never named in a systemMessage (the issue #691 bug);
#   - the previously exempt shapes (*-build-spec.md, the feature-spec
#     genre's *-feature-build-spec.md, *.blog.md, README.md) stay exempt
#     (no regression);
#   - a generic report that fails projection is still flagged (the fix
#     must not defeat the backstop itself);
#   - a non-kiro file merely containing "kiro" in its stem (e.g.
#     kiro-notes.md) is NOT exempted (the globs must anchor on the exact
#     genre suffixes, not the substring).
#
# Exit 0 = the exemption contract holds. Exit 1 = a case failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/check-output-conformance.sh"
fail=0
note() { printf '  output-conformance-exemptions: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Synthetic project: a git repo with a stub mif-project.sh that always
# fails and logs each path it is invoked on. Every file the hook does NOT
# exempt is therefore both logged and flagged in the systemMessage.
PROJECT="$TMP/proj"
CALLED="$TMP/mif-project-called.log"
mkdir -p "$PROJECT/scripts" "$PROJECT/reports/mytopic"
cat > "$PROJECT/scripts/mif-project.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$CALLED"
exit 1
STUB
chmod +x "$PROJECT/scripts/mif-project.sh"
git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email eval@example.invalid
git -C "$PROJECT" config user.name eval

# Dirty (untracked) outputs under reports/<topic>/:
#   exempt shapes — the three kiro genres (the bug), plus the shapes that
#   were already exempt before the fix;
#   non-exempt shapes — a generic report, and a near-miss "kiro" stem.
EXEMPT=(
  reports/mytopic/mytopic-kiro-requirements.md
  reports/mytopic/mytopic-kiro-design.md
  reports/mytopic/mytopic-kiro-tasks.md
  reports/mytopic/mytopic-build-spec.md
  reports/mytopic/mytopic-feature-build-spec.md
  reports/mytopic/mytopic.blog.md
  reports/mytopic/README.md
)
NONEXEMPT=(
  reports/mytopic/generic-report.md
  reports/mytopic/kiro-notes.md
)
for f in "${EXEMPT[@]}" "${NONEXEMPT[@]}"; do
  printf '# %s\n' "$f" > "$PROJECT/$f"
done

OUT=$(echo '{}' | CLAUDE_PROJECT_DIR="$PROJECT" bash "$HOOK")
MSG=$(printf '%s' "$OUT" | jq -r '.systemMessage // empty' 2>/dev/null)
touch "$CALLED"

# --- Exempt shapes: never projected, never flagged ------------------------
for f in "${EXEMPT[@]}"; do
  if grep -qF "$f" "$CALLED"; then
    note "FAIL: exempt file was handed to mif-project.sh: $f"; fail=1
  elif printf '%s' "$MSG" | grep -qF "$f"; then
    note "FAIL: exempt file was flagged in the systemMessage: $f"; fail=1
  else
    note "exempt: $f (not projected, not flagged)"
  fi
done

# --- Non-exempt shapes: still projected and still flagged -----------------
for f in "${NONEXEMPT[@]}"; do
  if ! grep -qF "$f" "$CALLED"; then
    note "FAIL: non-exempt file was never handed to mif-project.sh: $f (backstop defeated)"; fail=1
  elif ! printf '%s' "$MSG" | grep -qF "$f"; then
    note "FAIL: non-exempt failing file was not flagged in the systemMessage: $f"; fail=1
  else
    note "still checked: $f (projected and flagged on failure)"
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "output-conformance-exemptions: PASS"
  exit 0
fi
echo "output-conformance-exemptions: FAIL"
exit 1
