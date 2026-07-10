#!/usr/bin/env bash
# mif-container-detect-sameas.sh — candidate concordance sameAs detector
# (Story #324, Task #327, ADR-0017 AD-6).
#
# A cross-instance import can introduce two nodes that represent the same
# real-world concept/entity under two DIFFERENT @ids (each instance having
# independently minted its own id for it). This never gets merged
# automatically -- it is surfaced as a reviewable proposal, requiring a
# human's explicit confirmation before any two ids are treated as the same
# thing. This script only detects and reports; it never rewrites @ids,
# never touches concordance.json, and never merges anything.
#
# Heuristic (M1): any two DISTINCT-id nodes of the SAME kind (concept-concept
# or entity-entity, never cross-kind) whose labels are identical after
# normalization (trim + casefold) are a candidate pair. This is intentionally
# conservative-recall (may surface false positives for a human to reject) --
# never conservative-precision (silently dropping a real duplicate).
#
# Usage: mif-container-detect-sameas.sh <concordance.json>
#   Prints a proposals JSON object to stdout: {"proposals": [...]}. Always
#   produces the object (empty proposals[] if no candidates), deterministic
#   and idempotent like every other artifact this repo rebuilds.
set -uo pipefail

[ "$#" -eq 1 ] || {
  echo "usage: mif-container-detect-sameas.sh <concordance.json>" >&2
  exit 2
}
CONCORDANCE="$1"
[ -f "$CONCORDANCE" ] || { echo "mif-container-detect-sameas: concordance file not found: $CONCORDANCE" >&2; exit 2; }
[ -r "$CONCORDANCE" ] || { echo "mif-container-detect-sameas: concordance file not readable: $CONCORDANCE" >&2; exit 2; }

jq -c '
  # Normalize: trim + casefold. Group by (kind, normalized label); any group
  # with more than one DISTINCT id is a candidate cluster. A single pass
  # (not a separate presence-check pass first) -- jq'"'"'s `//` treats only
  # `false`/`null` as falsy, so an empty (but present) nodes[] correctly
  # skips the error() branch below.
  (.nodes // error("does not have a .nodes[] array -- not a valid concordance"))
  | map(. + {_norm: (.label | ascii_downcase | gsub("^\\s+|\\s+$"; ""))})
  | group_by([.kind, ._norm])
  | map(select((map(.id) | unique | length) > 1))
  | map(
      (.[0].kind) as $kind
      | (.[0]._norm) as $norm
      | ([.[].id] | unique | sort) as $ids
      | [range(0; ($ids | length) - 1) as $i
         | range($i + 1; ($ids | length)) as $j
         | {a: $ids[$i], b: $ids[$j], kind: $kind, reason: "label-match", label: $norm}]
    )
  | flatten
  | {proposals: (. | sort_by(.a, .b))}
' "$CONCORDANCE" || { echo "mif-container-detect-sameas: jq failed to process $CONCORDANCE" >&2; exit 1; }
