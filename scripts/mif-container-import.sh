#!/usr/bin/env bash
# mif-container-import.sh — the MIF Container fail-closed import gate
# (Stories #318/#324, ADR-0017). A strict, ordered sequence -- never a
# best-effort merge. Every step must pass before ANYTHING is written; a
# failure at any step rejects the entire import, never a partial write:
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
#      already durably written -- a real partial write review caught.) For
#      any @id that already exists at the destination, step 2 ALSO computes
#      and validates step 4's reconciliation MERGE here (Story #324) -- the
#      merge draws on the destination's own on-disk content, which step 2's
#      incoming-bytes-only validation cannot otherwise rule out producing
#      invalid output from (a corrupt/hand-edited destination finding is the
#      realistic trigger); this closes the same partial-write class the
#      earlier fix closed, for the one path this story's merge reopened.
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
#      copy of the same logic). The manifest's ontology-map resource is
#      digest-verified in step 2 and written here: for a FULL-scope export,
#      verbatim (mktemp+mv, same directory, skipped as a no-op if the
#      destination's copy already matches the incoming digest) -- Story #328
#      review found this resource was exported but never materialized at the
#      destination on import, silently dropping a topic's ontology typing on
#      a round-trip. A SUBSET export's ontology-map.json only covers the
#      exported ids, so a verbatim overwrite would delete typing for every
#      other finding already at the destination -- instead its entries are
#      upserted into the destination array by finding_id, keeping every
#      destination entry not present in the incoming set (issue #376;
#      Story #328 shipped the conservative skip-only version and filed the
#      merge as this follow-up). concordance is a cross-topic
#      global file and stays rebuilt fresh in step 5, not written from the
#      container. An overwrite is NOT a blind replace: a per-field
#      reconciliation policy (Task #326,
#      ADR-0017 AD-6) applies -- `.provenance` (the finding's own W3C-PROV
#      block, distinct from the container-level `sourceInstance` tag) and
#      `.extensions.harness.{verification,gathered_under}` (falsification
#      verdict, session lineage) are origin-scoped and always kept from the
#      DESTINATION's existing copy; `.tags[]` reconciles toward a union of
#      both sides; every other field (content, summary, title, citations,
#      relationships, ontology, entity) reconciles toward the incoming
#      container's value, same as before this story.
#   5. Trigger the existing deterministic rebuilders (Task #323):
#      build-graph.sh, build-topic-readme.sh, build-concordance.sh, THEN
#      scan the rebuilt concordance for candidate cross-@id sameAs matches
#      (Task #327, ADR-0017 AD-6) via scripts/mif-container-detect-sameas.sh,
#      writing reports/concordance-sameas-proposals.json. This is detection
#      ONLY -- never an automatic merge; a human confirms any real match.
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
# A failed mkdir means EITHER a genuine lock (another run got there first,
# so $LOCK_DIR now exists) OR an unrelated failure (missing parent dir,
# permissions, read-only FS) -- distinguish them so a misconfigured
# destination corpus isn't misreported as "another import in progress".
LOCK_DIR="reports/$TOPIC/.container.lock"
if lock_err="$(mkdir "$LOCK_DIR" 2>&1)"; then
  :
elif [ -d "$LOCK_DIR" ]; then
  fail "another export/import is in progress for topic '$TOPIC' (lock held: $LOCK_DIR)"
else
  fail "failed to create import lock at $LOCK_DIR: ${lock_err:-mkdir failed for an unknown reason}"
fi
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
#
# Story #324: step 4's overwrite-in-place path applies a per-field
# reconciliation MERGE (see the policy block at step 4), not a verbatim
# copy of the incoming bytes -- so validating only the incoming resource
# here is not enough to rule out step 4 producing invalid content: the
# merge also draws from the DESTINATION's existing on-disk copy, which
# this script does not control (a corrupt/hand-edited destination finding
# is the only realistic way a merge of two already-schema-valid documents
# produces an invalid result). So for every finding whose @id already
# exists at the destination, the reconciled merge is computed and
# validated HERE too, in this same bulk pre-pass -- before step 4 writes
# anything for ANY resource in this manifest, not discovered mid-write.
FINDINGS_DIR="reports/$TOPIC/findings"
mkdir -p "$FINDINGS_DIR"
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

    rid="$(jq -r '."@id" // empty' "$rfile" 2>/dev/null)"
    if [ -n "$rid" ]; then
      existing_probe_matches="$(find "$FINDINGS_DIR" -maxdepth 1 -name '*.json' -exec grep -Fl "\"@id\": \"$rid\"" {} + 2>/dev/null || true)"
      existing_probe_match_count="$(printf '%s\n' "$existing_probe_matches" | grep -c . || true)"
      # Same ambiguous-@id fail-closed check step 4 already does: a
      # multi-line $existing_probe_matches used as a single filename below
      # would mask a real "destination corpus already corrupted" root
      # cause behind a confusing digest/slurp failure instead.
      [ "$existing_probe_match_count" -le 1 ] || fail "multiple existing findings share @id $rid in $FINDINGS_DIR -- destination corpus is already corrupted (duplicate @id), refusing to guess which one to check"
      existing_probe="$existing_probe_matches"
      # Only check the merge if step 4 would actually PERFORM one: a
      # matching digest means step 4 skips as a no-op, never touching
      # (or being able to trip over corruption in) the existing file --
      # checking the merge unconditionally here would reject an import
      # that step 4 itself would have cleanly skipped.
      existing_probe_digest=""
      [ -n "$existing_probe" ] && existing_probe_digest="$(scripts/mif-container-digest.sh resource "$existing_probe" 2>/dev/null || true)"
      if [ -n "$existing_probe" ] && [ "$existing_probe_digest" != "$rdigest" ]; then
        merge_check_err="$(jq --slurpfile ex "$existing_probe" '
          ($ex[0]) as $e
          | .provenance = ($e.provenance // null)
          | .tags = ((($e.tags // []) + (.tags // [])) | unique | sort)
          | .extensions.harness.verification = ($e.extensions.harness.verification // null)
          | .extensions.harness.gathered_under = ($e.extensions.harness.gathered_under // null)
          | (if .provenance == null then del(.provenance) else . end)
          | (if .extensions.harness.verification == null then del(.extensions.harness.verification) else . end)
          | (if .extensions.harness.gathered_under == null then del(.extensions.harness.gathered_under) else . end)
          | (if (.tags | length) == 0 then del(.tags) else . end)
        ' "$rfile" 2>&1 > /dev/null)"
        if [ -n "$merge_check_err" ]; then
          BAD_SCHEMAS="${BAD_SCHEMAS}${rpath} (reconciliation merge against the existing destination finding at $existing_probe failed: $merge_check_err); "
        else
          # A real temp file is required (ajv-cli's `-d /dev/stdin` is
          # unreliable on this platform), and it MUST have a real .json
          # suffix: ajv-cli's own openFile() derives the parse format from
          # path.extname(), and on a bare `mktemp` name like `tmp.aB3xY9`
          # the random suffix itself gets mistaken for the "extension" --
          # decodeFile then throws on the bogus format, and ajv-cli's
          # catch-all fallback calls Node's require() on the file, which
          # parses valid JSON as JAVASCRIPT and dies on the first `:` in
          # `{"@context": ...}` with a wildly misleading "Unexpected token
          # ':'" error that looks exactly like a real schema failure. A
          # mktemp -d directory + an explicitly-named "<name>.json" file
          # inside it (the same pattern write-finding.sh's own staging
          # uses) sidesteps this entirely.
          merge_check_dir="$(mktemp -d)" || fail "failed to create a temp directory to validate the reconciliation merge for $rpath"
          merge_check_file="$merge_check_dir/merge-check.json"
          jq --slurpfile ex "$existing_probe" '
            ($ex[0]) as $e
            | .provenance = ($e.provenance // null)
            | .tags = ((($e.tags // []) + (.tags // [])) | unique | sort)
            | .extensions.harness.verification = ($e.extensions.harness.verification // null)
            | .extensions.harness.gathered_under = ($e.extensions.harness.gathered_under // null)
            | (if .provenance == null then del(.provenance) else . end)
            | (if .extensions.harness.verification == null then del(.extensions.harness.verification) else . end)
            | (if .extensions.harness.gathered_under == null then del(.extensions.harness.gathered_under) else . end)
            | (if (.tags | length) == 0 then del(.tags) else . end)
          ' "$rfile" > "$merge_check_file" 2>/dev/null
          ajv validate --spec=draft2020 --strict=false -c ajv-formats \
            -s schemas/findings.schema.json \
            -r schemas/mif/mif.schema.json \
            -r schemas/mif/definitions/entity-reference.schema.json \
            -d "$merge_check_file" > /dev/null 2>&1 \
            || BAD_SCHEMAS="${BAD_SCHEMAS}${rpath} (the reconciled merge with the existing destination finding at $existing_probe is not schema-valid); "
          rm -rf "$merge_check_dir"
        fi
      fi
    fi
  fi

  # A SUBSET import's step-4 write (issue #376) merges the incoming
  # ontology-map.json INTO the destination's existing on-disk copy, which,
  # like a finding's reconciliation merge above, this script does not
  # control -- a corrupt/hand-edited/non-array destination ontology-map.json
  # would otherwise only be discovered live inside step 4's write loop,
  # after every 'finding' resource in this same manifest has already been
  # durably written, breaking this script's own "reject entire import,
  # never a partial write" guarantee. Checked here, in this same bulk
  # pre-pass, before step 4 writes anything for ANY resource. Scoped to
  # subset scope only (read inline from the manifest -- EXPORT_SCOPE_TYPE
  # itself isn't assigned until after this pre-validation loop runs): a FULL
  # export's step-4 write always overwrites the destination VERBATIM, never
  # parses it as data, so a corrupt destination doesn't crash the full-scope
  # path and a full re-import remains a valid way to heal it -- rejecting it
  # here too would break that self-healing path for no safety benefit.
  if [ "$rmiftype" = "ontology-map" ]; then
    dest_ontmap="reports/$TOPIC/ontology-map.json"
    resource_scope_type="$(jq -r '.exportScope.type // empty' "$MANIFEST" 2>/dev/null)"
    if [ "$resource_scope_type" = "subset" ] && [ -f "$dest_ontmap" ] \
       && ! jq -e 'type == "array"' "$dest_ontmap" > /dev/null 2>&1; then
      BAD_SCHEMAS="${BAD_SCHEMAS}${rpath} (destination ontology-map.json at $dest_ontmap is not a JSON array -- a subset merge cannot safely fold it; refusing before any write); "
    fi
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
# ($FINDINGS_DIR is already set from step 2, which needs it to locate any
# existing @id for the bulk reconciliation-merge pre-check.)
# EXPORT_SCOPE_TYPE gates the ontology-map write below: a FULL export's
# ontology-map.json represents the whole topic, so overwriting the
# destination's copy verbatim is correct. A SUBSET export's ontology-map.json
# only covers the exported ids -- writing that verbatim over an
# already-populated destination topic would silently delete ontology typing
# for every OTHER finding already there (review finding, Story #328: this is
# real data loss, not a rare corner case, since importing into an
# already-populated topic is /import's normal documented use). Merging a
# subset's entries into the destination by finding_id (parallel to AD-6's
# per-field reconciliation policy for findings) is filed as a follow-up, not
# built here -- for now, a subset import leaves the destination's own
# ontology-map.json untouched.
EXPORT_SCOPE_TYPE="$(jq -r '.exportScope.type // empty' "$MANIFEST")"
UPSERTED=0
SKIPPED=0
ONTMAP_WRITTEN=0
while IFS=$'\t' read -r rpath rdigest rmiftype; do
  if [ "$rmiftype" = "ontology-map" ]; then
    rfile="$CONTAINER_DIR/$rpath"
    dest="reports/$TOPIC/ontology-map.json"
    jq -e 'type == "array"' "$rfile" > /dev/null 2>&1 \
      || fail "ontology-map.json resource $rpath is not a JSON array -- refusing to write it into $dest"
    if [ "$EXPORT_SCOPE_TYPE" = "full" ]; then
      # A full export's ontology-map.json represents the whole topic -- overwriting the
      # destination's copy verbatim is correct.
      if [ -f "$dest" ]; then
        dest_digest="$(scripts/mif-container-digest.sh resource "$dest" 2>/dev/null)" || dest_digest=""
        [ "$dest_digest" = "$rdigest" ] && continue
      fi
      ontmap_stage="$(mktemp "reports/$TOPIC/.ontology-map-import.XXXXXX")" \
        || fail "failed to create a staging file for ontology-map.json"
      cp "$rfile" "$ontmap_stage" || { rm -f "$ontmap_stage"; fail "failed to stage ontology-map.json for $TOPIC"; }
      mv -f "$ontmap_stage" "$dest" \
        || { rm -f "$ontmap_stage"; fail "failed to publish ontology-map.json for $TOPIC"; }
      ONTMAP_WRITTEN=1
      continue
    fi
    # A subset export's ontology-map.json only covers the exported ids (issue #376):
    # upsert the incoming entries into the destination array by finding_id, keeping
    # every destination entry whose finding_id is NOT in the incoming set -- never a
    # verbatim overwrite, which would delete typing for every other finding already
    # at the destination. Order-preserving: an existing entry that IS being updated
    # keeps its original array position (replaced in place, not moved to the end) --
    # only a genuinely NEW finding_id (present in incoming, absent from the
    # destination) is appended. This matters because gate_m31's own regression test
    # compares the destination array before/after a same-content subset re-import and
    # expects it byte-identical, not merely set-equal.
    ontmap_stage="$(mktemp "reports/$TOPIC/.ontology-map-import.XXXXXX")" \
      || fail "failed to create a staging file for ontology-map.json"
    if [ -f "$dest" ]; then
      jq -s '
        (.[0]) as $incoming
        | (.[1]) as $existing
        | ($incoming | map({(.finding_id): .}) | add // {}) as $incoming_by_id
        | ($existing | map({(.finding_id): true}) | add // {}) as $existing_by_id
        | ($existing | map(.finding_id as $id | ($incoming_by_id[$id] // .))) as $updated_existing
        | ($incoming | map(select(.finding_id as $id | ($existing_by_id | has($id)) | not))) as $new_entries
        | $updated_existing + $new_entries
      ' "$rfile" "$dest" > "$ontmap_stage" \
        || { rm -f "$ontmap_stage"; fail "failed to merge ontology-map.json entries for $TOPIC"; }
    else
      cp "$rfile" "$ontmap_stage" || { rm -f "$ontmap_stage"; fail "failed to stage ontology-map.json for $TOPIC"; }
    fi
    if [ -f "$dest" ] && cmp -s "$ontmap_stage" "$dest"; then
      rm -f "$ontmap_stage"
      continue
    fi
    mv -f "$ontmap_stage" "$dest" \
      || { rm -f "$ontmap_stage"; fail "failed to publish merged ontology-map.json for $TOPIC"; }
    ONTMAP_WRITTEN=1
    continue
  fi
  [ "$rmiftype" = "finding" ] || continue
  rfile="$CONTAINER_DIR/$rpath"
  rid="$(jq -r '."@id"' "$rfile")"
  [ -n "$rid" ] && [ "$rid" != "null" ] || fail "resource $rpath has no @id, cannot upsert"

  # -F: literal substring match, not a BRE pattern -- @id is schema-
  # constrained only to a "^urn:mif:" prefix (schemas/mif/mif.schema.json),
  # so any later segment can legally contain regex metacharacters
  # ('.', '*', '[', ...) that would otherwise be interpreted as a pattern
  # and could match the wrong existing finding (or fail to match its own).
  # `find -exec grep +` (not a bare "$FINDINGS_DIR"/*.json glob) so a large
  # topic's file count can't hit ARG_MAX; matches are counted explicitly so
  # a destination corpus already corrupted with a duplicate @id is rejected
  # instead of non-deterministically picking one (this script's own writes
  # can never create that state -- write-finding.sh and the overwrite path
  # below never introduce a second file for the same @id -- but a corpus
  # written before this script existed could already be corrupted).
  existing_matches="$(find "$FINDINGS_DIR" -maxdepth 1 -name '*.json' -exec grep -Fl "\"@id\": \"$rid\"" {} + 2>/dev/null || true)"
  existing_match_count="$(printf '%s\n' "$existing_matches" | grep -c . || true)"
  [ "$existing_match_count" -le 1 ] || fail "multiple existing findings share @id $rid in $FINDINGS_DIR -- destination corpus is already corrupted (duplicate @id), refusing to guess which one to update"
  existing="$existing_matches"
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

    # ============================================================
    # NAMED RECONCILIATION POLICY (Story #324, ADR-0017 AD-6):
    #   ORIGIN-SCOPED (always the DESTINATION's value, or its absence --
    #   NEVER falls back to the incoming value even when the destination
    #   lacks one; absence is itself part of the destination's own
    #   origin-scoped state, so a foreign verdict/session id is not
    #   rendered true by the destination simply never having recorded
    #   one of its own):
    #     - .provenance                          (the finding's OWN
    #       W3C-PROV block -- distinct from the container-level
    #       sourceInstance tag, which this policy does not consult)
    #     - .extensions.harness.verification      (falsification verdict
    #       -- a verdict reached by THIS instance's own adversarial gate
    #       is not something a re-import from elsewhere overwrites)
    #     - .extensions.harness.gathered_under    (session lineage)
    #   UNION (both sides' values kept, never a replace):
    #     - .tags[]
    #   RECONCILE (incoming container's value wins -- everything else:
    #     content, summary, title, citations, relationships, ontology,
    #     entity -- that's the point of the update):
    #     - (implicit: every field not named above)
    # This exact merge is ALSO computed and schema-validated in step 2's
    # bulk pre-check (before ANY resource in this manifest is written),
    # so it is not re-validated here -- see step 2's comment for why.
    # ============================================================
    CURRENT_STAGE_DIR="$(mktemp -d "$FINDINGS_DIR/.import-staging-XXXXXX")" \
      || fail "failed to create staging directory under $FINDINGS_DIR"
    STAGE="$CURRENT_STAGE_DIR/$(basename "$existing")"
    jq --slurpfile ex "$existing" '
      ($ex[0]) as $e
      | .provenance = ($e.provenance // null)
      | .tags = ((($e.tags // []) + (.tags // [])) | unique | sort)
      | .extensions.harness.verification = ($e.extensions.harness.verification // null)
      | .extensions.harness.gathered_under = ($e.extensions.harness.gathered_under // null)
      | (if .provenance == null then del(.provenance) else . end)
      | (if .extensions.harness.verification == null then del(.extensions.harness.verification) else . end)
      | (if .extensions.harness.gathered_under == null then del(.extensions.harness.gathered_under) else . end)
      | (if (.tags | length) == 0 then del(.tags) else . end)
    ' "$rfile" > "$STAGE" 2>/dev/null || fail "failed to apply the per-field reconciliation policy to $rpath (step 2 already validated this merge would succeed -- an unexpected failure here means the destination file changed after step 2's pre-check)"
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
echo "mif-container-import: step 4/5 idempotent upsert OK ($UPSERTED written, $SKIPPED already up to date, ontology-map.json $([ "$ONTMAP_WRITTEN" -eq 1 ] && echo written || echo unchanged))"

# --- Step 5: trigger the existing deterministic rebuilders (Task #323) ------
bash scripts/build-graph.sh "$FINDINGS_DIR" "reports/$TOPIC/knowledge-graph.json" \
  || fail "build-graph.sh failed after a successful upsert -- corpus is in a partially-rebuilt state, re-run scripts/build-graph.sh manually"
bash scripts/build-topic-readme.sh "$TOPIC" \
  || fail "build-topic-readme.sh failed after a successful upsert -- re-run manually"
bash scripts/build-concordance.sh \
  || fail "build-concordance.sh failed after a successful upsert -- re-run manually"

# Candidate concordance sameAs detection (Task #327, ADR-0017 AD-6): scan the
# freshly-rebuilt concordance for same-labeled-but-different-@id node pairs
# a cross-instance import can introduce. This NEVER merges or rewrites
# anything -- it only surfaces a reviewable proposals file; a human decides.
# Skipped on a true no-op (nothing written this run) -- an import that
# upserted nothing cannot have introduced a new candidate pair, so
# re-scanning the entire (potentially large, cross-topic) concordance
# would be pure wasted work.
if [ "$UPSERTED" -gt 0 ]; then
  # Write via mktemp+mv (same filesystem, same directory) rather than a
  # bare `>` redirect: this is a GLOBAL (not per-topic) file, so a
  # concurrent import into a DIFFERENT topic's own lock can still reach
  # this same step at the same time -- an atomic rename can't prevent
  # last-writer-wins between the two runs' proposals (reports/concordance.json
  # itself, which this scan reads, has that same pre-existing cross-topic
  # exposure -- not something Story #324 introduces or owns), but it does
  # rule out an interleaved/corrupt half-written file.
  sameas_tmp="$(mktemp reports/.concordance-sameas-proposals.XXXXXX)" \
    || fail "failed to create a temp file for the sameAs proposals write"
  scripts/mif-container-detect-sameas.sh reports/concordance.json > "$sameas_tmp" \
    || { rm -f "$sameas_tmp"; fail "mif-container-detect-sameas.sh failed after a successful upsert -- re-run manually"; }
  mv -f "$sameas_tmp" reports/concordance-sameas-proposals.json \
    || fail "failed to publish the sameAs proposals file"
fi
echo "mif-container-import: step 5/5 deterministic rebuilders + sameAs detection OK"

echo "mif-container-import: import complete -- $UPSERTED finding(s) written, $SKIPPED already up to date"
