#!/usr/bin/env bash
# render-artifact.sh — render one typed Artifact (schemas/artifact.schema.json)
# to a first-class output channel (SPEC §6d). Blog and book are the always-on
# first-class channels; both consume the SAME artifact contract, which is the
# point of the typed findings->artifact seam — research and publication ship as
# one system and the citation gates run uniformly across every output.
#
# Published prose is written from the artifact's synthesized body + public
# citations only; it carries no internal finding ids or corpus paths, so the
# citation-leak gate stays green.
#
# Usage: render-artifact.sh <artifact.json> <blog|book> <out.md>

set -uo pipefail
ART="${1:?usage: render-artifact.sh <artifact.json> <blog|book> <out.md>}"
CHANNEL="${2:?usage: render-artifact.sh <artifact.json> <blog|book> <out.md>}"
OUT="${3:?usage: render-artifact.sh <artifact.json> <blog|book> <out.md>}"
[ -f "$ART" ] || { echo "render: artifact not found: $ART" >&2; exit 2; }

case "$CHANNEL" in
  blog)
    # A blog post: title, lede, body sections as ## headings, a Sources list.
    jq -r '
      "# " + .title,
      "",
      (.sections[0].body),
      "",
      ( .sections[1:][] | "## " + .heading + "\n\n" + .body + "\n" ),
      "## Sources",
      "",
      ( .sources[] | "- [" + .title + "](" + .url + ")" )
    ' "$ART" > "$OUT"
    ;;
  book)
    # A book chapter: chapter title, an intro, each section as a numbered ###
    # subsection, and chapter endnotes.
    jq -r '
      "# Chapter: " + .title,
      "",
      "> Genre: " + .genre + " · audience: " + (.audience // "general"),
      "",
      ( .sections[0].body ),
      "",
      ( [ .sections[1:][] ] | to_entries[]
        | "### " + ((.key + 1)|tostring) + ". " + .value.heading + "\n\n" + .value.body + "\n" ),
      "## Endnotes",
      "",
      ( .sources | to_entries[] | "[" + ((.key+1)|tostring) + "] " + .value.title + " — " + .value.url )
    ' "$ART" > "$OUT"
    ;;
  *)
    echo "render: channel must be blog|book (got '$CHANNEL')" >&2
    exit 2
    ;;
esac

echo "render: wrote $OUT ($CHANNEL, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
