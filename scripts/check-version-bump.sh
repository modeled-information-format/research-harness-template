#!/usr/bin/env bash
# check-version-bump.sh — enforce change-driven versioning (ADR-0010) in CI.
#
# The companion to scripts/bump-version.sh: that tool MAKES the version mutations,
# this gate PROVES they happened. It diffs the working ref against a base and fails
# when something changed but its version did not move:
#
#   - a changed pack (packs/<family>/<component>/**) whose plugin.json .version is
#     unchanged from the base,
#   - a changed core skill (.claude/skills/<name>/**) whose SKILL.md `version:` is
#     unchanged from the base,
#   - ANY tracked change at all while harness.config.json .version (the single
#     release pointer) stayed put.
#
# Independently-versioned ontology packs (packs/ontologies/**, schemas/ontologies/**)
# are exempt — they carry their own version on their own cadence.
#
# Escape hatch: put `[skip-version-check]` in the head commit message for a change
# that genuinely warrants no release (it bypasses the pointer rule only; a changed
# pack/skill must still bump, since that is never a no-op).
#
# Usage:
#   check-version-bump.sh [BASE_REF]      # BASE_REF default: $BASE_REF env, else origin/main
#
# Requires git history for BASE_REF (CI must check out with fetch-depth: 0 and fetch
# the base branch). Run from the repository root.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

BASE="${1:-${BASE_REF:-origin/main}}"
command -v jq >/dev/null 2>&1 || { echo "check-version-bump: jq not found" >&2; exit 2; }
git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "check-version-bump: base ref '$BASE' not found — fetch it first (CI needs fetch-depth: 0)" >&2
  exit 2
}

# Escape hatch for the release-pointer rule.
SKIP_POINTER=0
if git log -1 --format=%B HEAD 2>/dev/null | grep -qF '[skip-version-check]'; then
  SKIP_POINTER=1
  echo "check-version-bump: '[skip-version-check]' in head commit — release-pointer rule waived"
fi

changed="$(git diff --name-only "$BASE...HEAD")"
if [ -z "$changed" ]; then
  echo "check-version-bump: no changes vs $BASE — nothing to enforce"
  exit 0
fi

# Version readers — base side via `git show`, head side from the working tree.
base_json_ver() { git show "$BASE:$1" 2>/dev/null | jq -r '.version // empty' 2>/dev/null; }
head_json_ver() { jq -r '.version // empty' "$1" 2>/dev/null; }
base_fm_ver()   { git show "$BASE:$1" 2>/dev/null | sed -n 's/^version:[[:space:]]*//p' | head -1 | tr -d '"'"'"' '; }
head_fm_ver()   { sed -n 's/^version:[[:space:]]*//p' "$1" 2>/dev/null | head -1 | tr -d '"'"'"' '; }

fail=0

# Rule A.1 — every changed pack (excluding ontologies) must move its plugin.json version.
changed_packs="$(printf '%s\n' "$changed" \
  | grep -E '^packs/[^/]+/[^/]+/' \
  | grep -vE '^packs/ontologies/' \
  | sed -E 's#^(packs/[^/]+/[^/]+)/.*#\1#' | sort -u || true)"
for p in $changed_packs; do
  pj="$p/.claude-plugin/plugin.json"
  [ -f "$pj" ] || continue                      # pack removed at HEAD — no requirement
  b="$(base_json_ver "$pj")"; h="$(head_json_ver "$pj")"
  [ -n "$b" ] || continue                        # new pack (absent at base) — its version is its first
  if [ "$b" = "$h" ]; then
    echo "FAIL: $p changed but $pj .version stayed at $h — bump it (scripts/bump-version.sh <ver> --pack $(basename "$p"))" >&2
    fail=1
  fi
done

# Rule A.2 — every changed core skill must move its SKILL.md version.
changed_skills="$(printf '%s\n' "$changed" \
  | grep -E '^\.claude/skills/[^/]+/' \
  | sed -E 's#^(\.claude/skills/[^/]+)/.*#\1#' | sort -u || true)"
for s in $changed_skills; do
  sk="$s/SKILL.md"
  [ -f "$sk" ] || continue
  b="$(base_fm_ver "$sk")"; h="$(head_fm_ver "$sk")"
  [ -n "$b" ] || continue
  if [ "$b" = "$h" ]; then
    echo "FAIL: $s changed but $sk version stayed at $h — bump its frontmatter version" >&2
    fail=1
  fi
done

# Rule B — any change at all requires the release pointer to move (unless waived).
if [ "$SKIP_POINTER" -eq 0 ]; then
  b="$(base_json_ver harness.config.json)"; h="$(head_json_ver harness.config.json)"
  if [ "$b" = "$h" ]; then
    echo "FAIL: files changed vs $BASE but harness.config.json .version stayed at $h — run scripts/bump-version.sh <patch|minor|major>, or add [skip-version-check] to the commit if no release is warranted" >&2
    fail=1
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "check-version-bump: every changed component moved its version (pointer $(head_json_ver harness.config.json))"
fi
exit "$fail"
