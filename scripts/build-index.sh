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
# Since research-harness-template#276 (Story #293, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: build-index.sh <findings-dir> [<out.json>]
#        default out: <findings-dir>/../research-index.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

DIR="${1:?usage: build-index.sh <findings-dir> [out.json]}"
[ -d "$DIR" ] || { echo "build-index: not a directory: $DIR" >&2; exit 2; }

if [ -n "${2:-}" ]; then
  exec "$ENGINE" harness build-index "$DIR" "$2"
fi
exec "$ENGINE" harness build-index "$DIR"
