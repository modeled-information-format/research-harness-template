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

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

CFG="harness.config.json"
MARKET=".claude-plugin/marketplace.json"
CHANGELOG="CHANGELOG.md"
DOC_DIR="docs/reference/packs"

die() { echo "bump-version: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq not found"
[ -f "$CFG" ] || die "$CFG not found (run from a harness clone)"

# --- parse args -------------------------------------------------------------
SPEC=""; DATE=""; CHECK=0; PACKS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --check)   CHECK=1; shift ;;
    --date)    DATE="${2:?--date needs YYYY-MM-DD}"; shift 2 ;;
    --pack)    PACKS+=("${2:?--pack needs a component name}"); shift 2 ;;
    -*)        die "unknown option: $1" ;;
    *)         [ -z "$SPEC" ] || die "unexpected extra argument: $1"; SPEC="$1"; shift ;;
  esac
done
[ -n "$SPEC" ] || die "usage: bump-version.sh <new-version|patch|minor|major> [--pack <name>]... [--date YYYY-MM-DD] [--check]"

OLD="$(jq -r '.version' "$CFG")"
[ -n "$OLD" ] && [ "$OLD" != "null" ] || die "$CFG has no .version"
echo "$OLD" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "current version is not semver: $OLD"

# --- resolve the new version ------------------------------------------------
case "$SPEC" in
  major|minor|patch)
    IFS=. read -r MA MI PA <<<"$OLD"
    case "$SPEC" in
      major) MA=$((MA+1)); MI=0; PA=0 ;;
      minor) MI=$((MI+1)); PA=0 ;;
      patch) PA=$((PA+1)) ;;
    esac
    NEW="${MA}.${MI}.${PA}" ;;
  *)
    echo "$SPEC" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "not a semver or bump keyword: $SPEC"
    NEW="$SPEC" ;;
esac
[ "$NEW" != "$OLD" ] || die "new version equals current ($OLD); nothing to bump"

# DATE default deferred to here so --help/--check never shell out to `date`.
if [ -z "$DATE" ]; then DATE="$(date '+%Y-%m-%d')"; fi
echo "$DATE" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "bad --date (want YYYY-MM-DD): $DATE"

# semver compare: returns 0 if $1 > $2
semver_gt() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$1" ]
}

# --- resolve --pack components to their files -------------------------------
declare -a PACK_PLUGIN PACK_SKILL PACK_DOC PACK_FAMILY PACK_NAME
for comp in ${PACKS[@]+"${PACKS[@]}"}; do
  hits=$(find packs -mindepth 2 -maxdepth 2 -type d -name "$comp" 2>/dev/null | grep -v '^packs/ontologies/' || true)
  [ -n "$hits" ] || die "--pack '$comp': no such pack under packs/<family>/$comp (ontology packs version independently and are not bumpable here)"
  [ "$(echo "$hits" | wc -l)" -eq 1 ] || die "--pack '$comp' is ambiguous:"$'\n'"$hits"
  dir="$hits"
  family="$(echo "$dir" | cut -d/ -f2)"
  plugin="$dir/.claude-plugin/plugin.json"
  skill="$(find "$dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | head -1)"
  doc="$DOC_DIR/$family.md"
  [ -f "$plugin" ] || die "--pack '$comp': missing $plugin"
  [ -f "$skill" ]  || die "--pack '$comp': no SKILL.md under $dir/skills"
  [ -f "$doc" ]    || die "--pack '$comp': missing family doc $doc"
  PACK_NAME+=("$comp"); PACK_FAMILY+=("$family")
  PACK_PLUGIN+=("$plugin"); PACK_SKILL+=("$skill"); PACK_DOC+=("$doc")
done

# --- report -----------------------------------------------------------------
echo "bump-version: $OLD -> $NEW  (date $DATE)"
echo "  template : $CFG .version, $MARKET .metadata.version, $CHANGELOG"
for i in ${PACK_NAME[@]+"${!PACK_NAME[@]}"}; do
  echo "  pack     : ${PACK_NAME[$i]} (${PACK_FAMILY[$i]}) — skills/$(basename "$(dirname "${PACK_SKILL[$i]}")")/SKILL.md, plugin.json, ${PACK_DOC[$i]} row"
done

# --- pre-flight: validate EVERY mutation BEFORE writing ANY file -------------
# Transactional: a malformed input (missing CHANGELOG anchor, a pack with no
# version stamp or doc row, a pack ahead of the release) must fail here, with the
# tree untouched — never half-bumped. Running before the --check exit also lets a
# dry run surface these failures.
grep -q "^## \[$NEW\]" "$CHANGELOG" || grep -q '^## \[Unreleased\]$' "$CHANGELOG" \
  || die "CHANGELOG has no '## [Unreleased]' anchor to insert '[$NEW]' under (nor an existing [$NEW] section)"
for i in ${PACK_NAME[@]+"${!PACK_NAME[@]}"}; do
  comp="${PACK_NAME[$i]}"; pv="$(jq -r '.version // empty' "${PACK_PLUGIN[$i]}")"
  echo "$pv" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "pack '$comp' ${PACK_PLUGIN[$i]} has no valid semver .version (got '${pv:-MISSING}')"
  ! semver_gt "$pv" "$NEW" \
    || die "pack '$comp' is at $pv, ahead of the new release $NEW — refusing to move it backward"
  grep -q "^version:[[:space:]]" "${PACK_SKILL[$i]}" \
    || die "pack '$comp' ${PACK_SKILL[$i]} has no 'version:' frontmatter"
  grep -Eq "^#{2,3} $comp\$" "${PACK_DOC[$i]}" \
    || die "pack '$comp': no '## $comp' section in ${PACK_DOC[$i]}"
  # The section must actually contain a **Version:** row to rewrite — otherwise the
  # awk below is a silent no-op. Validate it here so a missing row fails BEFORE any
  # write (the post-write self-verify is the second net, not the first).
  awk -v comp="$comp" '
    /^#{1,6} / { insec = ($0 ~ "^#{2,3} " comp "$") }
    insec && /^\*\*Version:\*\*/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "${PACK_DOC[$i]}" \
    || die "pack '$comp': the '## $comp' section in ${PACK_DOC[$i]} has no '**Version:**' row to bump"
done

if [ "$CHECK" -eq 1 ]; then echo "bump-version: --check, no files written."; exit 0; fi

# --- apply: template stamps (structural, via jq) ----------------------------
write_json() { # <file> <jq-filter>
  local f="$1" filter="$2" tmp; tmp="$(mktemp)"
  jq "$filter" "$f" >"$tmp" || die "jq failed on $f"
  mv "$tmp" "$f"
}
write_json "$CFG" ".version = \"$NEW\""
write_json "$MARKET" ".metadata.version = \"$NEW\""

# --- apply: CHANGELOG (insert dated header under [Unreleased]) ---------------
if grep -q "^## \[$NEW\]" "$CHANGELOG"; then
  echo "bump-version: CHANGELOG already has a [$NEW] section, leaving it."
else
  tmp="$(mktemp)"
  awk -v ver="$NEW" -v date="$DATE" '
    { print }
    /^## \[Unreleased\]$/ && !done { print ""; print "## [" ver "] - " date; done=1 }
  ' "$CHANGELOG" >"$tmp" || die "awk failed on $CHANGELOG"
  grep -q "^## \[$NEW\] - $DATE\$" "$tmp" || die "CHANGELOG insert failed (no '## [Unreleased]' anchor?)"
  mv "$tmp" "$CHANGELOG"
fi

# --- apply: per-pack stamps (all inputs pre-validated above) -----------------
for i in ${PACK_NAME[@]+"${!PACK_NAME[@]}"}; do
  comp="${PACK_NAME[$i]}"
  write_json "${PACK_PLUGIN[$i]}" ".version = \"$NEW\""
  # SKILL.md frontmatter: first `version: X` -> `version: NEW`. awk (not the
  # GNU-only `sed 0,/re/`) so it runs the same on BSD/macOS and Linux.
  sk="${PACK_SKILL[$i]}"
  tmp="$(mktemp)"
  awk -v ver="$NEW" '!d && /^version:[[:space:]]/ { print "version: " ver; d=1; next } { print }' "$sk" >"$tmp" && mv "$tmp" "$sk"
  # Family doc: the FIRST `**Version:** X` row inside comp's section. Reset `insec`
  # on EVERY heading (set iff it is the comp heading) so the rewrite is bounded to
  # comp's section — otherwise a comp section lacking a **Version:** row would bleed
  # the substitution into a later pack's row.
  doc="${PACK_DOC[$i]}"
  tmp="$(mktemp)"
  awk -v comp="$comp" -v ver="$NEW" '
    /^#{1,6} / { insec = ($0 ~ "^#{2,3} " comp "$") }
    insec && /^\*\*Version:\*\*/ && !done {
      sub(/\*\*Version:\*\* [0-9]+\.[0-9]+\.[0-9]+/, "**Version:** " ver); done=1
    }
    { print }
  ' "$doc" >"$tmp" || die "awk failed on $doc"
  mv "$tmp" "$doc"
done

# --- self-verify: nothing in the touched template set still shows OLD -------
fail=0
[ "$(jq -r '.version' "$CFG")" = "$NEW" ] || { echo "VERIFY: $CFG not updated" >&2; fail=1; }
[ "$(jq -r '.metadata.version' "$MARKET")" = "$NEW" ] || { echo "VERIFY: $MARKET not updated" >&2; fail=1; }
grep -q "^## \[$NEW\]" "$CHANGELOG" || { echo "VERIFY: CHANGELOG missing [$NEW]" >&2; fail=1; }
for i in ${PACK_NAME[@]+"${!PACK_NAME[@]}"}; do
  [ "$(jq -r '.version' "${PACK_PLUGIN[$i]}")" = "$NEW" ] || { echo "VERIFY: ${PACK_PLUGIN[$i]} not updated" >&2; fail=1; }
  grep -q "^version: $NEW\$" "${PACK_SKILL[$i]}" || { echo "VERIFY: ${PACK_SKILL[$i]} not updated" >&2; fail=1; }
  # The family-doc row is a mutation too — verify comp's **Version:** now reads NEW.
  docv="$(awk -v comp="${PACK_NAME[$i]}" '
    /^#{1,6} / { insec = ($0 ~ "^#{2,3} " comp "$") }
    insec && /^\*\*Version:\*\*/ { sub(/.*\*\*Version:\*\* /, ""); sub(/[^0-9.].*$/, ""); print; exit }
  ' "${PACK_DOC[$i]}")"
  [ "$docv" = "$NEW" ] || { echo "VERIFY: ${PACK_DOC[$i]} ${PACK_NAME[$i]} row not updated (got '${docv:-MISSING}')" >&2; fail=1; }
done
[ "$fail" -eq 0 ] || die "self-verification failed — inspect the files above"

echo "bump-version: done. Changed files:"
git diff --name-only 2>/dev/null | sed 's/^/  /' || true
echo "bump-version: completeness check — run:  git grep -n '${OLD//./\\.}'  (should show only CHANGELOG history)"
