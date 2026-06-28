#!/usr/bin/env bash
# synthesize-artifact.sh — the report-synthesizer's deterministic substrate
# (SPEC §6d). Consumes the SURVIVING findings (verdict != falsified) under a
# findings dir and produces one typed Artifact (schemas/artifact.schema.json):
# the genre/channel-neutral intermediate that every output channel renders.
#
# Usage: synthesize-artifact.sh <findings-dir> [<genre>] [<out.json>]
#        defaults: genre=general  out=<findings-dir>/../artifact.json

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

DIR="${1:?usage: synthesize-artifact.sh <findings-dir> [genre] [out.json]}"
GENRE="${2:-general}"
OUT="${3:-$DIR/../artifact.json}"
[ -d "$DIR" ] || { echo "synthesize: not a directory: $DIR" >&2; exit 2; }

FILES=$(find "$DIR" -maxdepth 1 -name '*.json' | sort)
[ -n "$FILES" ] || { echo "synthesize: no findings in $DIR" >&2; exit 2; }

# Build the artifact from surviving findings: one section per finding, sources
# deduplicated across the set, finding_refs collected, newsworthiness rolled up.
# Write to a temp first so a jq failure (e.g. all findings falsified) is fatal and
# never leaves a stale/empty artifact behind.
# shellcheck disable=SC2086
if ! jq -s --arg genre "$GENRE" '
  map(select((.extensions.harness.verification.verdict // "survived") != "falsified")) as $surv
  | if ($surv | length) == 0 then error("no surviving findings to synthesize") else . end
  | {
      "@type": "Artifact",
      title: ($surv[0].namespace // "Research" | "Findings: " + .),
      genre: $genre,
      audience: "general",
      newsworthiness: "medium",
      namespace: ($surv[0].namespace // "harness/report"),
      mif: { conformanceLevel: 3 },
      finding_refs: [ $surv[] | .["@id"] ],
      sections: [ $surv[] | {
        heading: .title,
        body: (.content // .summary // .title),
        supports: [ .["@id"] ],
        sources: [ (.citations // [])[]
                   | { title: .title, url: .url, citationType: (.citationType // "website"), citationRole: (.citationRole // "supports") } + (if .note then {note: .note} else {} end) ],
        entities: [ (.entities // [])[] | { name: .name, entityType: (.entityType // "entity") } ],
        dimension: (.extensions.harness.dimension // "general"),
        verdict: (.extensions.harness.verification.verdict // "inconclusive")
      } ],
      sources: ( [ $surv[] | (.citations // [])[]
                   | { title: .title, url: .url, citationType: (.citationType // "website"), citationRole: (.citationRole // "supports") } + (if .note then {note: .note} else {} end) ]
                 | group_by(.url) | map(max_by((.note // "") | length)) )
    }
' $FILES > "$OUT.tmp" 2>"$OUT.err"; then
  echo "synthesize: failed —" >&2; cat "$OUT.err" >&2
  rm -f "$OUT.tmp" "$OUT.err"; exit 1
fi
rm -f "$OUT.err"

# Self-validate the required shape before publishing the artifact: a publishable
# artifact must have at least one section, one finding ref, and one source. This
# fails loud on a falsified-only or citation-less finding set rather than emitting
# a schema-invalid (or empty) artifact a renderer would silently accept.
if ! jq -e '(.sections | length >= 1) and (.finding_refs | length >= 1) and (.sources | length >= 1)' "$OUT.tmp" >/dev/null 2>&1; then
  echo "synthesize: artifact has no publishable content (no surviving findings, or no citations to cite)" >&2
  rm -f "$OUT.tmp"; exit 1
fi
mv "$OUT.tmp" "$OUT"

echo "synthesize: wrote $OUT (genre=$GENRE, $(jq '.sections|length' "$OUT") sections, $(jq '.sources|length' "$OUT") sources)"
