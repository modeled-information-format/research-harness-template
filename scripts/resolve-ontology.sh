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
# Classification (which type a finding resembles) is an upstream agent step that
# stamps entity.entity_type; this script only resolves + validates + records.
#
# Usage: resolve-ontology.sh <finding.json> [--topic <id>] [--catalog <p>] [--config <p>]
#   exit 0 = resolved or untyped; non-zero = unresolvable / invalid / environment broken.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

fid=$(jq -r '."@id" // .id // empty' "$FINDING" 2>/dev/null); [ -z "$fid" ] && fid="$(basename "$FINDING")"
et=$(jq -r '.entity.entity_type // empty' "$FINDING" 2>/dev/null)
oid=$(jq -r '.ontology.id // empty' "$FINDING" 2>/dev/null)

# Determine the topic (flag, else the reports/<topic>/ path).
if [ -z "$TOPIC" ]; then
  case "$FINDING" in
    *reports/*) TOPIC=$(printf '%s' "$FINDING" | sed -E 's#.*reports/([^/]+)/.*#\1#') ;;
  esac
fi

# Upsert one record into reports/<topic>/ontology-map.json (deterministic: sorted by
# finding_id, no timestamps). Caller passes the absolute map path via env or we derive.
record() { # entity_type resolved_ontology basis valid
  local et_="$1" ro="$2" basis="$3" valid="$4"
  local map="$MAP"
  if [ -z "$map" ]; then
    [ -z "$TOPIC" ] && return 0                 # nowhere to record (ad-hoc invocation)
    [ -d "$ROOT/reports/$TOPIC" ] || return 0
    map="$ROOT/reports/$TOPIC/ontology-map.json"
  fi
  local cur='[]'; [ -f "$map" ] && cur=$(cat "$map")
  printf '%s' "$cur" | jq -S --arg f "$fid" --arg et "$et_" --arg ro "$ro" --arg b "$basis" --argjson v "$valid" \
    '[ .[] | select(.finding_id != $f) ]
     + [{finding_id:$f, entity_type:(if $et=="" then null else $et end),
         resolved_ontology:(if $ro=="" then null else $ro end), basis:$b, valid:$v}]
     | sort_by(.finding_id)' > "$map.tmp" && mv "$map.tmp" "$map"
}

# 1. Untyped finding -> nothing to resolve.
if [ -z "$et" ] && [ -z "$oid" ]; then
  record "" "" "untyped" true
  echo "resolve-ontology: $fid is untyped (no entity/ontology) — ok"
  exit 0
fi

# 2. The catalog is the source of truth for what is enabled/registered. Its absence
#    means we cannot determine the bound set — fail closed, never pass vacuously.
[ -f "$CATALOG" ] || { echo "resolve-ontology: catalog missing ($CATALOG) — run sync-packs.sh; refusing to resolve" >&2; exit 3; }

# 3. Build the topic's BOUND set: core (always) + this topic's bound ids (each of
#    which MUST be cataloged/enabled). An explicit binding to a non-cataloged id fails.
# Portable (bash 3.2 — no associative arrays): resolve an ontology id to its
# cataloged source path. Empty result = not cataloged/enabled.
src_of() { jq -r --arg id "$1" '.ontologies[]? | select(.id==$id) | .source' "$CATALOG" | head -1; }

core_ids=$(jq -r '.ontologies[]? | select(.core) | .id' "$CATALOG")
allowed=""
for c in $core_ids; do allowed="$allowed $c"; done
if [ -n "$TOPIC" ]; then
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    bid="${b%@*}"
    if [ -z "$(src_of "$bid")" ]; then
      echo "resolve-ontology: topic '$TOPIC' binds '$bid' which is not enabled/cataloged — fail" >&2
      record "$et" "" "unresolved" false; exit 1
    fi
    allowed="$allowed $bid"
  done < <(jq -r --arg t "$TOPIC" '.topics[]? | select(.id==$t) | .ontologies[]?' "$CONFIG")
fi

# 4. Resolve entity_type against the allowed ontologies' declared entity_types.
matches=""
for aid in $allowed; do
  src="$(src_of "$aid")"; [ -z "$src" ] && continue
  if yq -r '.entity_types[].name' "$ROOT/$src" 2>/dev/null | grep -qx "$et"; then
    matches="$matches $aid"
  fi
done
matches=$(printf '%s' "$matches" | tr ' ' '\n' | sed '/^$/d' | sort -u)
mcount=$(printf '%s\n' "$matches" | grep -c . || true)

resolved=""
if [ "$mcount" -eq 0 ]; then
  echo "resolve-ontology: entity_type '$et' is declared by no ontology bound to topic '$TOPIC' — fail" >&2
  record "$et" "" "unresolved" false; exit 1
elif [ "$mcount" -eq 1 ]; then
  resolved=$(printf '%s' "$matches")
  basis="resolved"
  if [ -n "$oid" ]; then
    [ "$oid" = "$resolved" ] || { echo "resolve-ontology: declared ontology.id '$oid' is not bound / does not declare '$et' — fail" >&2; record "$et" "" "unresolved" false; exit 1; }
    basis="declared"
  fi
else
  # ambiguous: require an explicit ontology.id within the matches
  [ -n "$oid" ] || { echo "resolve-ontology: entity_type '$et' is ambiguous across [$(echo $matches)]; needs explicit ontology.id — fail" >&2; record "$et" "" "ambiguous" false; exit 1; }
  printf '%s\n' "$matches" | grep -qx "$oid" || { echo "resolve-ontology: declared ontology.id '$oid' not among bound declarers of '$et' — fail" >&2; record "$et" "" "ambiguous" false; exit 1; }
  resolved="$oid"; basis="declared"
fi

rsrc="$(src_of "$resolved")"
ver=$(yq -r '.ontology.version' "$ROOT/$rsrc" 2>/dev/null)

# 5. Validate the finding's entity against the resolved type's schema (additive).
type_schema=$(yq -o=json '.entity_types[] | select(.name == "'"$et"'") | .schema' "$ROOT/$rsrc" 2>/dev/null \
  | jq '{type:"object", required:(.required // []), properties:(.properties // {}), additionalProperties:true}')
entity=$(jq -c '.entity' "$FINDING")
echo "$type_schema" > /tmp/ro-schema.$$.json
echo "$entity" > /tmp/ro-entity.$$.json
if ajv validate --spec=draft2020 --strict=false -c ajv-formats -s /tmp/ro-schema.$$.json -d /tmp/ro-entity.$$.json >/dev/null 2>&1; then
  rm -f /tmp/ro-schema.$$.json /tmp/ro-entity.$$.json
  record "$et" "$resolved@$ver" "$basis" true
  echo "resolve-ontology: $fid -> $resolved@$ver:$et ($basis) — valid"
  exit 0
else
  rm -f /tmp/ro-schema.$$.json /tmp/ro-entity.$$.json
  record "$et" "$resolved@$ver" "$basis" false
  echo "resolve-ontology: $fid entity fails $resolved:$et schema (required field missing) — fail" >&2
  exit 1
fi
