#!/usr/bin/env bash
# mif-container-import.sh — the MIF Container fail-closed import gate
# (Story #318, ADR-0017). A strict, ordered sequence -- never a best-effort
# merge. Every step must pass before ANYTHING is written; a failure at any
# step rejects the entire import, never a partial write:
#
#   1. Manifest schema validation (Task #319) against
#      schemas/mif-container.schema.json.
#   2. Per-resource digest verification against the manifest, plus the
#      manifest-level digest itself, via scripts/mif-container-digest.sh
#      (Task #320, NFR-2) -- any single mismatch rejects the whole import.
#   3. Ontology-binding compatibility check against the destination corpus's
#      cataloged packs (Task #321, NFR-3): base layers under
#      schemas/ontologies/<id>/<version>.yaml (the version is the filename
#      stem) and vendored domain packs pinned in ontologies.lock.json. Any
#      binding not an EXACT version match rejects the whole import -- never
#      a silent best-effort re-typing. ("An explicitly-declared compatible
#      successor" per the feature-spec has no declaration mechanism
#      anywhere else in this repo yet; M1 is exact-match only.)
#   4. Idempotent upsert-by-@id write (Task #322, NFR-4): a finding resource
#      whose @id already exists at the destination is overwritten in place
#      only if its digest differs (a no-op re-run otherwise, never a
#      duplicate); a new @id is written as a new file. ontology-map/
#      concordance resources are digest-verified in step 2 but never
#      hand-written here -- the destination's own copies are rebuilt fresh
#      in step 5, per this story's own "rather than hand-writing derived
#      artifacts" scope.
#   5. Trigger the existing deterministic rebuilders (Task #323):
#      build-graph.sh, build-topic-readme.sh, build-concordance.sh.
#
# Usage:
#   mif-container-import.sh <container-dir> <topic> [--dry-run]
#     <container-dir>: a directory containing mif-package.json plus every
#       resource file it names (resources[].path, relative to this dir).
#     <topic>: the destination reports/<topic> -- MUST already be a
#       registered topic in harness.config.json (this gate imports into an
#       existing topic; it does not create one).
#     --dry-run: run steps 1-3 (validation) and report the outcome without
#       writing anything to reports/ (feature-spec AC11).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
[ "${#POSITIONAL[@]}" -ge 2 ] || {
  echo "usage: mif-container-import.sh <container-dir> <topic> [--dry-run]" >&2
  exit 2
}
CONTAINER_DIR="${POSITIONAL[0]}"
TOPIC="${POSITIONAL[1]}"
MANIFEST="$CONTAINER_DIR/mif-package.json"

[ -d "$CONTAINER_DIR" ] || { echo "mif-container-import: not a directory: $CONTAINER_DIR" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "mif-container-import: manifest not found: $MANIFEST" >&2; exit 2; }
jq -e --arg t "$TOPIC" '.topics[] | select(.id == $t)' harness.config.json > /dev/null 2>&1 || {
  echo "mif-container-import: topic '$TOPIC' is not registered in harness.config.json -- this gate imports into an existing topic, it does not create one" >&2
  exit 2
}

fail() { echo "mif-container-import: REJECTED -- $1" >&2; exit 1; }

# --- Step 1: manifest schema validation (Task #319) -------------------------
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/mif-container.schema.json -d "$MANIFEST" > /dev/null 2>&1 \
  || fail "manifest does not validate against schemas/mif-container.schema.json"
echo "mif-container-import: step 1/5 manifest schema validation OK"

PROFILE="$(jq -r '.profile' "$MANIFEST")"
[ "$PROFILE" = "https://research-harness.dev/schema/mif-container/v1" ] \
  || fail "unrecognized container profile: $PROFILE"

# --- Step 2: per-resource + manifest-level digest verification (Task #320, NFR-2) ---
BAD_DIGESTS=""
while IFS=$'\t' read -r rpath rdigest; do
  rfile="$CONTAINER_DIR/$rpath"
  if [ ! -f "$rfile" ]; then
    BAD_DIGESTS="${BAD_DIGESTS}${rpath} (missing file); "
    continue
  fi
  actual="$(scripts/mif-container-digest.sh resource "$rfile" 2>/dev/null)" || {
    BAD_DIGESTS="${BAD_DIGESTS}${rpath} (digest computation failed); "
    continue
  }
  [ "$actual" = "$rdigest" ] || BAD_DIGESTS="${BAD_DIGESTS}${rpath} (expected $rdigest, got $actual); "
done < <(jq -r '.resources[] | [.path, .digest] | @tsv' "$MANIFEST")
[ -z "$BAD_DIGESTS" ] || fail "per-resource digest mismatch: $BAD_DIGESTS"

MANIFEST_DIGEST_DECLARED="$(jq -r '.manifestDigest' "$MANIFEST")"
MANIFEST_DIGEST_ACTUAL="$(jq -r '.resources[].digest' "$MANIFEST" | scripts/mif-container-digest.sh manifest)"
[ "$MANIFEST_DIGEST_DECLARED" = "$MANIFEST_DIGEST_ACTUAL" ] \
  || fail "manifest-level digest mismatch (expected $MANIFEST_DIGEST_DECLARED, got $MANIFEST_DIGEST_ACTUAL)"
echo "mif-container-import: step 2/5 digest verification OK"

# --- Step 3: ontology-binding compatibility check (Task #321, NFR-3) --------
BAD_BINDINGS=""
while IFS=$'\t' read -r packid version; do
  cataloged=""
  base_file="$(find "schemas/ontologies/$packid" -maxdepth 1 -name '*.yaml' 2>/dev/null | head -1)"
  if [ -n "$base_file" ]; then
    cataloged="$(basename "$base_file" .yaml)"
  elif [ -f ontologies.lock.json ]; then
    cataloged="$(jq -r --arg id "$packid" '.ontologies[$id].version // empty' ontologies.lock.json)"
  fi
  if [ -z "$cataloged" ]; then
    BAD_BINDINGS="${BAD_BINDINGS}${packid}@${version} (not cataloged at destination); "
  elif [ "$cataloged" != "$version" ]; then
    BAD_BINDINGS="${BAD_BINDINGS}${packid}@${version} (destination has ${cataloged}); "
  fi
done < <(jq -r '.ontologyBindings[] | [.packId, .version] | @tsv' "$MANIFEST")
[ -z "$BAD_BINDINGS" ] || fail "ontology-binding incompatible with destination catalog: $BAD_BINDINGS"
echo "mif-container-import: step 3/5 ontology-binding compatibility OK"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "mif-container-import: --dry-run OK -- all validation steps passed, nothing written"
  exit 0
fi

# --- Step 4: idempotent upsert-by-@id write (Task #322, NFR-4) --------------
FINDINGS_DIR="reports/$TOPIC/findings"
mkdir -p "$FINDINGS_DIR"
UPSERTED=0
SKIPPED=0
while IFS=$'\t' read -r rpath rdigest rmiftype; do
  [ "$rmiftype" = "finding" ] || continue
  rfile="$CONTAINER_DIR/$rpath"
  rid="$(jq -r '."@id"' "$rfile")"
  [ -n "$rid" ] && [ "$rid" != "null" ] || fail "resource $rpath has no @id, cannot upsert"

  existing="$(grep -rl "\"@id\": *\"$rid\"" "$FINDINGS_DIR"/*.json 2>/dev/null | head -1 || true)"
  if [ -n "$existing" ]; then
    existing_digest="$(scripts/mif-container-digest.sh resource "$existing" 2>/dev/null)"
    if [ "$existing_digest" = "$rdigest" ]; then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    dest="$existing"
  else
    dest="$FINDINGS_DIR/$(basename "$rpath")"
    if [ -e "$dest" ]; then
      fail "$(basename "$rpath") already exists at $dest under a different @id -- refusing to overwrite an unrelated finding"
    fi
  fi

  STAGE_DIR="$(mktemp -d "$FINDINGS_DIR/.import-staging-XXXXXX")" \
    || fail "failed to create staging directory under $FINDINGS_DIR"
  STAGE="$STAGE_DIR/$(basename "$dest")"
  cp "$rfile" "$STAGE"
  if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
        -s schemas/findings.schema.json \
        -r schemas/mif/mif.schema.json \
        -r schemas/mif/definitions/entity-reference.schema.json \
        -d "$STAGE" > /dev/null 2>&1; then
    rm -f "$STAGE"; rmdir "$STAGE_DIR" 2>/dev/null
    fail "$rpath does not validate against schemas/findings.schema.json -- refusing to write a resource that already passed manifest digest verification but fails schema validation"
  fi
  mv -f "$STAGE" "$dest"
  rmdir "$STAGE_DIR" 2>/dev/null
  UPSERTED=$((UPSERTED + 1))
done < <(jq -r '.resources[] | [.path, .digest, .mifType] | @tsv' "$MANIFEST")
echo "mif-container-import: step 4/5 idempotent upsert OK ($UPSERTED written, $SKIPPED already up to date)"

# --- Step 5: trigger the existing deterministic rebuilders (Task #323) ------
bash scripts/build-graph.sh "$FINDINGS_DIR" "reports/$TOPIC/knowledge-graph.json" \
  || fail "build-graph.sh failed after a successful upsert -- corpus is in a partially-rebuilt state, re-run scripts/build-graph.sh manually"
bash scripts/build-topic-readme.sh "$TOPIC" \
  || fail "build-topic-readme.sh failed after a successful upsert -- re-run manually"
bash scripts/build-concordance.sh \
  || fail "build-concordance.sh failed after a successful upsert -- re-run manually"
echo "mif-container-import: step 5/5 deterministic rebuilders OK"

echo "mif-container-import: import complete -- $UPSERTED finding(s) written, $SKIPPED already up to date"
