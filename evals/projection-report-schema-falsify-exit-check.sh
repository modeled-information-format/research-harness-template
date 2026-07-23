#!/usr/bin/env bash
# projection-report-schema-falsify-exit-check.sh — regression eval for
# research-harness-template#773: research-projection.js's REPORT_SCHEMA
# unconditionally required `frontmatterLevel` (integer) and `reportId`
# (string) even on the step-3 falsify early-exit path, where
# render-artifact.sh/mif-project.sh (the ONLY place either value is ever
# actually determined) never runs. The subagent was therefore forced to
# either fabricate a plausible-looking MIF level and @id for an artifact
# that was never rendered, or fail structured-output validation on a call
# that otherwise terminated correctly and as designed.
#
# THE FIX: `frontmatterLevel` now types as `['integer', 'null']` and
# `reportId` stays `string` but its description documents `""` as the ONLY
# correct falsified-path value (mirroring the exact sentinel convention this
# same schema already uses for genreApplied/genreSkillInvoked/
# provenanceOutcome/provenanceReason on this identical falsified-early-exit
# path) — never a fabricated level or @id.
#
# Two proof classes:
#
#   A. Structural: REPORT_SCHEMA's frontmatterLevel type includes "null",
#      and the Report-phase prompt text (both step 3's falsified-exit
#      instruction and the final "Return the report path..." instruction)
#      explicitly names frontmatterLevel=null / reportId="" for the
#      falsified case, tagged #773.
#
#   B. Behavioral, via a REAL ajv schema validation (not a hand-rolled
#      duck-typed check): REPORT_SCHEMA is extracted VERBATIM (brace-
#      matched, never re-typed) from the module, turned into a real JSON
#      Schema file, and ajv is driven against two payloads:
#        (a) a step-3 falsified-quarantine payload with
#            frontmatterLevel=null, reportId="" -> must be VALID under the
#            CURRENT (fixed) schema.
#        (b) the SAME payload run against the ORIGINAL pre-fix schema
#            (frontmatterLevel typed as plain "integer", hardcoded here as
#            the historical baseline) -> must be INVALID, proving this eval
#            would have caught the original bug (fails before the fix,
#            passes after — never just an ad hoc manual reproduction).
#        (c) a normal non-falsified payload (frontmatterLevel=3,
#            reportId="urn:...") -> must stay VALID under the current
#            schema, proving the fix does not loosen the happy path.
#
# Hermetic: node + the ajv CLI only — no network, no live model/API calls.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required
# tool is missing or the module's shape has changed enough that extraction
# itself failed — this eval refuses to silently skip.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-projection.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  projection-report-schema-falsify-exit-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v ajv >/dev/null 2>&1 || { note "ajv (ajv-cli) is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-projection workflow must ship (Epic #543, Task #569)"; exit 2; }

# ============================================================================
# A: structural — REPORT_SCHEMA and the Report-phase prompt text.
# ============================================================================
schema_span="$(awk '/^const REPORT_SCHEMA = \{/{f=1} f{print} /^const GENRE_SCHEMA = \{/{exit}' "$WF")"
[ -n "$schema_span" ] || { note "could not locate the REPORT_SCHEMA .. GENRE_SCHEMA span in $WF — has the schema-declaration shape changed?"; fail=1; }

grep -qF "frontmatterLevel: { type: ['integer', 'null']" <<<"$schema_span" \
  || { note "REPORT_SCHEMA's frontmatterLevel no longer types as ['integer','null'] — the #773 fix (permit an honest null on the falsify early-exit) has regressed"; fail=1; }
grep -qF 'research-harness-template#773' <<<"$schema_span" \
  || { note "REPORT_SCHEMA no longer references research-harness-template#773 in its field descriptions — the fix's rationale documentation has been stripped"; fail=1; }

report_span="$(awk '/^phase\(.Report.\)/{f=1} f{print} /^phase\(.Index.\)/{exit}' "$WF")"
[ -n "$report_span" ] || { note "could not locate the Report phase body (phase('Report') .. phase('Index') span) in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF 'frontmatterLevel=null and reportId=""' <<<"$report_span" \
  || { note "the step-3 falsified-exit instruction no longer tells the subagent to set frontmatterLevel=null and reportId=\"\" — the #773 fix has regressed"; fail=1; }
grep -qF 'research-harness-template#773' <<<"$report_span" \
  || { note "the Report-phase prompt no longer references research-harness-template#773 — the fix's rationale documentation has been stripped"; fail=1; }

# ============================================================================
# B: behavioral — extract REPORT_SCHEMA verbatim (brace-matched), realize it
# as a JSON Schema file, and drive ajv against it directly.
# ============================================================================
cat > "$TMP/extract-report-schema.cjs" <<'NODE'
'use strict';
const fs = require('fs');

const wfPath = process.argv[2];
const outPath = process.argv[3];
if (!wfPath || !outPath) {
  console.error('usage: extract-report-schema.cjs <research-projection.js> <out.json>');
  process.exit(2);
}
const src = fs.readFileSync(wfPath, 'utf8');

function extractObjectLiteral(text, marker) {
  const m = text.indexOf(marker);
  if (m < 0) throw new Error(`marker not found: ${JSON.stringify(marker)}`);
  const braceStart = text.indexOf('{', m);
  if (braceStart < 0) throw new Error('no opening brace found after marker');
  let depth = 0, i = braceStart;
  for (; i < text.length; i++) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) break; }
  }
  if (depth !== 0) throw new Error('unbalanced braces');
  return text.slice(braceStart, i + 1);
}

let schemaObj;
try {
  const literal = extractObjectLiteral(src, 'const REPORT_SCHEMA = ');
  // eslint-disable-next-line no-new-func
  schemaObj = new Function(`return (${literal});`)();
} catch (e) {
  console.error(`FAIL extracting REPORT_SCHEMA: ${e.message}`);
  process.exit(1);
}

// ajv-cli's plain `validate`/`test` command treats the top-level schema as
// draft-07-ish by default; REPORT_SCHEMA uses no exotic keywords (plain
// type/enum/items/required) so no $schema/format-plugin wiring is needed.
fs.writeFileSync(outPath, JSON.stringify(schemaObj, null, 2));
console.log('ok extracted REPORT_SCHEMA');
NODE

if ! node "$TMP/extract-report-schema.cjs" "$WF" "$TMP/report-schema.current.json"; then
  note "REPORT_SCHEMA verbatim extraction FAILED"
  fail=1
else
  # ----------------------------------------------------------------------
  # (a) the falsified-quarantine payload research-harness-template#773
  # describes — no rendered file ever existed, so frontmatterLevel/reportId
  # can only honestly be null/"".
  # ----------------------------------------------------------------------
  cat > "$TMP/falsify-exit-payload.json" <<'JSON'
{
  "reportPath": "reports/evaltopic/evaltopic.md",
  "frontmatterLevel": null,
  "checksAddressed": [],
  "verificationVerdict": "falsified",
  "reportId": "",
  "genreApplied": false,
  "genreSkillInvoked": "",
  "provenanceOutcome": "not-applicable",
  "provenanceReason": "report quarantined at step 3 (falsified) -- step 7 never reached"
}
JSON

  # ----------------------------------------------------------------------
  # (b) the SAME payload's shape, but the (b) case below is driven against
  # the historical PRE-FIX schema baseline instead of the current one.
  # ----------------------------------------------------------------------
  cat > "$TMP/report-schema.pre-fix-baseline.json" <<'JSON'
{
  "type": "object",
  "properties": {
    "reportPath": { "type": "string" },
    "frontmatterLevel": { "type": "integer" },
    "checksAddressed": { "type": "array", "items": { "type": "string" } },
    "verificationVerdict": { "type": "string", "enum": ["falsified", "weakened", "survived", "inconclusive"] },
    "reportId": { "type": "string" },
    "genreApplied": { "type": "boolean" },
    "genreSkillInvoked": { "type": "string" },
    "provenanceOutcome": { "type": "string", "enum": ["stamped", "declined", "error", "not-applicable"] },
    "provenanceReason": { "type": "string" }
  },
  "required": ["reportPath", "frontmatterLevel", "checksAddressed", "verificationVerdict", "reportId", "genreApplied", "genreSkillInvoked", "provenanceOutcome", "provenanceReason"]
}
JSON

  # ----------------------------------------------------------------------
  # (c) a normal, non-falsified payload -- must stay valid under the CURRENT
  # schema, proving the fix does not loosen the happy path.
  # ----------------------------------------------------------------------
  cat > "$TMP/survived-payload.json" <<'JSON'
{
  "reportPath": "reports/evaltopic/evaltopic.md",
  "frontmatterLevel": 3,
  "checksAddressed": ["check-1"],
  "verificationVerdict": "survived",
  "reportId": "urn:mif:report:evaltopic:evaltopic",
  "genreApplied": false,
  "genreSkillInvoked": "",
  "provenanceOutcome": "declined",
  "provenanceReason": "capture disabled"
}
JSON

  if ajv test -s "$TMP/report-schema.current.json" -d "$TMP/falsify-exit-payload.json" --valid >"$TMP/ajv-a.out" 2>&1; then
    note "(a) OK -- the falsify-quarantine payload (frontmatterLevel=null, reportId=\"\") validates under the CURRENT (fixed) REPORT_SCHEMA"
  else
    note "(a) FAIL -- the falsify-quarantine payload no longer validates under the current REPORT_SCHEMA; the #773 fix has regressed:"
    sed 's/^/    /' "$TMP/ajv-a.out"
    fail=1
  fi

  if ajv test -s "$TMP/report-schema.pre-fix-baseline.json" -d "$TMP/falsify-exit-payload.json" --invalid >"$TMP/ajv-b.out" 2>&1; then
    note "(b) OK -- the SAME falsify-quarantine payload is correctly rejected by the historical PRE-FIX schema baseline, proving this eval would have caught research-harness-template#773 before the fix (fails before, passes after)"
  else
    note "(b) FAIL -- the pre-fix baseline schema unexpectedly accepted the falsify-quarantine payload; the baseline itself no longer reproduces the original bug, so this eval is not a real regression trap:"
    sed 's/^/    /' "$TMP/ajv-b.out"
    fail=1
  fi

  if ajv test -s "$TMP/report-schema.current.json" -d "$TMP/survived-payload.json" --valid >"$TMP/ajv-c.out" 2>&1; then
    note "(c) OK -- a normal non-falsified payload (frontmatterLevel=3, a real reportId) still validates under the current REPORT_SCHEMA -- the fix does not loosen the happy path"
  else
    note "(c) FAIL -- a normal non-falsified payload no longer validates under the current REPORT_SCHEMA:"
    sed 's/^/    /' "$TMP/ajv-c.out"
    fail=1
  fi
fi

[ "$fail" -eq 0 ] && note "REPORT_SCHEMA no longer forces fabrication of frontmatterLevel/reportId on the step-3 falsify early-exit path (research-harness-template#773): the Report-phase prompt explicitly instructs the honest null/\"\" sentinel for that path (grepped structurally, tagged #773), and a real ajv validation proves the falsify-quarantine payload is accepted by the CURRENT schema, rejected by the historical pre-fix baseline (this eval is a genuine regression trap, not just a documentation check), and the happy path is untouched"
exit "$fail"
