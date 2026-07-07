#!/usr/bin/env bash
# check-shippable-typing.sh — fail-closed pre-synthesis gate (ADR-0011). A finding that
# SHIPS (extensions.harness.verification.verdict in survived|weakened) MUST resolve to a
# valid ontology type. Untyped/unresolved/invalid/missing-from-map shippable findings BLOCK
# synthesis (exit 1); an UNPARSEABLE finding file also blocks (its verdict/type are
# unknowable — fail closed). Falsified/quarantined/inconclusive never block. Read-only.
#
# This covers the gap validate-concordance.sh structurally cannot see: a concept node for an
# untyped finding gets entityType:null (build-concordance.sh), and validate-concordance.sh
# filters `entityType != null`, so an untyped shippable finding passes the spine validator
# VACUOUSLY. This gate refuses to SHIP such a finding.
#
# Usage: check-shippable-typing.sh <reports-dir>     # e.g. reports/<topic>
#   exit 0 = all shippable findings carry a valid ontology type
#   exit 1 = one or more shippable findings are untyped/unresolved/invalid (synthesis BLOCKED)
#   exit 2 = reports-dir does not exist ; exit 3 = ontology-map.json missing/unparseable (cannot prove typing)
#   exit 5 = mif-rh-cli engine not found (cannot evaluate typing — fail closed)
#
# Since research-harness-template#276 (Story #287, Category B cutover), typing
# resolution (discovery, verdict/basis lookup, blocker formatting) delegates to
# the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI. The
# reports-dir usage/existence check (pure bash, never used jq) stays as-is.

set -uo pipefail
RD="${1:?usage: check-shippable-typing.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
# Guard the reports-dir, NOT $RD/findings: discovery scans both the findings/ subdir
# AND a flat reports/<topic>/finding-*.json, matching reconcile-session.sh's list_findings — so
# a flat-only/legacy layout (or a topic without a findings/ subdir) must reach the scan, not be
# rejected here. A genuinely empty topic yields no blockers (nothing to gate), which is correct.
[ -d "$RD" ] || { echo "check-shippable-typing: reports dir does not exist: $RD" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

exec "$ENGINE" harness check-shippable-typing "$RD"
