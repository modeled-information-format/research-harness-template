#!/usr/bin/env bash
# mif-id.sh (lib) — MIF 1.4 concept-id helpers for the bash tooling.
#
# Sourced, not executed. MIF 1.4 requires a concept @id of the form
# urn:mif:<uuid>; scripts/lib/mif_id.py holds the org-wide minting rule
# (uuid5 in the MIF namespace of the remainder after `urn:mif:`).
#
# Engine compatibility shim: mif-rh-cli up to and including the version pinned
# in scripts/fetch-engine.sh still composes legacy structured ids for the
# artifacts it mints itself (urn:mif:source:<ns>:<slug> from `harness
# wrap-source`, urn:mif:<channel>:<ns>:<slug> from `harness render-artifact`).
# mif-rs#164 moves the engine to the same uuid5 rule; until an engine release
# carrying it is pinned, the wrappers rewrite the engine's legacy id with
# exactly the id that release will mint, record the legacy id in `aliases`,
# and validate the result against the vendored MIF 1.4 schema. Once the engine
# mints urn:mif:<uuid> itself every helper here is a no-op (mif_id.py is
# idempotent on a concept URN), so the shim can be deleted with no data change.

_MIF_ID_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mif_concept_urn <remainder-or-legacy-urn> — print the urn:mif:<uuid> id.
mif_concept_urn() {
  python3 "$_MIF_ID_LIB_DIR/mif_id.py" "$1"
}

# mif_fm_migrate_id <file.md> — if the markdown file's frontmatter @id is a
# legacy structured id, replace it with its urn:mif:<uuid> form and append the
# legacy id to `aliases`. No-op on an already-migrated or absent @id.
mif_fm_migrate_id() {
  local f="$1" old new
  old="$(yq --front-matter=extract '.["@id"] // ""' "$f")" || return 1
  case "$old" in ""|null) return 0 ;; esac
  new="$(mif_concept_urn "$old")" || return 1
  [ "$new" = "$old" ] && return 0
  OLD_ID="$old" NEW_ID="$new" yq --front-matter=process -i \
    '.["@id"] = strenv(NEW_ID) | .aliases = (((.aliases // []) + [strenv(OLD_ID)]) | unique)' "$f"
}

# mif_json_migrate_id <in.json> <out.json> [jq-filter [jq-args...]] — write
# <in.json> to <out.json> with a legacy top-level @id replaced by its
# urn:mif:<uuid> form (the legacy id appended to `aliases`), then apply the
# optional extra jq filter; any further arguments (e.g. --arg ns "$NS") are
# passed to that jq call. An already-migrated or absent @id is left as is.
mif_json_migrate_id() {
  local in="$1" out="$2" extra="${3:-.}" old new
  shift 2; [ "$#" -gt 0 ] && shift
  old="$(jq -r '."@id" // ""' "$in")" || return 1
  new="$old"
  if [ -n "$old" ]; then
    new="$(mif_concept_urn "$old")" || return 1
  fi
  if [ "$new" = "$old" ]; then
    jq "$@" "$extra" "$in" > "$out"
  else
    jq --arg old_id "$old" --arg new_id "$new" "$@" \
      '."@id" = $new_id | .aliases = (((.aliases // []) + [$old_id]) | unique) | '"$extra" "$in" > "$out"
  fi
}

# mif_compat_schema <vendored-mif.schema.json> <out.json> — write a copy of the
# vendored MIF schema whose concept @id pattern is relaxed to the pre-1.4
# "^urn:mif:" prefix (same $id), for the engine's own internal validation pass
# while it still composes legacy ids. Never used for a final verdict: the
# wrapper re-validates the migrated document against the real vendored schema.
mif_compat_schema() {
  jq '.properties["@id"].pattern = "^urn:mif:"' "$1" > "$2"
}
