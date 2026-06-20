#!/usr/bin/env bash
# validate-concordance.sh — fail-closed ontology conformance for the concordance (SPEC §8d).
# Asserts that every node entityType and every relationship edge type is declared by an
# ontology BOUND to the node's topic(s) (core mif-generic/mif-base ∪ the topic's bound
# ontologies), and that each relationship's endpoints satisfy the ontology's from/to
# domains. Any undeclared type or domain violation -> non-zero (fail-closed). Mention
# edges (via:entity) are structural and not domain-checked.
#
# Usage: validate-concordance.sh <concordance.json> [--config <p>] [--catalog <p>]

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for t in yq jq; do command -v "$t" >/dev/null 2>&1 || { echo "validate-concordance: '$t' not found" >&2; exit 5; }; done
GRAPH=""; CONFIG="$ROOT/harness.config.json"; CATALOG="$ROOT/.claude/enabled-packs.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --catalog) CATALOG="$2"; shift 2 ;;
    *) GRAPH="$1"; shift ;;
  esac
done
[ -n "$GRAPH" ] && [ -f "$GRAPH" ] || { echo "validate-concordance: concordance not found: ${GRAPH:-<none>}" >&2; exit 2; }
# Fail-safe: without the catalog OR the config we cannot determine bound ontologies — abort,
# never validate with an empty/unknowable binding set (which could pass a domain graph vacuously).
[ -f "$CATALOG" ] || { echo "validate-concordance: catalog missing ($CATALOG) — run sync-packs.sh; refusing to validate" >&2; exit 3; }
[ -f "$CONFIG" ]  || { echo "validate-concordance: config missing ($CONFIG) — topic bindings unknowable; refusing to validate" >&2; exit 3; }

src_of() { jq -r --arg id "$1" '.ontologies[]? | select(.id==$id) | .source' "$CATALOG" | head -1; }
core_ids=$(jq -r '.ontologies[]? | select(.core) | .id' "$CATALOG")

# Gather every relevant ontology's declared types + relationships into one JSON doc,
# and a topic -> allowed-ontology-ids map. Reading the YAML with yq (not in jq).
all_ids=$(
  { printf '%s\n' $core_ids
    jq -r '.topics[]?.ontologies[]?' "$CONFIG" 2>/dev/null | sed 's/@.*//'; } | sed '/^$/d' | sort -u)
ONTO='{}'
for oid in $all_ids; do
  src="$(src_of "$oid")"; [ -z "$src" ] && continue
  # yq only converts yaml->json; jq extracts the shape (robust against yq construction quirks).
  if ! ofull=$(yq -o=json '.' "$ROOT/$src" 2>/dev/null); then
    echo "validate-concordance: yq failed reading ontology '$oid' ($src) — aborting (fail closed)" >&2; exit 4
  fi
  od=$(jq -c '{types:[.entity_types[]?.name], rels:(.relationships // {})}' <<<"$ofull")
  ONTO=$(jq -c --arg id "$oid" --argjson d "$od" '. + {($id):$d}' <<<"$ONTO")
done
ALLOWED='{}'
for tp in $(jq -r '.topics[].id' "$CONFIG" 2>/dev/null); do
  ids=$( { printf '%s\n' $core_ids
           jq -r --arg t "$tp" '.topics[]? | select(.id==$t) | .ontologies[]?' "$CONFIG" 2>/dev/null | sed 's/@.*//'; } \
         | sed '/^$/d' | sort -u | jq -R . | jq -cs .)
  ALLOWED=$(jq -c --arg t "$tp" --argjson ids "$ids" '. + {($t):$ids}' <<<"$ALLOWED")
done
# MIF core vocabulary, always valid: the built-in entity types (the entity-reference
# enum, e.g. Concept/Person/Organization/Technology/File) and the STRUCTURAL relationship
# types declared by CORE ontologies (domain-agnostic links like supports/derived-from).
# Domain-ontology relationships are NOT in this set, so they still get from/to-enforced.
BUILTIN=$(jq -c '[.. | .enum? | select(.) | .[]] | map(select(type=="string" and test("^[A-Z]"))) | unique' \
            "$ROOT/schemas/mif/definitions/entity-reference.schema.json" 2>/dev/null); [ -z "$BUILTIN" ] && BUILTIN='[]'
core_arr=$(printf '%s\n' $core_ids | sed '/^$/d' | jq -R . | jq -cs .)
STRUCTURAL=$(jq -cn --argjson onto "$ONTO" --argjson core "$core_arr" '[ $core[] | ($onto[.].rels // {} | keys[]) ] | unique')

# All conformance logic in one jq (deterministic, portable).
if ! viol=$(jq -rn --slurpfile W "$GRAPH" --argjson onto "$ONTO" --argjson allowed "$ALLOWED" \
              --argjson builtin "$BUILTIN" --argjson structural "$STRUCTURAL" '
  $W[0] as $G
  | ($G.nodes | map({key:.id, value:.}) | from_entries) as $byid
  | def allowed_ids($topics): [ ($topics // [])[] | $allowed[.] // [] ] | add // [] | unique;
    ( [ $G.nodes[]
        | select(.entityType != null and (.external != true))
        | .entityType as $et
        | select( ( ($builtin | index($et)) or any(allowed_ids(.topics)[]; ($onto[.].types // []) | index($et)) ) | not )
        | "node \(.id) (topic: \((.topics // []) | join(","))): entityType \($et) not in MIF core nor declared by a bound ontology — fix: /ontology-review --topic \((.topics // [])[0] // "<id>") --enrich" ] )
  + ( [ $G.edges[] | select(.via == "relationship")
        | . as $e
        | ($byid[$e.source] // {}) as $s
        | ($byid[$e.target] // {}) as $t
        | if ($structural | index($e.type)) then empty            # MIF-native structural link: no domain check
          else
            ( [ allowed_ids($s.topics // [])[] | ($onto[.].rels[$e.type] // empty) ] ) as $rels
            | if ($rels | length) == 0
              then "edge \($e.source) ->\($e.type)-> \($e.target) (topic: \(($s.topics // []) | join(","))): relationship type not MIF-core nor declared by a bound ontology — fix: /ontology-review --topic \(($s.topics // [])[0] // "<id>") --enrich"
              elif any($rels[]; ((.from // []) | index($s.entityType)) and ((.to // []) | index($t.entityType)))
              then empty
              else "edge \($e.source) ->\($e.type)-> \($e.target): from/to domain violation (\($s.entityType // "null") -> \($t.entityType // "null"))"
              end
          end ] )
  | .[]'); then
  echo "validate-concordance: conformance check errored (jq) — aborting (fail closed)" >&2; exit 4
fi

if [ -z "$viol" ]; then
  echo "validate-concordance: conformant ($(jq '.nodes|length' "$GRAPH") nodes, $(jq '.edges|length' "$GRAPH") edges)"
  exit 0
fi
printf '%s\n' "$viol" >&2
echo "validate-concordance: $(printf '%s\n' "$viol" | grep -c .) conformance violation(s) — fail" >&2
# Only suggest /ontology-review when a violation is an undeclared TYPE (a binding gap the
# tool can fix). A from/to domain violation is a data/modeling issue — no footer for it.
if printf '%s\n' "$viol" | grep -q "/ontology-review"; then
  echo "validate-concordance: bind/enrich the named topic(s) with /ontology-review --topic <id> --enrich, then rebuild." >&2
fi
exit 1
