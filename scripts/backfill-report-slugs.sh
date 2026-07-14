#!/usr/bin/env bash
# One-time remediation for reports rendered BEFORE render-artifact.sh started
# stamping `slug:`/`version:` frontmatter (see that script's SLUGPATH/VERSION
# comments): the site's cross-link rewriter (astro-rehype-relative-markdown-
# links) slugifies path segments with github-slugger, a HEADING-anchor
# algorithm that strips embedded "." without inserting a separator. Any
# genre-suffixed filename ("<slug>.<genre>.md") rendered before that fix
# therefore has a mismatched, 404ing rewritten href on the served site, even
# though Astro's own content-collection route (which keeps the dot) resolves
# fine. The plugin honors an explicit `slug:` frontmatter field over its own
# computation, so this backfills one — plus `version: 1`, since a file already
# on disk with no version field is, by definition, the only known revision.
#
# Idempotent: a file that already carries BOTH a `slug:` and a `version:` key
# is left untouched; a file missing only one of the two gets just that key
# added. Only touches files with real YAML frontmatter (a leading `---`
# line) — plain-markdown deliverables (research-progress.md, falsification
# reports) have no frontmatter and are skipped automatically.
#
# Usage: backfill-report-slugs.sh [--dry-run] [<topic> ...]
#        no <topic> args = every reports/<topic> directory (excluding _meta).

set -euo pipefail
cd "$(dirname "$0")/.." || exit 2

DRY=0
TOPICS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -h|--help)
      echo "usage: backfill-report-slugs.sh [--dry-run] [<topic> ...]"
      exit 0
      ;;
    *) TOPICS+=("$a") ;;
  esac
done
if [ "${#TOPICS[@]}" -eq 0 ]; then
  while IFS= read -r t; do
    TOPICS+=("$t")
  done < <(find reports -maxdepth 1 -mindepth 1 -type d ! -name '_meta' -exec basename {} \; | sort)
fi

FIXED=0
SKIPPED=0
for t in "${TOPICS[@]+"${TOPICS[@]}"}"; do
  dir="reports/$t"
  if [ ! -d "$dir" ]; then
    echo "backfill-report-slugs: no such topic dir: $dir" >&2
    continue
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # Only touch files with real YAML frontmatter (a leading "---" line).
    head -n1 "$f" | grep -q '^---$' || continue

    fm=$(sed -n '/^---$/,/^---$/p' "$f" 2>/dev/null)
    # Anchored at column 0: slug/version are always top-level keys in the
    # frontmatter this tool and render-artifact.sh emit. An indented match
    # (e.g. a nested "ontology: { version: 1.0.0 }") is a DIFFERENT field and
    # must not be mistaken for this report's own slug/version.
    has_slug=$(printf '%s' "$fm" | grep -c -E '^slug:[[:space:]]*[^[:space:]]' || true)
    has_version=$(printf '%s' "$fm" | grep -c -E '^version:[[:space:]]*[0-9]+' || true)
    if [ "$has_slug" -gt 0 ] && [ "$has_version" -gt 0 ]; then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi

    rel="${f%.md}"
    if [ "$DRY" -eq 1 ]; then
      msg=""
      [ "$has_slug" -gt 0 ] || msg+=" slug: $rel"
      [ "$has_version" -gt 0 ] || msg+=" version: 1"
      echo "would stamp$msg  -> $f"
      FIXED=$((FIXED + 1))
      continue
    fi

    tmp=$(mktemp)
    awk -v slug="$rel" -v add_slug="$([ "$has_slug" -gt 0 ] && echo 0 || echo 1)" \
        -v add_version="$([ "$has_version" -gt 0 ] && echo 0 || echo 1)" '
      NR==1 && /^---$/ {
        print
        if (add_slug == "1")    print "slug: " slug
        if (add_version == "1") print "version: 1"
        next
      }
      { print }
    ' "$f" > "$tmp" && mv "$tmp" "$f"
    FIXED=$((FIXED + 1))
  done < <(find "$dir" -maxdepth 1 -name '*.md' ! -name 'README.md' ! -name '*-delta.md')
done

if [ "$DRY" -eq 1 ]; then
  echo "backfill-report-slugs: (dry-run) $FIXED would be fixed, $SKIPPED already OK"
else
  echo "backfill-report-slugs: $FIXED fixed, $SKIPPED already OK"
fi
