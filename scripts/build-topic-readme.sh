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

# Dimensions: union of goal dimensions and dimensions seen in findings.
DIMENSIONS=$(jq -rn \
  --argjson roll "$ROLL" \
  --slurpfile goal_arr <(cat "$GOAL" 2>/dev/null || echo '{}') '
  ($goal_arr[0] // {}) as $g
  | (($g.dimensions // []) + $roll.dimensions) | unique
  | if length == 0 then "—" else join(", ") end')

TAGS=$(printf '%s' "$ROLL" | jq -r 'if (.tags | length) == 0 then "—" else (.tags | join(", ")) end')

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

report_desc() {
  case "$1" in
    *delta*|*DELTA*)                    echo "Delta update" ;;
    blog*|*-blog.md)                    echo "Blog post" ;;
    ARCHITECT*)                         echo "Architecture / engineering document" ;;
    RESEARCH-REPORT.md|REPORT.md|report.md|*-report.md) echo "Full research report" ;;
    *.pdf)                              echo "PDF document" ;;
    *)                                  echo "Document" ;;
  esac
}

artifact_type() {
  case "$1" in
    *infographic*) echo "Infographic" ;;
    *.png|*.jpg|*.jpeg|*.webp|*.svg)    echo "Image" ;;
    *.m4a|*.mp3|*.wav)                  echo "Audio" ;;
    *.mp4|*.webm)                       echo "Video" ;;
    *mindmap*|*mind-map*)               echo "Mind map" ;;
    *.pdf)                              echo "Slide deck" ;;
    *)                                  echo "Asset" ;;
  esac
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
  printf '**Status:** %s\n\n' "$STATUS"
  printf -- '---\n\n'

  printf '## Purpose\n\n%s\n\n' "$PURPOSE"

  printf '## Dimensions\n\n%s\n\n' "$DIMENSIONS"

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
  # Rendered deliverables only — exclude README.md and research-progress.md (a
  # continuity/audit log, not a report; consistent with PR #72).
  local docs base
  docs=$(find "$TOPIC_DIR" -maxdepth 1 -name '*.md' \
    ! -name 'README.md' ! -name 'research-progress.md' 2>/dev/null | sort)
  if [ -z "$docs" ]; then
    printf 'No reports rendered yet.\n\n'
  else
    printf '| File | Description |\n'
    printf '| --- | --- |\n'
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      base=$(basename "$f")
      printf '| [`%s`](%s) | %s |\n' "$base" "$base" "$(report_desc "$base")"
    done <<< "$docs"
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
    printf '| File | Type |\n'
    printf '| --- | --- |\n'
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      local rel; rel="${f#"$TOPIC_DIR"/}"
      printf '| [`%s`](%s) | %s |\n' "$(basename "$f")" "$rel" "$(artifact_type "$(basename "$f")")"
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

  # Every linked file in a table must exist on disk (relative to the topic dir).
  local link
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    [ -f "$TOPIC_DIR/$link" ] || { echo "FAIL: dangling link: $link" >&2; errs=$((errs+1)); }
  done < <(grep -oE '\| \[`[^`]+`\]\([^)]+\)' "$OUT" | grep -oE '\]\([^)]+\)' | sed -E 's/^\]\(//; s/\)$//')

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
