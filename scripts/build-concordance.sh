#!/usr/bin/env bash
# build-concordance.sh — the ontological spine: ONE unified, cross-topic "concordance"
# (SPEC §8d). Merges every topic's findings into a single MIF-native graph typed by
# the ontology: concept nodes (one per finding) stamped with their resolved ontology
# entity_type (from reports/<topic>/ontology-map.json) AND falsification verdict;
# entity nodes merged across topics by urn:mif: @id (one node spanning every topic
# that references it). ALL findings are nodes; falsified are FLAGGED, not excluded.
# Deterministic/idempotent (sorted, no wall-clock) — "living" = on-demand rebuild.
#
# Usage: build-concordance.sh [<reports-dir>] [<out.json>]
#   default reports-dir: reports/ ; default out: <reports-dir>/concordance.json

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RD="${1:-$ROOT/reports}"; case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
OUT="${2:-$RD/concordance.json}"
[ -d "$RD" ] || { echo "build-concordance: reports dir not found: $RD" >&2; exit 2; }

# Topics are the subdirectories of the reports dir that hold a findings/ — build
# whatever corpus is actually present (independent of harness.config.json, so the
# graph reflects the given reports tree, never a stale or vacuous topic list).
# Accumulate nodes/edges as JSONL in temp files (one object per line), merged with
# --slurpfile. The old per-iteration `jq --argjson "$concepts"` re-serialized the whole
# growing graph through argv and overflowed ARG_MAX on a large corpus; streaming to files
# removes that. Per-topic findings are likewise read via `find -exec cat` (file list kept
# off argv), so no path in this build is bounded by ARG_MAX.
CFILE=$(mktemp); EFILE=$(mktemp); GFILE=$(mktemp)
trap 'rm -f "$CFILE" "$EFILE" "$GFILE" "$OUT.tmp"' EXIT
for fdir in "$RD"/*/findings; do
  [ -d "$fdir" ] || continue
  topic="$(basename "$(dirname "$fdir")")"
  # Stream this topic's findings into a temp via `find -exec cat` so the file list never
  # lands on argv (a topic with very many findings can't hit ARG_MAX either).
  tf=$(mktemp)
  find "$fdir" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp' -exec cat {} + > "$tf" 2>/dev/null
  if [ ! -s "$tf" ]; then rm -f "$tf"; continue; fi
  mapdoc='[]'; [ -f "$RD/$topic/ontology-map.json" ] && mapdoc=$(cat "$RD/$topic/ontology-map.json")

  # Concept nodes: one per finding, joined to its ontology-map entry by @id; carries the
  # resolved ontology entity_type, source ontology, and verdict. Fail CLOSED (exit) on a
  # malformed finding so a parse error can't silently drop the topic.
  c=$(jq -s --arg t "$topic" --argjson map "$mapdoc" '
    map( ."@id" as $fid
       | (.extensions.harness.verification.verdict // null) as $v
       | (first($map[] | select(.finding_id == $fid)) // {}) as $om
       | { id:$fid, kind:"concept", label:(.title // $fid), topics:[$t],
           entityType:($om.entity_type // .entity.entity_type // null),
           ontology:($om.resolved_ontology // null),
           verdict:$v, flagged:($v == "falsified") } )' "$tf") \
    || { echo "build-concordance: jq failed on topic '$topic' (concepts) — corrupt finding?" >&2; rm -f "$tf"; exit 1; }

  # Entity nodes: one per referenced MIF entity (merged later across topics by @id).
  e=$(jq -s --arg t "$topic" '[ .[] | (.entities // [])[]
        | { id:.entity["@id"], kind:"entity", label:(.name // .entity["@id"]),
            entityType:(.entityType // null), topics:[$t], flagged:false } ]' "$tf") \
    || { echo "build-concordance: jq failed on topic '$topic' (entities)" >&2; rm -f "$tf"; exit 1; }

  # Edges: typed relationships[] + mention edges (finding -> referenced entity).
  g=$(jq -s '
      ( [ .[] | ."@id" as $s | (.relationships // [])[]
          | { source:$s, target:(if (.target|type)=="object" then .target."@id" else .target end), type:(.type // .relationshipType), strength:(.strength // null), via:"relationship" } ] )
    + ( [ .[] | ."@id" as $s | (.entities // [])[]
          | { source:$s, target:.entity["@id"], type:"mentions", strength:null, via:"entity" } ] )' "$tf") \
    || { echo "build-concordance: jq failed on topic '$topic' (edges)" >&2; rm -f "$tf"; exit 1; }
  rm -f "$tf"

  # Append as JSONL; abort on error so a bad parse can't write a partial graph.
  jq -c '.[]' <<<"$c" >> "$CFILE" || { echo "build-concordance: append failed (concepts)" >&2; exit 1; }
  jq -c '.[]' <<<"$e" >> "$EFILE" || { echo "build-concordance: append failed (entities)" >&2; exit 1; }
  jq -c '.[]' <<<"$g" >> "$GFILE" || { echo "build-concordance: append failed (edges)" >&2; exit 1; }
done

# Merge by @id (entities and concepts), union topics; dedup edges; materialize external
# stubs for unresolved targets; sort everything for byte-determinism. The accumulated
# nodes/edges are read via --slurpfile (from disk, not argv) so corpus size is unbounded
# by ARG_MAX; an empty file slurps to [] (same as the old empty-array seed).
jq -n --slurpfile concepts "$CFILE" --slurpfile entities "$EFILE" --slurpfile edges "$GFILE" '
  ($concepts | group_by(.id) | map(.[0] + {topics:([.[].topics[]] | unique)})) as $con
  | ($entities | group_by(.id) | map(.[0] + {topics:([.[].topics[]] | unique)})) as $ent
  | ($con + $ent) as $known
  | ($known | map(.id)) as $ids
  | ($edges | unique) as $ed
  | ( $ed | map(.target) | unique | map(select(. as $t | ($ids | index($t)) | not))
      | map({ id:., kind:"concept", label:., topics:[], entityType:null,
              ontology:null, verdict:null, flagged:false, external:true }) ) as $stubs
  | { "@type":"Concordance",
      generator:"build-concordance.sh (MIF-native ontological spine; SPEC §8d)",
      nodes: (($known + $stubs) | sort_by(.id)),
      edges: ($ed | sort_by(.source, .target, .type, .via)) }' > "$OUT.tmp" \
  || { echo "build-concordance: merge failed (jq)" >&2; exit 1; }
mv "$OUT.tmp" "$OUT"

echo "build-concordance: wrote $OUT ($(jq '.nodes|length' "$OUT") nodes, $(jq '.edges|length' "$OUT") edges) across topics"
