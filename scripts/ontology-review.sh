#!/usr/bin/env bash
# ontology-review.sh — review + validate ontology coverage across topics (SPEC §8c).
#
# For each topic, resolves every finding's ontology mapping (refreshing
# reports/<topic>/ontology-map.json via resolve-ontology.sh) and prints a coverage
# summary: typed (resolved + valid), untyped (no entity/ontology), and
# unresolved/invalid (a stamped type that does not resolve or whose entity fails the
# type schema). Read-only except the derived ontology-map.json. This is the
# deterministic engine behind the /ontology-review tool; the tool adds the agent
# enrichment (bind an ontology to an unbound topic, retro-classify untyped findings).
#
# Usage: ontology-review.sh [--topic <id>] [--strict] [--reports-dir <p>]
#                           [--config <p>] [--catalog <p>]
#   exit 0 = reviewed; with --strict, non-zero if any finding is unresolved/invalid.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/harness.config.json"
CATALOG="$ROOT/.claude/enabled-packs.json"
RD="$ROOT/reports"
ONE_TOPIC=""; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --topic) ONE_TOPIC="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --reports-dir) RD="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    *) echo "ontology-review: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -f "$CONFIG" ] || { echo "ontology-review: config not found: $CONFIG" >&2; exit 2; }

# A catalog is required to resolve anything; if absent, run sync-packs first.
if [ ! -f "$CATALOG" ]; then
  echo "ontology-review: catalog missing — running sync-packs.sh first" >&2
  scripts/sync-packs.sh >/dev/null 2>&1 || { echo "ontology-review: sync-packs failed" >&2; exit 3; }
fi

if [ -n "$ONE_TOPIC" ]; then topics="$ONE_TOPIC"; else topics=$(jq -r '.topics[].id' "$CONFIG"); fi

g_total=0 g_typed=0 g_untyped=0 g_bad=0 g_topics=0 any_bad=0
printf '%-28s %-22s %6s %6s %8s %9s\n' "TOPIC" "BOUND" "FIND" "TYPED" "UNTYPED" "INVALID"
for topic in $topics; do
  fdir="$RD/$topic/findings"
  [ -d "$fdir" ] || continue
  g_topics=$((g_topics+1))
  map="$RD/$topic/ontology-map.json"
  bound=$(jq -r --arg t "$topic" '.topics[]|select(.id==$t)|.ontologies // [] | join(",")' "$CONFIG"); [ -z "$bound" ] && bound="(core-only)"
  rm -f "$map"   # rebuild deterministically from disk
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    scripts/resolve-ontology.sh "$f" --topic "$topic" --catalog "$CATALOG" --config "$CONFIG" --map "$map" >/dev/null 2>&1 || true
  done < <(find "$fdir" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp' 2>/dev/null | sort)

  local_total=0; typed=0; untyped=0; bad=0
  if [ -f "$map" ]; then
    local_total=$(jq 'length' "$map")
    typed=$(jq '[.[] | select(.resolved_ontology != null and .valid)] | length' "$map")
    untyped=$(jq '[.[] | select(.basis == "untyped")] | length' "$map")
    bad=$(jq '[.[] | select(.valid == false)] | length' "$map")
  fi
  [ "$bad" -gt 0 ] && any_bad=1
  printf '%-28s %-22s %6s %6s %8s %9s\n' "$topic" "$(printf '%s' "$bound" | cut -c1-22)" "$local_total" "$typed" "$untyped" "$bad"
  g_total=$((g_total+local_total)); g_typed=$((g_typed+typed)); g_untyped=$((g_untyped+untyped)); g_bad=$((g_bad+bad))
done
echo "---"
printf 'ontology-review: %d topic(s); %d findings — %d typed, %d untyped, %d invalid/unresolved\n' \
  "$g_topics" "$g_total" "$g_typed" "$g_untyped" "$g_bad"

if [ "$STRICT" = 1 ] && [ "$any_bad" = 1 ]; then
  echo "ontology-review: --strict and $g_bad finding(s) have an invalid/unresolved mapping — failing" >&2
  exit 1
fi
exit 0
