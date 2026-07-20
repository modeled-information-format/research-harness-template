#!/usr/bin/env bash
# deliverables-genre-catalog-check.sh — regression eval for
# research-harness-template#658.
#
# evals/deliverables-route-check.sh's part A cross-checks research-
# deliverables.js's GENRE_PACKS table against docs/reference/packs/index.md,
# but that check is inherently one-directional: it can only catch a genre
# that IS in GENRE_PACKS getting the wrong docs row, never a genre that is
# MISSING FROM GENRE_PACKS ENTIRELY — because it iterates over
# GENRE_PACKS's own keys to begin with. #658's real defect (13 of the
# mif-docs plugin's 37 real genre skills, later found to be 14 counting
# arc42-arch-doc, were simply absent from GENRE_PACKS) drifted silently
# because docs/reference/packs/index.md had drifted from the real plugin
# catalog IN THE SAME DIRECTION — both were missing the same rows, so the
# two hand-maintained tables agreed with each other while both disagreeing
# with the real substrate. Checking GENRE_PACKS against index.md can never
# catch that class of drift; only checking against the REAL mif-docs-plugin
# skill catalog can.
#
# This eval does exactly that: it reads the pinned mif-docs-plugin cache
# (vendored by scripts/fetch-mif-docs-plugin.sh, ADR-0018 — same cache
# scripts/verify.sh's gate_m32 requires) directly off disk and asserts every
# one of its real genre skills (every skills/<name>/ directory except the 6
# known non-genre utility skills: doc-set-planner, ears-acceptance-criteria,
# mif-corpus, mif-frontmatter, mif-provenance, mif-validate) has a matching
# entry in GENRE_PACKS. Run against the pre-#658 GENRE_PACKS, this eval
# fails naming exactly the 14 genres #658 found missing; run against the
# fixed table, it passes.
#
# Hermetic once the plugin cache exists (no network, no live model calls);
# fails closed (never silently skips) if the cache is absent, naming the
# fetch command to run first — same convention as scripts/verify.sh's
# gate_m32.
#
# Exit 0 = GENRE_PACKS covers every real genre skill. Exit 1 = at least one
# is missing. Exit 2 = a required tool or the plugin cache itself is absent.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

WF=".claude/workflows/research-deliverables.js"
PLUGIN_CACHE="${MIF_DOCS_PLUGIN_ROOT:-$ROOT/.mif-docs-plugin-cache}"
note() { printf '  deliverables-genre-catalog-check: %s\n' "$1"; }

command -v python3 >/dev/null 2>&1 || { note "python3 is required but not on PATH"; exit 2; }
[ -f "$WF" ] || { note "$WF not found"; exit 2; }
if [ ! -d "$PLUGIN_CACHE/skills" ]; then
  note "mif-docs-plugin cache NOT FETCHED at $PLUGIN_CACHE — run scripts/fetch-mif-docs-plugin.sh first (same prerequisite as verify.sh's gate_m32)"
  exit 2
fi

python3 - "$WF" "$PLUGIN_CACHE/skills" <<'PY'
import os, re, sys

wf_path, skills_dir = sys.argv[1], sys.argv[2]
wf = open(wf_path).read()

m = re.search(r'const GENRE_PACKS = \{(.*?)\n\}', wf, re.S)
if not m:
    print("FAIL: could not find `const GENRE_PACKS = {...}` in", wf_path)
    sys.exit(1)
# Match every top-level key (value starts with '{': an empty {} genre entry
# or a { consumingChannel: ... } entry) — correctly excludes the nested
# `consumingChannel` key itself, whose value starts with a quote, not a
# brace. Same pattern evals/deliverables-route-check.sh uses (research-
# harness-template#658 fixed both to stop under-checking via a line-
# anchored regex that silently matched only the first key per source line).
genre_packs = set(re.findall(r"'?([A-Za-z][A-Za-z0-9-]*)'?:\s*\{", m.group(1)))

UTILITY_SKILLS = {
    'doc-set-planner', 'ears-acceptance-criteria', 'mif-corpus',
    'mif-frontmatter', 'mif-provenance', 'mif-validate',
}
real_genre_skills = {
    d for d in os.listdir(skills_dir)
    if os.path.isdir(os.path.join(skills_dir, d)) and d not in UTILITY_SKILLS
}

missing = sorted(real_genre_skills - genre_packs)
extra = sorted(genre_packs - real_genre_skills)

fail = False
if missing:
    print(f"FAIL: GENRE_PACKS is missing {len(missing)} real mif-docs genre skill(s), unroutable regardless of pack enablement: {missing}")
    fail = True
if extra:
    print(f"FAIL: GENRE_PACKS names {len(extra)} entr(y/ies) with no matching mif-docs-plugin skill directory — renamed/removed upstream?: {extra}")
    fail = True

if not fail:
    print(f"deliverables-genre-catalog-check: GENRE_PACKS covers all {len(real_genre_skills)} real mif-docs genre skills")

sys.exit(1 if fail else 0)
PY
exit $?
