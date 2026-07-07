#!/usr/bin/env bash
# validate-concordance.sh — fail-closed ontology conformance for the concordance (SPEC §8d).
# Asserts that every node entityType and every relationship edge type is declared by an
# ontology BOUND to the node's topic(s) (core mif-generic/mif-base ∪ the topic's bound
# ontologies), and that each relationship's endpoints satisfy the ontology's from/to
# domains. Any undeclared type or domain violation -> non-zero (fail-closed). Mention
# edges (via:entity) are structural and not domain-checked.
#
# Usage: validate-concordance.sh <concordance.json> [--config <p>] [--catalog <p>]
#
# Since research-harness-template#276 (Story #287, Category B cutover), the
# ontology extends-chain resolution, subtype_of transitive closure, and the
# node/edge conformance pass delegate to the mif-rh engine (mif-rh-cli), hard
# required: install it with scripts/fetch-engine.sh, put mif-rh-cli on PATH,
# or set MIF_RH_CLI. The concordance-file existence check (pure bash, never
# used jq) stays as-is.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRAPH=""; CONFIG="$ROOT/harness.config.json"; CATALOG="$ROOT/.claude/enabled-packs.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    *) GRAPH="$1"; shift ;;
  esac
done
[ -n "$GRAPH" ] && [ -f "$GRAPH" ] || { echo "validate-concordance: concordance not found: ${GRAPH:-<none>}" >&2; exit 2; }

# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" harness validate-concordance "$GRAPH" --config "$CONFIG" --catalog "$CATALOG" --root "$ROOT"
