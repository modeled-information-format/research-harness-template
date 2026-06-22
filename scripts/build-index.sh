#!/usr/bin/env bash
# build-index.sh — incremental research-index maintenance over the MIF substrate
# (SPEC §4a: replace tag-derived recomputation with incremental maintenance).
#
# Emits a flat index of every MIF finding (id, title, dimension, tags, namespace,
# verdict, citation count) that the search/discover/topics services read. The
# index is a projection of the MIF files, so it is always reproducible from them.
#
# It also projects the goal-version membership mirror (SPEC §11): for each finding,
# goal_versions[] (which goal versions it is in scope for) and stale_in[] (the
# versions where its verification has decayed), derived from the authoritative
# per-version members files at <findings-dir>/../goals/*.members.json. The members
# files are the source of truth; this projection is re-derivable.
#
# Usage: build-index.sh <findings-dir> [<out.json>]
#        default out: <findings-dir>/../research-index.json

set -uo pipefail

DIR="${1:?usage: build-index.sh <findings-dir> [out.json]}"
OUT="${2:-$DIR/../research-index.json}"
[ -d "$DIR" ] || { echo "build-index: not a directory: $DIR" >&2; exit 2; }

# Collect file lists space-safely (the harness is a template cloned into arbitrary
# paths, which may contain spaces).
FILES=()
while IFS= read -r -d '' f; do FILES+=("$f"); done \
  < <(find "$DIR" -maxdepth 1 -name '*.json' -print0 | sort -z)
[ ${#FILES[@]} -gt 0 ] || { echo "build-index: no finding JSON in $DIR" >&2; exit 2; }
NFILES=${#FILES[@]}

# Membership map: finding-id -> { goal_versions[], stale_in[] }, folded over every
# per-version members file. Empty {} when no goal versions have been resolved yet.
# `// []` guards a foreign/legacy/partial members file missing a members/stale key
# (raw `[]` iteration would throw "Cannot iterate over null").
MEMBERS=()
while IFS= read -r -d '' f; do MEMBERS+=("$f"); done \
  < <(find "$DIR/../goals" -maxdepth 1 -name '*.members.json' -print0 2>/dev/null | sort -z)
if [ ${#MEMBERS[@]} -gt 0 ]; then
  # Skip any members file without a string `version` (legacy/partial) so a null
  # version is never projected into goal_versions[]/stale_in[] as a fake id.
  MEMBERSHIP=$(jq -s 'reduce .[] as $m ({};
    if ($m.version | type) == "string" then
      reduce (($m.members // [])[]) as $id (.; .[$id].goal_versions += [$m.version])
      | reduce (($m.stale // [])[]) as $id (.; .[$id].stale_in     += [$m.version])
    else . end )' \
    "${MEMBERS[@]}") || { echo "build-index: failed to fold membership files" >&2; exit 2; }
else
  MEMBERSHIP='{}'
fi

# Write atomically and fail loudly — a swallowed jq failure must not leave an empty
# index behind a "success" message that downstream services then read as valid.
TMP_OUT="$OUT.tmp.$$"
jq -s --argjson membership "$MEMBERSHIP" '{
  "@type": "ResearchIndex",
  count: length,
  findings: map({
    id: .["@id"],
    title: (.title // null),
    namespace: (.namespace // null),
    dimension: (.extensions.harness.dimension // null),
    tags: (.tags // []),
    verdict: (.extensions.harness.verification.verdict // null),
    citations: (.citations | length),
    goal_versions: (($membership[.["@id"]].goal_versions // []) | unique),
    stale_in: (($membership[.["@id"]].stale_in // []) | unique)
  })
}' "${FILES[@]}" > "$TMP_OUT" || { rm -f "$TMP_OUT"; echo "build-index: failed to build $OUT" >&2; exit 2; }
mv "$TMP_OUT" "$OUT"

echo "build-index: wrote $OUT ($(jq '.count' "$OUT") findings) from $NFILES MIF files"
