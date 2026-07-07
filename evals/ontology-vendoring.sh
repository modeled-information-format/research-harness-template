#!/usr/bin/env bash
# ontology-vendoring.sh — eval for on-demand ontology vendoring (fetch-ontology.sh
# + check-ontology-lock.sh). Builds a throwaway harness root + a fixture registry
# in a temp dir, then asserts the full contract WITHOUT touching the real tree:
#   1. fetch resolves + verifies + materializes a domain pack and pins the lock
#   2. a tampered registry sha256 is rejected fail-closed (no pack written)
#   3. a locally-drifted vendored file is caught by the lock gate
#   4. an id absent from the registry fails with the author-ontology pointer
#
# Exit 0 = vendoring contract holds. Exit 1 = a check failed.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # real repo root (source of scripts)
SHA="sha256sum"; command -v sha256sum >/dev/null || SHA="shasum -a 256"
sha_of() { $SHA "$1" | awk '{print $1}'; }
fail=0; note() { printf '  vendoring: %s\n' "$1"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/packs/ontologies" "$TMP/schemas/ontologies/mif-base" "$TMP/registry"
cp "$SELF_DIR/scripts/fetch-ontology.sh" "$SELF_DIR/scripts/check-ontology-lock.sh" "$TMP/scripts/"
# Both cutover scripts source scripts/lib/engine.sh relative to their own
# root (Story #277); the isolated copy above needs it too, or `engine_bin`
# fails with "No such file or directory" before it ever gets to resolve
# anything.
cp -r "$SELF_DIR/scripts/lib" "$TMP/scripts/lib"
printf '{"ontologies":[{"id":"eval-onto","enabled":true}]}\n' > "$TMP/harness.config.json"

# Resolve the REAL installed engine (via the real repo root, where
# engine_bin's PATH/<root>/bin/mif-rh-cli resolution actually applies) and
# pin it as an explicit override for every isolated-copy invocation below —
# the isolated $TMP has no bin/mif-rh-cli of its own.
# shellcheck source=scripts/lib/engine.sh
. "$SELF_DIR/scripts/lib/engine.sh"
REAL_ENGINE="$(engine_bin "$SELF_DIR")" || { echo "ontology-vendoring: engine not found" >&2; exit 5; }
export MIF_RH_CLI="$REAL_ENGINE"

# fixture domain ontology (extends nothing -> closure is just itself)
cat > "$TMP/registry/eval-onto.ontology.yaml" <<'YAML'
---
ontology:
  id: eval-onto
  version: "0.1.0"
  description: "eval fixture ontology"
entity_types:
  - name: widget
    description: "a fixture type"
    base: semantic
    schema: { required: [], properties: {} }
    disposition: mint
YAML
sha="$(sha_of "$TMP/registry/eval-onto.ontology.yaml")"
cat > "$TMP/registry/index.json" <<JSON
{"schema":"mif-ontology-index/v1","source":"fixture",
 "ontologies":{"eval-onto":{"version":"0.1.0","file":"eval-onto.ontology.yaml","sha256":"$sha","extends":[]}}}
JSON

run_fetch() { ( cd "$TMP" && MIF_ONTOLOGY_SOURCE="$TMP/registry" bash scripts/fetch-ontology.sh "$@" ); }
run_gate()  { ( cd "$TMP" && bash scripts/check-ontology-lock.sh ); }

# 1. fetch + verify + materialize + lock
if run_fetch eval-onto >/dev/null 2>&1 \
   && [ -f "$TMP/packs/ontologies/eval-onto/eval-onto.ontology.yaml" ] \
   && [ "$(jq -r '.ontologies["eval-onto"].sha256' "$TMP/ontologies.lock.json")" = "$sha" ]; then
  note "fetch verified + materialized + pinned the lock (ok)"
else note "FAIL: fetch did not verify/materialize/pin"; fail=1; fi

# 1b. lock gate passes on the clean vendored state
if run_gate >/dev/null 2>&1; then note "lock gate passes on clean vendored state (ok)"
else note "FAIL: lock gate rejected a clean vendored state"; fail=1; fi

# 2. tampered registry sha is rejected fail-closed
T2="$(mktemp -d)"; cp "$TMP/registry/eval-onto.ontology.yaml" "$T2/"
jq '.ontologies["eval-onto"].sha256="0000000000000000000000000000000000000000000000000000000000000000"' \
   "$TMP/registry/index.json" > "$T2/index.json"
rm -rf "$TMP/packs/ontologies/eval-onto"
if ( cd "$TMP" && MIF_ONTOLOGY_SOURCE="$T2" bash scripts/fetch-ontology.sh eval-onto ) >/dev/null 2>&1; then
  note "FAIL: tampered checksum was NOT rejected"; fail=1
elif [ -f "$TMP/packs/ontologies/eval-onto/eval-onto.ontology.yaml" ]; then
  note "FAIL: a pack was written despite checksum mismatch"; fail=1
else note "tampered checksum rejected fail-closed, no pack written (ok)"; fi
rm -rf "$T2"

# 3. local drift is caught by the lock gate
run_fetch eval-onto >/dev/null 2>&1
printf '\n# drift\n' >> "$TMP/packs/ontologies/eval-onto/eval-onto.ontology.yaml"
if run_gate >/dev/null 2>&1; then note "FAIL: lock gate missed local drift"; fail=1
else note "local drift caught by lock gate (ok)"; fi

# 4. unknown id -> fail with a pointer to the `ontology author` subcommand
# (capture first; piping a failed fetch into grep would trip pipefail)
unk_out="$( ( cd "$TMP" && MIF_ONTOLOGY_SOURCE="$TMP/registry" bash scripts/fetch-ontology.sh no-such-onto ) 2>&1 || true )"
if printf '%s' "$unk_out" | grep -q "ontology author"; then
  note "unknown id fails with an 'ontology author' pointer (ok)"
else note "FAIL: unknown id did not point to 'ontology author'"; fail=1; fi

[ "$fail" = 0 ] && echo "ontology-vendoring: PASS" || { echo "ontology-vendoring: FAIL" >&2; exit 1; }
