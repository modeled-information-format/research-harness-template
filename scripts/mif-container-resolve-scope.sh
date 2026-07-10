#!/usr/bin/env bash
# mif-container-resolve-scope.sh — the MIF Container export-scope resolver
# (Story #315, ADR-0017 AD-4: closure-first, marker-fallback).
#
# Consumes the knowledge graph scripts/build-graph.sh already produces
# (nodes[]/edges[] with via: "relationship"|"entity") rather than re-walking a
# finding's relationships[]/entities[] by hand: reusing the existing graph
# projection instead of inventing a second one, matching this repo's own
# "extends" precedent (ADR-0012) for reuse over parallel mechanisms. The
# graph's "entity" edges are the operationalization of ADR-0017's
# "ontology-map.json edges" language: ontology-map.json itself carries no
# target reference to walk (it is a per-finding type record, finding_id ->
# resolved_ontology, not a finding-to-finding/entity edge), but it is exactly
# what backs the entity typing behind each finding's entities[]/"mentions"
# edge -- so walking both graph edge kinds satisfies AD-4's "walk both edge
# sources" requirement without a second, redundant read of ontology-map.json.
#
# For every candidate finding already in scope, walks its outgoing edges (both
# via kinds -- Task #316) and classifies each target:
#   - already in scope -> nothing to do
#   - --closure requested AND target is an in-topic concept node -> included
#     transitively (closure takes precedence over marking, AD-4)
#   - otherwise -> an explicit boundaryReferences[] entry (Task #317, NFR-5/
#     NFR-6), never a silent drop. reason is "cross-topic" when the target's
#     concept namespace differs from the in-scope set's own namespace,
#     "unresolvable" when the target isn't a node in this graph at all
#     (a dangling reference), else "out-of-scope" (a real in-topic node --
#     concept or entity -- genuinely excluded from this subset).
#
# Usage:
#   mif-container-resolve-scope.sh <knowledge-graph.json> <in-scope-ids.json> [--closure]
#     <in-scope-ids.json>: a JSON array of urn:mif:concept:... ids (the
#     subset selector's initial match set).
#
# Prints a JSON object to stdout:
#   {"resourceIds": [<sorted, deduped, closure-expanded concept ids -- bare
#                     ids, NOT schemas/mif-container.schema.json's resources[]
#                     object shape; a caller materializes each id into a full
#                     {mifType,path,ontologyType,digest} entry separately>],
#    "boundaryReferences": [{"target": "...", "reason": "..."}]}
set -uo pipefail

[ "$#" -ge 2 ] || {
  echo "usage: mif-container-resolve-scope.sh <knowledge-graph.json> <in-scope-ids.json> [--closure]" >&2
  exit 2
}
GRAPH="$1"
IDS="$2"
CLOSURE=0
[ "${3:-}" = "--closure" ] && CLOSURE=1

[ -f "$GRAPH" ] || { echo "mif-container-resolve-scope: not a file: $GRAPH" >&2; exit 2; }
[ -f "$IDS" ] || { echo "mif-container-resolve-scope: not a file: $IDS" >&2; exit 2; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Read+validate the graph exactly once (not once per closure iteration, and
# not three separate times as the first version of this script did) into a
# compact temp copy every later jq call reads from. Fail closed here, loudly,
# on a missing/malformed .nodes[]/.edges[] -- rather than that malformed shape
# silently producing empty jq output deep inside the closure loop below, which
# previously hung forever: a failed jq call produced an empty $new_count, and
# comparing an empty string with -eq threw bash's "integer expression
# expected" on every single pass without ever breaking the loop, since the
# script runs under -uo pipefail, not -e.
jq -e '(.nodes | type == "array") and (.edges | type == "array")' "$GRAPH" > /dev/null 2>&1 || {
  echo "mif-container-resolve-scope: $GRAPH is not a valid graph (.nodes[]/.edges[] required)" >&2
  exit 2
}
jq -c '.' "$GRAPH" > "$T/graph.json"

jq -e 'type == "array"' "$IDS" > /dev/null 2>&1 || {
  echo "mif-container-resolve-scope: $IDS is not a JSON array" >&2
  exit 2
}
jq -c 'unique' "$IDS" > "$T/scope.json"

if [ "$CLOSURE" -eq 1 ]; then
  # Fixpoint BFS: repeatedly add any concept-kind edge target reachable from a
  # node already in scope, until a pass adds nothing new. Entity nodes are
  # never closure-included -- they are not a packageable resource mifType
  # (only finding/ontology-map/concordance are), so a mentions edge to an
  # entity always falls through to boundary-marking regardless of --closure.
  prev_count=0
  while :; do
    if ! jq -c -n --slurpfile graph "$T/graph.json" --slurpfile scope "$T/scope.json" '
      $graph[0] as $g | $scope[0] as $s
      | ($s + (
          $g.edges
          | map(select(.via == "relationship" and (.source as $x | $s | index($x)) and ((.target as $x | $s | index($x)) | not)))
          | map(.target)
          | map(select(. as $t | $g.nodes | any(.id == $t and .kind == "concept")))
        )) | unique
    ' > "$T/scope-next.json"; then
      echo "mif-container-resolve-scope: closure expansion failed on malformed graph/scope data" >&2
      exit 2
    fi
    new_count="$(jq 'length' "$T/scope-next.json")"
    mv "$T/scope-next.json" "$T/scope.json"
    [ "$new_count" -eq "$prev_count" ] && break
    prev_count="$new_count"
  done
fi

jq -c -n --slurpfile graph "$T/graph.json" --slurpfile scope "$T/scope.json" '
  $graph[0] as $g | $scope[0] as $s
  # Topic namespace: the first WELL-FORMED concept id anywhere in scope, not
  # just the first array element -- a single malformed leading element
  # previously poisoned every later same-topic classification to
  # "cross-topic" instead of "out-of-scope" (an empty-string sentinel from an
  # unmatched first element compared unequal to every real namespace). null
  # (not "") when no in-scope id is a well-formed concept id, so the
  # cross-topic branch below simply cannot fire on a false-positive mismatch.
  | ([$s[] | [scan("^urn:mif:concept:([^:]+):")] | if length > 0 then .[0][0] else empty end] | first // null) as $topic_ns
  | {
      resourceIds: ($s | unique | sort),
      boundaryReferences: (
        $g.edges
        | map(select((.source as $x | $s | index($x)) and ((.target as $x | $s | index($x)) | not)))
        | map(.target)
        | unique
        | map({
            target: .,
            reason: (
              . as $t
              # scan(), not capture(): capture() produces ZERO jq outputs (not
              # null) when the pattern does not match, which silently vanishes
              # the whole map() element for any concept-PREFIXED-but-malformed
              # id (e.g. "urn:mif:concept:noslug", no second colon) -- exactly
              # the silent-drop this script exists to prevent (Task #317).
              # scan() always yields a definite (possibly-empty) array.
              | ([$t | scan("^urn:mif:concept:([^:]+):")] | if length > 0 then .[0][0] else null end) as $t_ns
              | if ($t_ns != null) and ($t_ns != $topic_ns) then "cross-topic"
                elif ($g.nodes | any(.id == $t) | not) then "unresolvable"
                else "out-of-scope"
                end
            )
          })
      )
    }
'
