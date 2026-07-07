#!/usr/bin/env bash
# build-graph.sh — build the first-class knowledge graph from the MIF substrate
# (SPEC §6c, §4a). The graph is derived from MIF EntityReferences and typed
# relationships, NOT from tag co-occurrence (the prior system's bolt-on). Every
# node and edge traces to a urn:mif: id.
#
#   nodes: one per finding concept (@id) and one per referenced MIF entity
#          (entities[].entity.@id), deduplicated.
#   edges: typed relationships[] (source concept -> target, by relationship type)
#          plus "mentions" edges from a finding to each entity it references.
#
# Since research-harness-template#276 (Story #293, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: build-graph.sh <findings-dir> [<out.json>]
#        default out: <findings-dir>/../knowledge-graph.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

DIR="${1:?usage: build-graph.sh <findings-dir> [out.json]}"
[ -d "$DIR" ] || { echo "build-graph: not a directory: $DIR" >&2; exit 2; }

if [ -n "${2:-}" ]; then
  exec "$ENGINE" harness build-graph "$DIR" "$2"
fi
exec "$ENGINE" harness build-graph "$DIR"
