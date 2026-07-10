#!/usr/bin/env bash
# mif-container-migration-eval-bench.sh -- Story #334 (Epic #275, AD-7).
#
# Measures whether the current shell/jq mif-container-export.sh /
# -import.sh implementation has a REAL performance bottleneck at a corpus
# scale analogous to ADR-0014's own reference bottleneck (4296 findings,
# 20+ minutes, per-finding subprocess spawning across yq/jq/ajv) -- the
# exact trigger condition AD-7 names for migrating this logic into
# mif-rh-cli as new subcommands. Not a permanent gate: a one-time (or
# re-run-on-demand) evaluation tool, not wired into verify.sh/run-evals.sh.
#
# Builds a synthetic topic of N schema-valid findings (default 4300,
# matching ADR-0014's 4296 reference scale for an apples-to-apples
# comparison), then times:
#   1. export.sh   -- full export of the synthetic topic
#   2. import.sh    -- import into a FRESH topic (new-@id upsert path)
#   3. import.sh again into the SAME now-populated topic (re-import /
#      existing-@id upsert path -- import.sh's own code takes a second
#      digest.sh subprocess call per finding on this path, so it is
#      timed separately as the more expensive of the two import paths)
#
# Exit 0 on success; non-zero (see individual FAIL messages) if any backup,
# generation, export, or import step fails -- prints wall-clock numbers and
# a summary a human reads to judge AD-7 on success.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

N="${1:-4300}"
EXPORT="scripts/mif-container-export.sh"
IMPORT="scripts/mif-container-import.sh"
SRC_TOPIC="mif-rh-cli-eval-bench-source"
FRESH_TOPIC="mif-rh-cli-eval-bench-fresh"
note() { printf '  mif-container-migration-eval-bench: %s\n' "$1"; }

# Fail closed BEFORE any backup/mutation if either synthetic topic id
# collides with a real, pre-existing topic (registered in harness.config.json
# OR a reports/<id> directory already on disk) -- this script's cleanup does
# an unconditional `rm -rf reports/$SRC_TOPIC reports/$FRESH_TOPIC`, which
# would delete real corpus data on a collision instead of just synthetic
# scratch state.
for id in "$SRC_TOPIC" "$FRESH_TOPIC"; do
  if jq -e --arg id "$id" '.topics[] | select(.id == $id)' harness.config.json > /dev/null 2>&1; then
    note "FAIL: topic id '$id' is already registered in harness.config.json -- refusing to run (this script's cleanup deletes reports/$id, which would destroy real data)"
    exit 1
  fi
  if [ -e "reports/$id" ]; then
    note "FAIL: reports/$id already exists on disk -- refusing to run (this script's cleanup deletes it)"
    exit 1
  fi
done

T="$(mktemp -d)" || { note "FAIL: could not create scratch dir"; exit 1; }

cp harness.config.json "$T/harness.config.json.orig" \
  || { note "FAIL: could not back up harness.config.json"; rm -rf "$T"; exit 1; }
cp reports/concordance.json "$T/concordance.json.orig" \
  || { note "FAIL: could not back up reports/concordance.json"; rm -rf "$T"; exit 1; }
had_sameas=0
[ -f reports/concordance-sameas-proposals.json ] && {
  had_sameas=1
  cp reports/concordance-sameas-proposals.json "$T/concordance-sameas-proposals.json.orig" \
    || { note "FAIL: could not back up concordance-sameas-proposals.json"; rm -rf "$T"; exit 1; }
}

cleanup() {
  cp "$T/harness.config.json.orig" harness.config.json \
    || note "FAIL: could not restore harness.config.json from backup -- check $T/harness.config.json.orig manually"
  cp "$T/concordance.json.orig" reports/concordance.json \
    || note "FAIL: could not restore reports/concordance.json from backup -- check $T/concordance.json.orig manually"
  if [ "$had_sameas" -eq 1 ]; then
    cp "$T/concordance-sameas-proposals.json.orig" reports/concordance-sameas-proposals.json \
      || note "FAIL: could not restore concordance-sameas-proposals.json from backup -- check $T/concordance-sameas-proposals.json.orig manually"
  else
    rm -f reports/concordance-sameas-proposals.json
  fi
  rm -rf "reports/$SRC_TOPIC" "reports/$FRESH_TOPIC"
  rm -rf "$T"
}
trap cleanup EXIT

register_topic() {
  local id="$1"
  # Defense-in-depth: the same collision check runs up front for both
  # topic ids before any backup/mutation, but this function is the actual
  # dangerous operation (appends to harness.config.json, creates
  # reports/<id>/) -- re-check here too, since a future caller of this
  # function might not go through the up-front loop.
  if jq -e --arg id "$id" '.topics[] | select(.id == $id)' harness.config.json > /dev/null 2>&1; then
    note "FAIL: refusing to register '$id' -- already present in harness.config.json"
    exit 1
  fi
  if [ -e "reports/$id" ]; then
    note "FAIL: refusing to register '$id' -- reports/$id already exists on disk"
    exit 1
  fi
  jq --arg id "$id" '.topics += [{id: $id, title: "mif-rh-cli migration eval synthetic instance", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$T/harness.config.json.next" \
    && mv "$T/harness.config.json.next" harness.config.json \
    || { note "FAIL: could not register synthetic topic $id"; exit 1; }
  mkdir -p "reports/$id/findings"
}

note "generating $N synthetic schema-valid findings (this takes a while)..."
register_topic "$SRC_TOPIC"
TEMPLATE="reports/example-okf-mif-knowledge-spine/findings/finding-landscape-frictionless-data-packages.json"
i=0
while [ "$i" -lt "$N" ]; do
  slug="synthetic-finding-$i"
  jq --arg id "urn:mif:concept:harness/$SRC_TOPIC:$slug" \
     --arg ns "harness/$SRC_TOPIC" \
     --arg title "Synthetic bench finding $i" \
     '.["@id"] = $id | .namespace = $ns | .title = $title | .relationships = []' \
     "$TEMPLATE" > "reports/$SRC_TOPIC/findings/finding-$slug.json" \
    || { note "FAIL: could not generate synthetic finding $i"; exit 1; }
  i=$((i + 1))
  if [ "$((i % 500))" -eq 0 ]; then note "  ...$i/$N generated"; fi
done
jq -n --arg id_prefix "urn:mif:concept:harness/$SRC_TOPIC:synthetic-finding-" \
  --argjson n "$N" \
  '[range(0; $n) | {finding_id: ($id_prefix + (. | tostring)), entity_type: "technology", resolved_ontology: "mif-generic@1.0.0", basis: "declared", valid: true}]' \
  > "reports/$SRC_TOPIC/ontology-map.json" \
  || { note "FAIL: could not build synthetic ontology-map.json"; exit 1; }
note "generated $N findings + ontology-map.json for $SRC_TOPIC"

OUT="$T/bench-export"
note "timing: export.sh (full export of $N findings)..."
EXPORT_START=$(date +%s)
"$EXPORT" "$SRC_TOPIC" "$OUT" > "$T/export.log" 2>&1
EXPORT_RC=$?
EXPORT_END=$(date +%s)
EXPORT_SECS=$((EXPORT_END - EXPORT_START))
if [ "$EXPORT_RC" -ne 0 ]; then
  note "FAIL: export.sh exited $EXPORT_RC -- see $T/export.log"
  cat "$T/export.log" >&2
  exit 1
fi
note "export.sh: ${EXPORT_SECS}s for $N findings (rc=$EXPORT_RC)"

register_topic "$FRESH_TOPIC"
note "timing: import.sh into a FRESH topic (new-@id upsert path)..."
IMPORT1_START=$(date +%s)
"$IMPORT" "$OUT" "$FRESH_TOPIC" > "$T/import1.log" 2>&1
IMPORT1_RC=$?
IMPORT1_END=$(date +%s)
IMPORT1_SECS=$((IMPORT1_END - IMPORT1_START))
if [ "$IMPORT1_RC" -ne 0 ]; then
  note "FAIL: import.sh (fresh) exited $IMPORT1_RC -- see $T/import1.log"
  cat "$T/import1.log" >&2
  exit 1
fi
note "import.sh (fresh, new-@id): ${IMPORT1_SECS}s for $N findings (rc=$IMPORT1_RC)"

note "timing: import.sh AGAIN into the now-populated topic (existing-@id upsert path)..."
IMPORT2_START=$(date +%s)
"$IMPORT" "$OUT" "$FRESH_TOPIC" > "$T/import2.log" 2>&1
IMPORT2_RC=$?
IMPORT2_END=$(date +%s)
IMPORT2_SECS=$((IMPORT2_END - IMPORT2_START))
if [ "$IMPORT2_RC" -ne 0 ]; then
  note "FAIL: import.sh (re-import) exited $IMPORT2_RC -- see $T/import2.log"
  cat "$T/import2.log" >&2
  exit 1
fi
note "import.sh (re-import, existing-@id): ${IMPORT2_SECS}s for $N findings (rc=$IMPORT2_RC)"

echo
note "=== SUMMARY ($N findings) ==="
note "export.sh:                        ${EXPORT_SECS}s"
note "import.sh (fresh, new-@id):        ${IMPORT1_SECS}s"
note "import.sh (re-import, existing-@id): ${IMPORT2_SECS}s"
if [ "$N" -eq 4296 ]; then
  note "ADR-0014's own reference bottleneck: 20+ minutes for 4296 findings (ontology-review.sh, 3 subprocess tools/finding)"
  note "AD-7's PDD-1-style bar (per ADR-0014): low-single-digit-minutes-or-better"
else
  note "(compare per-finding rate against other N runs to extrapolate to ADR-0014's 4296-finding reference scale)"
fi
