#!/usr/bin/env bash
# falsify-remediation-citation-shape.sh — regression eval for
# research-harness-template#656: research-falsify.js's weakened-verdict
# remediation writes schema-invalid citations and can null out unrelated
# top-level fields.
#
# REMEDIATION_CONTRACT (.claude/workflows/research-falsify.js) is prompt
# text handed to a low-effort haiku write agent, not deterministic code —
# there is no client-side function to extract and drive the way
# falsify-verdict-merge.sh (#562) does for mergeVotes()/claimBudget. This
# eval proves what CAN be proven deterministically, in two layers, and
# documents plainly what it cannot:
#
#   A. Structural grep of REMEDIATION_CONTRACT's ACTUAL text (never a
#      reimplementation) proving the fix's four required clauses are
#      present: the full citationType enum, the full citationRole enum,
#      the exact wrong values #656 observed in practice named explicitly
#      (so the agent has a concrete negative example, not just a positive
#      spec), the required "title" field, the strict field-scoping
#      instruction (citations[]/summary/provenance.trustLevel/
#      provenance.confidence only — never touch/drop/null any other
#      top-level field), and the strengthened "run the actual ajv command"
#      re-validate instruction.
#
#   B. Fixture-level proof against the REAL schemas (schemas/mif/
#      citation.schema.json, schemas/findings.schema.json) via ajv, no
#      model call involved: each of #656's four named corruption patterns
#      (missing title; citationType "web"; citationRole "disconfirms";
#      temporal nulled to null) is reproduced as a fixture and proven to
#      GENUINELY fail schema validation — this is the deterministic proof
#      that the bug #656 reports is real, not merely asserted. A citation
#      built by mechanically following the fixed contract's spec (title
#      present, citationType "website", citationRole "refutes") is proven
#      to PASS. A full weakened-and-remediated finding fixture — carrying
#      a correctly-shaped disconfirming citation, a downgraded
#      provenance.trustLevel, a bounded summary qualifier, AND its
#      original temporal block preserved untouched — is proven to
#      validate cleanly end to end against schemas/findings.schema.json
#      with the full mif/ ref closure, the same command the module's own
#      write step is instructed to run.
#
#   LIMITATION, stated plainly (same class of gap #562/#566 already
#   document for this module): whether the real haiku write agent actually
#   follows REMEDIATION_CONTRACT's instructions when composing a citation
#   is NOT exercised here and cannot be, deterministically, in CI — that
#   requires a live model call. What this eval closes is the layer under
#   the agent's control: the instructions themselves now state the correct
#   shape unambiguously (Part A), and that shape, once followed, is
#   genuinely schema-valid (Part B) — where before the fix, following the
#   old instructions literally ("Append the fixture's disconfirming URLs
#   to citations[]", with no shape guidance at all) had no path to a
#   schema-valid citation without the agent independently inventing the
#   correct enum values, title, and field-scoping on its own.
#
# Hermetic: only evals/fixtures/falsify-remediation-citation-shape/*, the
# repo's own schemas/, and ajv-cli (already required elsewhere in this
# suite). No network, no model/API calls.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  falsify-remediation-citation-shape: %s\n' "$1"; }

WF=.claude/workflows/research-falsify.js
FX=evals/fixtures/falsify-remediation-citation-shape

command -v ajv >/dev/null 2>&1 || { note "ajv-cli is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }

# ============================================================================
# A: structural grep of REMEDIATION_CONTRACT's ACTUAL text.
# ============================================================================

# Full citationType enum, verbatim from schemas/mif/citation.schema.json.
grep -qF 'article, book, paper, website, documentation, repository, video, podcast, specification, ' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the full citationType enum spec"; fail=1; }
grep -qF 'dataset, tool, other' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the tail of the citationType enum spec (dataset, tool, other)"; fail=1; }

# The exact wrong citationType values #656 observed in practice, named
# explicitly so the write agent has a concrete negative example.
for bad in '"web"' '"source-code"' '"reference"' '"verification"'; do
  grep -qF "$bad" "$WF" \
    || { note "$WF's REMEDIATION_CONTRACT no longer names the observed-invalid citationType value $bad"; fail=1; }
done

# Full citationRole enum, verbatim from schemas/mif/citation.schema.json.
grep -qF 'supports, refutes, background, methodology, ' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the full citationRole enum spec"; fail=1; }
grep -qF 'contradicts, extends, derived, source, ' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the middle of the citationRole enum spec"; fail=1; }
grep -qF 'example, review' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the tail of the citationRole enum spec (example, review)"; fail=1; }

# The exact wrong citationRole values #656 observed in practice, named
# explicitly, plus the correct value spelled out.
grep -qF 'disconfirming source' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer states which role a disconfirming source takes"; fail=1; }
grep -qF 'ALWAYS "refutes"' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer states the correct citationRole (\"refutes\") for a disconfirming source"; fail=1; }
for bad in '"disconfirms"' '"disconfirming"' '"counter-evidence"' '"disconfirms-qualifier"'; do
  grep -qF "$bad" "$WF" \
    || { note "$WF's REMEDIATION_CONTRACT no longer names the observed-invalid citationRole value $bad"; fail=1; }
done

# The required "title" field is now called out explicitly.
grep -qF '"title", a non-empty string' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer spells out the required non-empty title field"; fail=1; }

# accessed must be a bare YYYY-MM-DD calendar date (schema format:date), NOT
# the full attempted_at TIMESTAMP — copying attempted_at verbatim fails the
# date-format constraint the same way #656's enum/title violations did.
grep -qF 'DATE PORTION (the leading YYYY-MM-DD only)' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer scopes accessed to the leading YYYY-MM-DD date portion (attempted_at is a full timestamp; copying it whole fails format:date)"; fail=1; }

# Strict field-scoping instruction (the nulled-temporal corruption pattern).
grep -qF 'SCOPE THE MUTATION STRICTLY' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the strict field-scoping instruction"; fail=1; }
grep -qF 'touch ONLY citations[], ' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer scopes the mutation to citations[]/summary/provenance fields only"; fail=1; }
grep -qF 'never let this step touch, drop, or null out a field it was not told to change' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the explicit never-null-unrelated-fields instruction (the exact #656 nulled-temporal failure mode)"; fail=1; }
grep -qF '(temporal, modified, created, extensions, etc.)' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer names temporal explicitly among the fields that must survive untouched"; fail=1; }

# Strengthened re-validate instruction.
grep -qF 'RUN THE ACTUAL ajv command yourself and read its ACTUAL exit code and output' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT lost the strengthened run-the-actual-ajv-command re-validate instruction"; fail=1; }
grep -qF 'do not assume it passed' "$WF" \
  || { note "$WF's REMEDIATION_CONTRACT no longer tells the agent not to assume re-validation passed"; fail=1; }

# ============================================================================
# B: fixture-level proof against the REAL schemas via ajv.
# ============================================================================
check_citation_invalid() { # check_citation_invalid <fixture> <label>
  local fx="$1" label="$2"
  if [ ! -f "$fx" ]; then
    note "FAIL: $label ($fx) fixture file not found -- cannot prove the corruption pattern without it"
    fail=1
    return
  fi
  local out
  out="$(mktemp)"
  if ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/mif/citation.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$fx" >"$out" 2>&1; then
    note "FAIL: $label ($fx) validated cleanly against schemas/mif/citation.schema.json -- it should reproduce a #656 corruption pattern and genuinely fail"
    fail=1
  else
    note "$label ($fx) genuinely fails schema validation, as #656 reports"
  fi
  rm -f "$out"
}

check_citation_valid() { # check_citation_valid <fixture> <label>
  local fx="$1" label="$2"
  if [ ! -f "$fx" ]; then
    note "FAIL: $label ($fx) fixture file not found -- cannot prove the fixed shape validates without it"
    fail=1
    return
  fi
  local out
  out="$(mktemp)"
  if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/mif/citation.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$fx" >"$out" 2>&1; then
    note "FAIL: $label ($fx) did not validate against schemas/mif/citation.schema.json: $(cat "$out")"
    fail=1
  else
    note "$label ($fx) validates cleanly against schemas/mif/citation.schema.json"
  fi
  rm -f "$out"
}

check_citation_invalid "$FX/citation-bad-missing-title.json"        "corruption pattern 1 (missing title)"
check_citation_invalid "$FX/citation-bad-wrong-citationtype.json"   "corruption pattern 2 (citationType: \"web\")"
check_citation_invalid "$FX/citation-bad-wrong-citationrole.json"   "corruption pattern 3 (citationRole: \"disconfirms\")"
check_citation_valid   "$FX/citation-good.json"                     "fixed-contract-shaped citation"

# Corruption pattern 4: an unrelated top-level field (temporal) nulled out
# by the write step, against the full findings schema (full mif/ ref
# closure, mirroring falsify-verdict-merge.sh's own ajv invocation).
if ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/findings.schema.json \
    -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$FX/finding-nulled-temporal.json" >/tmp/ajv-out-nulled-$$.txt 2>&1; then
  note "FAIL: finding-nulled-temporal.json validated cleanly -- it should reproduce #656's nulled-temporal corruption pattern and genuinely fail schemas/findings.schema.json"
  fail=1
else
  note "corruption pattern 4 (temporal nulled out) genuinely fails schemas/findings.schema.json, as #656 reports"
fi
rm -f /tmp/ajv-out-nulled-$$.txt

# The positive control: a full weakened-and-remediated finding, shaped
# exactly as the FIXED REMEDIATION_CONTRACT instructs (correctly-shaped
# disconfirming citation with citationRole "refutes", downgraded
# provenance.trustLevel/confidence, a bounded summary qualifier, and the
# original temporal block left untouched) validates cleanly end to end.
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/findings.schema.json \
    -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$FX/finding-weakened-remediated-good.json" >/tmp/ajv-out-good-$$.txt 2>&1; then
  note "FAIL: finding-weakened-remediated-good.json (the fixed-contract-shaped positive control) did not validate against schemas/findings.schema.json: $(cat /tmp/ajv-out-good-$$.txt)"
  fail=1
else
  note "the fixed-contract-shaped weakened-and-remediated finding validates cleanly end to end (schemas/findings.schema.json, full mif/ ref closure)"
fi
rm -f /tmp/ajv-out-good-$$.txt

[ "$fail" -eq 0 ] && note "REMEDIATION_CONTRACT states the full Citation shape (enums, required title, the exact observed-invalid values named explicitly, strict field-scoping naming temporal, and a strengthened run-the-actual-ajv-command re-validate instruction); all four of #656's named corruption patterns are proven to genuinely fail the real schemas; a citation and a full finding built by following the fixed contract's spec are proven to validate cleanly against those same real schemas"
exit "$fail"
