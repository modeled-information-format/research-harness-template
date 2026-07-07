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
#     before the next release is cut.
#
# Independently-versioned ontology packs (packs/ontologies/**, schemas/ontologies/**)
# are exempt from Rule A — they carry their own version on their own cadence.
#
# Since research-harness-template#276 (Story #298, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage:
#   check-version-bump.sh [BASE_REF]      # BASE_REF default: $BASE_REF env, else origin/main
#
# Requires git history for BASE_REF (CI must check out with fetch-depth: 0 and fetch
# the base branch) AND tags (fetch-depth: 0 also fetches tags by default). Run from
# the repository root.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

BASE="${1:-${BASE_REF:-origin/main}}"
git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "check-version-bump: base ref '$BASE' not found — fetch it first (CI needs fetch-depth: 0)" >&2
  exit 2
}

exec "$ENGINE" harness check-version-bump "$BASE" --root "$ROOT"
