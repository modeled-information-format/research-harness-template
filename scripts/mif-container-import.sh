#!/usr/bin/env bash
# mif-container-import.sh — the MIF Container fail-closed import gate
# (Story #318, ADR-0017). A strict, ordered sequence -- never a best-effort
# merge. Every step must pass before ANYTHING is written; a failure at any
# step rejects the entire import, never a partial write:
#
#   1. Manifest schema validation (Task #319) against
#      schemas/mif-container.schema.json.
#   2. Per-resource digest verification against the manifest, the
#      manifest-level digest itself, AND a bulk findings.schema.json
#      pre-validation of every finding resource (Task #320, NFR-2) -- any
#      single mismatch or schema failure rejects the whole import BEFORE
#      step 4 writes anything. (An earlier version validated each finding's
#      schema one at a time inside the step-4 write loop; a later resource
#      failing that check left earlier resources in the same manifest
#      already durably written -- a real partial write review caught.)
#   3. Ontology-binding compatibility check against the destination corpus's
#      cataloged packs (Task #321, NFR-3): base layers under
#      schemas/ontologies/<id>/<version>.yaml (the version is the filename
#      stem) and vendored domain packs pinned in ontologies.lock.json. Any
#      binding not an EXACT version match rejects the whole import -- never
#      a silent best-effort re-typing. ("An explicitly-declared compatible
#      successor" per the feature-spec has no declaration mechanism
#      anywhere else in this repo yet; M1 is exact-match only.) More than
#      one cataloged file for a packId is ambiguous and rejected rather than
#      silently picking one.
#   4. Idempotent upsert-by-@id write (Task #322, NFR-4): a finding resource
#      whose @id already exists at the destination is overwritten in place
#      only if its digest differs (a no-op re-run otherwise, never a
#      duplicate); a new @id is written via scripts/write-finding.sh (the
#      same hardened stage+ajv+atomic-ln-publish primitive every other
#      first-write path in this repo uses, rather than a second hand-rolled
#      copy of the same logic). ontology-map/concordance resources are
#      digest-verified in step 2 but never hand-written here -- the
#      destination's own copies are rebuilt fresh in step 5.
#   5. Trigger the existing deterministic rebuilders (Task #323):
#      build-graph.sh, build-topic-readme.sh, build-concordance.sh.
#
# Concurrency (feature-spec AC12): a second invocation against the same
# topic while one is already running fails closed on an mkdir-based lock
# (atomic, no flock dependency) rather than racing steps 4/5.
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
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || { echo "mif-container-import: failed to resolve repo root" >&2; exit 5; }
cd "$ROOT" || { echo "mif-container-import: failed to cd to repo root: $ROOT" >&2; exit 5; }

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

# --- Concurrency lock (feature-spec AC12): mkdir is atomic, no flock -------
LOCK_DIR="reports/$TOPIC/.container.lock"
mkdir "$LOCK_DIR" 2>/dev/null || fail "another export/import is in progress for topic '$TOPIC' (lock held: $LOCK_DIR)"
# One EXIT trap for the whole script (not per-loop-iteration RETURN traps,
# which never fire in top-level script code -- only in functions/sourced
# scripts): releases the lock and, if step 4's overwrite-in-place path left
# CURRENT_STAGE_DIR set when `fail` aborted mid-write, cleans that up too.
CURRENT_STAGE_DIR=""
cleanup() {
  [ -n "$CURRENT_STAGE_DIR" ] && rm -rf "$CURRENT_STAGE_DIR" 2>/dev/null
  rmdir "$LOCK_DIR" 2>/dev/null
}
trap cleanup EXIT

# --- Step 1: manifest schema validation (Task #319) -------------------------
# The specific "unrecognized profile" check runs BEFORE the general ajv
# validate: schemas/mif-container.schema.json already enum-constrains
# profile to one value, so ajv alone would reject an unrecognized profile
# too, but with a generic "does not validate" message -- checking the
# specific field first surfaces the named error feature-spec AC9 asks for
# instead of leaving it unreachable behind the general schema failure.
PROFILE="$(jq -r '.profile // empty' "$MANIFEST" 2>/dev/null)"
[ "$PROFILE" = "https://research-harness.dev/schema/mif-container/v1" ] \
  || fail "unrecognized container profile: ${PROFILE:-<missing>}"

ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/mif-container.schema.json -d "$MANIFEST" > /dev/null 2>&1 \
  || fail "manifest does not validate against schemas/mif-container.schema.json"
echo "mif-container-import: step 1/5 manifest schema validation OK"

# --- Step 2: per-resource digest + schema verification (Task #320, NFR-2) --
# Every finding resource's own findings.schema.json validity is checked HERE,
# in a bulk pass before anything is written, not one-at-a-time during the
# step-4 write loop -- so a later resource's schema failure can no longer
# leave earlier resources in the same manifest already durably written.
BAD_DIGESTS=""
BAD_SCHEMAS=""
while IFS=$'\t' read -r rpath rdigest rmiftype; do
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

  if [ "$rmiftype" = "finding" ]; then
    ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/findings.schema.json \
      -r schemas/mif/mif.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$rfile" > /dev/null 2>&1 \
      || BAD_SCHEMAS="${BAD_SCHEMAS}${rpath}; "
  fi
done < <(jq -r '.resources[] | [.path, .digest, .mifType] | @tsv' "$MANIFEST")
[ -z "$BAD_DIGESTS" ] || fail "per-resource digest mismatch: $BAD_DIGESTS"
[ -z "$BAD_SCHEMAS" ] || fail "finding resource(s) do not validate against schemas/findings.schema.json (passed digest verification but are not schema-valid): $BAD_SCHEMAS"

MANIFEST_DIGEST_DECLARED="$(jq -r '.manifestDigest' "$MANIFEST")"
MANIFEST_DIGEST_ACTUAL="$(jq -r '.resources[].digest' "$MANIFEST" | scripts/mif-container-digest.sh manifest)" \
  || fail "failed to recompute the manifest-level digest"
[ "$MANIFEST_DIGEST_DECLARED" = "$MANIFEST_DIGEST_ACTUAL" ] \
  || fail "manifest-level digest mismatch (expected $MANIFEST_DIGEST_DECLARED, got $MANIFEST_DIGEST_ACTUAL)"
echo "mif-container-import: step 2/5 digest + finding-schema verification OK"

# --- Step 3: ontology-binding compatibility check (Task #321, NFR-3) --------
BAD_BINDINGS=""
while IFS=$'\t' read -r packid version; do
  cataloged=""
  # packId is already constrained to ^[a-z][a-z0-9-]*$ by step 1's schema
  # validation (no path separators or ".." possible), but the destination
  # catalog lookup still fails closed on an ambiguous match rather than
  # silently picking one via an unordered `head -1`. Portable (no mapfile/
  # readarray, bash 4+ only) -- this repo's macOS dev default is bash 3.2.
  base_files="$(find "schemas/ontologies/$packid" -maxdepth 1 -name '*.yaml' 2>/dev/null | sort)"
  base_file_count="$(printf '%s\n' "$base_files" | grep -c . || true)"
  if [ "$base_file_count" -gt 1 ]; then
    BAD_BINDINGS="${BAD_BINDINGS}${packid}@${version} (ambiguous: ${base_file_count} cataloged files for this packId); "
    continue
  elif [ "$base_file_count" -eq 1 ]; then
    cataloged="$(basename "$base_files" .yaml)"
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
  echo "mif-container-import: --dry-run OK -- all validation steps passed (including per-finding schema validation), nothing written"
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

  # -F: literal substring match, not a BRE pattern -- @id is schema-
  # constrained only to a "^urn:mif:" prefix (schemas/mif/mif.schema.json),
  # so any later segment can legally contain regex metacharacters
  # ('.', '*', '[', ...) that would otherwise be interpreted as a pattern
  # and could match the wrong existing finding (or fail to match its own).
  existing="$(grep -Fl "\"@id\": \"$rid\"" "$FINDINGS_DIR"/*.json 2>/dev/null | head -1 || true)"
  if [ -n "$existing" ]; then
    existing_digest="$(scripts/mif-container-digest.sh resource "$existing" 2>/dev/null)" \
      || fail "failed to compute the digest of the existing finding at $existing -- refusing to guess whether an upsert is needed"
    if [ "$existing_digest" = "$rdigest" ]; then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    # Overwrite-in-place: re-verify the incoming file's digest immediately
    # before staging/copying (closing the TOCTOU window between step 2's
    # verification and this write, in case $CONTAINER_DIR could change
    # between them), then publish via the same atomic pattern
    # write-finding.sh uses (mktemp under the SAME filesystem, then an
    # atomic rename only after full validation) -- explicit exit-status
    # checks on every step, unlike the earlier version's unchecked `mv -f`.
    recheck="$(scripts/mif-container-digest.sh resource "$rfile" 2>/dev/null)" \
      || fail "failed to re-verify the digest of $rpath immediately before writing"
    [ "$recheck" = "$rdigest" ] || fail "$rpath's digest changed between verification and write (expected $rdigest, got $recheck) -- refusing to write unverified content"
    CURRENT_STAGE_DIR="$(mktemp -d "$FINDINGS_DIR/.import-staging-XXXXXX")" \
      || fail "failed to create staging directory under $FINDINGS_DIR"
    STAGE="$CURRENT_STAGE_DIR/$(basename "$existing")"
    cp "$rfile" "$STAGE" || fail "failed to stage $rpath for overwrite"
    mv -f "$STAGE" "$existing" || fail "failed to publish the overwrite of $existing (mv failed -- destination may be on a read-only filesystem or out of space)"
    rmdir "$CURRENT_STAGE_DIR" 2>/dev/null
    CURRENT_STAGE_DIR=""
    UPSERTED=$((UPSERTED + 1))
    continue
  fi

  # Brand-new @id: delegate to scripts/write-finding.sh, the same hardened
  # stage+ajv+atomic-ln-publish primitive every other first-write path in
  # this repo uses (per-invocation mktemp staging immune to the BSD/macOS
  # mktemp suffix gotcha, ln-based publish that fails closed on EEXIST
  # instead of a check-then-act mv that a concurrent writer could race).
  scripts/write-finding.sh "$rfile" "$FINDINGS_DIR" "$(basename "$rpath")" \
    || fail "failed to write new finding $rpath via write-finding.sh"
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
