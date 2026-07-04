#!/usr/bin/env bash
# sync-registry-ontologies.sh — eval for scripts/sync-registry-ontologies.sh.
# Builds a throwaway harness root + a fixture registry in a temp dir, then
# asserts the discovery contract WITHOUT touching the real tree:
#   1. an ontology already known to harness.config.json is left untouched
#      (no duplicate entry)
#   2. an ontology present in the registry but absent from harness.config.json
#      entirely is discovered, added with enabled: true, then vendored and
#      cataloged
#   3. running it again is idempotent (no duplicate entries, no re-fetch churn)
#   4. a registry id satisfied by a committed base layer under
#      schemas/ontologies/ is never added to harness.config.json's
#      ontologies[] — check-pack-docs.py treats every id there as a
#      component requiring its own doc section, so toggling a base layer
#      would spuriously demand doc coverage for infrastructure this harness
#      never curates per-instance
#
# Exit 0 = discovery contract holds. Exit 1 = a check failed.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # real repo root (source of scripts)
SHA="sha256sum"; command -v sha256sum >/dev/null || SHA="shasum -a 256"
sha_of() { $SHA "$1" | awk '{print $1}'; }
fail=0; note() { printf '  sync-registry: %s\n' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/.claude" "$TMP/packs/ontologies" "$TMP/schemas/ontologies/mif-base" "$TMP/registry"
cp "$SELF_DIR/scripts/sync-registry-ontologies.sh" "$SELF_DIR/scripts/fetch-ontology.sh" \
   "$SELF_DIR/scripts/sync-packs.sh" "$TMP/scripts/"
printf '{"ontologies":[{"id":"known-onto","enabled":true}],"topics":[]}\n' > "$TMP/harness.config.json"

fixture_onto() { # id
  cat > "$TMP/registry/$1.ontology.yaml" <<YAML
---
ontology:
  id: $1
  version: "0.1.0"
  description: "eval fixture ontology"
entity_types:
  - name: widget
    description: "a fixture type"
    base: semantic
    schema: { required: [], properties: {} }
    disposition: mint
YAML
}
fixture_onto known-onto
fixture_onto new-onto
fixture_onto mif-base
known_sha="$(sha_of "$TMP/registry/known-onto.ontology.yaml")"
new_sha="$(sha_of "$TMP/registry/new-onto.ontology.yaml")"
base_sha="$(sha_of "$TMP/registry/mif-base.ontology.yaml")"
cat > "$TMP/registry/index.json" <<JSON
{"schema":"mif-ontology-index/v1","source":"fixture",
 "ontologies":{
   "known-onto":{"version":"0.1.0","file":"known-onto.ontology.yaml","sha256":"$known_sha","extends":[]},
   "new-onto":{"version":"0.1.0","file":"new-onto.ontology.yaml","sha256":"$new_sha","extends":[]},
   "mif-base":{"version":"0.1.0","file":"mif-base.ontology.yaml","sha256":"$base_sha","extends":[]}
 }}
JSON

run_sync() { ( cd "$TMP" && MIF_ONTOLOGY_SOURCE="$TMP/registry" bash scripts/sync-registry-ontologies.sh ); }

# 1+2. first run: known-onto stays a single entry; new-onto is discovered,
#      added enabled, vendored, and cataloged.
if run_sync >/dev/null 2>&1 \
   && [ "$(jq '[.ontologies[] | select(.id=="known-onto")] | length' "$TMP/harness.config.json")" = 1 ] \
   && [ "$(jq -r '.ontologies[] | select(.id=="new-onto") | .enabled' "$TMP/harness.config.json")" = "true" ] \
   && [ -f "$TMP/packs/ontologies/new-onto/new-onto.ontology.yaml" ] \
   && [ "$(jq -r '.ontologies[] | select(.id=="new-onto") | .version' "$TMP/.claude/enabled-packs.json")" = "0.1.0" ]; then
  note "new-onto discovered, added enabled:true, vendored, and cataloged (ok); known-onto untouched (ok)"
else note "FAIL: discovery/vendor/catalog contract not met"; fail=1; fi

# 3. idempotent: running again adds no duplicate entries.
if run_sync >/dev/null 2>&1 \
   && [ "$(jq '[.ontologies[] | select(.id=="new-onto")] | length' "$TMP/harness.config.json")" = 1 ]; then
  note "second run is idempotent, no duplicate entries (ok)"
else note "FAIL: second run duplicated an entry"; fail=1; fi

# 4. mif-base is in the registry AND satisfied by a committed base layer
#    (schemas/ontologies/mif-base/ exists in this fixture) — it must never
#    be added to harness.config.json's ontologies[], and never vendored.
if [ "$(jq '[.ontologies[] | select(.id=="mif-base")] | length' "$TMP/harness.config.json")" = 0 ] \
   && [ ! -e "$TMP/packs/ontologies/mif-base" ]; then
  note "committed base layer mif-base excluded from ontologies[] and never vendored (ok)"
else note "FAIL: committed base layer mif-base was added to ontologies[] or vendored"; fail=1; fi

[ "$fail" = 0 ] && echo "sync-registry-ontologies: PASS" || { echo "sync-registry-ontologies: FAIL" >&2; exit 1; }
