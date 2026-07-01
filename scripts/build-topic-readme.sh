#!/usr/bin/env bash
# build-topic-readme.sh — maintain (build) and validate (check) a topic's
# navigation README at reports/<topic>/README.md.
#
# The README is a per-topic navigation index modeled on a research corpus's
# per-directory READMEs: an H1 title; a metadata header (research id, dates,
# finding/verdict counts, source count, status); Purpose; Dimensions; Key
# Findings; a Reports table; a Findings-by-Dimension table; an optional Artifacts
# table; and Tags. It is a navigation projection, NOT a MIF Level-3 report — it
# carries no MIF frontmatter and is exempt from the output-conformance gate
# (see .claude/hooks/check-output-conformance.sh).
#
# This script computes everything deterministic — counts, dates, verdict
# breakdown, source totals, dimension rollup, the report/artifact tables, and a
# summary-based Key Findings DRAFT. It is the structural backbone. SYNTHESIS-GRADE
# Key Findings and a tight Purpose are authored on top by the report-synthesizer
# agent / the `readme` skill (which hold the surviving findings) — those two
# prose sections, and the original Created date, are PRESERVED across rebuilds so
# the synthesis is never clobbered by a later run.
#
# Usage:
#   build-topic-readme.sh <topic> [--check] [--findings <dir>] [--out <path>]
#
#   build (default)  write/refresh reports/<topic>/README.md
#   --check          structural validation gate; exits non-zero on any defect
#   --findings <dir> override findings dir (default reports/<topic>/findings)
#   --out <path>     override output path (default reports/<topic>/README.md)

set -uo pipefail

die() { echo "build-topic-readme: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
CONFIG="$PROJECT_DIR/harness.config.json"

TOPIC=""
MODE="build"
FINDINGS_DIR=""
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)    MODE="check" ;;
    --findings) FINDINGS_DIR="${2:?--findings needs a dir}"; shift ;;
    --out)      OUT="${2:?--out needs a path}"; shift ;;
    --*)        die "unknown flag: $1" ;;
    *)          if [ -z "$TOPIC" ]; then TOPIC="$1"; else die "unexpected arg: $1"; fi ;;
  esac
  shift
done

[ -n "$TOPIC" ] || die "usage: build-topic-readme.sh <topic> [--check] [--findings <dir>] [--out <path>]"
[ -f "$CONFIG" ] || die "manifest not found: $CONFIG"

# Resolve the manifest entry — the topic MUST be registered.
TOPIC_JSON=$(jq -c --arg id "$TOPIC" '.topics[] | select(.id == $id)' "$CONFIG")
[ -n "$TOPIC_JSON" ] || die "topic \"$TOPIC\" is not registered in harness.config.json"

TITLE=$(printf '%s' "$TOPIC_JSON" | jq -r '.title // empty')
[ -n "$TITLE" ] || TITLE="$TOPIC"
STATUS=$(printf '%s' "$TOPIC_JSON" | jq -r '.status // "active"')

TOPIC_DIR="$PROJECT_DIR/reports/$TOPIC"
[ -n "$FINDINGS_DIR" ] || FINDINGS_DIR="$TOPIC_DIR/findings"
[ -n "$OUT" ] || OUT="$TOPIC_DIR/README.md"
GOAL="$TOPIC_DIR/goal.json"

# ----- deterministic data over the MIF substrate -------------------------------

read_findings() {
  local files
  files=$(find "$FINDINGS_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  if [ -z "$files" ]; then
    echo '{"count":0,"sources":0,"dimensions":[],"tags":[],"created":null,"verdicts":{},"by_dim":[],"key":[]}'
    return
  fi
  # shellcheck disable=SC2086
  jq -s '
    {
      count: length,
      sources: ([.[].citations[]?.url] | map(select(. != null)) | unique | length),
      dimensions: ([.[].extensions.harness.dimension] | map(select(. != null)) | unique),
      tags: ([.[].tags[]?] | map(select(. != null)) | unique),
      created: ([.[].created] | map(select(. != null)) | sort | first),
      verdicts: (reduce .[] as $f ({};
        .[($f.extensions.harness.verification.verdict // "none")] += 1)),
      by_dim: ([.[] | (.extensions.harness.dimension // "unspecified")]
        | sort | group_by(.) | map({dim: .[0], count: length})
        | sort_by(-.count)),
      key: (
        map(select((.extensions.harness.verification.verdict // "") as $v
                   | $v == "survived" or $v == "weakened"))
        | sort_by(.extensions.harness.verification.verdict == "survived" | not)
        | map(.summary // .title) | map(select(. != null)) | .[0:8]
      )
    }' $files
}

ROLL=$(read_findings)
COUNT=$(printf '%s' "$ROLL" | jq -r '.count')
SOURCES=$(printf '%s' "$ROLL" | jq -r '.sources')
SURV=$(printf '%s' "$ROLL" | jq -r '.verdicts.survived // 0')
WEAK=$(printf '%s' "$ROLL" | jq -r '.verdicts.weakened // 0')
INC=$(printf '%s' "$ROLL" | jq -r '.verdicts.inconclusive // 0')
FALS=$(printf '%s' "$ROLL" | jq -r '.verdicts.falsified // 0')

CREATED=$(printf '%s' "$ROLL" | jq -r '.created // empty')
TODAY=$(date -u +%Y-%m-%d)
[ -n "$CREATED" ] || CREATED="$TODAY"
CREATED="${CREATED:0:10}"   # normalize ISO datetime -> date-only

# Quarantined findings live under quarantine/; fall back to falsified verdicts.
QCOUNT=0
if [ -d "$TOPIC_DIR/quarantine" ]; then
  QCOUNT=$(find "$TOPIC_DIR/quarantine" -maxdepth 1 -name '*.json' 2>/dev/null | grep -c .)
fi
[ "$QCOUNT" -eq 0 ] && QCOUNT="$FALS"

# Dimensions: union of goal dimensions and dimensions seen in findings, rendered as a
# bulleted list with each dimension's harness.config description (matching the richer
# zircote/research per-topic READMEs) — falls back to a bare bullet when no description.
DIM_BULLETS=$(jq -rn \
  --argjson roll "$ROLL" \
  --slurpfile goal_arr <(cat "$GOAL" 2>/dev/null || echo '{}') \
  --slurpfile cfg_arr <(cat "$CONFIG") '
  ($cfg_arr[0] // {}) as $c
  | ($goal_arr[0] // {}) as $g
  | ((($g.dimensions // []) + $roll.dimensions) | unique) as $dims
  | ($c.dimensions // []) as $cd
  | if ($dims | length) == 0 then "—"
    else ($dims | map(
        . as $d
        | ([$cd[] | select(.id == $d or .name == $d) | .description]
           | map(select(. != null)) | first) as $desc
        | "- **" + $d + "**" + (if ($desc // "") != "" then " — " + $desc else "" end)
      ) | join("\n"))
    end')

# Tags rendered as backtick-quoted tokens (matches the zircote/research exemplars).
TAGS=$(printf '%s' "$ROLL" | jq -r '
  if (.tags | length) == 0 then "—" else (.tags | map("`" + . + "`") | join(" ")) end')

# Falsification audit trail: link + date of the topic's falsification report, if one exists.
FALS_REPORT=$(find "$TOPIC_DIR" -maxdepth 1 -name '*-falsification-report.md' 2>/dev/null | sort | tail -1)
FALS_BASE=""; FALS_DATE=""
if [ -n "$FALS_REPORT" ]; then
  FALS_BASE=$(basename "$FALS_REPORT")
  FALS_DATE=$(printf '%s' "$FALS_BASE" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
fi

# Optional hero image (a *-readme-hero.* asset), surfaced under the metadata header.
HERO=$(find "$TOPIC_DIR/_assets" -maxdepth 1 -iname '*readme-hero*' 2>/dev/null | sort | head -1)

# Purpose draft: the goal statement, else a generic line.
PURPOSE=$(jq -rn --slurpfile goal_arr <(cat "$GOAL" 2>/dev/null || echo '{}') --arg t "$TITLE" '
  ($goal_arr[0] // {}) as $g
  | ($g.goal_statement // $g.research_question // $g.goal // $g.question // null) as $q
  | if $q == null or $q == "" then ("Research session for " + $t + ".") else $q end')

# ----- preservation: keep authored prose + creation date on rebuild ------------

extract_section() {
  # Match the heading tolerantly: normalize a trailing CR (CRLF files) and any
  # trailing whitespace before comparing, so a cosmetically-perturbed heading does
  # not silently defeat prose preservation (this runs on every mutation now, so a
  # missed match would clobber synthesis-grade Purpose/Key Findings with the draft).
  # Body lines are still emitted verbatim ($0), not the normalized copy.
  awk -v hdr="$1" '
    { h=$0; sub(/\r$/,"",h); sub(/[ \t]+$/,"",h) }
    h == hdr { grab=1; next }
    grab && /^## / { grab=0 }
    grab { print }
  ' "$2" | awk '
    { lines[n++] = $0 }
    END { s=0; while (s<n && lines[s]=="") s++
          e=n; while (e>s && lines[e-1]=="") e--
          for (i=s;i<e;i++) print lines[i] }'
}

KEY_PRESERVED=""
if [ "$MODE" = "build" ] && [ -f "$OUT" ]; then
  prev_created=$(grep -oE '\*\*Created:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}' "$OUT" \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
  [ -n "$prev_created" ] && CREATED="$prev_created"
  prev_purpose=$(extract_section "## Purpose" "$OUT")
  [ -n "$prev_purpose" ] && PURPOSE="$prev_purpose"
  prev_key=$(extract_section "## Key Findings" "$OUT")
  [ -n "$prev_key" ] && KEY_PRESERVED="$prev_key"
fi

# ----- markdown assembly -------------------------------------------------------

# Canonical reader-consumption order for a topic's constituents: high-level decision →
# detail → audit → process. Echoes "<rank>\t<Type label>"; lower rank sorts higher.
# Unknown genres sort after the known set (then alphabetically by filename). This is the
# single source of truth for the README Reports-table ordering.
report_type() {
  case "$1" in
    report-exec-summary.md)            printf '1\tExecutive Summary' ;;
    report-briefing.md)                printf '2\tBriefing Report' ;;
    synthesis-*.md)                    printf '3\tSynthesis' ;;
    report-market-research-report.md)  printf '4\tMarket Research Report' ;;
    report-market-sizing.md)           printf '5\tMarket Sizing' ;;
    report-competitive-analysis.md)    printf '6\tCompetitive Analysis' ;;
    report-competitive-quadrant.md)    printf '7\tCompetitive Quadrant' ;;
    report-trend-analysis.md)          printf '8\tTrend Analysis' ;;
    report-trend-modeling.md)          printf '9\tTrend Modeling' ;;
    report-engineering.md)             printf '10\tEngineering Report' ;;
    report-academic.md)                printf '11\tAcademic Paper' ;;
    report-computing-paper.md)         printf '12\tComputing Paper' ;;
    *-falsification-report.md)         printf '13\tFalsification Report' ;;
    research-progress.md)              printf '14\tResearch Progress' ;;
    report-*.md)                       printf '40\tReport' ;;
    *.pdf)                             printf '45\tPDF Document' ;;
    *)                                 printf '50\tDocument' ;;
  esac
}

# Extract a deliverable's title: its YAML frontmatter `title:` (the genre report-*.md),
# else its first body `# H1` (synthesis, falsification report, progress), else filename.
file_title() {
  local fp="$1" t
  t=$(sed -n '/^---$/,/^---$/s/^title:[[:space:]]*//p' "$fp" 2>/dev/null | head -1 \
        | sed -E 's/^["'\'']//; s/["'\'']$//')
  [ -n "$t" ] || t=$(grep -m1 -E '^#[[:space:]]+' "$fp" 2>/dev/null | sed -E 's/^#[[:space:]]+//')
  [ -n "$t" ] || t=$(basename "$fp")
  printf '%s' "$t"
}

# Extract a deliverable's genre: the frontmatter `genre:` key at any nesting depth
# (e.g. top-level on a report, or nested under extensions.harness.genre), else the
# middle segment of a "<slug>.<genre>.md" filename (this harness's real naming
# convention — report_type()'s literal "report-<genre>.md" patterns do not match
# it, so most deliverables fall through to the generic "Document" label; this is
# the actual genre a reader wants to see). Empty when neither source has one.
file_genre() {
  local fp="$1" base g
  g=$(sed -n '/^---$/,/^---$/p' "$fp" 2>/dev/null | grep -m1 -E '^[[:space:]]*genre:[[:space:]]*[^[:space:]]' \
        | sed -E 's/^[[:space:]]*genre:[[:space:]]*//; s/^["'\'']//; s/["'\'']$//')
  if [ -z "$g" ]; then
    base=$(basename "$fp")
    case "$base" in
      *.*.md) g="${base%.md}"; g="${g##*.}" ;;
    esac
  fi
  printf '%s' "$g"
}

# Extract a deliverable's version: the frontmatter `version:` integer (stamped by
# render-artifact.sh, incremented every time the same genre is re-rendered for
# this topic, since a re-render overwrites its file in place with no automatic
# history). Empty on a file with no version field (not yet backfilled, or a
# non-genre deliverable like a falsification report).
file_version() {
  local fp="$1" v
  v=$(sed -n '/^---$/,/^---$/p' "$fp" 2>/dev/null | grep -m1 -E '^[[:space:]]*version:[[:space:]]*[0-9]+' \
        | grep -oE '[0-9]+')
  printf '%s' "$v"
}

artifact_type() {
  case "$1" in
    *infographic*) echo "Infographic" ;;
    *.png|*.jpg|*.jpeg|*.webp|*.svg)    echo "Image" ;;
    *.m4a|*.mp3|*.wav)                  echo "Audio" ;;
    *.mp4|*.webm)                       echo "Video" ;;
    *mindmap*|*mind-map*)               echo "Mind map" ;;
    *.pdf)                              echo "Slide deck" ;;
    *.json)                            echo "Data" ;;
    *)                                  echo "Asset" ;;
  esac
}

# Human-readable file size (e.g. "7.8 MB"); empty on error.
human_size() {
  local b
  b=$(wc -c < "$1" 2>/dev/null | tr -d ' ') || return 0
  [ -n "$b" ] || return 0
  awk -v b="$b" 'BEGIN{
    split("B KB MB GB TB",u," "); i=1;
    while (b>=1024 && i<5){b/=1024;i++}
    if (i==1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

build_readme() {
  printf '# %s\n\n' "$TITLE"
  printf '**Research ID:** %s\n' "$TOPIC"
  printf '**Created:** %s | **Updated:** %s\n' "$CREATED" "$TODAY"
  if [ "$COUNT" -eq 0 ]; then
    printf '**Findings:** 0 | **Sources:** 0\n'
  else
    local parts="" detail="" q=""
    [ "$SURV" -gt 0 ] && parts="survived $SURV"
    [ "$WEAK" -gt 0 ] && parts="${parts:+$parts, }weakened $WEAK"
    [ "$INC" -gt 0 ]  && parts="${parts:+$parts, }inconclusive $INC"
    [ -n "$parts" ] && detail=" ($parts)"
    [ "$QCOUNT" -gt 0 ] && q=" — quarantined $QCOUNT"
    printf '**Findings:** %s%s%s | **Sources:** %s unique URLs\n' "$COUNT" "$detail" "$q" "$SOURCES"
  fi
  if [ -n "$FALS_BASE" ]; then
    local fq=""
    [ "$QCOUNT" -gt 0 ] && fq=", quarantined $QCOUNT"
    printf '**Falsification:** %s — survived %s, weakened %s%s ([report](%s))\n' \
      "${FALS_DATE:-see report}" "$SURV" "$WEAK" "$fq" "$FALS_BASE"
  fi
  printf '**Status:** %s\n\n' "$STATUS"
  printf -- '---\n\n'

  if [ -n "$HERO" ]; then
    printf '![%s](%s)\n\n' "$TITLE" "${HERO#"$TOPIC_DIR"/}"
  fi

  printf '## Purpose\n\n%s\n\n' "$PURPOSE"

  printf '## Dimensions\n\n%s\n\n' "$DIM_BULLETS"

  printf '## Key Findings\n\n'
  if [ -n "$KEY_PRESERVED" ]; then
    printf '%s\n\n' "$KEY_PRESERVED"
  elif [ "$COUNT" -eq 0 ]; then
    printf -- '- No findings yet — run `/start --topic %s` to begin research.\n\n' "$TOPIC"
  else
    # Draft: surviving/weakened finding summaries. The report-synthesizer / readme
    # skill replaces these with cross-finding synthesis (see those definitions).
    printf '%s' "$ROLL" | jq -r '.key[] | "- " + .'
    printf '\n'
  fi

  printf '## Reports\n\n'
  # Every constituent deliverable EXCEPT this README index, listed as Type -> Genre ->
  # Title in a fixed reader-consumption order (report_type): exec summary → briefing →
  # synthesis → the genre reports → falsification report → research progress. Genre
  # (file_genre) is the deliverable's actual genre/template (engineering, arc42,
  # exec-summary, ...), distinct from Type's coarse structural bucket. The linked title
  # is the rendered page. Build logs (*-delta) are omitted.
  local docs base meta rank label title genre version rows
  docs=$(find "$TOPIC_DIR" -maxdepth 1 -name '*.md' \
    ! -name 'README.md' ! -name '*-delta.md' 2>/dev/null)
  if [ -z "$docs" ]; then
    printf 'No reports rendered yet.\n\n'
  else
    printf '| Type | Genre | Title |\n| --- | --- | --- |\n'
    rows=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      base=$(basename "$f")
      meta=$(report_type "$base"); rank=${meta%%$'\t'*}; label=${meta#*$'\t'}
      title=$(file_title "$f")
      genre=$(file_genre "$f")
      if [ -n "$genre" ]; then
        version=$(file_version "$f")
        [ -n "$version" ] && genre="$genre (v$version)"
      else
        genre="—"
      fi
      rows+=$(printf '%s\t| %s | %s | [%s](%s) |' "$rank" "$label" "$genre" "$title" "$base")$'\n'
    done <<< "$docs"
    printf '%s' "$rows" | LC_ALL=C sort -t"$(printf '\t')" -k1,1n -k2 | cut -f2-
    printf '\n'
  fi

  printf '## Findings by Dimension\n\n'
  if [ "$COUNT" -eq 0 ]; then
    printf 'No findings yet.\n\n'
  else
    printf '| Dimension | Findings |\n'
    printf '| --- | --- |\n'
    printf '%s' "$ROLL" | jq -r '.by_dim[] | "| \(.dim) | \(.count) |"'
    printf '\n'
  fi

  # Artifacts (only when channel-pack assets exist on disk).
  local assets
  assets=$(find "$TOPIC_DIR/_assets" "$TOPIC_DIR/slides" -maxdepth 1 -type f 2>/dev/null | sort)
  if [ -n "$assets" ]; then
    printf '## Artifacts\n\n'
    printf '| File | Type | Size |\n'
    printf '| --- | --- | --- |\n'
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      local rel; rel="${f#"$TOPIC_DIR"/}"
      printf '| [`%s`](%s) | %s | %s |\n' \
        "$(basename "$f")" "$rel" "$(artifact_type "$(basename "$f")")" "$(human_size "$f")"
    done <<< "$assets"
    printf '\n'
  fi

  printf '## Tags\n\n%s\n' "$TAGS"
}

# ----- check (structural validation gate) --------------------------------------

run_check() {
  local errs=0
  if [ ! -f "$OUT" ]; then
    echo "FAIL: README missing: $OUT" >&2
    return 1
  fi
  local required=("## Purpose" "## Dimensions" "## Key Findings" "## Reports" "## Findings by Dimension" "## Tags")
  for sec in "${required[@]}"; do
    grep -qF "$sec" "$OUT" || { echo "FAIL: missing section: $sec" >&2; errs=$((errs+1)); }
  done

  local stated
  stated=$(grep -oE '\*\*Findings:\*\* [0-9]+' "$OUT" | grep -oE '[0-9]+' | head -1)
  if [ -z "$stated" ]; then
    echo "FAIL: no '**Findings:** N' metadata line" >&2; errs=$((errs+1))
  elif [ "$stated" != "$COUNT" ]; then
    echo "FAIL: Findings count drift — README says $stated, substrate has $COUNT" >&2; errs=$((errs+1))
  fi

  # Synthesis gate: when findings exist, the Key Findings must be SYNTHESIZED, not
  # left as the deterministic draft (verbatim finding summaries). The draft is what
  # the build seeds; the report-synthesizer / readme skill must replace it. If the
  # on-disk bullets are byte-identical to a freshly-computed draft, synthesis was
  # never applied — refuse the skeleton (the floor that shipped as "shit").
  if [ "$COUNT" -gt 0 ]; then
    local draft ondisk
    draft=$(printf '%s' "$ROLL" | jq -r '.key[] | "- " + .')
    ondisk=$(extract_section "## Key Findings" "$OUT")
    if [ "$ondisk" = "$draft" ]; then
      echo "FAIL: Key Findings are the auto-generated draft — synthesis not applied (run the readme skill / report-synthesizer Step 4c)" >&2
      errs=$((errs+1))
    fi
  fi

  # Every local link/image target must exist on disk (relative to the topic dir).
  # Covers the Type->Title Reports table, the Artifacts table, the hero image, and the
  # falsification-report link in the header. External (http/mailto) and anchor links skip.
  local link
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$link" in http://*|https://*|"#"*|mailto:*) continue ;; esac
    [ -f "$TOPIC_DIR/$link" ] || { echo "FAIL: dangling link: $link" >&2; errs=$((errs+1)); }
  done < <(grep -oE '\]\([^)]+\)' "$OUT" | sed -E 's/^\]\(//; s/\)$//')

  if [ "$errs" -ne 0 ]; then
    echo "build-topic-readme: $errs validation error(s) for $TOPIC" >&2
    return 1
  fi
  echo "OK: $OUT valid ($COUNT findings, $SOURCES sources)"
  return 0
}

# ----- dispatch ----------------------------------------------------------------

if [ "$MODE" = "check" ]; then
  run_check
  exit $?
fi

mkdir -p "$(dirname "$OUT")"
# Atomic write: render to a sibling temp then mv into place, so a crash or a
# SIGKILL (e.g. the PostToolUse rebuild hook hitting its timeout) can never leave
# a half-written README on disk — the live file is replaced only once it is
# complete. Matches the repo's `tmp.$$ && mv` idiom.
OUT_TMP="$OUT.tmp.$$"
build_readme > "$OUT_TMP" || { rm -f "$OUT_TMP"; die "failed to write $OUT"; }
mv "$OUT_TMP" "$OUT"
echo "wrote $OUT ($COUNT findings, $SOURCES sources)"
