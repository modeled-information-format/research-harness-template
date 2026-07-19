#!/usr/bin/env bash
# projection-supersession-check.sh — regression eval for the research-projection
# workflow module (research-harness-template#571, Epic #543, following #569's
# resolution of the reference implementation's script-delegation gap).
#
# The vendored module (.claude/workflows/research-projection.js) has NO
# extractable pure arithmetic function comparable to research-falsify.js's
# mergeVotes()/claimBudget (#562) or research-synthesis.js's repair-loop
# while-block (#566): its Report/Index/Verify phases are entirely `agent()`
# (model) calls driven by prompt text, with exactly one deterministic branch
# each (the same-process synthesisPath preflight guard, and the
# falsified-verdict short-circuit). This eval was designed against that real
# constraint, mirroring the falsify-verdict-merge (#562) / synthesis-citation
# (#566) precedent of "hermetic where the module's own logic can express it,
# structural greps where the behavior is inherently model-driven, say so
# explicitly rather than fake determinism":
#
#   A. Script-delegated composition, not prompt reimplementation (#569's own
#      resolved gap). Structural grep of the module's ACTUAL AGENT PROMPT TEXT
#      (the Report/Index phase bodies, extracted by phase() marker so a mere
#      header-comment mention can never satisfy this) for every script name the
#      resolution names: Report invokes synthesize-artifact.sh -> falsify.sh ->
#      render-artifact.sh -> mif-project.sh; Index invokes build-topic-readme.sh
#      + build-graph.sh + assert-graph-mif.sh. A regression back to the
#      reference's prompt-only shape (dropping any one of these invocations)
#      is caught here, not just at review time.
#
#   B. Supersession identity — REAL fixture run through the actual script
#      pipeline (no stubs, no model calls: synthesize-artifact.sh -> falsify.sh
#      (fixture-evidence, offline) -> render-artifact.sh -> mif-project.sh),
#      run TWICE against the SAME topic/slug with a genuinely changed
#      artifact (different genre -> different rendered content) in between —
#      proving the report's @id is the SAME both times (never a fresh one),
#      `version:` increments (an in-place supersession, not a silent
#      no-op), and the content actually changed (never a stale/unchanged
#      report masquerading as "updated").
#
#   C. synthesisPath existence-check — the module's own preflight guard block
#      is extracted VERBATIM (brace-matched, same technique as #562/#566) and
#      driven with a stubbed `agent()`, proving BEHAVIORALLY that a
#      nonexistent/unusable synthesisPath makes the module throw a clear,
#      actionable error (never silently proceed to render an empty/garbage
#      report), while a usable synthesisPath passes through untouched.
#
#   D. Computed counts, never guessed — structural grep of the module's Index
#      prompt for the "never hand-guessed" / "stale numbers are defects"
#      language, PLUS a real fixture proving build-topic-readme.sh's --check
#      gate (the script the Index phase actually delegates to) catches a
#      stale hand-typed Findings count that a naive "recompute from memory"
#      would drift from — the seed's own "never guessed" acceptance
#      criterion, made a real regression trap.
#
#   E. Targeted-gates-only (D-10) — structural grep that the Verify phase's
#      own prompt text still says "never the full verify.sh suite" / "D-10",
#      not a full-suite invocation.
#
#   F. ontology-map.json is an ARRAY, not an object (#631). The Verify phase's
#      own prompt text must document ontology-map.json's real, established
#      shape (a JSON array of {finding_id, entity_type, resolved_ontology,
#      basis, valid} rows, per scripts/mif-container-import.sh and every
#      on-disk ontology-map.json in this repo) and explicitly instruct the
#      verifying model not to flag its array root as wrong. A regression back
#      to a bare "ajv-validate against its schema" instruction with no such
#      carve-out reintroduces the false-positive "root element is array but
#      schema expects object" failure this eval traps.
#
#   G. Genre skill invocation (research-harness-template#633). Before this
#      fix, `genre` was passed straight through to synthesize-artifact.sh as
#      pass-through metadata — no genre's real Skill(<genre>:<genre>) template
#      was ever invoked, so every genre rendered the identical neutral body
#      with only the frontmatter `genre:` field differing, indistinguishable
#      from a correctly-genred report by inspection. Two-part proof, mirroring
#      the #632 precedent immediately above: (1) a REAL jq run of the EXACT
#      pack-enablement filter the Report phase prompt instructs the agent to
#      run (extracted from the prompt text, never hand-retyped) against a
#      fixture harness.config.json, proving it correctly distinguishes an
#      enabled genre pack, a disabled one, and a genre absent from packs[]
#      entirely; (2) structural proof (grepped from the Report phase's own
#      AGENT PROMPT body) that an enabled genre pack's resolution literally
#      invokes Skill(<genre>:<genre>) and that a disabled/absent pack's
#      resolution explicitly forbids the output from claiming a genre it
#      didn't earn, plus schema/return-shape proof that genreApplied and
#      genreSkillInvoked are actually surfaced to callers rather than
#      silently discarded.
#
# Hermetic: node/jq/the vendored bin/mif-rh-cli (offline, fixture-supplied
# evidence — ADR-0016), evals/fixtures/raw-finding.json + evidence.json,
# schemas/samples/*, and mktemp scratch only. No network, no live model/API
# calls anywhere in this eval.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# (node/jq/the engine) is missing — this eval refuses to silently skip.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-projection.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  projection-supersession-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-projection workflow must ship (Epic #543, Task #569)"; exit 2; }
if [ -z "${MIF_RH_CLI:-}" ] && [ ! -x "$ROOT/bin/mif-rh-cli" ] && ! command -v mif-rh-cli >/dev/null 2>&1; then
  note "the mif-rh-cli engine is required (scripts/fetch-engine.sh, PATH, or MIF_RH_CLI) — see ADR-0016"
  exit 2
fi

# ============================================================================
# A: Script-delegated composition. Extract the Report-phase and Index-phase
# AGENT PROMPT BODIES (between the phase() markers), never the header
# comment, so a comment-only mention of a script name can never satisfy this.
# ============================================================================
report_span="$(awk '/^phase\(.Report.\)/{f=1} f{print} /^phase\(.Index.\)/{exit}' "$WF")"
index_span="$(awk '/^phase\(.Index.\)/{f=1} f{print} /^phase\(.Verify.\)/{exit}' "$WF")"

[ -n "$report_span" ] || { note "could not locate the Report phase body (phase('Report') .. phase('Index') span) in $WF — has the phase-marker shape changed?"; fail=1; }
[ -n "$index_span" ] || { note "could not locate the Index phase body (phase('Index') .. phase('Verify') span) in $WF — has the phase-marker shape changed?"; fail=1; }

for s in synthesize-artifact.sh falsify.sh render-artifact.sh mif-project.sh; do
  grep -qF "scripts/$s" <<<"$report_span" \
    || { note "Report phase prompt no longer invokes scripts/$s — the #569-resolved script-delegation composition (synthesize-artifact.sh -> falsify.sh -> render-artifact.sh -> mif-project.sh) has regressed toward the reference's prompt-only reimplementation"; fail=1; }
done
for s in build-topic-readme.sh build-graph.sh assert-graph-mif.sh; do
  grep -qF "scripts/$s" <<<"$index_span" \
    || { note "Index phase prompt no longer invokes scripts/$s — the #569-resolved readme/graph script delegation has regressed toward the reference's prompt-only reimplementation"; fail=1; }
done
# Defense-in-depth: the falsified-verdict path must never hand-author a verdict.
grep -qF 'never hand-authored' <<<"$report_span" \
  || { note "Report phase prompt lost its explicit never-hand-author-the-verdict instruction"; fail=1; }
grep -qF "verificationVerdict === 'falsified'" "$WF" \
  || { note "$WF lost the falsified-verdict quarantine short-circuit — a falsified report must never ship"; fail=1; }

# ============================================================================
# E: Targeted-gates-only (D-10) — structural grep of the Verify phase's own
# prompt text.
# ============================================================================
verify_span="$(awk '/^phase\(.Verify.\)/{f=1} f{print}' "$WF")"
grep -qF 'never the full verify.sh suite' <<<"$verify_span" \
  || { note "Verify phase prompt lost its explicit never-the-full-verify.sh-suite instruction (D-10)"; fail=1; }
grep -qF 'D-10' <<<"$verify_span" \
  || { note "Verify phase prompt lost its D-10 citation"; fail=1; }

# ============================================================================
# G: ontology-map.json is an established ARRAY, not an object (#631). The
# Verify phase prompt must name the real shape and explicitly rule out
# flagging its array root, or a false-positive "schema expects object"
# failure fires on every topic that has a populated ontology-map.json.
# ============================================================================
grep -qF 'ontology-map.json' <<<"$verify_span" \
  || { note "Verify phase prompt no longer mentions ontology-map.json — the #631 array-shape carve-out has regressed"; fail=1; }
grep -qF 'JSON ARRAY' <<<"$verify_span" \
  || { note "Verify phase prompt lost the 'ontology-map.json is a JSON ARRAY' shape documentation (#631)"; fail=1; }
grep -qF 'do not flag its array root as wrong' <<<"$verify_span" \
  || { note "Verify phase prompt lost the explicit instruction not to flag ontology-map.json's array root as wrong (#631) — regressing this reintroduces the false-positive 'schema expects object' failure"; fail=1; }

# ============================================================================
# F: Witnessed provenance (research-harness-template#632). Before this fix,
# the Report phase stopped at mif-project.sh's L3 re-confirmation and never
# invoked mif-docs-plugin's mif-provenance skill — every rendered report's
# `provenance` block was whatever synthesize-artifact.sh/render-artifact.sh
# asserted, identical boilerplate across every genre/run (ADR-0018's own
# "Current Limitations" confirms this). Structural proof (grepped from the
# Report phase's own AGENT PROMPT body, never a header-comment mention) that
# the stamp step is actually wired, plus schema/return-shape proof the
# outcome is actually surfaced rather than silently discarded.
# ============================================================================
grep -qF 'Skill(mif-docs:mif-provenance)' <<<"$report_span" \
  || { note "Report phase prompt no longer invokes Skill(mif-docs:mif-provenance) — the #632 witnessed-provenance stamp has regressed away, reports would go back to carrying only model-asserted provenance"; fail=1; }
grep -qF 'Do NOT hand-author a provenance' <<<"$report_span" \
  || { note "Report phase prompt lost its explicit never-hand-author-a-provenance-block-to-work-around-a-decline instruction (#632)"; fail=1; }
grep -qF 'DECLINES' <<<"$report_span" \
  || { note "Report phase prompt lost its documented graceful-decline handling for the mif-provenance stamp (#632) — a capture-off/unwitnessed-file decline must never be treated as a projection failure"; fail=1; }
grep -qF "'provenanceOutcome'" "$WF" \
  || { note "REPORT_SCHEMA no longer declares provenanceOutcome — the #632 stamp result would no longer be surfaced to callers"; fail=1; }
grep -qF 'provenanceOutcome: report.provenanceOutcome' "$WF" \
  || { note "the module's final return no longer forwards report.provenanceOutcome — the #632 stamp result would be silently dropped even if the Report phase still computes it"; fail=1; }

# ============================================================================
# G: Genre skill invocation (research-harness-template#633).
# ============================================================================

# G1 — REAL jq run of the EXACT pack-enablement filter the Report phase
# prompt instructs the agent to run, extracted from the prompt text (never
# hand-retyped), proving it actually distinguishes an enabled genre pack, a
# disabled one, and a genre absent from packs[] entirely.
genre_filter_line="$(grep -m1 '\.packs\[\] | select' "$WF")"
if [ -z "$genre_filter_line" ]; then
  note "could not find the genre pack-enablement jq invocation in $WF — has the GENRE RESOLUTION step's prompt text changed shape?"
  fail=1
else
  genre_filter="$(sed -E "s/.*'(\.packs\[\][^']*)'.*/\1/" <<<"$genre_filter_line")"
  if [ -z "$genre_filter" ] || [ "$genre_filter" = "$genre_filter_line" ]; then
    note "could not extract the jq filter expression out of the genre pack-enablement line: $genre_filter_line"
    fail=1
  else
    GENRE_CFG="$TMP/genre-harness.config.json"
    cat > "$GENRE_CFG" <<'EOF'
{"version":"0.1.0","topics":[],"packs":[{"name":"engineering","enabled":true},{"name":"briefing","enabled":false}]}
EOF
    enabled_out="$(jq -r --arg g "engineering" "$genre_filter" "$GENRE_CFG" 2>"$TMP/g1.err")"
    [ "$enabled_out" = "engineering" ] \
      || { note "genre pack-enablement filter did not resolve an ENABLED pack ('engineering') as enabled: got '$enabled_out' ($(cat "$TMP/g1.err"))"; fail=1; }
    disabled_out="$(jq -r --arg g "briefing" "$genre_filter" "$GENRE_CFG" 2>"$TMP/g2.err")"
    [ -z "$disabled_out" ] \
      || { note "genre pack-enablement filter did not resolve a DISABLED pack ('briefing') as unavailable: got '$disabled_out'"; fail=1; }
    absent_out="$(jq -r --arg g "nonexistent-genre" "$genre_filter" "$GENRE_CFG" 2>"$TMP/g3.err")"
    [ -z "$absent_out" ] \
      || { note "genre pack-enablement filter did not resolve a genre ABSENT from packs[] entirely as unavailable: got '$absent_out'"; fail=1; }
  fi
fi

# G2 — structural proof (grepped from the Report phase's own AGENT PROMPT
# body, never a header-comment mention) that an enabled genre pack's
# resolution literally invokes Skill(<genre>:<genre>), that a disabled/absent
# pack's resolution explicitly forbids claiming an unearned genre, and that
# the outcome is surfaced through REPORT_SCHEMA and the module's final return.
grep -qF 'GENRE ENABLEMENT CHECK' <<<"$report_span" \
  || { note "Report phase prompt lost its GENRE ENABLEMENT CHECK step — the #633 pack-enablement resolution has regressed away"; fail=1; }
grep -qF 'Skill(${genreResolution.genreSkillRef})' "$WF" \
  || { note "the module no longer invokes Skill(\${genreResolution.genreSkillRef}) when a genre's pack is enabled — the #633 genre-skill application has regressed away"; fail=1; }
grep -qF 'never let the output claim a genre whose' <<<"$report_span" \
  || { note "Report phase prompt lost its explicit never-claim-an-unearned-genre instruction (#633) — mirrors report-synthesizer.md's own rule"; fail=1; }
grep -qF "'genreApplied'" "$WF" \
  || { note "REPORT_SCHEMA no longer declares genreApplied — the #633 genre-skill outcome would no longer be surfaced to callers"; fail=1; }
grep -qF "'genreSkillInvoked'" "$WF" \
  || { note "REPORT_SCHEMA no longer declares genreSkillInvoked — the #633 genre-skill outcome would no longer be surfaced to callers"; fail=1; }
grep -qF 'genreApplied: report.genreApplied' "$WF" \
  || { note "the module's final return no longer forwards report.genreApplied — the #633 genre-skill outcome would be silently dropped even if the Report phase still computes it"; fail=1; }
grep -qF 'genreSkillInvoked: report.genreSkillInvoked' "$WF" \
  || { note "the module's final return no longer forwards report.genreSkillInvoked — the #633 genre-skill outcome would be silently dropped even if the Report phase still computes it"; fail=1; }

# ============================================================================
# B: Supersession identity. REAL pipeline run, no stubs: synthesize-artifact.sh
# -> falsify.sh (offline fixture evidence) -> render-artifact.sh ->
# mif-project.sh, exercised TWICE against the SAME $OUT with a genuinely
# different artifact (different genre) in between.
# ============================================================================
SF="reports/_meta/sample-session/findings"
OUT="$TMP/supersession-report.md"

if ! bash scripts/synthesize-artifact.sh "$SF" general "$TMP/a1.json" >/dev/null 2>"$TMP/a1.err"; then
  note "setup: synthesize-artifact.sh (genre=general) failed: $(cat "$TMP/a1.err")"; fail=1
fi
if ! bash scripts/falsify.sh evals/fixtures/raw-finding.json evals/fixtures/evidence.json > "$TMP/ff.json" 2>"$TMP/falsify.err"; then
  note "setup: falsify.sh (offline fixture evidence) failed: $(cat "$TMP/falsify.err")"; fail=1
fi
jq '.extensions.harness.verification' "$TMP/ff.json" > "$TMP/vf.json" 2>/dev/null

if [ "$fail" -eq 0 ]; then
  if ! bash scripts/render-artifact.sh "$TMP/a1.json" report "$OUT" "$TMP/vf.json" >/dev/null 2>"$TMP/r1.err"; then
    note "first render (genre=general) failed: $(cat "$TMP/r1.err")"; fail=1
  fi
  if ! bash scripts/mif-project.sh "$OUT" >"$TMP/mp1.out" 2>&1; then
    note "first render does not project to a valid MIF L3 finding: $(cat "$TMP/mp1.out")"; fail=1
  fi
fi

id1="" ver1="" genre1=""
if [ "$fail" -eq 0 ]; then
  id1="$(grep -m1 "'@id'" "$OUT" | sed -E "s/.*'@id':[[:space:]]*//")"
  ver1="$(grep -m1 '^version:' "$OUT" | sed -E 's/^version:[[:space:]]*//')"
  genre1="$(grep -m1 '^genre:' "$OUT" | sed -E 's/^genre:[[:space:]]*//')"
  [ -n "$id1" ] || { note "first render: could not read back an @id from $OUT"; fail=1; }
fi

# The "updated synthesis" — a genuinely different artifact (genre changes,
# so the rendered content demonstrably differs), re-rendered to the SAME
# $OUT path: exactly the supersede-in-place scenario, never a fresh path.
if [ "$fail" -eq 0 ]; then
  if ! bash scripts/synthesize-artifact.sh "$SF" engineering "$TMP/a2.json" >/dev/null 2>"$TMP/a2.err"; then
    note "setup: synthesize-artifact.sh (genre=engineering, the 'updated synthesis') failed: $(cat "$TMP/a2.err")"; fail=1
  fi
fi
if [ "$fail" -eq 0 ]; then
  if ! bash scripts/render-artifact.sh "$TMP/a2.json" report "$OUT" "$TMP/vf.json" >/dev/null 2>"$TMP/r2.err"; then
    note "second render (supersession re-render, genre=engineering) failed: $(cat "$TMP/r2.err")"; fail=1
  fi
  if ! bash scripts/mif-project.sh "$OUT" >"$TMP/mp2.out" 2>&1; then
    note "second (superseding) render does not project to a valid MIF L3 finding: $(cat "$TMP/mp2.out")"; fail=1
  fi
fi

id2="" ver2="" genre2=""
if [ "$fail" -eq 0 ]; then
  id2="$(grep -m1 "'@id'" "$OUT" | sed -E "s/.*'@id':[[:space:]]*//")"
  ver2="$(grep -m1 '^version:' "$OUT" | sed -E 's/^version:[[:space:]]*//')"
  genre2="$(grep -m1 '^genre:' "$OUT" | sed -E 's/^genre:[[:space:]]*//')"

  [ "$id2" = "$id1" ] \
    || { note "supersession @id drifted: first render @id='$id1', second (superseding) render @id='$id2' — a re-projection over the SAME topic/slug must preserve the SAME @id, never mint a fresh one"; fail=1; }
  if [ -n "$ver1" ] && [ -n "$ver2" ] && [ "$ver2" = "$((ver1 + 1))" ]; then
    :
  else
    note "supersession version did not increment in place: first=$ver1 second=$ver2 (want second == first+1)"; fail=1
  fi
  [ "$genre2" != "$genre1" ] \
    || { note "supersession fixture setup broken: genre unchanged ($genre1 == $genre2) between the two renders — this eval cannot prove 'updated content' without a genuinely differing second artifact"; fail=1; }
fi

# ============================================================================
# C: synthesisPath existence-check. The preflight guard block is extracted
# VERBATIM (brace-matched, never re-typed) and driven with a stubbed agent(),
# proving BEHAVIORALLY that the module fails CLOSED (throws, clear message)
# on a non-existent/unusable synthesisPath, and passes through on a usable one.
# ============================================================================
cat > "$TMP/extract-preflight-guard.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const path = require('path');

const wfPath = process.argv[2];
const tmpDir = process.argv[3];
if (!wfPath || !tmpDir) {
  console.error('usage: extract-preflight-guard.cjs <research-projection.js> <tmpdir>');
  process.exit(2);
}
const src = fs.readFileSync(wfPath, 'utf8');

function extractBlockFrom(text, searchIdx, spanStartIdx) {
  const braceStart = text.indexOf('{', searchIdx);
  if (braceStart < 0) throw new Error('no opening brace found');
  let depth = 0, i = braceStart;
  for (; i < text.length; i++) {
    const c = text[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) break; }
  }
  if (depth !== 0) throw new Error('unbalanced braces');
  return text.slice(spanStartIdx, i + 1);
}
function extractSpan(text, startMarker, throughMarker) {
  const s = text.indexOf(startMarker);
  if (s < 0) throw new Error(`start marker not found: ${JSON.stringify(startMarker)}`);
  const t = text.indexOf(throughMarker, s);
  if (t < 0) throw new Error(`through-marker not found after start: ${JSON.stringify(throughMarker)}`);
  return extractBlockFrom(text, t, s);
}

let failed = 0;
function check(name, cond, detail) {
  if (cond) console.log(`  ok  ${name}`);
  else { failed = 1; console.log(`FAIL  ${name}${detail ? ' -- ' + detail : ''}`); }
}

// Verbatim extraction of `const preflight = await agent(` through the
// closing brace of the `if (!preflight || !preflight.exists) { throw ... }`
// guard -- the SAME span the module runs, never a bash/JS reimplementation
// of the guard logic.
let runPreflightGuard;
try {
  const spanText = extractSpan(
    src,
    'const preflight = await agent(',
    'if (!preflight || !preflight.exists) {',
  );
  const harnessSrc =
    'async function runPreflightGuard(agent, SYN) {\n' +
    '  const PREFLIGHT_SCHEMA = {};\n' +
    spanText + '\n' +
    '  return { ok: true, preflight };\n' +
    '}\n' +
    'module.exports = { runPreflightGuard };\n';
  const harnessPath = path.join(tmpDir, 'preflight-guard-harness.cjs');
  fs.writeFileSync(harnessPath, harnessSrc);
  ({ runPreflightGuard } = require(harnessPath));
} catch (e) {
  console.log(`FAIL  extraction of the preflight guard from ${wfPath}: ${e.message}`);
  process.exit(1);
}

async function driveMissingCase() {
  const agent = async () => ({ exists: false, reason: 'file missing' });
  let threw = null;
  try {
    await runPreflightGuard(agent, '/tmp/nonexistent-synthesis-path.json');
  } catch (e) {
    threw = e;
  }
  check('missing-path case: the guard THROWS (fails closed) rather than silently proceeding', threw instanceof Error, threw ? 'no error thrown' : undefined);
  if (threw) {
    check('missing-path case: the thrown message names the unusable path', threw.message.includes('/tmp/nonexistent-synthesis-path.json'), threw.message);
    check('missing-path case: the thrown message is actionable (states "is not usable")', threw.message.includes('is not usable'), threw.message);
    check('missing-path case: the thrown message surfaces the preflight-reported reason', threw.message.includes('file missing'), threw.message);
    check('missing-path case: the thrown message documents the same-process contract (not a silent generic error)', threw.message.includes('SAME-PROCESS-ONLY'), threw.message);
  }
}

async function driveMalformedCase() {
  // A preflight agent call that itself fails/returns nothing (null) must ALSO
  // fail closed -- the guard's `!preflight ||` branch, not just `!preflight.exists`.
  const agent = async () => null;
  let threw = null;
  try {
    await runPreflightGuard(agent, '/tmp/whatever.json');
  } catch (e) {
    threw = e;
  }
  check('null-preflight case: the guard THROWS when the preflight call itself yields nothing', threw instanceof Error, threw ? 'no error thrown' : undefined);
  if (threw) {
    check('null-preflight case: the thrown message reports the preflight-check-itself-failed reason', threw.message.includes('preflight check itself failed'), threw.message);
  }
}

async function driveUsableCase() {
  const agent = async () => ({ exists: true, reason: 'ok' });
  let threw = null;
  let result = null;
  try {
    result = await runPreflightGuard(agent, '/tmp/real-synthesis-path.json');
  } catch (e) {
    threw = e;
  }
  check('usable-path case: the guard does NOT throw when synthesisPath is usable', threw === null, threw ? threw.message : undefined);
  check('usable-path case: the guard returns the preflight result through, unmutated', !!(result && result.preflight && result.preflight.exists === true), JSON.stringify(result));
}

(async () => {
  await driveMissingCase();
  await driveMalformedCase();
  await driveUsableCase();
  process.exit(failed);
})();
NODE

if ! node "$TMP/extract-preflight-guard.cjs" "$WF" "$TMP" > "$TMP/preflight-guard.out" 2>&1; then
  note "preflight-guard extracted-function tests FAILED:"
  sed 's/^/    /' "$TMP/preflight-guard.out"
  fail=1
else
  sed 's/^/    /' "$TMP/preflight-guard.out"
fi

# ============================================================================
# D: Computed counts, never guessed. Structural grep of the Index prompt's
# own "never hand-guessed" language, PLUS a real fixture proving
# build-topic-readme.sh's --check gate (what the Index phase actually
# delegates to) catches a stale hand-typed count a naive recompute-from-memory
# would drift from.
# ============================================================================
grep -qF 'never hand-guessed' <<<"$index_span" \
  || { note "Index phase prompt lost the 'never hand-guessed' computed-counts language"; fail=1; }
grep -qF 'stale numbers are defects' <<<"$index_span" \
  || { note "Index phase prompt lost the 'stale numbers are defects' language"; fail=1; }

INST="$TMP/count-instance"
mkdir -p "$INST/reports/evaltopic/findings"
cat > "$INST/harness.config.json" <<'EOF'
{"version":"0.1.0","topics":[{"id":"evaltopic","namespace":"harness/evaltopic","title":"Eval Topic","status":"active"}]}
EOF
cp schemas/samples/citation-good.sample.json "$INST/reports/evaltopic/findings/f1.json"
cp schemas/samples/citation-internal.sample.json "$INST/reports/evaltopic/findings/f2.json"

if ! CLAUDE_PROJECT_DIR="$INST" bash scripts/build-topic-readme.sh evaltopic >"$TMP/count-build.out" 2>&1; then
  note "computed-counts fixture: build-topic-readme.sh (build) failed: $(cat "$TMP/count-build.out")"; fail=1
fi
README="$INST/reports/evaltopic/README.md"
# --check refuses an unsynthesized draft Key Findings section (a DIFFERENT,
# already-covered gate) -- author a distinct synthesized bullet on top so this
# eval isolates the count-drift assertion specifically, not that gate.
if [ -f "$README" ]; then
  python3 - "$README" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s2 = re.sub(
    r'## Key Findings\n\n.*?\n\n## Reports',
    '## Key Findings\n\n- SYNTHESIZED across both fixture findings for this eval, not a one-finding-per-bullet restatement.\n\n## Reports',
    s, flags=re.S,
)
if s2 == s:
    print('WARNING: Key Findings substitution did not match', file=sys.stderr)
open(p, 'w', encoding='utf-8').write(s2)
PY
fi

if ! CLAUDE_PROJECT_DIR="$INST" bash scripts/build-topic-readme.sh evaltopic --check >"$TMP/count-check-good.out" 2>&1; then
  note "computed-counts fixture: a freshly-built, synthesized README unexpectedly failed --check: $(cat "$TMP/count-check-good.out")"; fail=1
fi

# The regression trap: hand-corrupt the stated count to something that drifts
# from the real on-disk substrate (2 findings) -- exactly what a naive
# "recompute from memory" mistake would produce.
if [ -f "$README" ]; then
  sed -i.bak -E 's/(\*\*Findings:\*\*) [0-9]+/\1 99/' "$README"
fi
count_check_out="$(CLAUDE_PROJECT_DIR="$INST" bash scripts/build-topic-readme.sh evaltopic --check 2>&1)"
count_check_rc=$?
if [ "$count_check_rc" -eq 0 ]; then
  note "computed-counts regression trap did NOT fire: --check passed with a stale hand-typed Findings count (99) against a real substrate of 2 findings"
  fail=1
else
  grep -qF 'count drift' <<<"$count_check_out" \
    || { note "--check failed on the stale count as expected, but not with the count-drift message: $count_check_out"; fail=1; }
  grep -qF '99' <<<"$count_check_out" \
    || { note "count-drift message did not name the stale stated value (99): $count_check_out"; fail=1; }
fi

[ "$fail" -eq 0 ] && note "script-delegated composition holds (Report: synthesize-artifact.sh->falsify.sh->render-artifact.sh->mif-project.sh; Index: build-topic-readme.sh+build-graph.sh+assert-graph-mif.sh, both grepped from the module's own AGENT PROMPT bodies, never a comment); supersession @id is proven identical across two real pipeline renders with genuinely differing content (version incremented, genre changed); the synthesisPath preflight guard is proven (by driving the verbatim-extracted branch) to fail closed with a clear, actionable message on a missing/unusable path and pass through on a usable one; computed README counts are proven to catch a stale hand-typed value via build-topic-readme.sh's real --check gate; the Verify phase's targeted-gates-only (D-10) language is intact; the #632 witnessed-provenance stamp (Skill(mif-docs:mif-provenance), graceful decline handling, no hand-authored workaround) is wired into the Report phase prompt with its outcome surfaced through REPORT_SCHEMA and the module's final return; and the #633 genre-skill-invocation fix holds (the pack-enablement jq filter extracted from the prompt correctly resolves enabled/disabled/absent genre packs against a real fixture, an enabled pack's resolution invokes Skill(<genre>:<genre>), a disabled/absent pack's resolution forbids claiming an unearned genre, and genreApplied/genreSkillInvoked are surfaced through REPORT_SCHEMA and the module's final return)"
exit "$fail"
