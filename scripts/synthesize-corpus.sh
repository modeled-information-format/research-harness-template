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
#
# Since research-harness-template#276 (Story #282, Category B cutover), the
# build path (the corpus-map projection and the corpus-synthesis.md render)
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it
# with scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
# The --check gate (pure file/section reads) never used jq and stays as-is.

set -uo pipefail
die() { echo "synthesize-corpus: $*" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

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

# Fail closed: the atlas is a projection of the spine; without a valid spine there is nothing
# to build (and never a vacuous/partial atlas). (Graph-validity itself is checked by the
# engine below, which refuses a concordance with no .nodes array.)
[ -s "$CONC" ] || die "concordance not found or empty: $CONC — build it first (scripts/build-concordance.sh)"

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

# Preserve authored Insights across rebuilds (never preserve the draft).
PRESERVED=""
if [ -f "$MD_OUT" ]; then
  prev=$(extract_section "$INSIGHTS_HDR" "$MD_OUT")
  case "$prev" in *"$DRAFT_MARK"*) : ;; *) [ -n "$prev" ] && PRESERVED="$prev" ;; esac
fi

exec "$ENGINE" harness synthesize-corpus "$CONC" "$MAP_OUT" "$MD_OUT" --preserved-insights "$PRESERVED"
