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
# astro-rehype-relative-markdown-links (the site's cross-link rewriter) slugifies
# each path segment with github-slugger, which is a HEADING-anchor algorithm: it
# strips embedded "." without inserting a separator. Any genre-suffixed filename
# (e.g. "<slug>.engineering.md") therefore gets a mismatched, 404ing rewritten
# href, even though Astro's own content-collection route (which keeps the dot)
# resolves fine. The plugin honors an explicit `slug:` frontmatter field over its
# own computation, so stamp one here — the file's own path relative to the repo
# root, which is exactly the route the content collection already resolves to.
SLUGPATH="$(dirname "$OUT")/$SLUG"

# Version indicator: a genre re-rendered for the same topic overwrites its file
# in place (this harness keeps no automatic history), so a real, extractable
# `version:` field is the only on-disk record that this is revision N, not the
# first pass. Read the file's OWN prior version (if $OUT already exists) and
# increment; otherwise this is version 1.
VERSION=1
if [ -f "$OUT" ]; then
  PREV=$(sed -n '/^---$/,/^---$/p' "$OUT" 2>/dev/null \
    | grep -m1 -E '^[[:space:]]*version:[[:space:]]*[0-9]+' | grep -oE '[0-9]+')
  [ -n "$PREV" ] && VERSION=$((PREV + 1))
fi

# Shared per-section renderer: every finding's section carries its full body, key
# entities, optional dimension/verdict provenance ($meta), and its own evidence
# ($ev) as a cited list — markdownlint-safe (blank lines around headings/lists).
DEF='
  # Wrap bare emails / http(s) URLs in angle-bracket autolinks so the rendered body
  # is markdownlint-clean (MD034). Skips anything already inside a markdown link
  # "](...)" or an existing <...> autolink via lookbehind, so links are not double-wrapped.
  def autolink:
    gsub("(?<![\\w.<])(?<e>[\\w.%+-]+@[\\w.-]+\\.[A-Za-z]{2,})(?![\\w>])"; "<\(.e)>")
    | gsub("(?<!\\]\\()(?<![<\"])(?<u>https?://[^\\s)<>\"]*[^\\s)<>\".,;:!?])"; "<\(.u)>");
  # Disambiguate repeated section headings (two findings can share a title) so the
  # rendered body has no duplicate H2s (markdownlint MD024). Appends " (N)" on repeats.
  def dedupe_sections:
    reduce .[] as $s ({seen:{},out:[]};
      ((.seen[$s.heading] // 0) + 1) as $n
      | .seen[$s.heading] = $n
      | .out += [ $s + {heading: (if $n>1 then ($s.heading + " (" + ($n|tostring) + ")") else $s.heading end)} ] )
    | .out;
  # Escape every literal "*" and space-flanked "_" in body prose. Research bodies
  # carry math operators (beta * epsilon), glob/wildcard tokens (llm.token_count.*)
  # and stray asterisks, none of which are intended emphasis; escaping them keeps
  # markdownlint quiet (MD037 spaces-in-emphasis, MD049/MD050) without guessing which
  # mark is emphasis. But characters INSIDE an autolink "<...>" or a markdown link
  # target "](...)" must NOT be escaped: a "\*" inside an angle-bracket autolink is
  # rendered literally and breaks the link target. autolink runs before deglob, so a
  # URL containing "*" is already wrapped; we therefore escape only the prose segments
  # OUTSIDE link spans, leaving link spans verbatim.
  def _esc: gsub("\\*"; "\\*") | gsub("(?<=\\s)_|_(?=\\s)"; "\\_");
  def deglob:
    [ scan("<[^<>\\s]*>|\\]\\([^)]*\\)|(?:(?!<[^<>\\s]*>|\\]\\([^)]*\\))[\\s\\S])+") ]
    | map(if test("^(<[^<>\\s]*>|\\]\\([^)]*\\))$") then . else _esc end)
    | join("");
  # Strip trailing whitespace on every line (MD009).
  def detrail: gsub("[ \t]+(?=\n)"; "") | gsub("[ \t]+$"; "");
  # Render a section body: autolink + deglob escape PROSE only. A fenced ``` code
  # block (e.g. a Mermaid diagram) must pass through verbatim — escaping "*"/"_" or
  # autolinking a URL inside a fence corrupts the diagram/code. Walk the body
  # line-by-line: a fence opens/closes only on a line whose first non-space run is
  # ``` (CommonMark), so a stray ``` MID-prose is just prose and never disables the
  # escaping of the lines that follow. Fence lines and content between an opener and
  # its closer pass through untouched; an unclosed fence keeps the rest verbatim (no
  # content dropped). detrail then strips trailing whitespace (MD009).
  def render_body:
    ( . / "\n" ) as $lines
    | reduce range(0; $lines | length) as $i
        ( {out: [], infence: false};
          $lines[$i] as $ln
          | if ($ln | test("^[ \t]*```")) then (.out += [$ln] | .infence = (.infence | not))
            elif .infence then (.out += [$ln])
            else (.out += [$ln | autolink | deglob]) end )
    | .out | join("\n")
    | detrail;
  # Per-section knowledge graph: when a section carries entity/relationship data,
  # GENERATE a Mermaid `graph` of it (entities as nodes, the typed relationships
  # as edges) rather than omitting the diagram. Node ids are index-synthesised
  # (n0, n1, …) so MIF urn:/@id targets never leak special chars into Mermaid.
  # Labels replace any embedded double-quote with U+0027 (a single quote),
  # written as a jq escape because this program lives in a single-quoted shell string.
  def mermaid_graph($s):
    ($s.entities // []) as $ents
    | ($s.relationships // []) as $rels
    | ($s.supports[0]) as $src
    | if (($ents | length) == 0 and ($rels | length) == 0) then []
      else
        ( [ $src ] + [ $ents[].id ] + [ $rels[].target ] | map(select(. != null)) | unique ) as $ids
        | ( $ids | to_entries | map({ key: .value, value: ("n" + (.key | tostring)) }) | from_entries ) as $nid
        | ( reduce $ids[] as $id ({};
              .[$id] = ( if $id == $src then $s.heading
                         elif (($ents | map(select(.id == $id)) | length) > 0)
                           then (($ents | map(select(.id == $id)) | .[0]) | (.name + " (" + (.entityType // "entity") + ")"))
                         else ($id | sub("^.*[:/]"; "")) end ) ) ) as $lbl
        | [ "", "```mermaid", "graph TD" ]
          + [ $ids[] | "  " + $nid[.] + "[\"" + ($lbl[.] | gsub("\""; "\u0027") | gsub("[\n\r]"; " ")) + "\"]" ]
          + [ $rels[] | select(.target != null and $src != null)
              | "  " + $nid[$src] + " -->|" + ((.type // "relates-to") | gsub("\"|\\|"; "\u0027") | gsub("[\n\r]"; " ")) + "| " + $nid[.target] ]
          + [ "```" ]
      end;
  def secblock($s; $meta; $ev):
    [ "", "## " + ($s.heading | deglob | detrail), "", ($s.body | render_body) ]
    + mermaid_graph($s)
    + (if (($s.entities // []) | length) > 0
       then [ "", ("Key entities: " + ([ $s.entities[] | .name + " (" + (.entityType // "entity") + ")" ] | join(", ")) + ".") ] else [] end)
    + (if $meta and ($s.dimension != null)
       then [ "", ("_Dimension: " + $s.dimension + " · verification: " + ($s.verdict // "n/a")
                   + (if $s.entityType then " · type: " + $s.entityType
                        + (if $s.ontology then " (" + $s.ontology + ")" else "" end) else "" end)
                   + "._") ] else [] end)
    + (if $ev and (($s.sources // []) | length) > 0
       then [ "", "Evidence:", "" ] + [ $s.sources[] | "- [" + (.title|gsub("^[ \\t]+|[ \\t]+$";"")) + "](<" + .url + ">)" ] else [] end);
'

case "$CHANNEL" in
  report)
    # The generic MIF Level-3 markdown report: authoritative YAML frontmatter
    # (the MIF concept) + a Markdown body. The body becomes the MIF `content`.
    # The title lives in the frontmatter (the MIF concept); the body therefore
    # carries no H1 (a body H1 plus the frontmatter title trips markdownlint MD025).
    BODY=$(jq -r "$DEF"'
      ( [ ("This " + (.genre // "general") + " synthesis covers " + (((.finding_refs // []) | length) | tostring) + " surviving finding(s) across the research.") ]
        + ( reduce (.sections|dedupe_sections)[] as $s ([]; . + secblock($s; true; true)) )
        + [ "", "## Sources", "" ]
        + [ .sources[] | "- [" + (.title|gsub("^[ \\t]+|[ \\t]+$";"")) + "](<" + .url + ">)" ]
      ) | .[]
    ' "$ART")
    CONCEPT=$(jq --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" --arg slugpath "$SLUGPATH" --argjson version "$VERSION" '
      {
        "@context": "https://mif-spec.dev/schema/context.jsonld",
        "@type": "Concept",
        "@id": ("urn:mif:report:" + $ns + ":" + $slug),
        slug: $slugpath,
        version: $version,
        conceptType: "semantic",
        namespace: $ns,
        title: .title,
        created: $created,
        provenance: { "@type": "Provenance", sourceType: "system_generated", confidence: 0.9, trustLevel: "moderate_confidence" },
        citations: [ .sources[] | { "@type": "Citation", citationType: .citationType, citationRole: .citationRole, title: .title, url: .url } + (if .note then {note: .note} else {} end) ],
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
          ("slug: " + $slugpath),
          ("version: " + ($version|tostring)),
          "conceptType: semantic",
          ("created: \"" + $created + "\""),
          ("namespace: " + $ns),
          "---",
          "",
          ("# " + .title) ]
        + ( reduce (.sections|dedupe_sections)[] as $s ([]; . + secblock($s; false; true)) )
        + [ "", "## Sources", "" ]
        + [ .sources[] | "- [" + (.title|gsub("^[ \\t]+|[ \\t]+$";"")) + "](<" + .url + ">)" ]
      ) | .[]
    ' --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" --arg slugpath "$SLUGPATH" --argjson version "$VERSION" "$ART" > "$OUT"
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
          ("slug: " + $slugpath),
          ("version: " + ($version|tostring)),
          "conceptType: semantic",
          ("created: \"" + $created + "\""),
          ("namespace: " + $ns),
          "---",
          "",
          ("# Chapter: " + .title),
          "",
          ("> Genre: " + (.genre // "general") + " · audience: " + (.audience // "general")) ]
        + ( reduce (.sections|dedupe_sections)[] as $s ([]; . + secblock($s; false; false)) )
        + [ "", "## Endnotes", "" ]
        + [ .sources | to_entries[] | "[" + ((.key + 1) | tostring) + "] " + (.value.title|gsub("^[ \\t]+|[ \\t]+$";"")) + " — <" + .value.url + ">" ]
      ) | .[]
    ' --arg ns "$NS" --arg slug "$SLUG" --arg created "$CREATED" --arg slugpath "$SLUGPATH" --argjson version "$VERSION" "$ART" > "$OUT"
    ;;
  *)
    echo "render: channel must be report|blog|book (got '$CHANNEL')" >&2
    exit 2
    ;;
esac

echo "render: wrote $OUT ($CHANNEL, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
