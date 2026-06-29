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
#   exit 2 = no findings dir ; exit 3 = ontology-map.json missing/unparseable (cannot prove typing)
#   exit 5 = jq not found (cannot evaluate typing — fail closed)
set -uo pipefail
# Fail closed on a missing toolchain: every typing decision below runs through jq, and a
# jq failure inside a command substitution would yield "" (no blocker) — i.e. a vacuous
# pass. Require it up front (mirrors validate-concordance.sh) so the gate cannot fail open.
command -v jq >/dev/null 2>&1 || { echo "check-shippable-typing: 'jq' not found — cannot evaluate typing (fail closed)" >&2; exit 5; }
RD="${1:?usage: check-shippable-typing.sh <reports-dir>}"
case "$RD" in /*) : ;; *) RD="$(pwd)/$RD" ;; esac
FDIR="$RD/findings"; MAP="$RD/ontology-map.json"
[ -d "$FDIR" ] || { echo "check-shippable-typing: no findings dir: $FDIR" >&2; exit 2; }
# Fail closed: without a map we cannot prove typing (never pass vacuously).
[ -f "$MAP" ] || { echo "check-shippable-typing: ontology-map.json missing — run ontology-review.sh --topic first (fail closed)" >&2; exit 3; }
# Fail closed: a present-but-unparseable map cannot prove typing either. A corrupt/partial
# map makes every per-finding `bad` lookup error to "" (no blocker) — i.e. it would PASS
# vacuously, the exact hole this gate exists to close. Treat it like a missing map (exit 3).
jq -e 'type=="array"' "$MAP" >/dev/null 2>&1 || { echo "check-shippable-typing: ontology-map.json unparseable or not a record array — re-run ontology-review.sh --topic first (fail closed)" >&2; exit 3; }

blockers=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Fail closed on a finding we cannot parse: its verdict and type are unknowable, so we
  # cannot prove it is safe to ship — an unreadable shippable-or-unknown finding BLOCKS
  # rather than being silently skipped. (-e makes jq exit non-zero on a parse error; a
  # valid finding with no verdict yields "" and exit 0, so it is correctly not a blocker.)
  if ! verdict=$(jq -er '.extensions.harness.verification.verdict // ""' "$f" 2>/dev/null); then
    blockers="${blockers}  ${f} (unreadable JSON)"$'\n'
    continue
  fi
  # Only findings that SHIP gate. Falsified/quarantined/inconclusive (and any other verdict)
  # are excluded from synthesis already, so their typing never blocks.
  case "$verdict" in
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
done < <( { find "$FDIR" -maxdepth 1 -type f -name '*.json' ! -name '.*' ! -name '*.tmp'
            find "$RD" -maxdepth 1 -type f -name 'finding-*.json' ! -name '.*' ! -name '*.tmp'; } 2>/dev/null | sort -u )
# Discovery scans BOTH the canonical findings/ subdir AND a flat reports/<topic>/finding-*.json,
# matching reconcile-session.sh's list_findings — so a finding in either layout is gated and none
# can bypass the fail-closed typing check (sort -u dedupes; the two dirs do not overlap).

if [ -n "$blockers" ]; then
  topic="$(basename "$RD")"
  echo "check-shippable-typing: $(printf '%s' "$blockers" | grep -c .) shippable finding(s) lack a valid ontology type — synthesis BLOCKED (fail closed):" >&2
  printf '%s' "$blockers" >&2
  echo "check-shippable-typing: unblock with  /ontology-review --topic $topic --enrich  then  /resume --topic $topic" >&2
  exit 1
fi
echo "check-shippable-typing: all shippable findings carry a valid ontology type — ok"
exit 0
