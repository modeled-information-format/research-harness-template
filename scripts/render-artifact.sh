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
#   blog — the first-class PUBLISHED channel; book + channel packs — optional PUBLISHED
#            channels. blog and book now carry MIF **Level-1** frontmatter (a base
#            concept: @context/@type/@id/conceptType/created) — the doc's own
#            identity — so every report output is at least L1 (the report channel is
#            full L3). They remain exempt from the L3 I/O conformance gate (their
#            FORMAT is orthogonal): prose is written from the artifact's synthesised
#            body + public citations only and carries no internal finding identity,
#            so the citation-leak gate stays green.
#
# EXHAUSTIVE by contract: the synthesizer emits one section per surviving finding
# and carries each finding's own evidence (sources, entities, dimension, verdict)
# onto its section, so every channel renders every finding WITH its evidence — the
# same per-finding rigor the diataxis channel performs, not a thin summary.
#
# Usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [<verification.json>]

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ART="${1:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
CHANNEL="${2:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
OUT="${3:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
VERIF="${4:-}"
[ -f "$ART" ] || { echo "render: artifact not found: $ART" >&2; exit 2; }

NS=$(jq -r '.namespace // "harness/report"' "$ART")
SLUG=$(basename "$OUT"); SLUG="${SLUG%.md}"
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Shared per-section renderer: every finding's section carries its full body, key
# entities, optional dimension/verdict provenance ($meta), and its own evidence
# ($ev) as a cited list — markdownlint-safe (blank lines around headings/lists).
DEF='
  def secblock($s; $meta; $ev):
    [ "", "## " + $s.heading, "", $s.body ]
    + (if (($s.entities // []) | length) > 0
       then [ "", ("Key entities: " + ([ $s.entities[] | .name + " (" + (.entityType // "entity") + ")" ] | join(", ")) + ".") ] else [] end)
    + (if $meta and ($s.dimension != null)
       then [ "", ("_Dimension: " + $s.dimension + " · verification: " + ($s.verdict // "n/a") + "._") ] else [] end)
    + (if $ev and (($s.sources // []) | length) > 0
       then [ "", "Evidence:", "" ] + [ $s.sources[] | "- [" + .title + "](" + .url + ")" ] else [] end);
'

case "$CHANNEL" in
  report)
    # The generic MIF Level-3 markdown report: authoritative YAML frontmatter
    # (the MIF concept) + a Markdown body. The body becomes the MIF `content`.
    # The title lives in the frontmatter (the MIF concept); the body therefore
    # carries no H1 (a body H1 plus the frontmatter title trips markdownlint MD025).
    BODY=$(jq -r "$DEF"'
      ( [ ("This " + (.genre // "general") + " synthesis covers " + ((.sections | length) | tostring) + " surviving finding(s) across the research.") ]
        + ( reduce .sections[] as $s ([]; . + secblock($s; true; true)) )
        + [ "", "## Sources", "" ]
        + [ .sources[] | "- [" + .title + "](" + .url + ")" ]
      ) | .[]
    ' "$ART")
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
    RTMPD="$(mktemp -d)"; RTMP="$RTMPD/report.md"
    { echo "---"; printf '%s' "$CONCEPT" | yq -p=json -o=yaml '.'; echo "---"; echo; printf '%s\n' "$BODY"; } > "$RTMP"
    if ! scripts/mif-project.sh "$RTMP" >/dev/null 2>&1; then
      echo "render: report does NOT project to a valid MIF L3 finding (not written to $OUT)." >&2
      echo "render: run the falsification gate over the synthesised claims first and pass <verification.json>." >&2
      scripts/mif-project.sh "$RTMP" 2>&1 | sed 's/^/  /' >&2 || true
      rm -rf "$RTMPD"; exit 1
    fi
    mkdir -p "$(dirname "$OUT")"
    mv "$RTMP" "$OUT"; rm -rf "$RTMPD"
    ;;
  blog)
    # A blog post at MIF Level 1: a base-concept frontmatter (the post's own
    # urn:mif:blog: identity, NO title key so MD025 stays green) over published
    # prose — title H1, body sections per finding with key entities + cited
    # evidence, and a deduplicated Sources list. Internal finding identity never
    # leaks into the body.
    jq -r "$DEF"'
      ( [ "---",
          "\"@context\": https://mif-spec.dev/schema/context.jsonld",
          "\"@type\": Concept",
          ("\"@id\": urn:mif:blog:" + $ns + ":" + $slug),
          "conceptType: semantic",
          ("created: \"" + $created + "\""),
          ("namespace: " + $ns),
          "---",
          "",
          ("# " + .title) ]
        + ( reduce .sections[] as $s ([]; . + secblock($s; false; true)) )
        + [ "", "## Sources", "" ]
        + [ .sources[] | "- [" + .title + "](" + .url + ")" ]
      ) | .[]
    ' --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" "$ART" > "$OUT"
    ;;
  book)
    # A book chapter at MIF Level 1: base-concept frontmatter (the chapter's own
    # urn:mif:book: identity) over a chapter title, an intro, each finding as a
    # section with its key entities, and numbered chapter endnotes.
    jq -r "$DEF"'
      ( [ "---",
          "\"@context\": https://mif-spec.dev/schema/context.jsonld",
          "\"@type\": Concept",
          ("\"@id\": urn:mif:book:" + $ns + ":" + $slug),
          "conceptType: semantic",
          ("created: \"" + $created + "\""),
          ("namespace: " + $ns),
          "---",
          "",
          ("# Chapter: " + .title),
          "",
          ("> Genre: " + (.genre // "general") + " · audience: " + (.audience // "general")) ]
        + ( reduce .sections[] as $s ([]; . + secblock($s; false; false)) )
        + [ "", "## Endnotes", "" ]
        + [ .sources | to_entries[] | "[" + ((.key + 1) | tostring) + "] " + .value.title + " — <" + .value.url + ">" ]
      ) | .[]
    ' --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" "$ART" > "$OUT"
    ;;
  *)
    echo "render: channel must be report|blog|book (got '$CHANNEL')" >&2
    exit 2
    ;;
esac

echo "render: wrote $OUT ($CHANNEL, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
