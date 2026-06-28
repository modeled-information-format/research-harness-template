#!/usr/bin/env bash
# site-toggle.sh (eval) — exercise the site-projection control plane end-to-end:
# the site-toggle.sh helper mutates harness.config.json `.site`, astro.config.mjs
# reads and gates on it, content.config.ts binds reports with the report negations,
# and copier.yml activates reports-primary in a clone. Asserts each invariant
# without a full astro build (covered by the docs CI build + gate_m23).
#
#   bash evals/site-toggle.sh   # exit 0 iff every assertion holds

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail() { echo "site-toggle-eval: $1" >&2; exit 1; }

CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
# A minimal manifest with no .site block — the helper must create it.
echo '{"version":"1.0.0","topics":[],"dimensions":[],"packs":[]}' > "$CFG"

# 1. primary round-trip: the helper creates .site and sets primarySurface.
bash scripts/site-toggle.sh primary reports "$CFG" >/dev/null 2>&1 || fail "primary reports failed"
[ "$(jq -r '.site.primarySurface' "$CFG")" = "reports" ] || fail "primarySurface not set to reports"
bash scripts/site-toggle.sh primary docs "$CFG" >/dev/null 2>&1 || fail "primary docs failed"
[ "$(jq -r '.site.primarySurface' "$CFG")" = "docs" ] || fail "primarySurface not flipped to docs"

# 2. plugin round-trip: each known plugin flips on/off; unknown names rejected.
for p in llmsTxt mermaid imageZoom linksValidator; do
  bash scripts/site-toggle.sh plugin "$p" on "$CFG" >/dev/null 2>&1 || fail "plugin $p on failed"
  [ "$(jq -r --arg p "$p" '.site.plugins[$p]' "$CFG")" = "true" ] || fail "plugin $p not enabled"
  bash scripts/site-toggle.sh plugin "$p" off "$CFG" >/dev/null 2>&1 || fail "plugin $p off failed"
  [ "$(jq -r --arg p "$p" '.site.plugins[$p]' "$CFG")" = "false" ] || fail "plugin $p not disabled"
done
bash scripts/site-toggle.sh primary bogus "$CFG" >/dev/null 2>&1 && fail "invalid primary value accepted"
bash scripts/site-toggle.sh plugin nope on "$CFG" >/dev/null 2>&1 && fail "unknown plugin accepted"

# 3. astro.config.mjs is config-driven (reads the manifest; gates each plugin + surface).
ac=astro.config.mjs
for needle in "harness.config.json" "primarySurface" "plugins.llmsTxt" "plugins.mermaid" \
              "plugins.imageZoom" "plugins.linksValidator"; do
  grep -qF "$needle" "$ac" || fail "astro.config.mjs does not reference '$needle' (hardcoded integration?)"
done

# 4. content.config.ts binds reports via glob (standard src/content/docs base) with the
#    report negations, and reports/ is reached through the docs/reports symlink.
cc=src/content.config.ts
for needle in "glob(" "base: './src/content/docs'" "!reports/_meta/**" \
              "!reports/**/research-progress.md" "!reports/**/README.md"; do
  grep -qF "$needle" "$cc" || fail "content.config.ts missing '$needle' (reports binding regressed)"
done
[ "$(readlink docs/reports 2>/dev/null)" = "../reports" ] || fail "docs/reports symlink (-> ../reports) missing"

# 5. copier activates reports-primary in a clone.
grep -A3 '_tasks:' copier.yml | grep -qF "site-toggle.sh primary reports" \
  || fail "copier.yml _tasks does not run 'site-toggle.sh primary reports'"

echo "site-toggle-eval: PASS"
exit 0
