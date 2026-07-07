#!/usr/bin/env bash
# check-relationship-targets.sh — prove every relationships[].target in the
# active corpus resolves to a real finding @id.
#
# Root cause this closes (2026-07): relationships[].target is authored by an
# LLM analyst (dimension-analyst.md Step 5c: "target is the sibling finding's
# full @id... Re-validate the finding after adding relationships[]") with no
# machine-checked step backing that instruction — unlike citation-integrity,
# which has an actual `scripts/check-citation-integrity.sh` call at write
# time. That let bare/guessed slugs (e.g. "f-competitive-1" instead of the
# real "findings-competitive-f-competitive-1-0") land unnoticed. Separately,
# falsification-analyst.md's quarantine step ("move the finding file to
# $REPORTS_DIR/quarantine/... removed from the active set") never cascades to
# other findings' inbound relationships, leaving dangling references to a
# finding that used to be active.
#
# The "real @id" universe is corpus-wide (@id is a globally unique URN) and
# ACTIVE-ONLY: only <topic>/findings/*.json is globbed, so quarantine/ and
# archive/ are excluded, matching falsification-analyst.md's own working-set
# definition ("the quarantine/ and archive/ siblings are separate and
# excluded").
#
# KNOWN LIMITATION: dimension-analyst.md permits a target that is "a urn:mif:
# id of an external concept" outside this corpus. This gate cannot distinguish
# a legitimate external reference from a typo/dangling reference — it treats
# every urn:mif:concept: target not found in the active-id universe as a
# finding. If a genuine external target is ever introduced, this gate will
# need an allowlist; as of this writing zero such references exist in the
# corpus (verified by a full scan), so no allowlist is implemented yet.
#
# Usage: check-relationship-targets.sh [--reports-dir <path>]
#   exit 0 = every relationships[].target resolves to an active finding @id
#   exit 1 = one or more orphaned targets found (each printed as
#            "ORPHAN\t<source-file>\t<orphaned-target>")
#   exit 2 = usage/environment error (missing engine, missing reports dir, or
#            a finding file that cannot be parsed — see below for why this
#            must be a hard failure rather than a silent skip)
#   exit 5 = mif-rh-cli engine not found (fail closed)
#
# Since research-harness-template#276 (Story #287, Category B cutover), the
# active-@id/target universes and orphan detection delegate to the mif-rh
# engine (mif-rh-cli), hard required: install it with scripts/fetch-engine.sh,
# put mif-rh-cli on PATH, or set MIF_RH_CLI. The argument parsing and
# reports-dir existence check (pure bash, never used jq) stay as-is.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RD="$ROOT/reports"
while [ $# -gt 0 ]; do
  case "$1" in
    --reports-dir) RD="$2"; shift 2 ;;
    *) echo "check-relationship-targets: unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -d "$RD" ] || { echo "check-relationship-targets: reports dir not found: $RD" >&2; exit 2; }

# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" harness check-relationship-targets --reports-dir "$RD"
