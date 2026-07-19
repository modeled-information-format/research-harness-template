#!/usr/bin/env bash
# deliverables-genre-channel-route.sh — regression eval for the
# research-deliverables Route/Render/Check pipeline (research-harness-template#575,
# Epic #544), scoped to what #573 actually wired: real enabled packs, both
# mechanisms, unavailable[] reasons, synthesis-only citations.
#
# This is a SEPARATE, self-contained eval from evals/deliverables-route-check.sh
# (#573's own eval, which cross-checks the module's static pack tables against
# docs/reference/packs/index.md and proves the citation-leak gate for the
# neutral genre="general" blog render). This eval covers the four things #575
# asks for that #573's own eval does not:
#
#   (a) structural proof Route/Render actually dispatch BOTH mechanisms, using
#       the REAL names #573 wired (verified against the source, not assumed):
#       scripts/synthesize-artifact.sh -> scripts/render-artifact.sh for
#       mechanism 1 (artifact-based, blog/book), and the literal template
#       literal `Skill(${p.channel}:${p.channel})` for mechanism 2
#       (source-direct channel packs) — grepped from the module's own Route
#       and Render AGENT PROMPT bodies, never a header comment.
#
#   (b) a REAL fixture proving a genuinely-enabled genre pack resolves to a
#       servable route, not unavailable: exec-summary AND engineering are both
#       confirmed `enabled:true` in the CURRENT harness.config.json (a live
#       fact-check, not assumed), then driven end-to-end through the actual
#       scripts/synthesize-artifact.sh -> scripts/render-artifact.sh (blog)
#       pipeline (offline, reports/_meta/sample-session's real findings), and
#       the Check phase's real gates are asserted per rendered artifact: lint
#       clean (markdownlint-cli2, repo config), valid MIF Level-1 frontmatter
#       (ajv against schemas/mif/mif.schema.json, the same gate_m6d pattern
#       scripts/verify.sh already uses), citation-leak clean (the real
#       LEAK_RE from .claude/hooks/check-citation-leak.sh, extracted verbatim,
#       never re-typed), and >=1 citation under the rendered "## Sources"
#       list. NOTE on RENDER_SCHEMA's "finding-traced" citationsCount wording
#       (module source): this describes INTERNAL traceability (which finding
#       a citation came from), not literal finding-@id text in the output —
#       the rendered blog/book body is deliberately citation-leak-clean (public
#       URLs only, no urn:mif:/finding-id tokens); this eval asserts the real
#       behavior (URL-only Sources list, leak-clean body), not a literal
#       "finding @id in the text" reading of that field name.
#
#   (c) a genuinely-disabled real pack (sustainability-report,
#       `enabled:false` in the CURRENT harness.config.json — a live
#       fact-check) and a genuinely-nonexistent one (a genre string in NEITHER
#       harness.config.json packs[] NOR the module's own GENRE_PACKS table)
#       are proven, structurally, to land in DIFFERENT reason buckets than
#       the "out of scope" source-direct/third-mechanism case #573
#       introduces (diataxis/ai-spec) — see part C for why this decision
#       cannot be driven end-to-end without a live model call, and what is
#       proven instead.
#
#   (d) the synthesis-only evidence rule, driven with a seeded canary-claim
#       fixture: a finding-only claim absent from a companion synthesis
#       fixture. See part D for what this hermetically proves and what it
#       cannot (the module's own header comments, lines 66-82, already
#       document that synthesize-artifact.sh reads the FINDINGS DIR directly
#       and never consults synthesisPath — the exclusion of an
#       out-of-synthesis claim is enforced by the Render AGENT's own
#       cross-check instruction, not by any deterministic script; this eval
#       proves that fact rather than assuming the opposite).
#
# Hermetic except where the module's own behavior is inherently model-driven
# (Route/Render are bare `agent()` calls with no extractable pure function —
# already established by deliverables-route-check.sh's own header: "the
# vendored module has NO extractable pure arithmetic function comparable to
# research-falsify.js's mergeVotes()"). Every such spot is called out
# explicitly in the case's own comments, per that same precedent, rather than
# faking determinism. No network, no live model/API calls anywhere in this
# eval.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# (node/jq/python3/yq/ajv/markdownlint-cli2/the engine) is missing — this
# eval refuses to silently skip.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-deliverables.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  deliverables-genre-channel-route: %s\n' "$1"; }

for tool in node jq python3 yq ajv markdownlint-cli2; do
  command -v "$tool" >/dev/null 2>&1 || { note "$tool is required but not on PATH"; exit 2; }
done
[ -f "$WF" ] || { note "$WF not found — the vendored research-deliverables workflow must ship (Epic #544, Task #573)"; exit 2; }
if [ -z "${MIF_RH_CLI:-}" ] && [ ! -x "$ROOT/bin/mif-rh-cli" ] && ! command -v mif-rh-cli >/dev/null 2>&1; then
  note "the mif-rh-cli engine is required (scripts/fetch-engine.sh, PATH, or MIF_RH_CLI) — see ADR-0016"
  exit 2
fi

route_span="$(awk '/^const route = await agent\(/{f=1} f{print} /^if \(!route\)/{exit}' "$WF")"
render_span="$(awk '/^phase\(.Render.\)/{f=1} f{print} /^const artifacts = /{exit}' "$WF")"
[ -n "$route_span" ] || { note "could not locate the Route agent prompt body in $WF — has the shape changed?"; fail=1; }
[ -n "$render_span" ] || { note "could not locate the Render phase body in $WF — has the phase-marker shape changed?"; fail=1; }

# GENRE_PACKS/OUT_OF_SCOPE_CHANNELS entries are comma-separated MULTIPLE per
# line (not one key per line), so a line-anchored grep silently checks only
# the first key on each line. Extract the real key sets with python instead —
# every key is `name: {` (bare or quoted), every OUT_OF_SCOPE_CHANNELS entry
# is a quoted string in a `[...]` array.
genre_pack_has() { # genre_pack_has <name> -> exit 0 if present in GENRE_PACKS
  python3 - "$WF" "$1" <<'PY'
import re, sys
wf, name = open(sys.argv[1]).read(), sys.argv[2]
m = re.search(r'const GENRE_PACKS = \{(.*?)\n\}', wf, re.S)
keys = re.findall(r"'?([A-Za-z][A-Za-z0-9-]*)'?\s*:\s*\{", m.group(1)) if m else []
sys.exit(0 if name in keys else 1)
PY
}
out_of_scope_has() { # out_of_scope_has <name> -> exit 0 if present in OUT_OF_SCOPE_CHANNELS
  python3 - "$WF" "$1" <<'PY'
import re, sys
wf, name = open(sys.argv[1]).read(), sys.argv[2]
m = re.search(r"const OUT_OF_SCOPE_CHANNELS = \[(.*?)\]", wf)
items = re.findall(r"'([a-z0-9-]+)'", m.group(1)) if m else []
sys.exit(0 if name in items else 1)
PY
}

# ============================================================================
# A: structural proof Route/Render distinguish and dispatch BOTH mechanisms,
# using the REAL names #573 wired (verified against the source below, not
# assumed).
# ============================================================================
for s in synthesize-artifact.sh render-artifact.sh; do
  grep -qF "scripts/$s" <<<"$render_span" \
    || { note "Render phase prompt does not invoke scripts/$s for mechanism 1 (artifact-based) — verify #573's actual wiring"; fail=1; }
done
grep -qF 'Skill(${p.channel}:${p.channel})' "$WF" \
  || { note "the module's source no longer contains the literal Skill(\${p.channel}:\${p.channel}) invocation template for mechanism 2 (source-direct) — has #573's actual invocation shape changed?"; fail=1; }
grep -qF "mechanism === 'artifact'" "$WF" \
  || { note "the Render phase's dispatch no longer branches on p.mechanism === 'artifact' — mechanism selection may no longer be structural"; fail=1; }
grep -qF 'ARTIFACT-BASED' <<<"$route_span" && grep -qF 'SOURCE-DIRECT CHANNEL PACKS' <<<"$route_span" \
  || { note "Route prompt no longer names both mechanisms explicitly by their real labels"; fail=1; }

# ============================================================================
# B: REAL fixture — genuinely-enabled genre packs (exec-summary, engineering)
# resolve to a SERVABLE route, driven end-to-end through the real backing
# scripts, with every Check-phase gate asserted per rendered artifact.
# ============================================================================
for genre in exec-summary engineering; do
  jq -e --arg g "$genre" '.packs[] | select(.name==$g) | .enabled==true' harness.config.json >/dev/null 2>&1 \
    || { note "harness.config.json packs[] does not currently mark '$genre' enabled:true — pick a different real enabled genre pack, this fixture requires a LIVE fact, not an assumption"; fail=1; continue; }
  genre_pack_has "$genre" \
    || { note "the module's own GENRE_PACKS table does not recognize '$genre' — has the module's taxonomy drifted from harness.config.json?"; fail=1; continue; }

  ART="$TMP/artifact.$genre.json"
  OUT="$TMP/blog.$genre.md"
  if ! bash scripts/synthesize-artifact.sh reports/_meta/sample-session/findings "$genre" "$ART" >"$TMP/synth.$genre.out" 2>&1; then
    note "synthesize-artifact.sh (genre=$genre) failed on a real enabled pack: $(cat "$TMP/synth.$genre.out")"; fail=1; continue
  fi
  ajv validate --spec=draft2020 --strict=false -c ajv-formats -s schemas/artifact.schema.json -d "$ART" >/dev/null 2>&1 \
    || { note "artifact.$genre.json does not validate against schemas/artifact.schema.json"; fail=1; }
  if ! bash scripts/render-artifact.sh "$ART" blog "$OUT" >"$TMP/render.$genre.out" 2>&1; then
    note "render-artifact.sh (genre=$genre, channel=blog) failed on a real enabled pack: $(cat "$TMP/render.$genre.out")"; fail=1; continue
  fi
  [ -s "$OUT" ] || { note "render-artifact.sh (genre=$genre) produced an empty file — not a servable route"; fail=1; continue; }

  # Check-phase gate 1: lint clean.
  markdownlint-cli2 --config .markdownlint-cli2.jsonc "$OUT" >"$TMP/lint.$genre.out" 2>&1 \
    || { note "markdownlint-cli2 found problems in the '$genre' blog render: $(cat "$TMP/lint.$genre.out")"; fail=1; }

  # Check-phase gate 2: valid MIF Level-1 frontmatter (same pattern as
  # scripts/verify.sh's own gate_m6d — split frontmatter/body, project the
  # frontmatter + body content through schemas/mif/mif.schema.json).
  bclose=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$OUT")
  Dl="$TMP/mif-check-$genre"; mkdir -p "$Dl"
  sed -n "2,$((bclose-1))p" "$OUT" > "$Dl/fm.yaml"
  sed -n "$((bclose+1)),\$p" "$OUT" > "$Dl/body.md"
  yq -p=yaml -o=json '.' "$Dl/fm.yaml" 2>/dev/null | jq --rawfile b "$Dl/body.md" '. + {content:$b}' > "$Dl/c.json" 2>/dev/null
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/mif/mif.schema.json -r schemas/mif/definitions/entity-reference.schema.json -d "$Dl/c.json" >/dev/null 2>&1 \
    || { note "the '$genre' blog render's frontmatter does not project to a valid MIF Level-1 concept"; fail=1; }

  # Check-phase gate 3: citation-leak clean, by the REAL enforced pattern
  # (extracted verbatim from .claude/hooks/check-citation-leak.sh).
  LEAK_RE="$(grep -m1 '^LEAK_RE=' .claude/hooks/check-citation-leak.sh | sed -E "s/^LEAK_RE='(.*)'\$/\1/")"
  [ -n "$LEAK_RE" ] || { note "could not extract LEAK_RE from .claude/hooks/check-citation-leak.sh"; fail=1; }
  if grep -nE "$LEAK_RE" "$OUT" >"$TMP/leak.$genre.out" 2>/dev/null; then
    note "citation-leak gate FAILED on the '$genre' blog render: $(cat "$TMP/leak.$genre.out")"; fail=1
  fi

  # Check-phase gate 4: >=1 citation under the rendered "## Sources" list.
  # (RENDER_SCHEMA's citationsCount is described as "finding-traced for
  # mechanism 1" — internal traceability, not literal finding-@id text; the
  # real body is public-URL-only, per gate 3 above.)
  sources_n="$(awk '/^## Sources$/{f=1;next} f && /^- /{c++} END{print c+0}' "$OUT")"
  [ "${sources_n:-0}" -ge 1 ] || { note "the '$genre' blog render has 0 citations under '## Sources' — a servable route must carry at least one"; fail=1; }
done

# ============================================================================
# C: a genuinely-disabled real pack and a genuinely-nonexistent one, checked
# against structurally distinct reason categories from the "out of scope"
# source-direct/third-mechanism case #573 introduces.
#
# WHY THIS CANNOT BE DRIVEN END-TO-END: Route is a bare `agent()` call (see
# part A's dispatch proof) with no extractable pure function to invoke
# offline — deliverables-route-check.sh's own header already established
# this for the module as a whole. Concretely, and proven below: the
# deterministic engine substrate (synthesize-artifact.sh) does NOT itself
# gate on harness.config.json pack enablement at all — it accepts ANY genre
# string, real or bogus, as the run below shows. So "disabled pack -> lands
# in unavailable[]" is a decision the Route AGENT makes by reading
# harness.config.json's packs[] and the module's static tables; it is not
# something any deterministic script enforces. What IS hermetically provable
# is (1) the real facts the agent would have to read are actually true in
# THIS repo state, and (2) the module's own prompt/schema draw genuinely
# distinct, structurally separate reason categories for each case, so a
# model reading them cannot collapse "pack disabled" into the same bucket as
# "out-of-scope third mechanism" even if it wanted to.
# ============================================================================
if command -v mif-rh-cli >/dev/null 2>&1 || [ -x "$ROOT/bin/mif-rh-cli" ] || [ -n "${MIF_RH_CLI:-}" ]; then
  bogus_out="$TMP/artifact.bogus-substrate-proof.json"
  if bash scripts/synthesize-artifact.sh reports/_meta/sample-session/findings "totally-bogus-nonexistent-genre-proof" "$bogus_out" >/dev/null 2>&1 && [ -s "$bogus_out" ]; then
    note "confirmed: synthesize-artifact.sh accepts an unrecognized genre string with no pack-enablement check of its own — pack-enablement gating is a Route-agent-only decision (documented above), not a substrate gate"
  else
    note "expected synthesize-artifact.sh to succeed on an unrecognized genre string (proving pack-enablement is NOT a substrate-level gate) — it did not; the substrate's contract may have changed, re-verify this eval's part C rationale"
    fail=1
  fi
fi

# C1: sustainability-report is a REAL, recognized genre pack (present in the
# module's own GENRE_PACKS table) that is genuinely disabled RIGHT NOW.
jq -e '.packs[] | select(.name=="sustainability-report") | .enabled==false' harness.config.json >/dev/null 2>&1 \
  || { note "harness.config.json no longer marks 'sustainability-report' enabled:false — pick a currently-disabled real genre pack for this fixture"; fail=1; }
genre_pack_has 'sustainability-report' \
  || { note "the module's GENRE_PACKS table no longer recognizes 'sustainability-report' — this case needs a pack the module KNOWS about but is disabled, not an unrecognized one"; fail=1; }
out_of_scope_has 'sustainability-report' \
  && { note "'sustainability-report' unexpectedly appears in OUT_OF_SCOPE_CHANNELS — a disabled genre pack must not collapse into the third-mechanism bucket"; fail=1; }

# C2: a genuinely NONEXISTENT genre — absent from BOTH harness.config.json
# packs[] and the module's own GENRE_PACKS table.
BOGUS='underwater-basket-weaving'
jq -e --arg g "$BOGUS" '.packs[] | select(.name==$g)' harness.config.json >/dev/null 2>&1 \
  && { note "'$BOGUS' unexpectedly exists in harness.config.json packs[] — pick a genuinely nonexistent name for this fixture"; fail=1; }
genre_pack_has "$BOGUS" \
  && { note "'$BOGUS' unexpectedly appears in the module's GENRE_PACKS table — pick a genuinely nonexistent name for this fixture"; fail=1; }

# C3: structural distinguishability — the module's Route prompt and
# ROUTE_SCHEMA draw named, separate reason categories, so "pack disabled"
# and "unrecognized channel" (mechanism 1/disabled-or-nonexistent) are not
# the same wording as "out-of-scope-third-mechanism" (the real #573 case for
# diataxis/ai-spec) or "architectural-boundary" (the "report" channel case).
for phrase in 'pack disabled' 'unrecognized channel' 'architectural-boundary' 'artifact-based' 'source-direct'; do
  grep -qF "$phrase" <<<"$route_span" \
    || { note "Route prompt lost the distinct reason-category phrase '$phrase' — disabled/nonexistent-pack reasons could collapse into a single generic bucket"; fail=1; }
done
grep -qF 'out-of-scope' <<<"$route_span" \
  || { note "Route prompt lost the out-of-scope third-mechanism reason category"; fail=1; }
for c in diataxis ai-spec; do
  grep -qF "$c" <<<"$route_span" \
    || { note "Route prompt no longer names out-of-scope channel '$c' explicitly"; fail=1; }
done
# diataxis/ai-spec (the real out-of-scope case) must live in a DIFFERENT
# static table than sustainability-report (a disabled-but-recognized genre
# pack) — proving the two failure classes are structurally, not just
# textually, distinct.
out_of_scope_has 'diataxis' && out_of_scope_has 'ai-spec' \
  || { note "OUT_OF_SCOPE_CHANNELS no longer contains diataxis/ai-spec"; fail=1; }
out_of_scope_has 'sustainability-report' \
  && { note "sustainability-report incorrectly appears alongside the out-of-scope third-mechanism channels"; fail=1; }

# ============================================================================
# D: synthesis-only evidence rule — seeded canary-claim fixture.
#
# WHAT THIS PROVES (hermetic, deterministic): synthesize-artifact.sh reads
# the FINDINGS DIR directly and includes every surviving finding's claim
# regardless of what any companion "synthesis" file says — exactly what the
# module's own header comments (lines 66-82) already document ("mechanism 1
# ... synthesize-artifact.sh reads the FINDINGS DIR directly (never the
# synthesis file)"). A canary claim present ONLY in raw findings, and
# deliberately excluded from a companion synthesis fixture, therefore DOES
# appear in the deterministic artifact/render — proving the exclusion of an
# out-of-synthesis claim is NOT something any script in this pipeline
# enforces.
#
# WHAT THIS DOES NOT PROVE (inherently model-driven, checked structurally
# instead): the Render AGENT's own instruction to cross-check the artifact's
# claims against synthesisPath and refuse to introduce a claim the synthesis
# excludes. There is no way to drive that check offline without a live model
# call, so its presence is verified as an exact structural grep of the
# mechanism-1 Render prompt text below, per this repo's own established
# precedent (deliverables-route-check.sh, projection-supersession-check.sh).
# ============================================================================
CANARY_ID='urn:mif:concept:harness:kg-canary-9f3a1c'
CANARY_TITLE='ZZZ-CANARY-CLAIM-NOT-IN-SYNTHESIS-9f3a1c'
FDIR="$TMP/findings-with-canary"
mkdir -p "$FDIR"
cp reports/_meta/sample-session/findings/*.json "$FDIR/"
cat > "$FDIR/finding-canary.json" <<JSON
{
  "@context": "https://mif-spec.dev/schema/context.jsonld",
  "@type": "Concept",
  "@id": "$CANARY_ID",
  "conceptType": "semantic",
  "namespace": "harness/example-topic",
  "title": "$CANARY_TITLE",
  "content": "$CANARY_TITLE is a seeded canary claim present only in raw findings, deliberately excluded from the companion synthesis fixture used by this eval.",
  "summary": "$CANARY_TITLE",
  "created": "2026-07-18T00:00:00Z",
  "modified": "2026-07-18T00:00:00Z",
  "temporal": { "@type": "TemporalMetadata", "validFrom": "2026-07-18T00:00:00Z" },
  "tags": ["canary"],
  "entities": [],
  "provenance": { "@type": "Provenance", "sourceType": "agent_inferred", "confidence": 0.9, "trustLevel": "high_confidence" },
  "citations": [
    { "@type": "Citation", "citationType": "documentation", "citationRole": "supports", "title": "canary source", "url": "https://example.invalid/canary", "accessed": "2026-07-18" }
  ],
  "extensions": {
    "harness": {
      "dimension": "technical",
      "verification": { "verdict": "survived", "verdict_basis": "seeded canary fixture — no adversarial process ran over it" }
    }
  }
}
JSON

# Companion synthesis fixture (schemas/*-citation fixture shape, per
# evals/fixtures/synthesis-citation/synthesis-good.json's own "claims[]"
# convention) that cites the ORIGINAL findings but deliberately OMITS the
# canary's @id — i.e. the canary claim is present in raw findings but
# absent from the synthesis.
SYN_FIXTURE="$TMP/synthesis-excludes-canary.json"
cat > "$SYN_FIXTURE" <<'JSON'
{
  "_comment": "Seeded synthesis fixture (research-harness-template#575): cites the sample-session's real findings but deliberately omits the canary finding's @id, to prove the canary claim is present in raw findings but absent from the synthesis.",
  "synthesisPath": "/dev/null/synthesis-excludes-canary-fixture.json",
  "sections": ["distribution"],
  "findingsUsed": 3,
  "claims": [
    { "checkId": "distribution", "citedId": "urn:mif:concept:harness:kg-cookiecutter-0002", "confidence": "high" },
    { "checkId": "distribution", "citedId": "urn:mif:concept:harness:kg-copier-0001", "confidence": "high" },
    { "checkId": "distribution", "citedId": "urn:mif:concept:harness:kg-distribution-0003", "confidence": "high" }
  ]
}
JSON
jq -e --arg id "$CANARY_ID" '[.claims[].citedId] | index($id) | not' "$SYN_FIXTURE" >/dev/null 2>&1 \
  || { note "test-fixture bug: the synthesis fixture unexpectedly cites the canary @id — it must NOT, for this to prove anything"; fail=1; }

CANARY_ART="$TMP/artifact.canary.json"
if ! bash scripts/synthesize-artifact.sh "$FDIR" general "$CANARY_ART" >"$TMP/synth-canary.out" 2>&1; then
  note "setup: synthesize-artifact.sh over the canary-augmented findings dir failed: $(cat "$TMP/synth-canary.out")"; fail=1
else
  grep -qF "$CANARY_TITLE" "$CANARY_ART" \
    || { note "the canary claim did NOT appear in the synthesized artifact — synthesize-artifact.sh may no longer read the findings dir directly (re-verify this eval's part D rationale against the module's real behavior)"; fail=1; }
  CANARY_OUT="$TMP/blog.canary.md"
  if ! bash scripts/render-artifact.sh "$CANARY_ART" blog "$CANARY_OUT" >"$TMP/render-canary.out" 2>&1; then
    note "setup: render-artifact.sh over the canary artifact failed: $(cat "$TMP/render-canary.out")"; fail=1
  else
    grep -qF "$CANARY_TITLE" "$CANARY_OUT" \
      || { note "the canary claim did NOT appear in the rendered blog output — cannot demonstrate the synthesis-exclusion gap this eval targets"; fail=1; }
    note "confirmed: the canary claim (present in raw findings, absent from the companion synthesis fixture) DOES appear in the deterministic render — the synthesis-only evidence rule for mechanism 1 is enforced ONLY by the Render agent's own cross-check instruction (verified structurally below), never by synthesize-artifact.sh/render-artifact.sh themselves"
  fi
fi

# Structural proof the Render agent IS instructed to perform that cross-check
# (mechanism 1), and that mechanism 2 is instructed the opposite way (never
# consult the synthesis at all — by design, per the module's own header).
grep -qF 'SYNTHESIS-ONLY EVIDENCE RULE' <<<"$render_span" \
  || { note "Render phase prompt lost the synthesis-only evidence rule cross-check instruction for mechanism 1"; fail=1; }
grep -qF 'must never introduce a claim present in raw findings but excluded or contradicted' <<<"$render_span" \
  || { note "Render phase prompt lost the exact cross-check wording that forbids introducing a claim the synthesis excludes"; fail=1; }
grep -qF 'do NOT run synthesize-artifact.sh or render-artifact.sh' <<<"$render_span" \
  || { note "Render phase prompt no longer forbids the artifact pipeline for source-direct (mechanism 2) rows"; fail=1; }
grep -qF 'read or reference the synthesis' <<<"$render_span" \
  || { note "Render phase prompt no longer forbids consulting synthesisPath for source-direct (mechanism 2) rows"; fail=1; }

# ============================================================================
# E: Witnessed provenance (research-harness-template#632). Before this fix,
# mechanism 1 (artifact-based blog/book, which render-artifact.sh's own
# header confirms carry real MIF Level-1 frontmatter) never invoked
# mif-docs-plugin's mif-provenance skill, so every deliverable's provenance
# block was whatever render-artifact.sh asserted — the same gap #632
# reported for the report channel. Structural proof the stamp is wired for
# mechanism 1, explicitly skipped (never silently attempted) for mechanism 2,
# and the outcome is actually surfaced through RENDER_SCHEMA/the final return.
# ============================================================================
grep -qF 'Skill(mif-docs:mif-provenance)' <<<"$render_span" \
  || { note "Render phase prompt no longer invokes Skill(mif-docs:mif-provenance) for mechanism 1 — the #632 witnessed-provenance stamp has regressed away for blog/book deliverables"; fail=1; }
grep -qF 'Do NOT hand-author a' <<<"$render_span" \
  || { note "Render phase prompt lost its never-hand-author-a-provenance-block-to-work-around-a-decline instruction (#632)"; fail=1; }
grep -qF 'Do NOT attempt a Skill(mif-docs:mif-provenance) stamp for this row' <<<"$render_span" \
  || { note "Render phase prompt no longer explicitly forbids the mif-provenance stamp for mechanism 2 (source-direct) rows — #632's mechanism-1-only scoping has regressed"; fail=1; }
grep -qF 'not-applicable' <<<"$render_span" \
  || { note "Render phase prompt no longer instructs mechanism 2 rows to report provenanceOutcome=\"not-applicable\""; fail=1; }
grep -qF "'provenanceOutcome'" "$WF" \
  || { note "RENDER_SCHEMA no longer declares provenanceOutcome — the #632 stamp result (or its mechanism-2 not-applicable status) would no longer be surfaced to callers"; fail=1; }
grep -qF 'provenanceOutcome: a.provenanceOutcome' "$WF" \
  || { note "the module's final return no longer forwards a.provenanceOutcome per artifact — the #632 stamp result would be silently dropped even if the Render phase still computes it"; fail=1; }

# ============================================================================
# F: Genre skill invocation (research-harness-template#640, same class as
# research-projection.js's #633). Before this fix, mechanism 1's Render step
# passed the resolved genre straight through to synthesize-artifact.sh/
# render-artifact.sh as pass-through metadata and never invoked any genre's
# real Skill(mif-docs:<genre>) template — every genre rendered the identical
# neutral body with only the frontmatter `genre:` field differing,
# indistinguishable from a correctly-genred deliverable by inspection.
# Structural proof (grepped from the module's ACTUAL AGENT PROMPT/source,
# never a header comment) that: an enabled genre's Render row invokes
# Skill(mif-docs:<genre>) — every genre pack in harness.config.json is an
# external marketplace-ref to the "mif-docs" marketplace, which (verified
# against the real mif-docs-plugin repo) publishes exactly ONE plugin named
# "mif-docs" containing every genre as a skill inside it, never a
# same-named plugin per genre — a genre="general" row does not, mechanism 2 rows
# always report no genre applied, the outcome is surfaced through
# RENDER_SCHEMA/the final return, and a caller-supplied genre is validated
# against the pack-name pattern before being interpolated into a shell
# command or Skill() reference (mirrors #633's own injection guard). This is
# inherently model-driven (Route/Render are bare `agent()` calls, per this
# file's own header) — proven structurally, per this repo's established
# precedent, not faked as hermetic.
# ============================================================================
grep -qF "genreArg !== 'general'" "$WF" \
  || { note "the module's source no longer branches the genre-skill step on genreArg !== 'general' — has #640's conditional wiring changed?"; fail=1; }
grep -qF 'Skill(mif-docs:${genreArg})' "$WF" \
  || { note "the module's source no longer contains the literal Skill(mif-docs:\${genreArg}) invocation template for mechanism 1's enabled-genre case — has #640's actual invocation shape changed, or regressed to the wrong same-named-plugin form?"; fail=1; }
grep -qF 'GENRE SKILL APPLICATION' <<<"$render_span" \
  || { note "Render phase prompt lost the GENRE SKILL APPLICATION step (#640) — a requested genre could once again render only the neutral body"; fail=1; }
grep -qF 'genreApplied=false, genreSkillInvoked=""' "$WF" \
  || { note "the module no longer has an explicit genreApplied=false/genreSkillInvoked=\"\" branch (the genre=\"general\" neutral case, or mechanism 2's no-genre-axis case) — #640's honest-fallback wiring may have regressed"; fail=1; }
grep -qF 'There is no genre axis for this mechanism (#640)' <<<"$render_span" \
  || { note "Render phase prompt's source-direct (mechanism 2) branch no longer states genreApplied is always false — the genre-doesn't-apply contract could silently drift"; fail=1; }
grep -qF "'genreApplied'" "$WF" \
  || { note "RENDER_SCHEMA no longer declares genreApplied — the #640 genre-skill outcome would no longer be surfaced to callers"; fail=1; }
grep -qF "'genreSkillInvoked'" "$WF" \
  || { note "RENDER_SCHEMA no longer declares genreSkillInvoked — the #640 genre-skill outcome would no longer be surfaced to callers"; fail=1; }
grep -qF 'genreApplied: a.genreApplied' "$WF" \
  || { note "the module's final return no longer forwards a.genreApplied per artifact — the #640 genre-skill outcome would be silently dropped even if the Render phase still computes it"; fail=1; }
grep -qF 'genreSkillInvoked: a.genreSkillInvoked' "$WF" \
  || { note "the module's final return no longer forwards a.genreSkillInvoked per artifact — the #640 genre-skill outcome would be silently dropped even if the Render phase still computes it"; fail=1; }
grep -qF 'GENRE STRING VALIDATION' "$WF" \
  || { note "the module lost its genre-string validation guard (#640, mirrors #633's own injection guard) — an unvalidated route.plan genre could flow straight into a shell command / Skill() reference"; fail=1; }
grep -qF '/^[a-z][a-z0-9-]*$/.test(p.genre)' "$WF" \
  || { note "the module's genre-string validation no longer matches the harness.config.schema.json packs[].name pattern (^[a-z][a-z0-9-]*\$) — has the validation regex changed or been dropped?"; fail=1; }
# Every real GENRE_PACKS key must actually satisfy the validation pattern
# used above — proves the guard cannot reject a genuinely enabled genre.
python3 - "$WF" <<'PY'
import re, sys
wf = open(sys.argv[1]).read()
m = re.search(r'const GENRE_PACKS = \{(.*?)\n\}', wf, re.S)
keys = re.findall(r"'?([A-Za-z][A-Za-z0-9-]*)'?\s*:\s*\{", m.group(1)) if m else []
pat = re.compile(r'^[a-z][a-z0-9-]*$')
bad = [k for k in keys if not pat.match(k)]
if bad:
    print(f"FAIL: GENRE_PACKS entries {bad} do not match the ^[a-z][a-z0-9-]*$ pattern #640's validation guard enforces — a genuinely enabled genre would be rejected")
    sys.exit(1)
if not keys:
    print("FAIL: could not extract any GENRE_PACKS keys to cross-check against the validation pattern")
    sys.exit(1)
PY
[ $? -eq 0 ] || fail=1

# ============================================================================
# G: CHANNELS truthiness regression (research-harness-template#626). The
# module's own CHANNELS default previously collapsed an explicit
# `channels: []` ("caller wants zero channels rendered, on purpose") into
# the SAME branch as `channels` never being passed at all ("use the default")
# — both silently became ['blog']. G1 proves the fixed source line directly;
# G2/G3 drive the REAL module (same async-function-body technique
# research-pipeline-full-mode-check.sh uses) to prove the two cases now
# resolve to genuinely DIFFERENT CHANNELS values at runtime, not just in a
# source-text grep.
# ============================================================================
grep -qF "const CHANNELS = (args && Array.isArray(args.channels)) ? args.channels : ['blog']" "$WF" \
  || { note "G1: $WF no longer computes CHANNELS via Array.isArray — the explicit-empty-vs-omitted truthiness bug (#626) may have regressed"; fail=1; }

cat > "$TMP/channels-driver.cjs" <<'NODE'
'use strict';
const fs = require('fs');
const [, , wfPath, argsJsonPath, outPath] = process.argv;
const rawSrc = fs.readFileSync(wfPath, 'utf8');
const src = rawSrc.replace(/^export[ \t]+(const[ \t]+meta\b)/gm, '$1');
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const fn = new AsyncFunction('args', 'phase', 'agent', 'log', 'pipeline', 'parallel', src);
const args = JSON.parse(fs.readFileSync(argsJsonPath, 'utf8'));
let routePrompt = null;
let callCount = 0;
async function agentStub(prompt) {
  callCount += 1;
  if (callCount === 1) return { exists: true, reason: 'ok' }; // preflight
  routePrompt = prompt; // Route agent's own prompt — CHANNELS is embedded via JSON.stringify
  throw new Error('__stop_after_route_prompt_captured__');
}
function phaseStub() {}
function logStub() {}
async function pipelineStub() { return []; }
async function parallelStub(fns) { return Promise.all((fns || []).map((f) => f())); }
(async () => {
  try {
    await fn(args, phaseStub, agentStub, logStub, pipelineStub, parallelStub);
  } catch (e) {
    // expected — we threw deliberately once the Route prompt was captured
  }
  fs.writeFileSync(outPath, JSON.stringify({ routePrompt }, null, 2));
})();
NODE

# G2: explicit channels: [] must resolve to CHANNELS=[] — "Requested channels: []"
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"channels-eval-topic\",\"synthesisPath\":\"$TMP/syn.json\",\"channels\":[]}" > "$TMP/args-f2.json"
node "$TMP/channels-driver.cjs" "$WF" "$TMP/args-f2.json" "$TMP/out-f2.json" >"$TMP/f2.err" 2>&1
if [ -f "$TMP/out-f2.json" ]; then
  python3 -c "import json,sys; d=json.load(open('$TMP/out-f2.json')); sys.exit(0 if 'Requested channels: []' in (d.get('routePrompt') or '') else 1)" \
    || { note "G2: an explicit channels:[] did not resolve to CHANNELS=[] in the real Route prompt"; fail=1; }
else
  note "G2: driver produced no output ($(cat "$TMP/f2.err"))"; fail=1
fi

# G3: channels omitted entirely must still default to CHANNELS=['blog'] —
# "Requested channels: [\"blog\"]" — the existing single-genre convention is
# preserved unchanged for the common (no-args) case.
printf '%s' "{\"harnessDir\":\"$TMP/h\",\"topic\":\"channels-eval-topic\",\"synthesisPath\":\"$TMP/syn.json\"}" > "$TMP/args-f3.json"
node "$TMP/channels-driver.cjs" "$WF" "$TMP/args-f3.json" "$TMP/out-f3.json" >"$TMP/f3.err" 2>&1
if [ -f "$TMP/out-f3.json" ]; then
  python3 -c "import json,sys; d=json.load(open('$TMP/out-f3.json')); sys.exit(0 if 'Requested channels: [\"blog\"]' in (d.get('routePrompt') or '') else 1)" \
    || { note "G3: an omitted channels arg no longer defaults to CHANNELS=['blog'] in the real Route prompt"; fail=1; }
else
  note "G3: driver produced no output ($(cat "$TMP/f3.err"))"; fail=1
fi
note "G: explicit channels:[] resolves to zero channels (never silently coerced to the ['blog'] default), while an omitted channels arg still defaults to ['blog'] unchanged — proven against the real module, not just a source grep"

if [ "$fail" -eq 0 ]; then
  echo "deliverables-genre-channel-route: all cases passed"
else
  echo "deliverables-genre-channel-route: FAILED (see notes above)"
fi
exit "$fail"
