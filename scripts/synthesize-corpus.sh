#!/usr/bin/env bash
# synthesize-corpus.sh — the cross-topic corpus atlas (Epic 2; ontological spine, ADR-0011).
# From the spine (reports/concordance.json) it builds a corpus-level view spanning EVERY topic
# that shows the WHOLE research record — including what was falsified/weakened — which the
# per-topic report-synthesizer (survivors only) deliberately does not.
#
# Outputs (reports/_corpus/, an `_`-prefixed dir with NO findings/ subdir, so build-concordance
# never ingests it as a topic):
#   corpus-map.json      deterministic cross-topic projection (topics, verdict distribution,
#                        entity reuse, contradictions, disproven). Schema-free derived map,
#                        like reports/<topic>/ontology-map.json.
#   corpus-synthesis.md  human-facing atlas: a deterministic backbone (tables) + a PRESERVED
#                        synthesis-grade `## Cross-Corpus Insights` prose section authored by the
#                        corpus-synthesizer agent. A navigation/atlas projection (no MIF
#                        frontmatter); exempt from the output-conformance gate.
#
# Scales to a large corpus: all STRUCTURE comes from concordance.json (already merged), so this
# script opens NO finding files. Deterministic/idempotent: no wall-clock, every array sorted.
#
# Usage: synthesize-corpus.sh [<reports-dir>] [--check]
#   build (default)  write reports/_corpus/corpus-map.json + corpus-synthesis.md
#   --check          gate: concordance present AND the Insights section is synthesized (not the draft)

set -uo pipefail
die() { echo "synthesize-corpus: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is required"

RD=""; MODE="build"
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE="check" ;;
    --*)     die "unknown flag: $1" ;;
    *)       if [ -z "$RD" ]; then RD="$1"; else die "unexpected arg: $1"; fi ;;
  esac
  shift
done
[ -n "$RD" ] || RD="${CLAUDE_PROJECT_DIR:-.}/reports"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
[ -d "$RD" ] || die "reports dir not found: $RD"

CONC="$RD/concordance.json"
OUTDIR="$RD/_corpus"
MAP_OUT="$OUTDIR/corpus-map.json"
MD_OUT="$OUTDIR/corpus-synthesis.md"
INSIGHTS_HDR="## Cross-Corpus Insights"
DRAFT_MARK="_Draft — the corpus-synthesizer"
HIGHLIGHTS=12

# Fail closed: the atlas is a projection of the spine; without a valid spine there is nothing
# to build (and never a vacuous/partial atlas).
[ -s "$CONC" ] || die "concordance not found or empty: $CONC — build it first (scripts/build-concordance.sh)"
jq -e 'type=="object" and (.nodes | type) == "array"' "$CONC" >/dev/null 2>&1 \
  || die "concordance is not a valid graph (no .nodes array): $CONC"

# ----- deterministic projection from the spine (zero finding-body reads) --------
corpus_map() {
  jq -n --slurpfile c "$CONC" '
    ($c[0]) as $g
    | ($g.nodes // []) as $nodes
    | ($g.edges // []) as $edges
    | ($nodes | map(select(.kind=="concept"))) as $concepts
    | ($nodes | map(select(.kind=="entity"))) as $entities
    | { "@type":"CorpusMap",
        generator:"synthesize-corpus.sh",
        topics: ([ $nodes[].topics[]? ] | unique),
        verdict_distribution: (reduce $concepts[] as $n ({}; .[($n.verdict // "none")] += 1)),
        entity_reuse: ( [ $entities[] | .id as $id
              | { id, label, entityType,
                  topic_count: ((.topics // []) | length),
                  topics: ((.topics // []) | sort),
                  degree: ([ $edges[] | select(.source==$id or .target==$id) ] | length) } ]
            | sort_by([ (- .topic_count), (- .degree), .id ]) ),
        contradictions: ( [ $edges[]
              | select(.via=="relationship" and ((.type // "") | test("contradict|refut|disput")))
              | { source, target, type } ] | sort_by([.source, .target, .type]) ),
        disproven: ( [ $concepts[] | select(.flagged==true)
              | { id, label, topics: ((.topics // []) | sort) } ] | sort_by(.id) ) }'
}

# ----- preserved prose extraction (modeled on build-topic-readme.sh) -----------
extract_section() {  # $1 heading  $2 file — emit the section body, trimmed
  awk -v hdr="$1" '
    { h=$0; sub(/\r$/,"",h); sub(/[ \t]+$/,"",h) }
    h == hdr { grab=1; next }
    grab && /^## / { grab=0 }
    grab { print }
  ' "$2" | awk '
    { lines[n++]=$0 }
    END { s=0; while (s<n && lines[s]=="") s++; e=n; while (e>s && lines[e-1]=="") e--
          for (i=s;i<e;i++) print lines[i] }'
}

# ----- markdown backbone + preserved prose -------------------------------------
build_md() {  # $1 corpus-map json  $2 preserved insights (may be empty)
  local M="$1" preserved="$2"
  local ntopics nconc surv weak fals inc nent
  ntopics=$(jq -r '.topics | length' <<<"$M")
  nent=$(jq -r '.entity_reuse | length' <<<"$M")
  nconc=$(jq -r '[.verdict_distribution | to_entries[] | .value] | add // 0' <<<"$M")
  surv=$(jq -r '.verdict_distribution.survived // 0' <<<"$M")
  weak=$(jq -r '.verdict_distribution.weakened // 0' <<<"$M")
  inc=$(jq -r '.verdict_distribution.inconclusive // 0' <<<"$M")
  fals=$(jq -r '.verdict_distribution.falsified // 0' <<<"$M")

  printf '# Corpus Atlas\n\n'
  printf '**Topics:** %s | **Findings:** %s (survived %s, weakened %s, inconclusive %s, falsified %s) | **Entities:** %s\n\n' \
    "$ntopics" "$nconc" "$surv" "$weak" "$inc" "$fals" "$nent"
  printf 'The cross-topic ontological spine as a single view: what the whole corpus knows, including what was disproven. Unlike a per-topic report (survivors only), this atlas keeps the entire research record.\n\n'
  printf -- '---\n\n'

  printf '%s\n\n' "$INSIGHTS_HDR"
  if [ -n "$preserved" ]; then
    printf '%s\n\n' "$preserved"
  else
    printf -- '- %s replaces this with cross-topic synthesis (entity reuse, converging vs. contradicting evidence, and what was disproven)._\n\n' "$DRAFT_MARK"
  fi

  printf '## Entity Reuse\n\n'
  if [ "$nent" -eq 0 ]; then
    printf 'No cross-topic entities yet.\n\n'
  else
    printf '| Entity | Type | Topics | Cross-topic | Degree |\n| --- | --- | --- | --- | --- |\n'
    jq -r --argjson n "$HIGHLIGHTS" '.entity_reuse[0:$n][] | "| \(.label) | \(.entityType // "—") | \((.topics | join(", "))) | \(.topic_count) | \(.degree) |"' <<<"$M"
    printf '\n'
  fi

  printf '## Contradictions\n\n'
  if [ "$(jq -r '.contradictions | length' <<<"$M")" -eq 0 ]; then
    printf 'No cross-topic contradictions recorded.\n\n'
  else
    jq -r '.contradictions[] | "- `\(.source)` —\(.type)→ `\(.target)`"' <<<"$M"
    printf '\n'
  fi

  printf '## What Was Disproven\n\n'
  if [ "$(jq -r '.disproven | length' <<<"$M")" -eq 0 ]; then
    printf 'No findings were falsified.\n\n'
  else
    jq -r '.disproven[] | "- \(.label) _(topics: \(.topics | join(", ")))_"' <<<"$M"
    printf '\n'
  fi

  printf '## Topics\n\n'
  if [ "$ntopics" -eq 0 ]; then printf -- '—\n'; else jq -r '.topics[] | "- " + .' <<<"$M"; fi
}

# ----- check gate --------------------------------------------------------------
run_check() {
  [ -f "$MAP_OUT" ] || { echo "FAIL: corpus-map missing: $MAP_OUT" >&2; return 1; }
  [ -f "$MD_OUT" ]  || { echo "FAIL: corpus-synthesis missing: $MD_OUT" >&2; return 1; }
  local errs=0 sec
  for sec in "$INSIGHTS_HDR" "## Entity Reuse" "## Contradictions" "## What Was Disproven" "## Topics"; do
    grep -qF "$sec" "$MD_OUT" || { echo "FAIL: missing section: $sec" >&2; errs=$((errs+1)); }
  done
  # Synthesis gate: the Insights must be AUTHORED, not the seeded draft.
  if extract_section "$INSIGHTS_HDR" "$MD_OUT" | grep -qF "$DRAFT_MARK"; then
    echo "FAIL: Cross-Corpus Insights are the draft — synthesis not applied (run the corpus-synthesizer)" >&2
    errs=$((errs+1))
  fi
  [ "$errs" -eq 0 ] || { echo "synthesize-corpus: $errs validation error(s)" >&2; return 1; }
  echo "OK: corpus atlas valid ($MD_OUT)"
}

if [ "$MODE" = "check" ]; then run_check; exit $?; fi

# ----- build -------------------------------------------------------------------
mkdir -p "$OUTDIR"
MAP=$(corpus_map) || die "failed to project corpus-map from $CONC"

# corpus-map.json — atomic, key-sorted for byte-determinism.
if printf '%s\n' "$MAP" | jq -S '.' > "$MAP_OUT.tmp.$$"; then
  mv "$MAP_OUT.tmp.$$" "$MAP_OUT"
else
  rm -f "$MAP_OUT.tmp.$$"; die "failed to write $MAP_OUT"
fi

# Preserve authored Insights across rebuilds (never preserve the draft).
PRESERVED=""
if [ -f "$MD_OUT" ]; then
  prev=$(extract_section "$INSIGHTS_HDR" "$MD_OUT")
  case "$prev" in *"$DRAFT_MARK"*) : ;; *) [ -n "$prev" ] && PRESERVED="$prev" ;; esac
fi

if build_md "$MAP" "$PRESERVED" > "$MD_OUT.tmp.$$"; then
  mv "$MD_OUT.tmp.$$" "$MD_OUT"
else
  rm -f "$MD_OUT.tmp.$$"; die "failed to write $MD_OUT"
fi

echo "synthesize-corpus: wrote $MAP_OUT and $MD_OUT ($(jq -r '.topics|length' <<<"$MAP") topics, $(jq -r '.entity_reuse|length' <<<"$MAP") entities)"
