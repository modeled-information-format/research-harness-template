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
#      SOURCE_DIRECT_CHANNELS/SOURCE_DIRECT_GENRE_CHANNELS/ARTIFACT_CHANNELS),
#      which the module embeds so its Route prompt never has to guess a
#      pack's kind, are cross-checked against the REAL
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
#      reason, the diataxis/ai-spec source-direct channels (research-
#      harness-template#734 — real in-scope mechanism-2 channels, not an
#      out-of-scope third mechanism), and the noBackingMechanism handling
#      for the four standalone diataxis-* genre packs; the Render prompt's
#      artifact-based branch invokes scripts/synthesize-artifact.sh ->
#      scripts/render-artifact.sh (never free-form-authoring content), its
#      source-direct branch invokes Skill(<channel>:<skillName>) directly
#      without ever calling either script or reading synthesisPath, and its
#      ai-spec row passes a requested genre through as an argument (#734).
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
    # research-harness-template#658: a line-anchored '^...:' pattern only
    # matched the FIRST key on each source line, silently skipping every
    # other comma-separated entry sharing a line (GENRE_PACKS packs several
    # keys per line for density) — this cross-check was validating a small
    # minority of real GENRE_PACKS keys against the docs table without
    # anyone noticing, since a key it never extracted could never fail here
    # even if fully absent from the docs. Match every top-level key instead,
    # identified by its value starting with '{' (an empty {} genre entry or
    # a { consumingChannel: ... } entry) — this also correctly EXCLUDES the
    # nested `consumingChannel` key itself, whose value starts with a quote,
    # not a brace.
    return re.findall(r"'?([A-Za-z][A-Za-z0-9-]*)'?\s*:\s*\{", body)

def extract_arr(name):
    m = re.search(r'const %s = \[(.*?)\]' % re.escape(name), wf)
    if not m:
        print(f"FAIL: could not find `const {name} = [...]` in {wf_path}")
        return None
    return re.findall(r"'([a-z0-9-]+)'", m.group(1))

genre_packs = extract_obj_keys('GENRE_PACKS')
methodology_packs = extract_arr('METHODOLOGY_PACKS')
source_direct = extract_arr('SOURCE_DIRECT_CHANNELS')
source_direct_genre = extract_arr('SOURCE_DIRECT_GENRE_CHANNELS')
artifact_channels = extract_arr('ARTIFACT_CHANNELS')

ok = all(x is not None for x in (genre_packs, methodology_packs, source_direct, source_direct_genre, artifact_channels))
if not ok:
    sys.exit(1)

# Parse the real doc's "| Name | Family | Kind | ... |" table rows. A bare
# name is not guaranteed unique across families in this table (e.g.
# 'trend-analysis' is BOTH a reports/genre pack AND, separately, an
# ontologies/ontology pack of the same name) — collapsing to a single
# name->kind dict would let the LAST matching row silently overwrite an
# earlier one, so this must accumulate a SET of kinds seen per name, not one
# scalar (discovered by research-harness-template#658's own regex fix above:
# once extract_obj_keys stopped silently dropping most GENRE_PACKS keys,
# 'trend-analysis' was checked for the first time and a single-valued dict
# would have reported a false-positive kind mismatch against its own
# genuine 'genre' row, purely because 'ontology' came later in the table).
doc_kinds = {}
for line in doc.splitlines():
    m = re.match(r'^\|\s*([a-z][a-z0-9-]*)\s*\|\s*([a-z0-9-]+)\s*\|\s*(methodology|genre|channel|ontology)\s*\|', line)
    if m:
        doc_kinds.setdefault(m.group(1), set()).add(m.group(3))

def check_all(names, expected_kind, table_name):
    global fail
    for n in names:
        kinds = doc_kinds.get(n)
        if not kinds:
            print(f"FAIL: module's {table_name} names '{n}' but docs/reference/packs/index.md has no matching row — has the pack been renamed/removed?")
            fail = True
        elif expected_kind not in kinds:
            print(f"FAIL: module's {table_name} names '{n}' but the real docs classify it kind={sorted(kinds)!r}, never '{expected_kind}' — the module's static table has drifted from the real substrate")
            fail = True

fail = False
check_all(genre_packs, 'genre', 'GENRE_PACKS')
check_all(methodology_packs, 'methodology', 'METHODOLOGY_PACKS')
check_all(source_direct, 'channel', 'SOURCE_DIRECT_CHANNELS')
check_all(source_direct_genre, 'channel', 'SOURCE_DIRECT_GENRE_CHANNELS')
# 'book' must be a real channel pack (it gates channel="book" on top of any genre check).
if 'channel' not in doc_kinds.get('book', set()):
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
# research-harness-template#734: diataxis/ai-spec are real in-scope mechanism-2
# channels now, not an out-of-scope third mechanism — check they're still named
# as real source-direct channels (never silently dropped from the Route prompt).
for c in diataxis ai-spec; do
  grep -qF "$c" <<<"$route_span" \
    || { note "Route prompt no longer names source-direct channel '$c' explicitly — it could get silently dropped from routing"; fail=1; }
done
grep -qF 'GENRE PASSTHROUGH' <<<"$render_span" \
  || { note "Render phase prompt lost the ai-spec genre-passthrough branch (research-harness-template#734) — a requested genre would silently stop reaching the ai-spec skill"; fail=1; }
grep -qF 'noBackingMechanism' <<<"$route_span" \
  || { note "Route prompt lost the noBackingMechanism handling for the four standalone diataxis-* genre packs — a request for one could get silently routed through the diataxis channel pack as if genre selection applied there"; fail=1; }
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
