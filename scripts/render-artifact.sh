#!/usr/bin/env bash
# render-artifact.sh — render one typed Artifact (schemas/artifact.schema.json)
# to an output channel (SPEC §6d, §10). Three channels:
#   report — the generic MIF Level-3 markdown report (reports/<topic>/<slug>.md):
#            authoritative YAML frontmatter (the MIF concept) + Markdown body.
#            This is the canonical MIF source of truth and is NEVER exempt; it is
#            write-then-validated through scripts/mif-project.sh. A real
#            falsification verdict (extensions.harness.verification) is REQUIRED,
#            so the falsification gate must run over the synthesised claims BEFORE
#            rendering — pass the resulting verdict as <verification.json>.
#   blog/book — first-class PUBLISHED channels (MIF-exempt by declaration). Prose
#            is written from the artifact's synthesised body + public citations
#            only; it carries no internal finding ids, so the citation-leak gate
#            stays green.
# Every channel consumes the SAME artifact contract — the typed findings->artifact
# seam — so the citation gates run uniformly across every output.
#
# Usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [<verification.json>]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ART="${1:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
CHANNEL="${2:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
OUT="${3:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
VERIF="${4:-}"
[ -f "$ART" ] || { echo "render: artifact not found: $ART" >&2; exit 2; }

case "$CHANNEL" in
  report)
    # The generic MIF Level-3 markdown report: authoritative YAML frontmatter
    # (the MIF concept) + a Markdown body. The body becomes the MIF `content`.
    NS=$(jq -r '.namespace // "harness/report"' "$ART")
    SLUG=$(basename "$OUT"); SLUG="${SLUG%.md}"
    CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Body prose: lede, body sections as ## headings, a Sources list. The title
    # lives in the frontmatter (the MIF concept); emitting it again as a body H1
    # would both duplicate it and trip markdownlint MD025 (two top-level headings).
    BODY=$(jq -r '
      (.sections[0].body),
      "",
      ( .sections[1:][] | "## " + .heading + "\n\n" + .body + "\n" ),
      "## Sources",
      "",
      ( .sources[] | "- [" + .title + "](" + .url + ")" )
    ' "$ART")
    # The MIF concept (frontmatter) built from the artifact. dimension is the
    # reserved synthesis token; verification is attached from the falsification
    # pass below (REQUIRED for L3 validity).
    CONCEPT=$(jq --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" '
      {
        "@context": "https://mif-spec.dev/schema/context.jsonld",
        "@type": "Concept",
        "@id": ("urn:mif:report:" + $ns + ":" + $slug),
        conceptType: "semantic",
        namespace: $ns,
        title: .title,
        created: $created,
        provenance: { "@type": "Provenance", sourceType: "system_generated", confidence: 0.9, trustLevel: "moderate_confidence" },
        citations: [ .sources[] | { "@type": "Citation", citationType: .citationType, citationRole: .citationRole, title: .title, url: .url } ],
        extensions: { harness: { dimension: "synthesis" } }
      }' "$ART")
    if [ -n "$VERIF" ] && [ -f "$VERIF" ]; then
      CONCEPT=$(printf '%s' "$CONCEPT" | jq --slurpfile v "$VERIF" '.extensions.harness.verification = $v[0]')
    fi
    # Emit YAML frontmatter from the concept JSON via yq (the YAML analog of jq;
    # the same tool mif-project.sh reads it back with — consistent jq/yq tooling).
    { echo "---"; printf '%s' "$CONCEPT" | yq -p=json -o=yaml '.'; echo "---"; echo; printf '%s\n' "$BODY"; } > "$OUT"
    # Write-then-validate: the report is not emitted until it projects to a valid
    # MIF L3 finding (requires a real, non-falsified verification verdict).
    if ! scripts/mif-project.sh "$OUT" >/dev/null 2>&1; then
      echo "render: report $OUT does NOT project to a valid MIF L3 finding." >&2
      echo "render: run the falsification gate over the synthesised claims first and pass <verification.json>." >&2
      scripts/mif-project.sh "$OUT" 2>&1 | sed 's/^/  /' >&2 || true
      exit 1
    fi
    ;;
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
    echo "render: channel must be report|blog|book (got '$CHANNEL')" >&2
    exit 2
    ;;
esac

echo "render: wrote $OUT ($CHANNEL, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
