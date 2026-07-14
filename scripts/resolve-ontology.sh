#!/usr/bin/env bash
# resolve-ontology.sh — topical ontology resolution for one MIF finding (SPEC §8c).
#
# Reviews a produced finding, resolves which ontological mapping it receives WITHIN
# its topic's bound (enabled) ontologies, validates the finding's `entity` against
# the resolved entity_type's schema (additive), and upserts the mapping into
# reports/<topic>/ontology-map.json. Deterministic and fail-closed:
#   - a finding with no entity/ontology is UNTYPED -> exit 0, recorded as such;
#   - a typed finding whose entity_type no bound ontology declares -> non-zero;
#   - an ambiguous type (declared by >1 bound ontology) without an explicit
#     ontology.id -> non-zero; an ontology.id outside the topic's bound set -> non-zero;
#   - an entity failing the resolved type's required fields -> non-zero.
# An UNTYPED finding falls back to deterministic classification from the bound
# domain ontologies' OWN discovery patterns before being recorded untyped.
#
# Since ADR-0016 this script delegates to the mif-rh engine (mif-rh-cli),
# whose byte-level output and exit-code parity with the retired bash
# implementation is enforced fail-closed in mif-rs CI. The engine is hard
# required: install it with scripts/fetch-engine.sh, put mif-rh-cli on
# PATH, or set MIF_RH_CLI.
#
# Usage: resolve-ontology.sh <finding.json> [--topic <id>] [--catalog <p>]
#                            [--config <p>] [--map <p>]
#   exit 0 = resolved or untyped; non-zero = unresolvable / invalid / environment broken.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

CATALOG="$ROOT/.claude/enabled-packs.json"
CONFIG="$ROOT/harness.config.json"
FINDING=""; TOPIC=""; MAP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --topic) TOPIC="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    --config) CONFIG="$2"; shift 2 ;;
    --map) MAP="$2"; shift 2 ;;
    *) FINDING="$1"; shift ;;
  esac
done
[ -n "$FINDING" ] && [ -f "$FINDING" ] || { echo "resolve-ontology: finding not found: ${FINDING:-<none>}" >&2; exit 2; }

args=("$FINDING" --catalog "$CATALOG" --config "$CONFIG" --root "$ROOT")
[ -n "$TOPIC" ] && args+=(--topic "$TOPIC")
[ -n "$MAP" ] && args+=(--map "$MAP")
exec "$ENGINE" resolve "${args[@]+"${args[@]}"}"
