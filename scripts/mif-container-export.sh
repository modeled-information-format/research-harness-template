#!/usr/bin/env bash
# mif-container-export.sh — the MIF Container export builder
# (Story #328, Task #329, ADR-0017). Never modifies reports/<topic>/ (AC10):
# reads the existing corpus and writes a self-contained mif-package.json
# manifest plus every named resource under a fresh <output-dir>.
#
# Steps:
#   1. Resolve scope: full (every finding in the topic) or subset
#      (scripts/mif-container-resolve-scope.sh over a caller-supplied
#      in-scope-ids.json, optionally with --closure). The knowledge graph
#      resolve-scope.sh needs is built into a throwaway mktemp location
#      (never reports/<topic>/knowledge-graph.json) so this stays read-only
#      against the corpus regardless of whether that file is already
#      up to date.
#   2. Validate EVERY in-scope finding's @id resolves to exactly one file
#      and has an ontology-map.json entry with an entity_type -- in full,
#      before writing anything under <output-dir> -- then copy each
#      finding plus a filtered ontology-map.json (subset: only in-scope
#      entries; full: the whole file) under <output-dir>/ontology-map.json.
#      A failure partway through this validation pass leaves <output-dir>
#      exactly as empty as it started (see the cleanup trap below).
#   3. Compute per-resource + manifest-level digests (scripts/mif-container-
#      digest.sh), derive ontologyBindings[] from the in-scope ontology-map
#      entries' resolved_ontology values, and write mif-package.json.
#   4. Validate the finished manifest against schemas/mif-container.schema.json
#      before declaring success -- a self-check, not a substitute for the
#      import gate's own independent validation on the receiving end.
#
# Usage:
#   mif-container-export.sh <topic> <output-dir> [--subset <in-scope-ids.json>] [--closure] [--source-instance <name>]
#     <topic>: MUST already be a registered topic in harness.config.json.
#     <output-dir>: must not already exist (or must be empty) -- this script
#       never overwrites an existing directory's contents.
#     --subset <in-scope-ids.json>: a JSON array of urn:mif:concept:... ids
#       (see scripts/mif-container-resolve-scope.sh). Without this, every
#       finding in the topic is exported (full).
#     --closure: only meaningful with --subset; passed through to
#       scripts/mif-container-resolve-scope.sh.
#     --source-instance <name>: sourceInstance.namespace to stamp on the
#       manifest (Story #324, ADR-0017 AD-6). Defaults to the topic's own
#       namespace's first path segment (e.g. "harness" for
#       "harness/<topic>") -- a reasonable default in the absence of any
#       other instance-identifying field in harness.config.json, but
#       callers exporting for real cross-instance exchange should pass an
#       explicit, stable value instead of relying on this default.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)" || { echo "mif-container-export: failed to resolve repo root" >&2; exit 5; }
cd "$ROOT" || { echo "mif-container-export: failed to cd to repo root: $ROOT" >&2; exit 5; }

fail() { echo "mif-container-export: REJECTED -- $1" >&2; exit 1; }

SUBSET_IDS=""
CLOSURE=0
SOURCE_INSTANCE=""
POSITIONAL=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --subset)
      [ "$#" -ge 2 ] || fail "--subset requires a value"
      SUBSET_IDS="$2"; shift 2 ;;
    --closure) CLOSURE=1; shift ;;
    --source-instance)
      [ "$#" -ge 2 ] || fail "--source-instance requires a value"
      SOURCE_INSTANCE="$2"; shift 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
[ "${#POSITIONAL[@]}" -ge 2 ] || {
  echo "usage: mif-container-export.sh <topic> <output-dir> [--subset <in-scope-ids.json>] [--closure] [--source-instance <name>]" >&2
  exit 2
}
TOPIC="${POSITIONAL[0]}"
OUTPUT_DIR="${POSITIONAL[1]}"
[ "$CLOSURE" -eq 0 ] || [ -n "$SUBSET_IDS" ] || fail "--closure only applies with --subset"

TOPIC_JSON="$(jq -e --arg t "$TOPIC" '.topics[] | select(.id == $t)' harness.config.json 2>/dev/null)" \
  || fail "topic '$TOPIC' is not registered in harness.config.json"
TOPIC_NAMESPACE="$(printf '%s' "$TOPIC_JSON" | jq -r '.namespace')"
[ -n "$SOURCE_INSTANCE" ] || SOURCE_INSTANCE="${TOPIC_NAMESPACE%%/*}"
[ -n "$SOURCE_INSTANCE" ] || fail "topic '$TOPIC' has an empty/malformed namespace in harness.config.json -- pass --source-instance explicitly"

FINDINGS_DIR="reports/$TOPIC/findings"
[ -d "$FINDINGS_DIR" ] || fail "no findings directory for topic '$TOPIC': $FINDINGS_DIR"
ONTOLOGY_MAP="reports/$TOPIC/ontology-map.json"
[ -f "$ONTOLOGY_MAP" ] || fail "no ontology-map.json for topic '$TOPIC': $ONTOLOGY_MAP -- run /ontology-review first"

if [ -e "$OUTPUT_DIR" ]; then
  [ -d "$OUTPUT_DIR" ] || fail "$OUTPUT_DIR exists and is not a directory"
  [ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ] \
    || fail "$OUTPUT_DIR already exists and is not empty -- refusing to write into it"
fi

T="$(mktemp -d)" || fail "failed to create a scratch directory"
# $OUTPUT_DIR is confirmed empty-or-absent above, so removing it wholesale on
# any failure from this point on never destroys pre-existing CONTENT -- but
# note this does remove the directory ENTRY itself, not just its contents;
# a caller that pre-created $OUTPUT_DIR (e.g. with specific ownership/
# permissions) would need to recreate it before retrying, not just find it
# empty again. A prior version's cleanup only ever removed the $T scratch
# dir, never $OUTPUT_DIR itself: a mid-loop `fail` after some findings were
# already copied left partial content behind under $OUTPUT_DIR, directly
# contradicting this command's own documented "nothing written" guarantee on
# failure (review finding, Story #328). EXPORT_OK is set to 1 only
# immediately before the final success message.
EXPORT_OK=0
cleanup() {
  rm -rf "$T"
  [ "$EXPORT_OK" -eq 1 ] || rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT
mkdir -p "$OUTPUT_DIR/findings" || fail "failed to create $OUTPUT_DIR/findings"

# --- Step 1: build the @id -> path index once, resolve scope --------------
# `find`'s traversal order is not guaranteed (the same class of bug fixed in
# gate_m29's --dry-run test, Story #318): sort explicitly for a deterministic
# order across repeated exports of the same topic. One jq call per finding
# file builds the whole index in a single O(n) pass; a prior version instead
# re-scanned every finding file with `find|grep` once PER RESOLVED id
# (O(n*m), and brittle against exact "@id": "..." JSON formatting/whitespace)
# -- this index replaces that lookup for both id->path resolution and
# same-@id ambiguity detection (review finding, Story #328).
INDEX_FILE="$T/id-index.jsonl"
: > "$INDEX_FILE"
while IFS= read -r f; do
  # A missing/empty @id must fail closed here too (Copilot review, PR #378):
  # the prior `select(.id != "")` silently DROPPED such a file from the
  # index with a clean jq exit status, so it was never caught by the `|| fail`
  # guard below -- a full export could silently undercount instead of
  # rejecting a corrupted finding. `error()` makes jq exit non-zero for this
  # case too, same as an actual JSON parse failure.
  jq -c --arg p "$f" 'if ((."@id" // "") == "") then error("finding file has no @id: " + $p) else {id: ."@id", path: $p} end' "$f" >> "$INDEX_FILE" \
    || fail "failed to parse finding file as JSON, or it has no @id: $f -- a full export must fail closed, not silently omit a corrupted finding"
done < <(find "$FINDINGS_DIR" -maxdepth 1 -name '*.json' | LC_ALL=C sort)

if [ -n "$SUBSET_IDS" ]; then
  [ -f "$SUBSET_IDS" ] || fail "--subset file not found: $SUBSET_IDS"
  jq -e 'type == "array"' "$SUBSET_IDS" > /dev/null 2>&1 || fail "--subset file is not a JSON array: $SUBSET_IDS"
  GRAPH="$T/knowledge-graph.json"
  bash scripts/build-graph.sh "$FINDINGS_DIR" "$GRAPH" > /dev/null \
    || fail "failed to build the knowledge graph needed to resolve --subset scope"
  SCOPE_RESULT="$T/scope-result.json"
  if [ "$CLOSURE" -eq 1 ]; then
    scripts/mif-container-resolve-scope.sh "$GRAPH" "$SUBSET_IDS" --closure > "$SCOPE_RESULT" \
      || fail "scripts/mif-container-resolve-scope.sh failed"
  else
    scripts/mif-container-resolve-scope.sh "$GRAPH" "$SUBSET_IDS" > "$SCOPE_RESULT" \
      || fail "scripts/mif-container-resolve-scope.sh failed"
  fi
  RESOURCE_IDS_FILE="$T/resource-ids.json"
  jq '.resourceIds' "$SCOPE_RESULT" > "$RESOURCE_IDS_FILE"
  BOUNDARY_REFS_FILE="$T/boundary-refs.json"
  jq -c '.boundaryReferences' "$SCOPE_RESULT" > "$BOUNDARY_REFS_FILE"
  SCOPE_TYPE="subset"
  # selector is a STRING per schema (a free-form record of what was
  # requested), not the array itself -- the compact JSON text of the
  # sorted input ids is a self-describing, reproducible choice.
  SELECTOR_IS_NULL=0
  SELECTOR_STR="$(jq -c -S . "$SUBSET_IDS")"
else
  RESOURCE_IDS_FILE="$T/all-ids.json"
  jq -s '[.[].id]' "$INDEX_FILE" > "$RESOURCE_IDS_FILE"
  BOUNDARY_REFS_FILE="$T/boundary-refs-empty.json"
  echo '[]' > "$BOUNDARY_REFS_FILE"
  SCOPE_TYPE="full"
  SELECTOR_IS_NULL=1
  SELECTOR_STR=""
fi

RESOURCE_COUNT="$(jq 'length' "$RESOURCE_IDS_FILE")"
# A zero-finding scope is a VALID export, not an error (schemas/mif-container.
# schema.json's own resources[] description says so explicitly, and
# resolve-scope.sh's own test suite -- 28f -- established the same precedent
# for the resolver itself): a subset selector that matches nothing still
# produces a legitimate manifest (carrying at least the ontology-map.json
# resource).

# --- Step 2: validate every resolved id, THEN copy (validate-all-then-write-
#     all, mirroring mif-container-import.sh step 2's own fix for the same
#     partial-write class): resolving every id to exactly one path, and
#     confirming every id has an ontology-map.json entity_type entry, both
#     happen here BEFORE a single byte is copied into $OUTPUT_DIR/findings --
#     a validation failure on a LATER id can no longer leave EARLIER
#     resources already durably copied (review finding, Story #328).
LOOKUP_ERR="$T/lookup-err.txt"
LOOKUP_TSV="$T/resolved.tsv"
jq -r -e -s --slurpfile ids "$RESOURCE_IDS_FILE" '
  (group_by(.id) | map({key: .[0].id, value: (map(.path))}) | from_entries) as $lookup
  | $ids[0][] as $id
  | ($lookup[$id] // []) as $paths
  | if ($paths | length) != 1 then
      error("resolved scope id \($id) matches \($paths|length) finding file(s) in '"$FINDINGS_DIR"' -- destination corpus is ambiguous or corrupted")
    else
      "\($id)\t\($paths[0])"
    end
' "$INDEX_FILE" > "$LOOKUP_TSV" 2>"$LOOKUP_ERR"
# Raw jq stderr, not a sed-scraped substring: jq's actual format is
# "jq: error (at <file>:<line>): <msg>" -- the colon inside "(at ...)"
# defeats a "match up to the first colon" pattern, so an earlier version's
# sed extraction silently produced an EMPTY reason on every real failure here
# (review finding, Story #328, verified empirically). The raw "jq: error..."
# prefix is informative, not noise -- matches this repo's own "surface the
# script's stderr message directly" convention.
[ -s "$LOOKUP_ERR" ] && fail "$(cat "$LOOKUP_ERR")"

# resolved_ontology CAN legitimately be null (an untyped/falsified/quarantined
# finding has an ontology-map.json entry but no resolved type) -- select it
# out before .entity_type is required here, and before BINDINGS_JSON's
# split("@") below, so a null never reaches a `null | split("@")` jq crash
# (review finding, Story #328: this crash was previously masked by an
# unchecked command substitution and surfaced instead as a misleading "no
# resolvable ontology bindings at all" error).
TYPES_ERR="$T/types-err.txt"
TYPES_TSV="$T/resolved-types.tsv"
jq -r -e --slurpfile ids "$RESOURCE_IDS_FILE" '
  (map(select(.entity_type != null and .entity_type != "")) | map({key: .finding_id, value: .entity_type}) | from_entries) as $types
  | $ids[0][] as $id
  | ($types[$id]) as $t
  | if ($t == null) then
      error("no ontology-map.json entry (or no entity_type) for \($id) -- run /ontology-review first")
    else
      "\($id)\t\($t)"
    end
' "$ONTOLOGY_MAP" > "$TYPES_TSV" 2>"$TYPES_ERR"
[ -s "$TYPES_ERR" ] && fail "$(cat "$TYPES_ERR")"

# Both bulk passes above succeeded for every resolved id -- now it is safe to
# actually write.
DIGESTS_FILE="$T/digests.txt"
: > "$DIGESTS_FILE"
RESOURCES_JSON="$T/resources.jsonl"
: > "$RESOURCES_JSON"
# Process substitution (not a `... | while` pipe): a pipe's RHS runs in a
# subshell in bash, where `fail`'s `exit 1` would only kill the subshell,
# letting the main script silently continue past a copy/digest failure.
while IFS=$'\t' read -r rid existing _rid2 ontology_type; do
  # LOOKUP_TSV and TYPES_TSV are independently-generated jq passes over the
  # same $RESOURCE_IDS_FILE, joined positionally by `paste` -- this assertion
  # is the only thing standing between that positional join and a silently
  # mis-paired ontology_type if either jq filter's row order ever diverges
  # (review finding, Story #328).
  [ "$rid" = "$_rid2" ] || fail "internal error: id/type lookup misalignment ($rid != $_rid2) -- this should be unreachable"
  base="$(basename "$existing")"
  cp "$existing" "$OUTPUT_DIR/findings/$base" || fail "failed to copy $existing"
  digest="$(scripts/mif-container-digest.sh resource "$OUTPUT_DIR/findings/$base")" \
    || fail "failed to compute the digest of $base"
  echo "$digest" >> "$DIGESTS_FILE"
  jq -n -c --arg path "findings/$base" --arg ot "$ontology_type" --arg d "$digest" \
    '{mifType: "finding", path: $path, ontologyType: $ot, digest: $d}' >> "$RESOURCES_JSON"
done < <(paste "$LOOKUP_TSV" "$TYPES_TSV")

if [ "$SCOPE_TYPE" = "full" ]; then
  cp "$ONTOLOGY_MAP" "$OUTPUT_DIR/ontology-map.json" || fail "failed to copy $ONTOLOGY_MAP"
else
  jq --slurpfile ids "$RESOURCE_IDS_FILE" '[.[] | select(.finding_id as $f | $ids[0] | index($f) != null)]' \
    "$ONTOLOGY_MAP" > "$OUTPUT_DIR/ontology-map.json" \
    || fail "failed to build the filtered ontology-map.json for the subset export"
fi
ONTMAP_DIGEST="$(scripts/mif-container-digest.sh resource "$OUTPUT_DIR/ontology-map.json")" \
  || fail "failed to compute the digest of $OUTPUT_DIR/ontology-map.json"
echo "$ONTMAP_DIGEST" >> "$DIGESTS_FILE"
jq -n -c --arg d "$ONTMAP_DIGEST" '{mifType: "ontology-map", path: "ontology-map.json", ontologyType: null, digest: $d}' >> "$RESOURCES_JSON"

# --- Step 3: ontologyBindings[] + manifest ---------------------------------
# schemas/mif-container.schema.json requires ontologyBindings[] to be
# non-empty even when resources[] is legitimately empty (a subset selector
# matching nothing is a valid export, not an error -- see the note above).
# Fall back to the FULL topic's ontology-map.json (not the in-scope-filtered
# one) so the manifest still declares the topic's real ontology usage
# instead of an empty array that would fail schema validation. KNOWN
# LIMITATION (review finding, Story #328, not fixed here): this fallback can
# make an empty-scope export declare a binding the destination hasn't
# vendored, which would then fail closed on import for an unrelated pack --
# narrow (empty subset AND an unrelated pack AND a fresh destination
# instance) and left as a documented limitation rather than reopening the
# minItems:1-vs-actual-usage schema question.
BINDINGS_FILTER='[.[] | .resolved_ontology] | map(select(. != null)) | unique | map(split("@") | {packId: .[0], version: .[1]})'
BINDINGS_JSON="$(jq -c "$BINDINGS_FILTER" "$OUTPUT_DIR/ontology-map.json")"
if [ "$(printf '%s' "$BINDINGS_JSON" | jq 'length')" -eq 0 ]; then
  BINDINGS_JSON="$(jq -c "$BINDINGS_FILTER" "$ONTOLOGY_MAP")"
fi
[ "$(printf '%s' "$BINDINGS_JSON" | jq 'length')" -gt 0 ] || fail "topic '$TOPIC' has no resolvable ontology bindings at all (ontology-map.json is empty) -- run /ontology-review first"
RESOURCES_ARRAY="$(jq -c -s '.' "$RESOURCES_JSON")"
MANIFEST_DIGEST="$(scripts/mif-container-digest.sh manifest < "$DIGESTS_FILE")" \
  || fail "failed to compute the manifest-level digest"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
  --arg ns "$SOURCE_INSTANCE" \
  --arg scopeType "$SCOPE_TYPE" \
  --arg topic "$TOPIC" \
  --arg selectorStr "$SELECTOR_STR" \
  --argjson selectorIsNull "$([ "$SELECTOR_IS_NULL" -eq 1 ] && echo true || echo false)" \
  --arg generatedAt "$GENERATED_AT" \
  --argjson bindings "$BINDINGS_JSON" \
  --argjson resources "$RESOURCES_ARRAY" \
  --argjson boundaryReferences "$(cat "$BOUNDARY_REFS_FILE")" \
  --arg manifestDigest "$MANIFEST_DIGEST" \
  --arg createdAt "$GENERATED_AT" \
  '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: $ns, corpusUrl: null},
    exportScope: {type: $scopeType, topic: $topic, selector: (if $selectorIsNull then null else $selectorStr end), generatedAt: $generatedAt},
    ontologyBindings: $bindings,
    resources: $resources,
    boundaryReferences: $boundaryReferences,
    manifestDigest: $manifestDigest,
    createdAt: $createdAt
  }' > "$OUTPUT_DIR/mif-package.json" || fail "failed to write $OUTPUT_DIR/mif-package.json"

ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/mif-container.schema.json -d "$OUTPUT_DIR/mif-package.json" > /dev/null 2>&1 \
  || fail "the manifest this script just wrote does not validate against schemas/mif-container.schema.json -- this should be unreachable"

EXPORT_OK=1
echo "mif-container-export: exported $RESOURCE_COUNT finding(s) ($SCOPE_TYPE scope) from '$TOPIC' to $OUTPUT_DIR"
