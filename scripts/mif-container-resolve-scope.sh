#!/usr/bin/env bash
# mif-container-resolve-scope.sh — the MIF Container export-scope resolver
# (Story #315, ADR-0017 AD-4: closure-first, marker-fallback).
#
# Consumes the knowledge graph scripts/build-graph.sh already produces
# (nodes[]/edges[] with via: "relationship"|"entity" -- the same relationships[]
# and entity-mention edges ADR-0017 describes) rather than re-walking a
# finding's relationships[]/entities[] by hand: reusing the existing graph
# projection instead of inventing a second one, matching this repo's own
# "extends" precedent (ADR-0012) for reuse over parallel mechanisms.
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
#   {"resources": [<sorted, closure-expanded concept ids>],
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

jq -c '.' "$IDS" > "$T/scope.json"

if [ "$CLOSURE" -eq 1 ]; then
  # Fixpoint BFS: repeatedly add any concept-kind edge target reachable from a
  # node already in scope, until a pass adds nothing new. Entity nodes are
  # never closure-included -- they are not a packageable resource mifType
  # (only finding/ontology-map/concordance are), so a mentions edge to an
  # entity always falls through to boundary-marking regardless of --closure.
  prev_count=0
  while :; do
    jq -c --slurpfile scope "$T/scope.json" '
      ($scope[0]) as $s
      | .edges
      | map(select(.via == "relationship" and (.source as $x | $s | index($x)) and ((.target as $x | $s | index($x)) | not)))
      | map(.target)
    ' "$GRAPH" > "$T/new-targets.json"
    jq -sc '
      .[0] as $graph
      | .[1] as $scope
      | .[2] as $new
      | ($scope + ($new | map(select(. as $t | $graph.nodes | any(.id == $t and .kind == "concept"))))) | unique
    ' <(jq -c '.' "$GRAPH") "$T/scope.json" "$T/new-targets.json" > "$T/scope-next.json"
    new_count="$(jq 'length' "$T/scope-next.json")"
    mv "$T/scope-next.json" "$T/scope.json"
    [ "$new_count" -eq "$prev_count" ] && break
    prev_count="$new_count"
  done
fi

jq -sc '
  .[0] as $graph
  | .[1] as $scope
  | ($scope[0] // "" | capture("^urn:mif:concept:(?<ns>[^:]+):") .ns // "") as $topic_ns
  | {
      resources: ($scope | sort),
      boundaryReferences: (
        $graph.edges
        | map(select((.source as $x | $scope | index($x)) and ((.target as $x | $scope | index($x)) | not)))
        | map(.target)
        | unique
        | map({
            target: .,
            reason: (
              . as $t
              # Namespace check first, before node-presence: build-graph.sh only
              # ever sees one topic worth of findings, so a genuine cross-topic
              # concept id can NEVER appear as a node in this graph -- checking
              # presence first would misclassify every cross-topic reference as
              # "unresolvable" instead, since it is structurally always absent.
              | if ($t | test("^urn:mif:concept:")) and (($t | capture("^urn:mif:concept:(?<ns>[^:]+):") .ns) != $topic_ns) then "cross-topic"
                elif ($graph.nodes | any(.id == $t) | not) then "unresolvable"
                else "out-of-scope"
                end
            )
          })
      )
    }
' <(jq -c '.' "$GRAPH") "$T/scope.json"
