#!/usr/bin/env bash
# reconcile-session.sh — derive a durable session checkpoint
# (reports/<topic>/state.json) purely from disk and print the remaining-work plan.
# Crash-safe resume (SPEC §6b): a finding is DONE iff it validates against
# schemas/findings.schema.json — which REQUIRES extensions.harness.verification
# (verdict + verdict_basis), so a valid finding has already been through the
# falsification gate. Raw/partial/invalid findings and *.tmp / hidden partial
# writes are EXCLUDED from done-counts, so /resume never reworks a completed
# finding (re-running burns expensive web research + falsification budget).
#
# A finding is found WHEREVER it lives: the canonical reports/<topic>/findings/
# subdir AND, defensively, a flat reports/<topic>/finding-*.json — a real finding
# must never be missed, or its dimension would be re-run from scratch.
#
# Idempotent and byte-deterministic: no wall-clock field, sorted records, jq -S.
#
# Since research-harness-template#276 (Story #282, Category B cutover), this
# delegates to the mif-rh engine (mif-rh-cli), hard required: install it with
# scripts/fetch-engine.sh, put mif-rh-cli on PATH, or set MIF_RH_CLI.
#
# Usage: reconcile-session.sh <reports-dir>
#   writes <reports-dir>/state.json; prints the remaining plan to stdout; exit 0.
#   exit 4: the corpus still carries pre-MIF-1.4 structured ids (run
#   scripts/migrate-mif-ids.py first; nothing written).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

RD="${1:?usage: reconcile-session.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
[ -d "$RD" ] || { echo "reconcile: not a directory: $RD" >&2; exit 2; }

# MIF 1.4 guard. Since the template vendors MIF 1.4.1, a finding is valid only
# with a urn:mif:<uuid> @id. A corpus written before that (structured
# urn:mif:concept:<ns>:<slug> ids) would read as entirely NOT done -- every
# completed finding "invalid" -- and a resume would re-run all of its research
# and falsification. Refuse instead, naming the one-time migration.
LEGACY="$(
  find "$RD/findings" -maxdepth 1 -name '*.json' 2>/dev/null
  find "$RD" -maxdepth 1 -name 'finding-*.json' 2>/dev/null
)"
if [ -n "$LEGACY" ]; then
  LEGACY="$(printf '%s\n' "$LEGACY" | while IFS= read -r f; do
    jq -r --arg f "$f" '."@id" // empty
      | select(startswith("urn:mif:")
               and (test("^urn:mif:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") | not)
               and (test("^urn:mif:(entity|agent|activity|conversation|vector):") | not))
      | $f' "$f" 2>/dev/null
  done)"
fi
if [ -n "$LEGACY" ]; then
  echo "reconcile: $(printf '%s\n' "$LEGACY" | wc -l | tr -d ' ') finding(s) under $RD carry a pre-MIF-1.4 structured @id, which the vendored MIF 1.4.1 schema rejects -- refusing to reconcile (every one would count as not done and be re-researched). Migrate the corpus once, then re-run:" >&2
  echo "  find reports -type f \\( -name '*.json' -o -name '*.md' -o -name '*.html' \\) -exec python3 scripts/migrate-mif-ids.py --write --aliases {} +   # from the repo root; see docs/how-to/update-your-harness.md" >&2
  printf '%s\n' "$LEGACY" | head -5 | sed 's/^/  e.g. /' >&2
  exit 4
fi

exec "$ENGINE" harness reconcile-session "$RD" \
  --schema "$ROOT/schemas/findings.schema.json" \
  --ref "$ROOT/schemas/mif/mif.schema.json" \
  --ref "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
  --sample "$ROOT/schemas/samples/finding.sample.json"
