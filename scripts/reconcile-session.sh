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
  # Collapse duplicate @ids (the same finding can appear in both findings/ and the
  # flat legacy path). One record per id; prefer a DONE copy, else a valid copy, so
  # a stale invalid duplicate never demotes a completed finding back to rework.
  ($f | group_by(.id)
      | map( ( map(select(isdone)) | first ) // ( map(select(.valid)) | first ) // .[0] )
      | sort_by(.id)) as $findings
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

# Concordance status (ADR-0011): project the cross-topic spine's status into the
# checkpoint WHEN it has been built. The spine + its status sidecar live one level up
# from this topic dir (reports/concordance{,-status}.json) — a deliberate, existence-
# guarded exception to "purely from reports/<topic>". Absent concordance.json -> no
# concordance key (keeps temp-dir fixtures byte-identical). Deterministic: no wall-clock
# here; validated_at lives only in the sidecar. untyped_shippable mirrors the ship gate
# (scripts/check-shippable-typing.sh): count UNIQUE shippable (survived|weakened) findings
# whose ontology-map record is missing/invalid/untyped/unresolved. Dedupe by @id so a finding
# present in both the canonical findings/ path and a flat finding-*.json counts once; a
# missing/unparseable map means EVERY shippable finding is untyped (fail-closed, mirroring the
# gate's exit 3), not zero.
CONC="$RD/../concordance.json"; CSTAT="$RD/../concordance-status.json"
if [ -f "$CONC" ]; then
  mapok=false
  [ -f "$RD/ontology-map.json" ] && jq -e 'type=="array"' "$RD/ontology-map.json" >/dev/null 2>&1 && mapok=true
  uns=$(
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      v=$(jq -r '.extensions.harness.verification.verdict // empty' "$f" 2>/dev/null)
      [ "$v" = survived ] || [ "$v" = weakened ] || continue
      jq -r '."@id" // empty' "$f" 2>/dev/null
    done < <(list_findings) | sort -u | while IFS= read -r fid; do
      [ -z "$fid" ] && continue
      if [ "$mapok" != true ]; then echo x; continue; fi
      jq -e --arg id "$fid" '(map(select(.finding_id==$id))|first) as $r | ($r==null) or ($r.valid!=true) or ($r.basis=="untyped") or ($r.basis=="unresolved")' "$RD/ontology-map.json" >/dev/null 2>&1 && echo x
    done | grep -c x
  )
  [ -z "$uns" ] && uns=0
  cvalid=false; [ -f "$CSTAT" ] && cvalid=$(jq -r 'if .valid==true then true else false end' "$CSTAT" 2>/dev/null || echo false)
  state=$(jq -S --argjson n "$(jq '.nodes|length' "$CONC" 2>/dev/null || echo 0)" \
               --argjson e "$(jq '.edges|length' "$CONC" 2>/dev/null || echo 0)" \
               --argjson v "$cvalid" --argjson u "$uns" \
    '.concordance = {built:true, valid:$v, nodes:$n, edges:$e, untyped_shippable:$u}' <<<"$state")
fi

# Write the checkpoint atomically. A failed write/rename must NOT fall through to a
# plan computed from a stale/missing state.json — abort (callers treat non-zero as
# "cannot determine remaining work — stop", never "everything done").
if ! { printf '%s\n' "$state" > "$RD/.state.json.staging" && mv "$RD/.state.json.staging" "$RD/state.json"; }; then
  rm -f "$RD/.state.json.staging"
  echo "reconcile: failed to write the state.json checkpoint — refusing to emit a plan." >&2
  exit 4
fi

# Compute the plan from the checkpoint. A jq failure here (e.g. an unreadable
# state.json) must NOT silently become "nothing to do" — that would skip real work.
if ! plan=$(jq -r '
  ( [ .dimensions | to_entries[] | select(.value.done < .value.total)
      | "dimension \(.key): \(.value.total - .value.done) finding(s) need work" ] )
  + ( [ .checks[] | select(.passed | not) | "check \(.check): FAIL" ] )
  | sort | .[]' "$RD/state.json"); then
  echo "reconcile: failed to read back the state.json checkpoint — refusing to emit a plan." >&2
  exit 4
fi

if [ -z "$plan" ]; then
  echo "nothing to do"
else
  echo "REMAINING WORK PLAN"
  printf '%s\n' "$plan"
fi
