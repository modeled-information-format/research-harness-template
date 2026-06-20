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
# Usage: reconcile-session.sh <reports-dir>
#   writes <reports-dir>/state.json; prints the remaining plan to stdout; exit 0.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

RD="${1:?usage: reconcile-session.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
[ -d "$RD" ] || { echo "reconcile: not a directory: $RD" >&2; exit 2; }
FDIR="$RD/findings"
TOPIC="$(basename "$RD")"

ajv_ok() { # validate one finding file against the MIF-backed findings schema
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s "$ROOT/schemas/findings.schema.json" \
    -r "$ROOT/schemas/mif/mif.schema.json" \
    -r "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
    -d "$1" >/dev/null 2>&1
}

# Fail SAFE, not open. If the ajv toolchain cannot validate a KNOWN-GOOD finding,
# the environment is broken (ajv missing, schema refs unresolvable, wrong cwd,
# node broken). Do NOT then read every finding as invalid and emit a
# "re-run everything" plan — that re-runs the entire expensive session. Abort with
# no state.json and no plan; the caller must treat a non-zero exit as
# "cannot determine remaining work — stop", never as "everything remaining".
if ! ajv_ok "$ROOT/schemas/samples/finding.sample.json"; then
  echo "reconcile: ajv cannot validate the known-good sample finding — toolchain/environment is broken." >&2
  echo "reconcile: refusing to emit a plan (it would falsely mark every finding remaining and re-run the whole session)." >&2
  exit 3
fi

# All real finding files: findings/<*>.json (canonical) + flat finding-*.json
# (defensive). Hidden (.*) and *.tmp are in-flight partial writes; skip them.
list_findings() {
  {
    [ -d "$FDIR" ] && find "$FDIR" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp'
    find "$RD" -maxdepth 1 -type f -name 'finding-*.json' ! -name '.*' ! -name '*.tmp'
  } 2>/dev/null | sort -u
}

partial_count=$( { [ -d "$FDIR" ] && find "$FDIR" -maxdepth 1 -type f -name '*.tmp'
                   find "$RD" -maxdepth 1 -type f -name '*.tmp'; } 2>/dev/null | wc -l | tr -d ' ')

records="[]"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  id=$(jq -r '."@id" // .id // empty' "$f" 2>/dev/null); [ -z "$id" ] && id="$(basename "$f")"
  dim=$(jq -r '.extensions.harness.dimension // "unknown"' "$f" 2>/dev/null)
  att=$(jq -r '.extensions.harness.verification.attempted_at // empty' "$f" 2>/dev/null)
  vrd=$(jq -r '.extensions.harness.verification.verdict // empty' "$f" 2>/dev/null)
  if ajv_ok "$f"; then valid=true; else valid=false; fi
  records=$(jq -c --arg id "$id" --arg dim "$dim" --argjson valid "$valid" \
                  --arg att "$att" --arg vrd "$vrd" \
    '. + [{id:$id, dimension:$dim, valid:$valid,
           attempted_at:(if $att=="" then null else $att end),
           verdict:(if $vrd=="" then null else $vrd end)}]' <<<"$records")
done < <(list_findings)

# DONE = valid AND not falsified. Validity REQUIRES a verdict, so a valid finding
# has been gated; a falsified finding is valid but is NOT done — its dimension needs
# a replacement (falsify.sh normally quarantines it out of findings/; this is the
# belt-and-suspenders guard). Invalid findings count toward total, never toward done.
state=$(jq -S -n --arg topic "$TOPIC" --argjson f "$records" '
  def isdone: .valid and (.verdict != "falsified");
  ($f | sort_by(.id)) as $findings
  | ($findings | group_by(.dimension) | map({
       key: .[0].dimension,
       value: { total: length, done: ([.[] | select(isdone)] | length) }
    }) | from_entries) as $dims
  | { topic: $topic, findings: $findings, dimensions: $dims,
      checks: [
        {check:"findings_present",    passed: (($findings | map(select(isdone)) | length) > 0)},
        {check:"no_invalid_findings", passed: (($findings | map(select(.valid | not)) | length) == 0)}
      ] }')

if [ "$partial_count" -eq 0 ]; then nptw=true; else nptw=false; fi
state=$(jq -S --argjson nptw "$nptw" \
  '.checks += [{check:"no_partial_writes", passed:$nptw}] | .checks |= sort_by(.check)' <<<"$state")

printf '%s\n' "$state" > "$RD/.state.json.staging" && mv "$RD/.state.json.staging" "$RD/state.json"

plan=$(jq -r '
  ( [ .dimensions | to_entries[] | select(.value.done < .value.total)
      | "dimension \(.key): \(.value.total - .value.done) finding(s) need work" ] )
  + ( [ .checks[] | select(.passed | not) | "check \(.check): FAIL" ] )
  | sort | .[]' "$RD/state.json")

if [ -z "$plan" ]; then
  echo "nothing to do"
else
  echo "REMAINING WORK PLAN"
  printf '%s\n' "$plan"
fi
