#!/usr/bin/env bash
# Citation-integrity gate (SPEC §4 "Verifier/citation-integrity layer", §6c/§6d).
#
# Reference-hallucination and citation-quality failures are the dominant deep-
# research failure mode, so citation verification is a CORE gate that travels
# with the engine. This script asserts, over one or more MIF-backed findings
# files (a single finding object or an array of them):
#
#   1. every finding carries at least one citation (MIF Level 3);
#   2. every citation is traceable to a source — EITHER a well-formed http(s) URL
#      (web source) OR an internal/document citation (citationType ^internal:
#      carrying the quoted evidence in `note`) — and has a citationRole;
#   3. no finding ships with an adversarial verdict of "falsified";
#   4. no citation URL is listed dead (extensions.harness.citationStatus.deadUrls[]).
#
# Exit 0 = all findings pass (GOOD). Exit 1 = at least one violation (BAD),
# with one `file:finding-id: reason` line per violation.
#
# Usage: check-citation-integrity.sh <findings.json> [<findings.json> ...]
#
# Since research-harness-template#276 (Story #287, Category B cutover), the
# citation checks delegate to the mif-rh engine (mif-rh-cli), hard required:
# install it with scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set
# MIF_RH_CLI. Argument validation (pure bash, never used jq) stays as-is.

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: check-citation-integrity.sh <findings.json> [...]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

# Feature flag (SPEC §7): internal/document citations are accepted as traceable
# ONLY when harness.config.json opts in via features.internalCitations. The
# template ships strict (flag absent/false => http(s)-only); an instance that
# imported a legacy corpus with internal sources enables it. HARNESS_CONFIG
# overrides the config path.
CONFIG="${HARNESS_CONFIG:-harness.config.json}"

exec "$ENGINE" harness check-citation-integrity "$@" --config "$CONFIG"
