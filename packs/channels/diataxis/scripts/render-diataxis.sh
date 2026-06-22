#!/usr/bin/env bash
# render-diataxis.sh — render a research topic's surviving findings corpus into a
# COMPLETE Diátaxis documentation set (SPEC §6d channel pack).
#
# Diátaxis organizes documentation by user need into four modes that stay pure:
#   tutorial    — learning-oriented: guided lessons through the research.
#   how-to      — task-oriented: how to act on each dimension's findings.
#   reference   — information-oriented: ONE authoritative page per finding.
#   explanation — understanding-oriented: how a dimension's findings connect.
#
# The set is exhaustive, not a summary: every surviving finding (verdict ≠
# falsified) becomes a reference page; every research dimension yields an
# explanation, a how-to, and a guided tutorial; landing/index pages tie them
# together. Slugs are computed once (the `manifest`) and disambiguated, so two
# findings that slugify alike never overwrite each other and index links always
# resolve to the file that exists.
#
# All corpus-derived text is sanitized before it reaches a body:
#   - identity scrub: urn:mif: ids, reports/<topic>/ paths, f_<dim>_<n> handles,
#     and extensions.harness paths are redacted, so prose carries no
#     internal-research identity (the page's own urn:mif:doc: frontmatter @id is
#     its legitimate L1 identity);
#   - structure neutralized: a line-leading '#' in content is escaped so content
#     cannot inject a second top-level heading; titles are trimmed of stray '#'
#     and whitespace; link text drops '[]'; citation URLs are angle-bracketed.
# Titles live in the body H1 (not frontmatter), so markdownlint MD025 stays green.
#
# Every page carries MIF Level-1 frontmatter — a base MIF v1.0 concept
# (schemas/mif/mif.schema.json) plus the diataxis_type marker, validated by
# schemas/diataxis-doc.schema.json and enforced by verify.sh gate_m16. Level 1,
# not Level 3 — the report channel stays the canonical L3 source of truth and this
# channel stays mif.exempt.
#
# Depends only on jq.  Usage: render-diataxis.sh <findings-dir> <out-dir> [<topic-name>]

set -uo pipefail

FINDINGS="${1:?usage: render-diataxis.sh <findings-dir> <out-dir> [topic-name]}"
OUT="${2:?usage: render-diataxis.sh <findings-dir> <out-dir> [topic-name]}"
[ -d "$FINDINGS" ] || { echo "render-diataxis: findings dir not found: $FINDINGS" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "render-diataxis: jq is required" >&2; exit 2; }
shopt -s nullglob
FILES=("$FINDINGS"/*.json)
[ "${#FILES[@]}" -gt 0 ] || { echo "render-diataxis: no findings in $FINDINGS" >&2; exit 2; }

ALL="$(mktemp)"; MAN="$(mktemp)"; trap 'rm -f "$ALL" "$MAN"' EXIT
# Fail loudly if any finding is malformed JSON (jq -s aborts) rather than emitting a
# partial tree: this script does not use `set -e`, so the critical jq steps below
# (slurp, manifest) are error-checked explicitly.
if ! jq -s '[ .[] | select((.extensions.harness.verification.verdict // "") != "falsified") ]' "${FILES[@]}" > "$ALL"; then
  echo "render-diataxis: failed to read findings (malformed finding JSON in $FINDINGS?)" >&2; exit 2
fi
COUNT=$(jq 'length' "$ALL") || { echo "render-diataxis: failed to count findings" >&2; exit 2; }
[ "$COUNT" -gt 0 ] || { echo "render-diataxis: no surviving findings to document" >&2; exit 2; }
NS=$(jq -r '.[0].namespace // "harness/doc"' "$ALL")
TOPIC="${3:-$(basename "$NS")}"
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DIMS=()
while IFS= read -r _d; do [ -n "$_d" ] && DIMS+=("$_d"); done < <(jq -r '[.[].extensions.harness.dimension // "general"] | unique | .[]' "$ALL")

# Shared jq prelude: sanitizers + markdownlint-safe block builders + the slug
# manifest. Every heading/list/paragraph block is prefixed with one blank line, so
# blanks never double (MD012) and headings/lists are always surrounded (MD022/032).
DEF='
  def scrub: tostring
    | gsub("urn:mif:[a-z]+:[^\\s)\\]]+"; "[internal-ref]")
    | gsub("reports/[a-z0-9][a-z0-9-]*/[A-Za-z0-9_./-]+"; "[internal-ref]")
    | gsub("\\bf_[a-z]+_[0-9]+\\b"; "[internal-ref]")
    | gsub("extensions\\.harness[A-Za-z0-9_.]*"; "[internal-ref]");
  # Fence-aware STRUCTURAL normalizer: outside a code fence, escape a line-leading "#"
  # so content cannot inject a top-level heading (MD025); on a bare opening fence add a
  # language (MD040); INSIDE a fence it touches no line, so it never corrupts code
  # STRUCTURE. (Note: cleanprose runs `scrub` BEFORE normbody, and scrub is deliberately
  # NOT fence-aware — it redacts internal identity everywhere, including inside code
  # fences, so no urn:mif:/reports/ id can hide in a code block. That is the no-leak
  # guarantee, not corruption.)
  def normbody:
    (split("\n")) as $L
    | reduce range(0; ($L|length)) as $k ({fence:false, out:[]};
        $L[$k] as $ln
        | if ($ln | test("^[ \t]*(```|~~~)")) then
            (if .fence then {fence:false, out:(.out + [$ln])}
             else {fence:true, out:(.out + [ (if ($ln | test("^[ \t]*(```|~~~)[ \t]*$")) then ($ln | sub("(?<f>```|~~~)[ \t]*$"; "\(.f)text")) else $ln end) ])} end)
          elif ((.fence | not) and ($ln | test("^[ \t]*#"))) then
            {fence:.fence, out:(.out + [ ($ln | sub("^(?<s>[ \t]*)#"; "\(.s)\\#")) ])}
          else {fence:.fence, out:(.out + [$ln])} end )
    | .out | join("\n");
  def cleanprose: scrub | gsub("\\r";"") | gsub("[ \t]+\n";"\n")
    | sub("^\\s+";"") | sub("\\s+$";"") | gsub("\n{3,}";"\n\n") | normbody;
  def cleantitle: scrub | gsub("\\s+";" ") | gsub("^\\s+|\\s+$";"")
    | gsub("^#+[ \t]*";"") | gsub("[ \t]*#+$";"")
    | gsub("[ \t]*[.,;:!]+$";"") | gsub("^\\s+|\\s+$";"");
  def linktext: cleantitle | gsub("[\\[\\]]";"");
  def slug: ascii_downcase | gsub("[^a-z0-9]+";"-") | gsub("^-+|-+$";"") | (if . == "" then "untitled" else . end);
  def manifest:
    [ to_entries[] | { i:.key, dim:(.value.extensions.harness.dimension // "general"), title:.value.title, base:(.value.title|slug) } ]
    | group_by(.dim)
    | map( reduce .[] as $f ({seen:{},out:[]};
        ((.seen[$f.base] // 0) + 1) as $n | .seen[$f.base] = $n
        | .out += [ $f + { slug: ($f.base + (if $n>1 then "-"+($n|tostring) else "" end)) } ] ) | .out )
    | add | sort_by(.i);
  def fm($extra): [ "---",
      "\"@context\": https://mif-spec.dev/schema/context.jsonld", "\"@type\": Concept",
      ("\"@id\": " + $id), ("conceptType: " + $ctype), ("created: \"" + $created + "\""),
      ("namespace: " + $ns), ("diataxis_type: " + $dtype) ] + $extra + [ "---", "" ];
  def h1($t): [ "# " + ($t|cleantitle) ];
  def h2($t): [ "", "## " + ($t|cleantitle) ];
  def para($t): [ "", ($t|cleanprose) ];
  def bullets($a): if ($a|length) > 0 then [ "" ] + ($a | map("- " + .)) else [] end;
  def numbered($a): if ($a|length) > 0 then [ "" ] + ($a | to_entries | map(((.key+1)|tostring) + ". " + .value)) else [] end;
  def firstsentence: (scrub | gsub("\\s+";" ") | gsub("^\\s+|\\s+$";"") | split(". ")[0] | rtrimstr(".")) + ".";
  def titlemap: (map({ (.["@id"]): (.title|cleantitle) }) | add) // {};
  def dimsof: (map(.extensions.harness.dimension // "general") | unique);
  def bydim($d): [ .[] | select((.extensions.harness.dimension // "general") == $d) ];
  def srcfull: "[" + (.title|linktext) + "](<" + (.url|tostring) + ">) — " + ((.citationType // "source")|tostring) + ", " + ((.citationRole // "supports")|tostring);
  def srcplain: "[" + (.title|linktext) + "](<" + (.url|tostring) + ">)";
  def srclinks($f): [ $f[].citations[]? | srcplain ] | unique;
'

# emit <relpath> <conceptType> <diataxis_type> <jq-program> [jq args...]
emit() {
  local rel="$1" ctype="$2" dtype="$3" prog="$4"; shift 4
  local out="$OUT/$rel" id idslug tmp
  idslug="$(printf '%s' "$rel" | sed 's#\.md$##; s#/#-#g; s#[^A-Za-z0-9-]#-#g')"
  id="urn:mif:doc:${NS}:${idslug}"
  local dir; dir="$(dirname "$out")"
  mkdir -p "$dir" || { echo "render-diataxis: cannot create dir for $rel" >&2; return 1; }
  # Temp lands in the target dir (not the system temp): the mv is same-filesystem and
  # therefore atomic, and nothing is ever written outside <out-dir>.
  tmp="$(mktemp "$dir/.render-XXXXXX")" || { echo "render-diataxis: cannot create temp for $rel" >&2; return 1; }
  if jq -r --arg id "$id" --arg ctype "$ctype" --arg dtype "$dtype" \
        --arg created "$CREATED" --arg ns "$NS" --arg topic "$TOPIC" \
        "$@" "$DEF $prog" "$ALL" > "$tmp"; then
    mv "$tmp" "$out" || { rm -f "$tmp"; echo "render-diataxis: failed to install $rel (mv)" >&2; return 1; }
  else
    rm -f "$tmp"; echo "render-diataxis: failed to render $rel (jq)" >&2; return 1
  fi
}

jq "$DEF"' manifest' "$ALL" > "$MAN" || { echo "render-diataxis: failed to build slug manifest" >&2; exit 1; }

# ── jq programs ─────────────────────────────────────────────────────────────────
REF='
  (. | titlemap) as $titles | .[$i] as $f
  | ([ $f.relationships[]? | ($titles[.target] // empty) ]) as $rel
  | fm([])
    + h1($f.title) + para($f.content)
    + h2("Classification")
    + bullets([ "Dimension: " + (($f.extensions.harness.dimension // "general")|tostring),
                "Verification: " + (($f.extensions.harness.verification.verdict // "n/a")|tostring),
                "Concept type: " + (($f.conceptType // "semantic")|tostring) ])
    + ( if (($f.entities // []) | length) > 0
        then h2("Key entities") + bullets([ $f.entities[] | ((.name|scrub) + " (" + ((.entityType // "entity")|scrub) + ")") ]) else [] end )
    + ( if (($f.citations // []) | length) > 0
        then h2("Evidence") + bullets([ $f.citations[] | srcfull ]) else [] end )
    + ( if ($rel | length) > 0 then h2("Related findings") + bullets($rel) else [] end )
  | .[]'

EXP='
  (. | titlemap) as $titles | bydim($dim) as $f | srclinks($f) as $src
  | fm([])
    + h1("Understanding the " + $dim + " findings")
    + para("This explanation connects the " + (($f|length)|tostring) + " " + $dim + " finding(s) and what they establish together.")
    + ( reduce $f[] as $x ([];
          . + h2($x.title) + para($x.content)
            + ( ([ $x.relationships[]? | ($titles[.target] // empty) ]) as $r
                | if ($r|length) > 0 then para("Connects to: " + ($r | join("; ")) + ".") else [] end ) ) )
    + ( if ($src | length) > 0 then h2("Sources") + bullets($src) else [] end )
  | .[]'

HOW='
  bydim($dim) as $f | srclinks($f) as $src
  | fm([])
    + h1("How to apply the " + $dim + " findings")
    + h2("Goal") + para("Put the " + $dim + " research conclusions to work.")
    + h2("Steps") + numbered([ $f[] | "Apply this conclusion: " + (.title | cleantitle | rtrimstr(".")) + "." ])
    + h2("Result") + para("You have applied each " + $dim + " conclusion. Verify outcomes against the reference pages, and revisit the explanation if a step is unclear.")
    + ( if ($src | length) > 0 then h2("Sources") + bullets($src) else [] end )
  | .[]'

TUTGS='
  fm([ "audience: newcomers" ])
  + h1("Getting started with " + $topic)
  + para("This tutorial walks you through the research on " + $topic + " one finding at a time. By the end you will have met each key result and know where to dive deeper.")
  + h2("Before you begin")
  + para("You will work through " + ((length)|tostring) + " short steps across " + ((dimsof|length)|tostring) + " dimension(s); no prior knowledge is assumed.")
  + ( reduce (to_entries[]) as $e ([];
        . + h2("Step " + (($e.key+1)|tostring) + " — " + $e.value.title)
          + para("In this step you meet a " + ($e.value.extensions.harness.dimension // "general") + " finding.")
          + para($e.value.content | firstsentence) ) )
  + h2("Where to go next")
  + para("Use the how-to guides to apply these findings, the reference pages for full detail, and the explanations to see how they connect.")
  | .[]'

TUTDIM='
  bydim($dim) as $f
  | fm([ "audience: newcomers" ])
    + h1("A guided tour of the " + $dim + " findings")
    + para("Work through the " + $dim + " research one finding at a time.")
    + ( reduce ($f | to_entries[]) as $e ([];
          . + h2("Step " + (($e.key+1)|tostring) + " — " + $e.value.title) + para($e.value.content | firstsentence) ) )
    + h2("Where to go next")
    + para("See the how-to guide for applying these " + $dim + " findings and the reference pages for full detail.")
  | .[]'

REFIDX='
  $man[0] as $m | ($m | map(.dim) | unique) as $dims
  | fm([]) + h1("Reference")
    + para("Authoritative, lookup-oriented pages — one per finding, grouped by research dimension.")
    + ( reduce $dims[] as $d ([];
          . + h2($d) + bullets([ $m[] | select(.dim == $d) | "[" + (.title|linktext) + "](" + .dim + "/" + .slug + ".md)" ]) ) )
  | .[]'

EXPIDX='
  dimsof as $dims | fm([]) + h1("Explanation")
    + para("Understanding-oriented discussions — how each dimension'"'"'s findings connect.")
    + h2("Topics") + bullets([ $dims[] | "[Understanding the " + . + " findings](" + . + ".md)" ])
  | .[]'

HOWIDX='
  dimsof as $dims | fm([]) + h1("How-to guides")
    + para("Task-oriented guides for applying the findings of each dimension.")
    + h2("Guides") + bullets([ $dims[] | "[How to apply the " + . + " findings](apply-" + . + ".md)" ])
  | .[]'

TUTIDX='
  dimsof as $dims | fm([ "audience: newcomers" ]) + h1("Tutorials")
    + para("Learning-oriented, hands-on lessons through the research.")
    + h2("Start here") + bullets([ "[Getting started with " + $topic + "](getting-started.md)" ])
    + h2("By dimension") + bullets([ $dims[] | "[A guided tour of the " + . + " findings](" + . + ".md)" ])
  | .[]'

TOPIDX='
  fm([]) + h1("Documentation: " + $topic)
    + para("A complete Diátaxis documentation set derived from the research on " + $topic + ". " + ((length)|tostring) + " finding(s) across " + ((dimsof|length)|tostring) + " dimension(s).")
    + h2("Sections")
    + bullets([ "[Tutorials](tutorials/index.md) — learning-oriented guided lessons",
                "[How-to guides](how-to/index.md) — task-oriented application of the findings",
                "[Reference](reference/index.md) — one authoritative page per finding",
                "[Explanation](explanation/index.md) — how the findings connect" ])
  | .[]'

# ── emit the full tree ──────────────────────────────────────────────────────────
rc=0
while IFS=$'\t' read -r i dim slug; do
  [ -n "$slug" ] || continue
  emit "reference/$dim/$slug.md" semantic reference "$REF" --argjson i "$i" || rc=1
done < <(jq -r '.[] | "\(.i)\t\(.dim)\t\(.slug)"' "$MAN")
for dim in "${DIMS[@]}"; do
  emit "explanation/$dim.md"  semantic   explanation "$EXP"    --arg dim "$dim" || rc=1
  emit "how-to/apply-$dim.md" procedural how-to      "$HOW"    --arg dim "$dim" || rc=1
  emit "tutorials/$dim.md"    procedural tutorial    "$TUTDIM" --arg dim "$dim" || rc=1
done
emit "tutorials/getting-started.md" procedural tutorial    "$TUTGS"  || rc=1
emit "reference/index.md"           semantic   reference   "$REFIDX" --slurpfile man "$MAN" || rc=1
emit "explanation/index.md"         semantic   explanation "$EXPIDX" || rc=1
emit "how-to/index.md"              procedural how-to      "$HOWIDX" || rc=1
emit "tutorials/index.md"           procedural tutorial    "$TUTIDX" || rc=1
emit "index.md"                     semantic   explanation "$TOPIDX" || rc=1

if [ "$rc" -ne 0 ]; then
  echo "render-diataxis: one or more documents failed to render" >&2
  exit 1
fi

TOTAL=$(find "$OUT" -name '*.md' | wc -l | tr -d ' ')
echo "render-diataxis: wrote $TOTAL Diátaxis documents to $OUT ($COUNT finding(s), ${#DIMS[@]} dimension(s))"
