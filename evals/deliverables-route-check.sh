#!/usr/bin/env bash
# deliverables-route-check.sh — regression eval for the research-deliverables
# workflow module (research-harness-template#573, Epic #544).
#
# The vendored module (.claude/workflows/research-deliverables.js) has NO
# extractable pure arithmetic function comparable to research-falsify.js's
# mergeVotes() (#562) — Route is necessarily an agent() call (the module
# itself has no filesystem access; only an agent's Bash/Read tools can read
# harness.config.json/.claude/settings.local.json), matching
# research-projection.js's own precedent (#571) of "hermetic where the
# module's own logic can express it, structural greps where the behavior is
# inherently model-driven, say so explicitly rather than fake determinism".
# This eval was designed against that real constraint:
#
#   A. Static pack-taxonomy tables (GENRE_PACKS/METHODOLOGY_PACKS/
#      SOURCE_DIRECT_CHANNELS/OUT_OF_SCOPE_CHANNELS/ARTIFACT_CHANNELS), which
#      the module embeds so its Route prompt never has to guess a pack's
#      kind, are cross-checked against the REAL
#      docs/reference/packs/index.md "Pack inventory" table (parsed, not
#      eyeballed) — a drift between this module's table and the real docs
#      (a pack's kind changes, a new genre pack ships, a channel is
#      reclassified) is a caught regression, never a silent guess.
#
#   B. Structural grep of the module's ACTUAL AGENT PROMPT BODIES (extracted
#      by phase() marker, so a mere header-comment mention can never satisfy
#      this): the Route prompt states the exact settings.local.json
#      enabledPlugins key shape ("<pack>@research-harness", never a bare
#      pack-name lookup), the report-channel architectural-boundary
#      reason, and the out-of-scope third-mechanism channels; the Render
#      prompt's artifact-based branch invokes scripts/synthesize-artifact.sh
#      -> scripts/render-artifact.sh (never free-form-authoring content) and
#      its source-direct branch invokes Skill(<pack>:<pack>) directly
#      without ever calling either script or reading synthesisPath.
#
#   C. A REAL, hermetic, no-model fixture run through the actual
#      synthesize-artifact.sh -> render-artifact.sh pipeline (offline,
#      against reports/_meta/sample-session's real findings) for the blog
#      channel, proving the exact claim the Render prompt makes: the
#      rendered output is citation-leak clean BY THE REAL ENFORCED PATTERN
#      (.claude/hooks/check-citation-leak.sh's own LEAK_RE, extracted
#      verbatim from that script, not re-typed) — never asserted, always
#      checked.
#
#   D. The two-mechanism scope boundary is proven structurally: "report" is
#      named as research-projection's job (never silently treated as an
#      unavailable artifact-based channel), and mechanism 2's genre-doesn't-
#      apply / synthesis-never-consulted rules are both present in the
#      source-direct Render prompt branch.
#
# Hermetic: node/jq/python3/the vendored bin/mif-rh-cli (offline —
# ADR-0016), reports/_meta/sample-session's real findings, and mktemp
# scratch only. No network, no live model/API calls anywhere in this eval.
#
# Exit 0 = every case holds. Exit 1 = a case failed. Exit 2 = a required tool
# (node/jq/python3/the engine) is missing — this eval refuses to silently skip.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-deliverables.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  deliverables-route-check: %s\n' "$1"; }

command -v node >/dev/null 2>&1 || { note "node is required but not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { note "jq is required but not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found — the vendored research-deliverables workflow must ship (Epic #544, Task #573)"; exit 2; }
if [ -z "${MIF_RH_CLI:-}" ] && [ ! -x "$ROOT/bin/mif-rh-cli" ] && ! command -v mif-rh-cli >/dev/null 2>&1; then
  note "the mif-rh-cli engine is required (scripts/fetch-engine.sh, PATH, or MIF_RH_CLI) — see ADR-0016"
  exit 2
fi

# ============================================================================
# A: Static pack-taxonomy cross-check against the REAL docs/reference/
#    packs/index.md "Pack inventory" table.
# ============================================================================
python3 - "$WF" "docs/reference/packs/index.md" <<'PY'
import json, re, sys
wf_path, doc_path = sys.argv[1], sys.argv[2]
wf = open(wf_path).read()
doc = open(doc_path).read()

def extract_obj_keys(name):
    m = re.search(r'const %s = \{(.*?)\n\}' % re.escape(name), wf, re.S)
    if not m:
        print(f"FAIL: could not find `const {name} = {{...}}` in {wf_path}")
        return None
    body = m.group(1)
    return re.findall(r"^\s*'?([A-Za-z][A-Za-z0-9-]*)'?:", body, re.M)

def extract_arr(name):
    m = re.search(r'const %s = \[(.*?)\]' % re.escape(name), wf)
    if not m:
        print(f"FAIL: could not find `const {name} = [...]` in {wf_path}")
        return None
    return re.findall(r"'([a-z0-9-]+)'", m.group(1))

genre_packs = extract_obj_keys('GENRE_PACKS')
methodology_packs = extract_arr('METHODOLOGY_PACKS')
source_direct = extract_arr('SOURCE_DIRECT_CHANNELS')
out_of_scope = extract_arr('OUT_OF_SCOPE_CHANNELS')
artifact_channels = extract_arr('ARTIFACT_CHANNELS')

ok = all(x is not None for x in (genre_packs, methodology_packs, source_direct, out_of_scope, artifact_channels))
if not ok:
    sys.exit(1)

# Parse the real doc's "| Name | Family | Kind | ... |" table rows.
doc_kind = {}
for line in doc.splitlines():
    m = re.match(r'^\|\s*([a-z][a-z0-9-]*)\s*\|\s*([a-z0-9-]+)\s*\|\s*(methodology|genre|channel|ontology)\s*\|', line)
    if m:
        doc_kind[m.group(1)] = m.group(3)

fail = False
for g in genre_packs:
    real = doc_kind.get(g)
    if real is None:
        print(f"FAIL: module's GENRE_PACKS names '{g}' but docs/reference/packs/index.md has no matching row — has the pack been renamed/removed?")
        fail = True
    elif real != 'genre':
        print(f"FAIL: module's GENRE_PACKS names '{g}' but the real docs classify it kind='{real}', not 'genre' — the module's static table has drifted from the real substrate")
        fail = True
for m_ in methodology_packs:
    real = doc_kind.get(m_)
    if real is None:
        print(f"FAIL: module's METHODOLOGY_PACKS names '{m_}' but docs/reference/packs/index.md has no matching row")
        fail = True
    elif real != 'methodology':
        print(f"FAIL: module's METHODOLOGY_PACKS names '{m_}' but the real docs classify it kind='{real}', not 'methodology' — this is exactly the genre/methodology confusion this module exists to avoid")
        fail = True
for c in source_direct:
    real = doc_kind.get(c)
    if real is None:
        print(f"FAIL: module's SOURCE_DIRECT_CHANNELS names '{c}' but docs/reference/packs/index.md has no matching row")
        fail = True
    elif real != 'channel':
        print(f"FAIL: module's SOURCE_DIRECT_CHANNELS names '{c}' but the real docs classify it kind='{real}', not 'channel'")
        fail = True
for c in out_of_scope:
    real = doc_kind.get(c)
    if real is None:
        print(f"FAIL: module's OUT_OF_SCOPE_CHANNELS names '{c}' but docs/reference/packs/index.md has no matching row")
        fail = True
    elif real != 'channel':
        print(f"FAIL: module's OUT_OF_SCOPE_CHANNELS names '{c}' but the real docs classify it kind='{real}', not 'channel'")
        fail = True
# 'book' must be a real channel pack (it gates channel="book" on top of any genre check).
if doc_kind.get('book') != 'channel':
    print("FAIL: 'book' is not classified kind='channel' in docs/reference/packs/index.md — the module's book-pack-gates-the-channel logic assumes this")
    fail = True
if 'blog' not in artifact_channels or 'book' not in artifact_channels:
    print("FAIL: ARTIFACT_CHANNELS must contain exactly 'blog' and 'book'")
    fail = True
if 'report' in artifact_channels:
    print("FAIL: ARTIFACT_CHANNELS must NOT contain 'report' — that channel is research-projection's job, not this module's")
    fail = True

sys.exit(1 if fail else 0)
PY
[ $? -eq 0 ] || fail=1

# ============================================================================
# B: Structural grep of the ACTUAL AGENT PROMPT BODIES, never a header
#    comment (extracted by phase() marker span).
# ============================================================================
route_span="$(awk '/^const route = await agent\(/{f=1} f{print} /^if \(!route\)/{exit}' "$WF")"
render_span="$(awk '/^phase\(.Render.\)/{f=1} f{print} /^const artifacts = /{exit}' "$WF")"

[ -n "$route_span" ] || { note "could not locate the Route agent prompt body in $WF — has the shape changed?"; fail=1; }
[ -n "$render_span" ] || { note "could not locate the Render phase body in $WF — has the phase-marker shape changed?"; fail=1; }

grep -qF '@research-harness' <<<"$route_span" \
  || { note "Route prompt lost the exact settings.local.json enabledPlugins key shape ('<pack>@research-harness') — regression toward a bare pack-name lookup"; fail=1; }
grep -qF 'research-projection' <<<"$route_span" \
  || { note "Route prompt lost the architectural-boundary reason for channel=\"report\" (research-projection's job, not this module's)"; fail=1; }
for c in diataxis ai-spec; do
  grep -qF "$c" <<<"$route_span" \
    || { note "Route prompt no longer names out-of-scope channel '$c' explicitly — a third-mechanism request could get silently mapped onto mechanism 1 or 2 instead of unavailable[]"; fail=1; }
done
grep -qF 'methodology' <<<"$route_span" \
  || { note "Route prompt lost the methodology-pack-is-not-a-genre-template distinction"; fail=1; }

for s in synthesize-artifact.sh render-artifact.sh; do
  grep -qF "scripts/$s" <<<"$render_span" \
    || { note "Render phase prompt no longer invokes scripts/$s for the artifact-based mechanism — regression toward free-form content authoring"; fail=1; }
done
grep -qF 'Skill(' <<<"$render_span" \
  || { note "Render phase prompt lost the direct Skill(<pack>:<pack>) invocation for source-direct channels"; fail=1; }
grep -qF 'do NOT run synthesize-artifact.sh or render-artifact.sh' <<<"$render_span" \
  || { note "Render phase prompt no longer explicitly forbids the artifact pipeline for source-direct rows — the two mechanisms could get conflated"; fail=1; }
grep -qF 'Do NOT' <<<"$render_span" && grep -qF 'read or reference the synthesis' <<<"$render_span" \
  || { note "Render phase prompt no longer explicitly forbids consulting synthesisPath for source-direct rows"; fail=1; }

# ============================================================================
# C: REAL fixture run — synthesize-artifact.sh -> render-artifact.sh (blog),
# offline, against reports/_meta/sample-session's real findings — proving the
# citation-leak gate holds BY THE REAL ENFORCED PATTERN (extracted verbatim
# from .claude/hooks/check-citation-leak.sh, not re-typed).
# ============================================================================
LEAK_RE="$(grep -m1 '^LEAK_RE=' .claude/hooks/check-citation-leak.sh | sed -E "s/^LEAK_RE='(.*)'$/\1/")"
[ -n "$LEAK_RE" ] || { note "could not extract LEAK_RE from .claude/hooks/check-citation-leak.sh — has its shape changed?"; fail=1; }

SF="reports/_meta/sample-session/findings"
if ! bash scripts/synthesize-artifact.sh "$SF" general "$TMP/artifact.json" >"$TMP/synth.out" 2>&1; then
  note "setup: synthesize-artifact.sh (genre=general) failed: $(cat "$TMP/synth.out")"; fail=1
elif ! bash scripts/render-artifact.sh "$TMP/artifact.json" blog "$TMP/blog-out.md" >"$TMP/render.out" 2>&1; then
  note "setup: render-artifact.sh (channel=blog) failed: $(cat "$TMP/render.out")"; fail=1
else
  [ -s "$TMP/blog-out.md" ] || { note "render-artifact.sh (blog) produced an empty file"; fail=1; }
  if grep -nE "$LEAK_RE" "$TMP/blog-out.md" >"$TMP/leak.out" 2>/dev/null; then
    note "citation-leak gate FAILED on the real blog render — the Render prompt's claim that render-artifact.sh's engine delegation keeps blog/book citation-clean does not hold against this fixture: $(cat "$TMP/leak.out")"
    fail=1
  fi
  grep -qE '^## ' "$TMP/blog-out.md" || { note "blog render has no per-finding sections — the pipeline did not actually run over the fixture findings"; fail=1; }
fi

# ============================================================================
# D: outputs[]/packs[] enablement asymmetry — 'blog' needs no pack, 'book'
# is itself a channel pack. Structural check that the Route prompt states
# this explicitly (the exact nuance a naive uniform pack-check would miss).
# ============================================================================
grep -qF 'core/always-on' <<<"$route_span" \
  || { note "Route prompt lost the blog-needs-no-pack / book-is-itself-a-pack distinction"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "deliverables-route-check: all cases passed"
else
  echo "deliverables-route-check: FAILED (see notes above)"
fi
exit "$fail"
