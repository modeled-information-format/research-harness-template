#!/usr/bin/env bash
# assert-graph-mif.sh — prove the knowledge graph is built from MIF entities and
# relations, not tags (Milestone 4 acceptance gate). Asserts:
#   1. every node id is a urn:mif: identifier;
#   2. every edge source is a urn:mif: concept and every edge target is a urn:mif: id;
#   3. at least one edge derives from a typed MIF relationship (via=relationship)
#      and at least one entity node exists (via=entity) — i.e. the graph uses the
#      MIF substrate, not tag co-occurrence;
#   4. no node or edge carries a tag-derived id (a bare tag string).
#
# Usage: assert-graph-mif.sh <knowledge-graph.json>
#
# Since research-harness-template#276 (Story #287, Category B cutover), the
# assertion checks delegate to the mif-rh engine (mif-rh-cli), hard required:
# install it with scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set
# MIF_RH_CLI. Argument/file-existence validation (pure bash, never used jq)
# stays as-is.

set -uo pipefail
G="${1:?usage: assert-graph-mif.sh <knowledge-graph.json>}"
[ -f "$G" ] || { echo "assert-graph: not found: $G" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" harness assert-graph-mif "$G"
