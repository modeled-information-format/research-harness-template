#!/usr/bin/env bash
# build-world.sh — the ontological spine: ONE unified, cross-topic "world graph"
# (SPEC §8d). Merges every topic's findings into a single MIF-native graph typed by
# the ontology: concept nodes (one per finding) stamped with their resolved ontology
# entity_type (from reports/<topic>/ontology-map.json) AND falsification verdict;
# entity nodes merged across topics by urn:mif: @id (one node spanning every topic
# that references it). ALL findings are nodes; falsified are FLAGGED, not excluded.
# Deterministic/idempotent (sorted, no wall-clock) — "living" = on-demand rebuild.
#
# Usage: build-world.sh [<reports-dir>] [<out.json>]
#   default reports-dir: reports/ ; default out: <reports-dir>/world.json

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RD="${1:-$ROOT/reports}"; case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
OUT="${2:-$RD/world.json}"
[ -d "$RD" ] || { echo "build-world: reports dir not found: $RD" >&2; exit 2; }

# Topics are the subdirectories of the reports dir that hold a findings/ — build
# whatever corpus is actually present (independent of harness.config.json, so the
# graph reflects the given reports tree, never a stale or vacuous topic list).
concepts='[]'; entities='[]'; edges='[]'
for fdir in "$RD"/*/findings; do
  [ -d "$fdir" ] || continue
  topic="$(basename "$(dirname "$fdir")")"
  files=$(find "$fdir" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp' 2>/dev/null | sort)
  [ -z "$files" ] && continue
  mapdoc='[]'; [ -f "$RD/$topic/ontology-map.json" ] && mapdoc=$(cat "$RD/$topic/ontology-map.json")

  # Concept nodes: one per finding, joined to its ontology-map entry by @id; carries
  # the resolved ontology entity_type, the source ontology, and the verdict.
  c=$(jq -s --arg t "$topic" --argjson map "$mapdoc" '
    map( ."@id" as $fid
       | (.extensions.harness.verification.verdict // null) as $v
       | ($map[] | select(.finding_id == $fid)) as $om
       | { id:$fid, kind:"concept", label:(.title // $fid), topics:[$t],
           entityType:($om.entity_type // .entity.entity_type // null),
           ontology:($om.resolved_ontology // null),
           verdict:$v, flagged:($v == "falsified") } )' $files)

  # Entity nodes: one per referenced MIF entity (merged later across topics by @id).
  e=$(jq -s --arg t "$topic" '[ .[] | (.entities // [])[]
        | { id:.entity["@id"], kind:"entity", label:(.name // .entity["@id"]),
            entityType:(.entityType // null), topics:[$t], flagged:false } ]' $files)

  # Edges: typed relationships[] + mention edges (finding -> referenced entity).
  g=$(jq -s '
      ( [ .[] | ."@id" as $s | (.relationships // [])[]
          | { source:$s, target:.target, type:.type, strength:(.strength // null), via:"relationship" } ] )
    + ( [ .[] | ."@id" as $s | (.entities // [])[]
          | { source:$s, target:.entity["@id"], type:"mentions", strength:null, via:"entity" } ] )' $files)

  concepts=$(jq -cn --argjson a "$concepts" --argjson b "$c" '$a + $b')
  entities=$(jq -cn --argjson a "$entities" --argjson b "$e" '$a + $b')
  edges=$(jq -cn --argjson a "$edges" --argjson b "$g" '$a + $b')
done

# Merge by @id (entities and concepts), union topics; dedup edges; materialize external
# stubs for unresolved targets; sort everything for byte-determinism.
jq -n --argjson concepts "$concepts" --argjson entities "$entities" --argjson edges "$edges" '
  ($concepts | group_by(.id) | map(.[0] + {topics:([.[].topics[]] | unique)})) as $con
  | ($entities | group_by(.id) | map(.[0] + {topics:([.[].topics[]] | unique)})) as $ent
  | ($con + $ent) as $known
  | ($known | map(.id)) as $ids
  | ($edges | unique) as $ed
  | ( $ed | map(.target) | unique | map(select(. as $t | ($ids | index($t)) | not))
      | map({ id:., kind:"concept", label:., topics:[], entityType:null,
              ontology:null, verdict:null, flagged:false, external:true }) ) as $stubs
  | { "@type":"WorldGraph",
      generator:"build-world.sh (MIF-native ontological spine; SPEC §8d)",
      nodes: (($known + $stubs) | sort_by(.id)),
      edges: ($ed | sort_by(.source, .target, .type, .via)) }' > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

echo "build-world: wrote $OUT ($(jq '.nodes|length' "$OUT") nodes, $(jq '.edges|length' "$OUT") edges) across topics"
