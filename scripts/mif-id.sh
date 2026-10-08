#!/usr/bin/env bash
# mif-id.sh — mint a MIF 1.4 concept id (urn:mif:<uuid>) with the org-wide rule.
#
# MIF 1.4 requires every concept @id to be urn:mif:<uuid>. The org mints it
# deterministically as uuid5(NS, "<remainder>"), NS = uuid5(NAMESPACE_URL,
# "https://mif-spec.dev"), where <remainder> is what used to follow `urn:mif:`
# in the legacy structured id. Same rule as mif-rs (mif_core::concept_urn), so
# the engine and the template agree on every id. See scripts/lib/mif_id.py.
#
# Usage:
#   mif-id.sh concept:<namespace>:<slug>     # a finding     -> urn:mif:<uuid>
#   mif-id.sh source:<namespace>:<slug>      # a source envelope
#   mif-id.sh report:<namespace>:<slug>      # a rendered report (blog:/book:/doc: likewise)
#   mif-id.sh urn:mif:concept:<ns>:<slug>    # a legacy id -> its migrated id
#   mif-id.sh --slug <doc-id>                # a bare uuid for a doc's frontmatter `id:`
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/lib/mif_id.py" "$@"
