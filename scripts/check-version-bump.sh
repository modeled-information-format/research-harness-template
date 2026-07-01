#!/usr/bin/env bash
# check-version-bump.sh — enforce change-driven versioning (ADR-0010, amended) in CI.
#
# The companion to scripts/bump-version.sh: that tool MAKES the version mutations,
# this gate PROVES the invariants that matter hold. Two independent rules:
#
#   Rule A — a changed pack (packs/<family>/<component>/**) or changed core skill
#     (.claude/skills/<name>/**) must move its OWN version (plugin.json .version or
#     SKILL.md version:). This is still per-PR: touching a versioned component
#     without moving its stamp is always a real omission.
#   Rule B — harness.config.json .version (the release pointer) must stay strictly
#     ahead of the last actual git tag release. This is NOT per-PR: it does not
#     have to move on THIS PR. Many PRs can land between releases without each
#     individually bumping the pointer — something just has to have bumped it
#     before the next release is cut. Comparing against a PR's own merge-base
#     (the old rule) meant two PRs racing off the same base collided even though
#     neither was wrong; comparing against the last release tag removes that.
#
# Independently-versioned ontology packs (packs/ontologies/**, schemas/ontologies/**)
# are exempt from Rule A — they carry their own version on their own cadence.
#
# Usage:
#   check-version-bump.sh [BASE_REF]      # BASE_REF default: $BASE_REF env, else origin/main
#
# Requires git history for BASE_REF (CI must check out with fetch-depth: 0 and fetch
# the base branch) AND tags (fetch-depth: 0 also fetches tags by default). Run from
# the repository root.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

BASE="${1:-${BASE_REF:-origin/main}}"
command -v jq >/dev/null 2>&1 || { echo "check-version-bump: jq not found" >&2; exit 2; }
git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "check-version-bump: base ref '$BASE' not found — fetch it first (CI needs fetch-depth: 0)" >&2
  exit 2
}

# Anchor the diff at the MERGE-BASE, not the base tip, for Rule A: the change set
# and the base-side version reads must share one anchor, or a pack independently
# bumped on main after this branch point could false-pass an un-bumped change.
DIFF_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"

changed="$(git diff --name-only "$DIFF_BASE...HEAD")"

# Version readers — base side via `git show`, head side from the working tree.
base_json_ver() { git show "$DIFF_BASE:$1" 2>/dev/null | jq -r '.version // empty' 2>/dev/null; }
head_json_ver() { jq -r '.version // empty' "$1" 2>/dev/null; }
base_fm_ver()   { git show "$DIFF_BASE:$1" 2>/dev/null | sed -n 's/^version:[[:space:]]*//p' | head -1 | tr -d '"'"'"' '; }
head_fm_ver()   { sed -n 's/^version:[[:space:]]*//p' "$1" 2>/dev/null | head -1 | tr -d '"'"'"' '; }

fail=0

if [ -n "$changed" ]; then
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
fi

# Rule B — the release pointer must be strictly ahead of the last actual release
# tag. Portable 3-field numeric semver compare (no `sort -V`, a GNU-only
# extension absent from stock macOS/BSD sort) so this runs identically in CI
# and on a contributor's shell.
LAST_TAG="$(git tag --list 'v*' | sed 's/^v//' \
  | awk -F. '{printf "%05d.%05d.%05d %s.%s.%s\n", $1,$2,$3,$1,$2,$3}' \
  | sort | tail -1 | cut -d' ' -f2)"
if [ -n "$LAST_TAG" ]; then
  HEAD_VER="$(head_json_ver harness.config.json)"
  if [ -z "$HEAD_VER" ]; then
    echo "FAIL: harness.config.json has no .version" >&2
    fail=1
  else
    IFS=. read -r lm ln lp <<<"$LAST_TAG"
    IFS=. read -r hm hn hp <<<"$HEAD_VER"
    behind=0
    if   [ "${hm:-0}" -lt "${lm:-0}" ]; then behind=1
    elif [ "${hm:-0}" -eq "${lm:-0}" ] && [ "${hn:-0}" -lt "${ln:-0}" ]; then behind=1
    elif [ "${hm:-0}" -eq "${lm:-0}" ] && [ "${hn:-0}" -eq "${ln:-0}" ] && [ "${hp:-0}" -le "${lp:-0}" ]; then behind=1
    fi
    if [ "$behind" -eq 1 ]; then
      echo "FAIL: harness.config.json .version ($HEAD_VER) is not ahead of the last release (v$LAST_TAG) — someone needs to run scripts/bump-version.sh before the next release is cut (not necessarily this PR)" >&2
      fail=1
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then
  echo "check-version-bump: changed components moved their own version, and the release pointer ($(head_json_ver harness.config.json)) is ahead of the last release"
fi
exit "$fail"
