#!/usr/bin/env bash
# bump-version.sh — change-driven version bump for the research harness.
#
# The harness versions by CHANGE, not by lockstep: `harness.config.json` is the
# single always-bumps release pointer, the marketplace catalog tracks it, and a
# pack's version moves ONLY when that pack's files change. This script performs
# exactly that — so a release where no pack changed touches three files, not
# eighty — and verifies its own work so a bump is never a hand-edit gamble.
#
# Usage:
#   bump-version.sh <new-version | patch | minor | major> [options]
#
# Options:
#   --pack <component>   Also bump this pack to the new version (repeatable).
#                        Updates its plugin.json, its SKILL.md frontmatter, and
#                        its **Version:** row in the family reference doc. Pass it
#                        for every pack whose files changed this release.
#   --date <YYYY-MM-DD>  CHANGELOG date for the new section (default: today).
#   --check              Dry run: report what would change, write nothing.
#   -h | --help          This help.
#
# Examples:
#   bump-version.sh patch                      # 0.4.2 -> 0.4.3, no pack changed
#   bump-version.sh minor --pack pdf           # 0.4.x -> 0.5.0, also bump the pdf pack
#   bump-version.sh 1.0.0 --check              # preview a 1.0.0 release
#
# The version-consistency gate in verify.sh (the marketplace catalog equals the
# template version; every stamp is well-formed semver) plus the PR-only bump-on-
# change gate (scripts/check-version-bump.sh) are the durable safety net; this
# script is the convenience that keeps you inside it.
#
# Since research-harness-template#276 (Story #298, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" harness bump-version "$@" --root "$ROOT"
