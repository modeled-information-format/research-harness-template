#!/usr/bin/env bash
# check-shippable-typing.sh — fail-closed pre-synthesis gate (ADR-0011). A finding that
# SHIPS (extensions.harness.verification.verdict in survived|weakened) MUST resolve to a
# valid ontology type. Untyped/unresolved/invalid/missing-from-map shippable findings BLOCK
# synthesis (exit 1). Falsified/quarantined/inconclusive never block. Deterministic, read-only.
#
# This covers the gap validate-concordance.sh structurally cannot see: a concept node for an
# untyped finding gets entityType:null (build-concordance.sh), and validate-concordance.sh
# filters `entityType != null`, so an untyped shippable finding passes the spine validator
# VACUOUSLY. This gate refuses to SHIP such a finding.
#
# Usage: check-shippable-typing.sh <reports-dir>     # e.g. reports/<topic>
#   exit 0 = all shippable findings carry a valid ontology type
#   exit 1 = one or more shippable findings are untyped/unresolved/invalid (synthesis BLOCKED)
#   exit 2 = no findings dir ; exit 3 = ontology-map.json missing (cannot prove typing)
set -uo pipefail
RD="${1:?usage: check-shippable-typing.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
FDIR="$RD/findings"; MAP="$RD/ontology-map.json"
[ -d "$FDIR" ] || { echo "check-shippable-typing: no findings dir: $FDIR" >&2; exit 2; }
# Fail closed: without a map we cannot prove typing (never pass vacuously).
[ -f "$MAP" ] || { echo "check-shippable-typing: ontology-map.json missing — run ontology-review.sh --topic first (fail closed)" >&2; exit 3; }

blockers=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Only findings that SHIP gate. Falsified/quarantined/inconclusive (and any other verdict)
  # are excluded from synthesis already, so their typing never blocks.
  case "$(jq -r '.extensions.harness.verification.verdict // empty' "$f" 2>/dev/null)" in
    survived|weakened) : ;;
    *) continue ;;
  esac
  id=$(jq -r '."@id" // empty' "$f" 2>/dev/null)
  # Block if the map has no record, the record is invalid, or it resolved to no type
  # (basis untyped/unresolved). Same predicate reconcile-session.sh uses for untyped_shippable.
  bad=$(jq -r --arg id "$id" '
    (map(select(.finding_id==$id)) | first) as $r
    | if   $r == null         then "missing"
      elif ($r.valid != true) then "invalid"
      elif ($r.basis=="untyped" or $r.basis=="unresolved") then $r.basis
      else "" end' "$MAP")
  [ -n "$bad" ] && blockers="${blockers}  ${id} (${bad})"$'\n'
done < <(find "$FDIR" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp' 2>/dev/null | sort)

if [ -n "$blockers" ]; then
  topic="$(basename "$RD")"
  echo "check-shippable-typing: $(printf '%s' "$blockers" | grep -c .) shippable finding(s) lack a valid ontology type — synthesis BLOCKED (fail closed):" >&2
  printf '%s' "$blockers" >&2
  echo "check-shippable-typing: unblock with  /ontology-review --topic $topic --enrich  then  /resume --topic $topic" >&2
  exit 1
fi
echo "check-shippable-typing: all shippable findings carry a valid ontology type — ok"
exit 0
