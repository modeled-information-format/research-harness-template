#!/usr/bin/env bash
# verify.sh — the harness build gate.
#
# Accretive by design: each milestone appends a `gate_mN` function and registers
# it in GATES. The whole script must always exit 0 when every registered gate
# passes. Run from the repository root.
#
#   bash scripts/verify.sh
#
# Requires: jq and yq (the YAML analog of jq), plus ajv (ajv-cli) + ajv-formats.
# The MIF report projector scripts/mif-project.sh reads YAML frontmatter with yq
# (MIF is markdown-native). markdownlint-cli2 is run separately by CI / G5.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

# Template vs instance. The distributable template carries copier.yml; an
# instantiated harness has it stripped at generation. Template-only self-tests
# (Milestone 7 distribution, and 8c/8d which assert the template stays clean and
# refuses in-place imports) run ONLY in the template. An instance legitimately
# holds an imported corpus in reports/, so those gates are skipped there; the
# instance still verifies all harness CAPABILITY gates. verify.sh stays identical
# template-and-instance so `copier update` never conflicts on it.
IS_TEMPLATE=0; [ -f copier.yml ] && IS_TEMPLATE=1

PASS=0
FAIL=0
RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; RST=$'\033[0m'

ok()   { PASS=$((PASS+1)); printf '%s  ok %s %s\n' "$GREEN" "$RST" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '%sFAIL%s %s\n'   "$RED"   "$RST" "$1"; }
info() { printf '%s--- %s%s\n' "$DIM" "$1" "$RST"; }

# ajv invocation with the vendored MIF schema closure registered.
ajv_mif() { # ajv_mif <schema> <data>
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s "$1" \
    -r schemas/mif/mif.schema.json \
    -r schemas/mif/definitions/entity-reference.schema.json \
    -d "$2" >/dev/null 2>&1
}

ajv_plain() { # ajv_plain <schema> <data>
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s "$1" -d "$2" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Milestone 1 — Contracts
# ---------------------------------------------------------------------------
gate_m1() {
  info "Milestone 1 — Contracts"

  # 1a. Each schema validates its paired sample (G3).
  if ajv_mif schemas/findings.schema.json schemas/samples/finding.sample.json; then
    ok "findings schema validates sample (MIF-backed)"
  else
    bad "findings schema does not validate sample"
  fi

  if ajv_plain harness.config.schema.json harness.config.json; then
    ok "harness.config schema validates sample manifest"
  else
    bad "harness.config schema does not validate sample manifest"
  fi

  if ajv_plain schemas/pack.schema.json schemas/samples/pack.sample.json; then
    ok "pack schema validates sample pack manifest"
  else
    bad "pack schema does not validate sample pack manifest"
  fi

  # 1b. marketplace.json is valid JSON.
  if jq -e . .claude-plugin/marketplace.json >/dev/null 2>&1; then
    ok "marketplace.json parses as valid JSON"
  else
    bad "marketplace.json is not valid JSON"
  fi

  # 1c. Citation-integrity gate flags BAD and passes GOOD (G4).
  if scripts/check-citation-integrity.sh schemas/samples/citation-good.sample.json >/dev/null 2>&1; then
    ok "citation-integrity gate PASSES the GOOD sample"
  else
    bad "citation-integrity gate rejected the GOOD sample"
  fi
  if scripts/check-citation-integrity.sh schemas/samples/citation-bad.sample.json >/dev/null 2>&1; then
    bad "citation-integrity gate PASSED the BAD sample (should flag it)"
  else
    ok "citation-integrity gate FLAGS the BAD sample"
  fi

  # 1d. Contamination scrub: no corpus finding IDs or corpus report-slug paths
  #     in built artifacts (criteria "Constraints"). Planning docs are excluded;
  #     they are meta, not built artifacts. The sigint-conversion test fixture is
  #     also excluded: it deliberately carries sigint-format ids (f_tech_*,
  #     findings_*.json) because it is the INPUT the M9 conversion gate converts
  #     FROM — a test fixture, not a built artifact. reports/ is excluded too: it
  #     is the corpus/data, not a built artifact, and in an instance it legitimately
  #     holds finding ids (the template's reports/ cleanliness is covered by 8c).
  # git grep handles filenames with spaces and an empty match set safely (it
  # never reads stdin and returns 1 on no match), unlike `git ls-files | xargs grep`.
  local hits
  hits=$(git grep -nE 'f_(tech|competitive|trends|customer|sizing|financial|regulatory)_[0-9]+|reports/[a-z0-9][a-z0-9-]+/findings_' -- \
           ':!COMPLETION-CRITERIA.md' ':!IMPLEMENTATION-PLAN.md' ':!PROGRESS.md' \
           ':!evals/fixtures/sample-sigint-corpus' ':!reports' 2>/dev/null || true)
  if [ -z "$hits" ]; then
    ok "no corpus finding IDs or corpus report-slug paths in built artifacts"
  else
    bad "corpus contamination found in built artifacts:"
    printf '%s\n' "$hits" >&2
  fi
}

# ---------------------------------------------------------------------------
# Milestone 2 — Scaffold
# ---------------------------------------------------------------------------
gate_m2() {
  info "Milestone 2 — Scaffold"

  # 2a. The section 7a tree is present.
  local d missing=""
  for d in .claude/agents .claude/commands .claude/hooks .claude/skills \
           .claude-plugin schemas/mif scripts docs/tutorials docs/how-to \
           docs/reference docs/explanation evals packs reports; do
    [ -d "$d" ] || missing="${missing}${d} "
  done
  if [ -z "$missing" ]; then
    ok "section 7a tree present"
  else
    bad "section 7a tree missing dirs: $missing"
  fi

  # 2b. settings.json, marketplace.json, and every plugin.json parse as JSON.
  local jf bad_json=""
  for jf in .claude/settings.json .claude-plugin/marketplace.json harness.config.json; do
    jq -e . "$jf" >/dev/null 2>&1 || bad_json="${bad_json}${jf} "
  done
  while IFS= read -r jf; do
    [ -z "$jf" ] && continue
    jq -e . "$jf" >/dev/null 2>&1 || bad_json="${bad_json}${jf} "
  done < <(find packs -name plugin.json 2>/dev/null)
  if [ -z "$bad_json" ]; then
    ok "settings.json, marketplace.json, and every plugin.json parse as valid JSON"
  else
    bad "invalid JSON in: $bad_json"
  fi

  # 2c. Flat skill discovery: every skill is .claude/skills/<name>/SKILL.md with
  #     a description, and there are no grouping subdirectories.
  local sk bad_skill="" nested=""
  while IFS= read -r sk; do
    [ -z "$sk" ] && continue
    [ -f "$sk/SKILL.md" ] || { bad_skill="${bad_skill}${sk} "; continue; }
    grep -q '^description:' "$sk/SKILL.md" 2>/dev/null || bad_skill="${bad_skill}${sk}(no description) "
  done < <(find .claude/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  # A grouping subdir is a dir under skills/ that itself has no SKILL.md but
  # contains skill dirs (i.e. skills nested two levels deep).
  nested=$(find .claude/skills -mindepth 2 -name SKILL.md 2>/dev/null | grep -vE '^\.claude/skills/[^/]+/SKILL\.md$' || true)
  if [ -z "$bad_skill" ] && [ -z "$nested" ]; then
    ok "skills are flat (.claude/skills/<name>/SKILL.md) with descriptions"
  else
    bad "skill discovery problems: ${bad_skill}${nested:+ nested:$nested}"
  fi

  # 2c-fm. EVERY SKILL.md in the repo (core skills AND pack-plugin skills) must
  #        carry complete frontmatter: a `name:` matching its skill directory, a
  #        `description:`, and a `version:`. (A prior gap let skills ship without
  #        `name:` because the discovery check above only looked for description.)
  local f fm_bad=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    local sdir; sdir="$(basename "$(dirname "$f")")"
    local nm; nm="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1 | tr -d '"'"'"' ' )"
    [ "$nm" = "$sdir" ] || fm_bad="${fm_bad}${f}(name='${nm:-MISSING}'!=${sdir}) "
    grep -q '^description:' "$f" || fm_bad="${fm_bad}${f}(no-description) "
    grep -q '^version:' "$f"     || fm_bad="${fm_bad}${f}(no-version) "
  done < <(find .claude/skills packs -name SKILL.md 2>/dev/null | sort)
  if [ -z "$fm_bad" ]; then
    ok "every SKILL.md has complete frontmatter (name matches dir, description, version)"
  else
    bad "incomplete skill frontmatter: $fm_bad"
  fi

  # 2d. Bundled hooks referenced by settings.json exist and are executable.
  local missing_hook=""
  for h in .claude/hooks/markdown/md_guard.py \
           .claude/hooks/check-research-pipeline.sh \
           .claude/hooks/check-citation-leak.sh; do
    [ -f "$h" ] || { missing_hook="${missing_hook}${h}(missing) "; continue; }
    [ -x "$h" ] || missing_hook="${missing_hook}${h}(not executable) "
  done
  if [ -z "$missing_hook" ]; then
    ok "bundled enforcement hooks present and executable"
  else
    bad "hook problems: $missing_hook"
  fi

  # 2e. The markdown hooks import cleanly (syntax check).
  if python3 -B -c 'import sys; [compile(open(f).read(), f, "exec") for f in sys.argv[1:]]' \
       .claude/hooks/markdown/md_guard.py \
       .claude/hooks/markdown/md_lint_core.py \
       .claude/hooks/markdown/md_remediate.py >/dev/null 2>&1; then
    ok "markdown hook modules compile"
  else
    bad "markdown hook modules fail to compile"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 3 — Engine
# ---------------------------------------------------------------------------
gate_m3() {
  info "Milestone 3 — Engine"

  # 3a. The session goal contract validates its sample (goal-driven execution).
  if ajv_plain schemas/goal.schema.json reports/_meta/sample-session/goal.json; then
    ok "session goal validates against goal.schema.json"
  else
    bad "sample session goal does not validate"
  fi

  # 3b. The five engine agents are present as flat .claude/agents/<name>.md with
  #     frontmatter (KEEP the swarm orchestrator + fan-out).
  local a miss=""
  for a in orchestrator dimension-analyst falsification-analyst source-chunker report-synthesizer; do
    if [ -f ".claude/agents/$a.md" ] && head -1 ".claude/agents/$a.md" | grep -q '^---'; then :; else
      miss="${miss}${a} "
    fi
  done
  if [ -z "$miss" ]; then
    ok "five engine agents present (flat, with frontmatter)"
  else
    bad "missing/malformed engine agents: $miss"
  fi

  # 3c. The goal-driven commands are present (incl. goal-writer and resume/continuity).
  local c cmiss=""
  for c in goal-writer start status resume falsify topics; do
    [ -f ".claude/commands/$c.md" ] || cmiss="${cmiss}${c} "
  done
  if [ -z "$cmiss" ]; then
    ok "engine commands present (goal-writer, start, status, resume, falsify, topics)"
  else
    bad "missing engine commands: $cmiss"
  fi

  # 3d. The smoke test: orchestrator pipeline toward the sample goal on a fixture;
  #     exactly one falsification gate runs; emitted finding validates (MIF-backed).
  if bash evals/smoke-test.sh >/dev/null 2>&1; then
    ok "engine smoke test passes (one falsification gate; MIF-valid finding emitted)"
  else
    bad "engine smoke test failed"
    bash evals/smoke-test.sh 2>&1 | sed 's/^/      /' >&2
  fi
}

# ---------------------------------------------------------------------------
# Milestone 4 — Harness services
# ---------------------------------------------------------------------------
gate_m4() {
  info "Milestone 4 — Harness services"
  local SF="reports/_meta/sample-session/findings"
  local KG="reports/_meta/sample-session/knowledge-graph.json"
  local IDX="reports/_meta/sample-session/research-index.json"

  # 4a. The sample MIF corpus validates against the MIF-backed findings schema.
  local f bad_f=""
  for f in "$SF"/*.json; do
    ajv_mif schemas/findings.schema.json "$f" || bad_f="${bad_f}$(basename "$f") "
  done
  if [ -z "$bad_f" ]; then
    ok "sample MIF corpus validates against the findings schema"
  else
    bad "sample findings invalid: $bad_f"
  fi

  # 4b. The knowledge graph builds from MIF entities/relations and the assertion
  #     proves nodes/edges derive from urn:mif: ids, not tags (#20).
  if scripts/build-graph.sh "$SF" "$KG" >/dev/null 2>&1 \
     && scripts/build-index.sh "$SF" "$IDX" >/dev/null 2>&1 \
     && scripts/assert-graph-mif.sh "$KG" >/dev/null 2>&1; then
    ok "knowledge graph built from MIF entities/relations (not tags); assertion passes"
  else
    bad "MIF-native knowledge graph build/assertion failed"
    scripts/assert-graph-mif.sh "$KG" 2>&1 | sed 's/^/      /' >&2
  fi

  # 4c. The graph viz renders.
  if scripts/build-graph-viz.sh "$KG" "${KG%.json}.html" >/dev/null 2>&1 \
     && [ -s "${KG%.json}.html" ]; then
    ok "graph visualization renders to HTML"
  else
    bad "graph visualization failed"
  fi

  # 4d. The five services exist as flat skills with descriptions (#21-25).
  local s smiss=""
  for s in search discover lab graph topics; do
    if [ -f ".claude/skills/$s/SKILL.md" ] && grep -q '^description:' ".claude/skills/$s/SKILL.md"; then :; else
      smiss="${smiss}${s} "
    fi
  done
  if [ -z "$smiss" ]; then
    ok "five harness-service skills present (search, discover, lab, graph, topics)"
  else
    bad "missing/malformed service skills: $smiss"
  fi

  # 4e. Services operate over the MIF sample: search filters the index; discover
  #     computes the config-vs-index dimension gap (a config-declared dimension
  #     with zero findings); topics lists the registry. Each derives from MIF.
  local search_hits topic_count gaps_ok
  search_hits=$(jq -r '[.findings[] | select(.dimension=="technical")] | length' "$IDX" 2>/dev/null)
  topic_count=$(jq -r '.topics | length' harness.config.json 2>/dev/null)
  # discover's gap computation: config dimensions not present in the index. The
  # result is a (possibly empty) list — the check is that it computes cleanly.
  gaps_ok=$(jq -n --slurpfile cfg harness.config.json --slurpfile idx "$IDX" '
    ($cfg[0].dimensions | map(.id)) as $declared
    | ($idx[0].findings | map(.dimension) | unique) as $present
    | ($declared - $present) | type == "array"' 2>/dev/null)
  if [ "${search_hits:-0}" -ge 1 ] && [ "${topic_count:-0}" -ge 1 ] && [ "$gaps_ok" = "true" ]; then
    ok "services operate over the MIF sample (search filters index; discover computes gaps; topics lists registry)"
  else
    bad "service smoke over MIF sample failed (search=$search_hits topics=$topic_count gaps_ok=$gaps_ok)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 5 — Packs
# ---------------------------------------------------------------------------
gate_m5() {
  info "Milestone 5 — Packs"

  # 5a. Every bundled SKILL is its own plugin (packs/<pack>/<skill>/): each
  #     plugin.json validates against the pack contract and has a flat skills/ dir.
  local mf pbad="" pcount=0
  while IFS= read -r mf; do
    [ -z "$mf" ] && continue
    pcount=$((pcount+1))
    local dir; dir="$(dirname "$(dirname "$mf")")"   # packs/<pack>/<skill>
    if ajv_plain schemas/pack.schema.json "$mf" \
       && [ -n "$(find "$dir/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null)" ]; then :; else
      pbad="${pbad}${dir} "
    fi
  done < <(find packs -path '*/.claude-plugin/plugin.json' | sort)
  if [ -z "$pbad" ] && [ "$pcount" -ge 1 ]; then
    ok "every bundled skill is its own plugin ($pcount), each a valid manifest + flat skills/"
  else
    bad "invalid/incomplete per-skill plugins: ${pbad:-none found}"
  fi

  # 5b. Skills are flat within each plugin (packs/<pack>/<skill>/skills/<skill>/SKILL.md).
  local nested
  nested=$(find packs -mindepth 4 -name SKILL.md 2>/dev/null | grep -vE '^packs/[^/]+/[^/]+/skills/[^/]+/SKILL\.md$' || true)
  if [ -z "$nested" ]; then
    ok "every plugin's skill is flat (packs/<pack>/<skill>/skills/<skill>/SKILL.md)"
  else
    bad "non-flat plugin skills: $nested"
  fi

  # 5c. Enabling a plugin through the manifest adds its skill to Claude Code's
  #     native enabledPlugins (settings.json); disabling removes it. Proven on a
  #     currently-disabled plugin (competitive-analysis), on temp copies.
  local T; T=$(mktemp -d)
  cp .claude/settings.json "$T/settings-on.json"
  cp .claude/settings.json "$T/settings-off.json"
  jq '(.packs[] | select(.name=="competitive-analysis") | .enabled) |= true' harness.config.json > "$T/on.cfg.json"
  jq '(.packs[] | select(.name=="competitive-analysis") | .enabled) |= false' harness.config.json > "$T/off.cfg.json"
  scripts/sync-packs.sh "$T/on.cfg.json"  "$T/on.json"  "$T/settings-on.json"  >/dev/null 2>&1
  scripts/sync-packs.sh "$T/off.cfg.json" "$T/off.json" "$T/settings-off.json" >/dev/null 2>&1
  local skills_added plugin_on plugin_off
  skills_added=$(jq -r '[.packs[]|select(.name=="competitive-analysis")|.skills[]] | index("competitive-analysis") != null' "$T/on.json" 2>/dev/null)
  plugin_on=$(jq -r '.enabledPlugins | has("competitive-analysis@research-harness")' "$T/settings-on.json" 2>/dev/null)
  plugin_off=$(jq -r '.enabledPlugins | has("competitive-analysis@research-harness") | not' "$T/settings-off.json" 2>/dev/null)
  if [ "$skills_added" = "true" ] && [ "$plugin_on" = "true" ] && [ "$plugin_off" = "true" ]; then
    ok "enabling a plugin adds its skill to native enabledPlugins; disabling removes it"
  else
    bad "plugin toggle failed (skills_added=$skills_added plugin_on=$plugin_on plugin_off=$plugin_off)"
  fi

  # 5d. An external/private plugin is ingested as a pack via the manifest and
  #     lands in native enabledPlugins.
  cp .claude/settings.json "$T/settings-ext.json"
  jq '.packs += [{"name":"external-demo","enabled":true,"source":{"type":"git","url":"https://example.com/some/plugin.git","ref":"v1.0.0"}}]' \
     harness.config.json > "$T/ext.cfg.json"
  if ajv_plain harness.config.schema.json "$T/ext.cfg.json" \
     && scripts/sync-packs.sh "$T/ext.cfg.json" "$T/ext.json" "$T/settings-ext.json" >/dev/null 2>&1 \
     && [ "$(jq -r '[.packs[]|select(.name=="external-demo")|.source] | index("external") != null' "$T/ext.json")" = "true" ] \
     && [ "$(jq -r '.enabledPlugins | has("external-demo@research-harness")' "$T/settings-ext.json")" = "true" ]; then
    ok "an external/private plugin is ingested as a pack and enabled via the manifest"
  else
    bad "external plugin ingestion failed"
  fi
  rm -rf "$T"

  # 5e. Every bundled per-skill plugin is registered in the marketplace, and its
  #     source path resolves to a real plugin.json.
  local reg_ok
  reg_ok=$(python3 - <<'PY'
import json, os
mk = json.load(open(".claude-plugin/marketplace.json"))
disk = set()
for root,_,files in os.walk("packs"):
    if "plugin.json" in files and root.endswith(".claude-plugin"):
        disk.add(os.path.dirname(root))            # packs/<pack>/<skill>
listed = {p["source"].lstrip("./") for p in mk.get("plugins", [])}
missing_from_market = disk - listed
broken_source = {s for s in listed if not os.path.isfile(os.path.join(s, ".claude-plugin", "plugin.json"))}
print("ok" if not missing_from_market and not broken_source and disk else f"bad missing={missing_from_market} broken={broken_source}")
PY
)
  if [ "$reg_ok" = "ok" ]; then
    ok "every per-skill plugin is registered in marketplace.json with a resolving source"
  else
    bad "marketplace registration mismatch: $reg_ok"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 6 — Outputs
# ---------------------------------------------------------------------------
gate_m6() {
  info "Milestone 6 — Outputs"
  local SF="reports/_meta/sample-session/findings"
  local T; T=$(mktemp -d)

  # 6a. blog and book are first-class skills (flat, in the core, not a pack).
  local s smiss=""
  for s in publish-blog book-author; do
    if [ -f ".claude/skills/$s/SKILL.md" ] && grep -q '^description:' ".claude/skills/$s/SKILL.md"; then :; else
      smiss="${smiss}${s} "
    fi
  done
  if [ -z "$smiss" ]; then
    ok "blog and book are first-class flat skills"
  else
    bad "missing first-class output skills: $smiss"
  fi

  # 6b. A sample findings set renders to BOTH a blog post and a book chapter
  #     through the SAME typed findings->artifact contract.
  if scripts/synthesize-artifact.sh "$SF" general "$T/artifact.json" >/dev/null 2>&1 \
     && ajv_plain schemas/artifact.schema.json "$T/artifact.json"; then
    ok "findings synthesize into a typed artifact (validates against artifact.schema.json)"
  else
    bad "artifact synthesis/validation failed"
  fi

  local blog_ok=false book_ok=false
  scripts/render-artifact.sh "$T/artifact.json" blog "$T/post.md" >/dev/null 2>&1 \
    && [ -s "$T/post.md" ] && blog_ok=true
  scripts/render-artifact.sh "$T/artifact.json" book "$T/chapter.md" >/dev/null 2>&1 \
    && [ -s "$T/chapter.md" ] && book_ok=true
  if [ "$blog_ok" = true ] && [ "$book_ok" = true ]; then
    ok "the same artifact renders to both a blog post and a book chapter"
  else
    bad "render failed (blog=$blog_ok book=$book_ok)"
  fi

  # 6c. Both published outputs are citation-leak clean (no internal references).
  local leak
  leak=$(grep -nE 'f_[a-z]+_[0-9]+|urn:mif:|extensions\.harness|reports/[a-z0-9-]+/(findings|_meta)' \
           "$T/post.md" "$T/chapter.md" 2>/dev/null || true)
  if [ -z "$leak" ]; then
    ok "both outputs are citation-leak clean (no internal-research references)"
  else
    bad "published output leaks internal references:"; printf '%s\n' "$leak" >&2
  fi
  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 7 — Distribution
# ---------------------------------------------------------------------------
gate_m7() {
  if [ "$IS_TEMPLATE" != 1 ]; then
    info "Milestone 7 — Distribution (template-only; skipped in instance)"
    return
  fi
  info "Milestone 7 — Distribution"

  # 7a. The Copier template config and its answers/identity templates are present.
  #     copier.yml's YAML validity is proven by 7c below (copier parses it), so
  #     this check stays dependency-free (no PyYAML, which CI does not install).
  if [ -f copier.yml ] && [ -s copier.yml ] \
     && [ -f .copier-answers.yml.jinja ] && [ -f docs/harness-instance.md.jinja ] \
     && grep -q '_templates_suffix' copier.yml; then
    ok "Copier template present (copier.yml + answers + identity templates)"
  else
    bad "Copier template incomplete"
  fi

  # 7b. The eval suite passes (shipped + run here and in CI).
  if bash evals/run-evals.sh >/dev/null 2>&1; then
    ok "eval suite passes (evals/run-evals.sh)"
  else
    bad "eval suite failed"
    bash evals/run-evals.sh 2>&1 | sed 's/^/      /' >&2
  fi

  # 7c. copier update re-applies a template change to an instantiated harness.
  #     Requires copier; the milestone genuinely depends on it.
  if command -v copier >/dev/null 2>&1; then
    if bash evals/copier-update.sh >/dev/null 2>&1; then
      ok "copier update re-applies a template change to an instantiated harness"
    else
      bad "copier-update eval failed"
      bash evals/copier-update.sh 2>&1 | sed 's/^/      /' >&2
    fi
  else
    bad "copier not installed — cannot demonstrate update propagation (pipx install copier)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 8 — Corpus / KG import
# ---------------------------------------------------------------------------
gate_m8() {
  info "Milestone 8 — Corpus/KG import"
  local SRC="evals/fixtures/sample-corpus"

  # 8a. The legacy v1->v2 migrate skill is intentionally NOT carried (SPEC §4a CUT).
  #     The import path (below), not a migration shim, is how a corpus comes forward.
  if [ ! -d .claude/skills/migrate ] && [ ! -e .claude/skills/migrate ]; then
    ok "legacy v1->v2 migrate skill is not carried (CUT)"
  else
    bad "a migrate skill is present but should have been cut"
  fi

  # 8b. An existing corpus + its knowledge graph imports into a FRESH harness with
  #     provenance and graph edges intact. The import targets a TEMPORARY fresh
  #     harness — this template repo's own reports/ is never populated with a corpus.
  local T; T=$(mktemp -d)
  cp harness.config.json "$T/config.json"
  if scripts/import-corpus.sh "$SRC" imported-sample "$T/reports" "$T/config.json" >/dev/null 2>&1; then
    local src_n imp_n src_nodes imp_nodes src_edges imp_edges prov_ok
    src_n=$(find "$SRC/findings" -name '*.json' | grep -c .)
    imp_n=$(find "$T/reports/imported-sample/findings" -name '*.json' 2>/dev/null | grep -c .)
    src_nodes=$(jq '.nodes|length' "$SRC/knowledge-graph.json")
    src_edges=$(jq '.edges|length' "$SRC/knowledge-graph.json")
    imp_nodes=$(jq '.nodes|length' "$T/reports/imported-sample/knowledge-graph.json" 2>/dev/null)
    imp_edges=$(jq '.edges|length' "$T/reports/imported-sample/knowledge-graph.json" 2>/dev/null)
    # Provenance preserved on every imported finding (W3C-PROV block survives).
    prov_ok=$(find "$T/reports/imported-sample/findings" -name '*.json' -exec jq -e '.provenance.sourceType != null' {} \; 2>/dev/null | grep -c true)

    if [ "$imp_n" = "$src_n" ] && [ "$imp_nodes" = "$src_nodes" ] && [ "$imp_edges" = "$src_edges" ]; then
      ok "corpus + knowledge graph import: $imp_n findings, $imp_nodes nodes, $imp_edges edges (counts match source)"
    else
      bad "import counts diverge (findings $imp_n/$src_n, nodes $imp_nodes/$src_nodes, edges $imp_edges/$src_edges)"
    fi
    # The exact edge SET survives the import (not just the count) — each
    # source->target->type triple is preserved (edges intact, SPEC §10).
    local norm='[.edges[]|{source,target,type}]|sort'
    if [ "$(jq -c "$norm" "$SRC/knowledge-graph.json")" = "$(jq -c "$norm" "$T/reports/imported-sample/knowledge-graph.json" 2>/dev/null)" ]; then
      ok "every source graph edge (source/target/type) survived the import"
    else
      bad "imported graph edge set diverges from the source corpus graph"
    fi
    if [ "$prov_ok" = "$src_n" ]; then
      ok "provenance preserved on every imported finding ($prov_ok/$src_n)"
    else
      bad "provenance lost on import ($prov_ok/$src_n retained)"
    fi
    # The imported graph still derives from MIF ids (edges intact).
    if scripts/assert-graph-mif.sh "$T/reports/imported-sample/knowledge-graph.json" >/dev/null 2>&1; then
      ok "imported knowledge graph is MIF-derived with edges intact"
    else
      bad "imported knowledge graph fails the MIF-derivation assertion"
    fi
    # The topic was registered in the (temp) manifest, not the template's.
    if [ "$(jq -r '[.topics[]|select(.id=="imported-sample")]|length' "$T/config.json")" = "1" ]; then
      ok "imported topic registered in the instantiated harness manifest"
    else
      bad "imported topic not registered in the manifest"
    fi
  else
    bad "corpus import failed"
    scripts/import-corpus.sh "$SRC" imported-sample "$T/reports" "$T/config.json" 2>&1 | sed 's/^/      /' >&2
  fi
  rm -rf "$T"

  # 8c/8d are template-only self-tests: an instantiated harness legitimately holds
  # an imported corpus in reports/ and may import in place, so these run only in
  # the template.
  if [ "$IS_TEMPLATE" = 1 ]; then
    # 8c. The template repo itself ships clean — no imported corpus committed under
    #     reports/ (only reports/_meta/ scaffolding and the sample session).
    if [ -z "$(find reports -path 'reports/_meta' -prune -o -name '*.json' -print 2>/dev/null)" ]; then
      ok "template repo reports/ ships clean (no corpus committed outside _meta)"
    else
      bad "unexpected corpus committed under reports/ (the template must stay clean)"
      find reports -path 'reports/_meta' -prune -o -name '*.json' -print 2>/dev/null | sed 's/^/      /' >&2
    fi

    # 8d. The import REFUSES to populate the template repo's own reports/ — the
    #     constraint is enforced by the script, not merely intended.
    if scripts/import-corpus.sh "$SRC" should-not-land reports >/dev/null 2>&1; then
      bad "import-corpus.sh did NOT refuse to import into the template's reports/"
      rm -rf reports/should-not-land
    else
      ok "import refuses to populate the template repo's own reports/"
    fi
  else
    info "Milestone 8 — 8c/8d template-clean checks skipped (instance holds a corpus)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 9 — Sigint -> MIF corpus conversion
# ---------------------------------------------------------------------------
gate_m9() {
  info "Milestone 9 — Sigint->MIF corpus conversion"
  local SRC="evals/fixtures/sample-sigint-corpus"
  local TOPIC="sigint-sample"
  local ST T cfg cfg_on
  ST=$(mktemp -d); T=$(mktemp -d)

  # The conversion path is opt-in (features.sigintCorpusImport). Run the gate with
  # a flag-on config, and pass the SAME topic id used for import below so each
  # unit's @id/namespace match the registered topic.
  cfg_on=$(mktemp)
  jq '.features = ((.features // {}) + {"sigintCorpusImport": true, "internalCitations": true})' \
    harness.config.json > "$cfg_on"

  # 9a. The converter turns a legacy sigint corpus (aggregated findings_<dim>.json
  #     wrappers) into individual MIF units — every unit validates and the count
  #     matches the source findings (lossless conversion).
  HARNESS_CONFIG="$cfg_on" scripts/convert-sigint-corpus.sh "$SRC" "$ST" "$TOPIC" >/dev/null 2>&1
  local src_n staged_n valid_n=0
  src_n=$(jq 'if type=="array" then length else ((.findings//[])|length) end' "$SRC"/findings_*.json | awk '{s+=$1} END{print s+0}')
  staged_n=$(find "$ST/findings" -name '*.json' 2>/dev/null | grep -c .)
  for u in "$ST/findings"/*.json; do
    ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/findings.schema.json \
      -r schemas/mif/mif.schema.json \
      -r schemas/mif/definitions/entity-reference.schema.json \
      -d "$u" >/dev/null 2>&1 && valid_n=$((valid_n+1))
  done
  if [ "$staged_n" -gt 0 ] && [ "$staged_n" = "$src_n" ] && [ "$valid_n" = "$staged_n" ]; then
    ok "sigint->MIF conversion is lossless ($staged_n/$src_n findings, all MIF-valid)"
  else
    bad "sigint->MIF conversion incomplete (src=$src_n staged=$staged_n valid=$valid_n)"
  fi

  # 9b. The converted corpus imports into a FRESH harness with provenance and a
  #     MIF-derived graph intact (entities + a typed relationship carried from
  #     updates_finding) — the same acceptance as gate_m8, over converted input.
  cp harness.config.json "$T/config.json"
  if scripts/import-corpus.sh "$ST" "$TOPIC" "$T/reports" "$T/config.json" >/dev/null 2>&1; then
    local imp_n prov_n ns_ok
    imp_n=$(find "$T/reports/$TOPIC/findings" -name '*.json' 2>/dev/null | grep -c .)
    prov_n=$(find "$T/reports/$TOPIC/findings" -name '*.json' -exec jq -e '.provenance.sourceType=="external_import"' {} \; 2>/dev/null | grep -c true)
    # The unit namespace must match the import topic id (no basename/topic drift).
    ns_ok=$(find "$T/reports/$TOPIC/findings" -name '*.json' -exec jq -e --arg t "$TOPIC" '.namespace == ("harness/" + $t)' {} \; 2>/dev/null | grep -c true)
    if [ "$imp_n" = "$staged_n" ] && [ "$prov_n" = "$imp_n" ] && [ "$ns_ok" = "$imp_n" ] \
       && scripts/assert-graph-mif.sh "$T/reports/$TOPIC/knowledge-graph.json" >/dev/null 2>&1; then
      ok "converted sigint corpus imports with provenance + MIF-derived graph ($imp_n findings)"
    else
      bad "converted sigint import failed (imported=$imp_n prov=$prov_n)"
    fi
  else
    bad "converted sigint corpus failed to import"
  fi

  # 9c. Internal/document citations are CONFIG-GATED (features.internalCitations):
  #     refused under the strict default, accepted only when the flag is enabled.
  local intf off_refused=0 on_accepted=0
  intf=$(grep -l 'internal:document' "$ST/findings"/*.json 2>/dev/null | head -1)
  if [ -n "$intf" ]; then
    cfg=$(mktemp)
    printf '{"features":{"internalCitations":false}}' > "$cfg"
    HARNESS_CONFIG="$cfg" scripts/check-citation-integrity.sh "$intf" >/dev/null 2>&1 || off_refused=1
    printf '{"features":{"internalCitations":true}}' > "$cfg"
    HARNESS_CONFIG="$cfg" scripts/check-citation-integrity.sh "$intf" >/dev/null 2>&1 && on_accepted=1
    if [ "$off_refused" = 1 ] && [ "$on_accepted" = 1 ]; then
      ok "internal-citation feature is config-gated (refused strict, accepted when enabled)"
    else
      bad "internal-citation feature flag not enforced (strict_refused=$off_refused enabled_accepted=$on_accepted)"
    fi
    rm -f "$cfg"
  else
    bad "sigint fixture produced no internal:document citation to gate-test"
  fi

  # 9d. The conversion path itself is CONFIG-GATED (features.sigintCorpusImport):
  #     refused when the flag is disabled.
  local conv_off=0 cfg_off ST2
  cfg_off=$(mktemp); ST2=$(mktemp -d)
  printf '{"features":{"sigintCorpusImport":false}}' > "$cfg_off"
  HARNESS_CONFIG="$cfg_off" scripts/convert-sigint-corpus.sh "$SRC" "$ST2" "$TOPIC" >/dev/null 2>&1 || conv_off=1
  if [ "$conv_off" = 1 ]; then
    ok "sigint conversion is config-gated (refused when sigintCorpusImport disabled)"
  else
    bad "sigint conversion ran with sigintCorpusImport disabled (flag not enforced)"
  fi
  rm -f "$cfg_off"; rm -rf "$ST2"

  rm -f "$cfg_on"
  rm -rf "$ST" "$T"
}

# ---------------------------------------------------------------------------
# Milestone 10 — MIF I/O conformance (SPEC §10)
# Every basic markdown report the harness emits is MIF Level 3 (same bar as a
# finding); every ingested source is a validated MIF source-envelope; and the
# only exceptions are channels explicitly declared exempt (logged, never silent).
# ---------------------------------------------------------------------------
gate_m10() {
  info "Milestone 10 — MIF I/O conformance"

  # 10a. The report sample is valid MIF L3 markdown (frontmatter+body projects to
  #      a finding that validates against findings.schema.json + citation-integrity).
  if scripts/mif-project.sh schemas/samples/report.sample.md >/dev/null 2>&1; then
    ok "report sample is valid MIF L3 markdown (projects to a finding)"
  else
    bad "report sample does not project to a valid MIF L3 finding"
  fi

  # 10b. The source-envelope sample validates at MIF L3 (inbound contract).
  if ajv_mif schemas/mif/source-envelope.schema.json schemas/samples/source-envelope.sample.json; then
    ok "source-envelope sample validates at MIF L3"
  else
    bad "source-envelope sample does not validate at MIF L3"
  fi

  # 10c. Every emitted generic report (reports/<topic>/<slug>.md, excluding the
  #      _meta scaffolding) projects to a valid L3 finding. Vacuously true in the
  #      clean template; binds the moment an instance emits a report.
  #      NOTE: this scans the `report` channel's known path — the only non-exempt
  #      channel today. A future non-exempt channel emitting elsewhere would need
  #      its path added here (cross-checked against outputs[] without mifExempt).
  local md bad_r=""
  while IFS= read -r md; do
    [ -z "$md" ] && continue
    scripts/mif-project.sh "$md" >/dev/null 2>&1 || bad_r="${bad_r}$md "
  done < <(find reports -mindepth 2 -maxdepth 2 -name '*.md' -not -path 'reports/_meta/*' 2>/dev/null)
  if [ -z "$bad_r" ]; then
    ok "every emitted generic report projects to a valid MIF L3 finding"
  else
    bad "non-conformant report(s): $bad_r"
  fi

  # 10d. Every ingested source-envelope (reports/<topic>/sources/*.json) validates.
  local sj bad_s=""
  while IFS= read -r sj; do
    [ -z "$sj" ] && continue
    ajv_mif schemas/mif/source-envelope.schema.json "$sj" || bad_s="${bad_s}$sj "
  done < <(find reports -path '*/sources/*.json' 2>/dev/null)
  if [ -z "$bad_s" ]; then
    ok "every ingested source-envelope validates at MIF L3"
  else
    bad "non-conformant source-envelope(s): $bad_s"
  fi

  # 10e. Exemptions are declared AND logged (no silent caps): first-class channels
  #      via harness.config outputs[].mifExempt, channel packs via plugin.json mif.exempt.
  local cexempt pexempt=""
  cexempt=$(jq -r '[.outputs[]? | select(.mifExempt==true) | .channel] | join(", ")' harness.config.json 2>/dev/null)
  local mf
  while IFS= read -r mf; do
    [ -z "$mf" ] && continue
    jq -e '.mif.exempt==true' "$mf" >/dev/null 2>&1 && pexempt="${pexempt}$(jq -r '.name' "$mf") "
  done < <(find packs -path '*/.claude-plugin/plugin.json' 2>/dev/null | sort)
  ok "MIF-exempt channels (skipped + logged) — outputs: [${cexempt:-none}]; packs: [${pexempt:-none}]"
}

# ---------------------------------------------------------------------------
# Milestone 11 — Session-recovery durability (SPEC §6b)
# Crash-safe, resumable sessions: a disk-derived state.json checkpoint; an
# idempotent reconcile that computes remaining work from disk only (never reworking
# completed findings); and atomic-to-valid finding writes. Purely additive.
# ---------------------------------------------------------------------------
gate_m11() {
  info "Milestone 11 — Session durability"

  # 11a. The session-state schema validates its sample.
  if ajv_plain schemas/session-state.schema.json schemas/samples/session-state.sample.json; then
    ok "session-state schema validates its sample"
  else
    bad "session-state schema does not validate its sample"
  fi

  # Fixture session: A,B gated+valid (DONE); C raw finding (ajv-invalid = remaining);
  # D a *.tmp partial write. A finding is ajv-valid only once the gate stamps
  # verification, so valid+gated move together.
  local T RD
  T="$(mktemp -d)"; RD="$T/durability-topic"; mkdir -p "$RD/findings"
  jq '."@id"="urn:mif:concept:harness/durability-topic:a" | .extensions.harness.dimension="technical"' \
    schemas/samples/finding.sample.json > "$RD/findings/finding-a.json"
  jq '."@id"="urn:mif:concept:harness/durability-topic:b" | .extensions.harness.dimension="landscape"' \
    schemas/samples/finding.sample.json > "$RD/findings/finding-b.json"
  jq '."@id"="urn:mif:concept:harness/durability-topic:c" | .extensions.harness.dimension="technical"' \
    evals/fixtures/raw-finding.json > "$RD/findings/finding-c.json"
  printf '{partial' > "$RD/findings/finding-d.json.tmp"

  scripts/reconcile-session.sh "$RD" > "$T/plan1.txt" 2>/dev/null

  # 11b (condition 1). The checkpoint exists and validates against the schema.
  if [ -f "$RD/state.json" ] && ajv_plain schemas/session-state.schema.json "$RD/state.json"; then
    ok "reconcile writes a state.json checkpoint that validates against session-state.schema.json"
  else
    bad "reconcile did not write a valid state.json checkpoint"
  fi

  # 11c (condition 3). Valid findings (A,B) recorded DONE; per-finding records carry
  # {id,dimension,valid,attempted_at,verdict}. A finding is done iff schema-valid —
  # validity requires verification.verdict, so a valid finding has been gated.
  local doneA doneB shape
  doneA=$(jq -r '[.findings[] | select(.id|endswith(":a")) | select(.valid)] | length' "$RD/state.json")
  doneB=$(jq -r '[.findings[] | select(.id|endswith(":b")) | select(.valid)] | length' "$RD/state.json")
  shape=$(jq -r '[.findings[] | has("id") and has("dimension") and has("valid") and has("attempted_at") and has("verdict")] | all' "$RD/state.json")
  if [ "$doneA" = 1 ] && [ "$doneB" = 1 ] && [ "$shape" = true ]; then
    ok "gated + valid findings recorded done (per-finding id/dimension/valid/attempted_at/verdict)"
  else
    bad "gated/valid findings not recorded done correctly (A=$doneA B=$doneB shape=$shape)"
  fi

  # 11d (condition 4). Invalid finding (C) and *.tmp partial (D) EXCLUDED from
  # done-counts: technical total=2 (A,C), done=1 (A); D never counted.
  local tot don
  tot=$(jq -r '.dimensions.technical.total' "$RD/state.json")
  don=$(jq -r '.dimensions.technical.done' "$RD/state.json")
  if [ "$tot" = 2 ] && [ "$don" = 1 ]; then
    ok "partial/invalid findings excluded from done-counts (technical total=2 done=1; *.tmp uncounted)"
  else
    bad "done-counts wrong (technical total=$tot done=$don; expected 2/1)"
  fi

  # 11e (condition 2). Reconcile is idempotent — a second run prints a byte-identical plan.
  scripts/reconcile-session.sh "$RD" > "$T/plan2.txt" 2>/dev/null
  if diff -q "$T/plan1.txt" "$T/plan2.txt" >/dev/null 2>&1; then
    ok "reconcile is idempotent (two runs print byte-identical plans)"
  else
    bad "reconcile is not idempotent (plans differ)"
  fi

  # 11f (condition 5). Writes are atomic-to-valid: a valid finding lands; an invalid
  # one never appears in findings/.
  local good=0 badw=0
  scripts/write-finding.sh "$RD/findings/finding-a.json" "$T/wf" "finding-ok.json" >/dev/null 2>&1 && [ -f "$T/wf/finding-ok.json" ] && good=1
  scripts/write-finding.sh evals/fixtures/raw-finding.json "$T/wf" "finding-bad.json" >/dev/null 2>&1; [ -e "$T/wf/finding-bad.json" ] || badw=1
  if [ "$good" = 1 ] && [ "$badw" = 1 ]; then
    ok "writes are atomic-to-valid (valid finding lands; invalid finding never written)"
  else
    bad "atomic-write contract broken (valid-landed=$good invalid-absent=$badw)"
  fi

  # 11g (condition 6). A fully-gated session reconciles to an empty plan.
  local RD2 plan
  RD2="$T/done-topic"; mkdir -p "$RD2/findings"
  jq '."@id"="urn:mif:concept:harness/done-topic:a" | .extensions.harness.dimension="technical"' \
    schemas/samples/finding.sample.json > "$RD2/findings/finding-a.json"
  plan=$(scripts/reconcile-session.sh "$RD2" 2>/dev/null)
  if [ "$plan" = "nothing to do" ]; then
    ok "a fully-gated session reconciles to an empty plan (nothing to do)"
  else
    bad "fully-gated session did not reconcile to an empty plan (got: $plan)"
  fi

  # 11h (reality guard). Reconcile the REAL shipped sample session (copied so the
  # repo is not mutated): its completed findings must reconcile to 'nothing to do',
  # NOT be reported as rework. This pins the cost-critical property against actual
  # session data — a completed finding is never re-run on resume.
  local SS sp
  SS="$T/sample-copy"; mkdir -p "$SS/findings"
  cp reports/_meta/sample-session/findings/*.json "$SS/findings/" 2>/dev/null
  sp=$(scripts/reconcile-session.sh "$SS" 2>/dev/null)
  if [ "$sp" = "nothing to do" ]; then
    ok "the shipped sample session reconciles to 'nothing to do' (completed findings never re-run)"
  else
    bad "sample session reported rework — resume would re-run completed findings: ${sp//$'\n'/ | }"
  fi

  # 11i (safety). A falsified finding (valid, verdict=falsified) is NOT done — its
  # dimension still needs a replacement.
  local RD3 ftot fdone
  RD3="$T/falsified-topic"; mkdir -p "$RD3/findings"
  jq '."@id"="urn:mif:concept:harness/falsified-topic:f" | .extensions.harness.dimension="technical" | .extensions.harness.verification.verdict="falsified"' \
    schemas/samples/finding.sample.json > "$RD3/findings/finding-f.json"
  scripts/reconcile-session.sh "$RD3" >/dev/null 2>&1
  ftot=$(jq -r '.dimensions.technical.total' "$RD3/state.json"); fdone=$(jq -r '.dimensions.technical.done' "$RD3/state.json")
  if [ "$ftot" = 1 ] && [ "$fdone" = 0 ]; then
    ok "a falsified finding is excluded from done-counts (its dimension still needs a replacement)"
  else
    bad "falsified finding mis-counted (technical total=$ftot done=$fdone; expected 1/0)"
  fi

  # 11j (fail-safe — THE cost guard). A broken ajv toolchain must make reconcile
  # ABORT (non-zero), not read every finding as invalid and emit a re-run-everything
  # plan. Shim a failing `ajv` onto PATH (jq/find still work) and assert reconcile
  # exits non-zero and prints no "need work" plan.
  local bad_out bad_rc
  mkdir -p "$T/badbin"; printf '#!/bin/sh\nexit 1\n' > "$T/badbin/ajv"; chmod +x "$T/badbin/ajv"
  bad_out=$(PATH="$T/badbin:$PATH" scripts/reconcile-session.sh "$RD2" 2>/dev/null); bad_rc=$?
  if [ "$bad_rc" -ne 0 ] && ! printf '%s' "$bad_out" | grep -q 'need work'; then
    ok "reconcile fails safe on a broken ajv toolchain (aborts; never emits a re-run-everything plan)"
  else
    bad "reconcile did NOT fail safe (rc=$bad_rc; out: ${bad_out//$'\n'/ | })"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 12 — MIF Ontology conformance (SPEC §8c)
# Ontology is a deterministic, per-topic member: a vendored definition contract,
# a yaml registry (core + example data packs) projected on the fly, a catalog of
# enabled ontologies, per-topic binding, and a topical resolver that classifies a
# finding's entity_type to exactly one bound ontology and validates its entity.
# Purely additive.
# ---------------------------------------------------------------------------
# Project a vendored ontology YAML to JSON and validate against the contract.
ajv_onto() { # ajv_onto <ontology.yaml>
  local j; j="$(mktemp /tmp/onto-XXXXXX.json)"
  yq -o=json '.' "$1" 2>/dev/null | jq '.' > "$j" 2>/dev/null \
    && ajv_plain schemas/mif/ontology.schema.json "$j"; local rc=$?
  rm -f "$j"; return $rc
}
# Every vendored ontology: core (schemas/ontologies/) + example packs (packs/ontologies/).
onto_registry_yaml() {
  # mindepth 2 mirrors sync-packs' globs (schemas/ontologies/<id>/<ver>.yaml,
  # packs/ontologies/<id>/<id>.ontology.yaml) — a stray top-level yaml is not a
  # registry ontology and must not be validated as one (kept symmetric with the catalog).
  { find schemas/ontologies -mindepth 2 -maxdepth 2 -type f -name '*.yaml'
    find packs/ontologies -mindepth 2 -maxdepth 2 -type f -name '*.ontology.yaml'; } 2>/dev/null | sort
}

gate_m12() {
  info "Milestone 12 — MIF Ontology conformance"

  # 12a. The vendored ontology contract validates its sample.
  if ajv_plain schemas/mif/ontology.schema.json schemas/samples/ontology-definition.sample.json; then
    ok "vendored ontology.schema.json validates its sample"
  else
    bad "vendored ontology.schema.json does not validate its sample"
  fi

  # 12b. EVERY vendored ontology (core + example packs) validates against the contract.
  local oy obad="" ocount=0
  while IFS= read -r oy; do
    [ -z "$oy" ] && continue
    ocount=$((ocount+1))
    ajv_onto "$oy" || obad="${obad}$(basename "$oy") "
  done < <(onto_registry_yaml)
  if [ -z "$obad" ] && [ "$ocount" -ge 1 ]; then
    ok "every vendored ontology validates against the contract ($ocount: core + example packs)"
  else
    bad "ontologies failing the contract: ${obad:-none found}"
  fi

  # 12c. id+version uniqueness across the registry.
  local dupes
  dupes=$(while IFS= read -r oy; do [ -z "$oy" ] && continue
            printf '%s@%s\n' "$(yq -r '.ontology.id' "$oy")" "$(yq -r '.ontology.version' "$oy")"
          done < <(onto_registry_yaml) | sort | uniq -d)
  if [ -z "$dupes" ]; then
    ok "ontology id@version is unique across the registry"
  else
    bad "duplicate ontology id@version: $(echo $dupes)"
  fi

  # 12d. The supply-chain floor is CONTRACT-only and EXACT: the verbatim set must be
  #      precisely the vendored ontology schema + context (both, and nothing else), and
  #      every verbatim checksum must match. Asserting the exact set catches unlocking a
  #      contract file (weakening the floor) AND re-locking any other file (e.g. an
  #      ontology definition, which would block editing).
  local lbad="" ln=0
  while IFS=$'\t' read -r lp lsum; do
    [ -z "$lp" ] && continue; ln=$((ln+1))
    [ "$(shasum -a 256 "$lp" 2>/dev/null | cut -d' ' -f1)" = "$lsum" ] || lbad="${lbad}${lp} "
  done < <(jq -r '.files[] | select(.verbatim) | "\(.path)\t\(.sha256)"' schemas/mif/VENDOR.lock 2>/dev/null)
  local verbatim_set expected_set
  verbatim_set=$(jq -r '[.files[] | select(.verbatim) | .path] | sort | join(",")' schemas/mif/VENDOR.lock 2>/dev/null)
  expected_set="schemas/mif/ontology.context.jsonld,schemas/mif/ontology.schema.json"   # sorted
  if [ -z "$lbad" ] && [ "$verbatim_set" = "$expected_set" ]; then
    ok "VENDOR.lock: exactly the 2 contract files are checksum-locked; ontology definitions unlocked (editable)"
  else
    bad "VENDOR.lock floor wrong: verbatim-set=[$verbatim_set] expected=[$expected_set] checksum-mismatch=[${lbad:-none}]"
  fi

  # Build a real catalog (core + k12 enabled) to drive the resolver fixtures.
  local T; T="$(mktemp -d)"
  jq '(.ontologies[] | select(.id=="k12-educational-publishing") | .enabled) |= true' harness.config.json > "$T/cfg.json"
  scripts/sync-packs.sh "$T/cfg.json" "$T/cat.json" "$T/settings.json" >/dev/null 2>&1
  # config: topic 'edu' binds k12; 'bare' binds nothing
  jq '.topics = [{"id":"edu","namespace":"x/edu","ontologies":["k12-educational-publishing"]},{"id":"bare","namespace":"x/bare"}]' "$T/cfg.json" > "$T/rcfg.json"
  local RO="scripts/resolve-ontology.sh"
  local G='{"name":"Algebra I","entity_type":"title","isbn":"9780000000002","subject":"mathematics","grade_range":{"min":9,"max":12}}'
  printf '{"@id":"f-good","entity":%s}\n' "$G" > "$T/good.json"
  printf '{"@id":"f-extra","entity":%s}\n' "$(echo "$G" | jq '.+{vibe:"x"}')" > "$T/extra.json"
  printf '{"@id":"f-untyped","content":"x"}\n' > "$T/untyped.json"
  printf '{"@id":"f-missing","entity":{"name":"A","entity_type":"title","subject":"mathematics"}}\n' > "$T/missing.json"
  printf '{"@id":"f-undecl","entity":{"name":"x","entity_type":"not-a-type"}}\n' > "$T/undecl.json"
  ro() { $RO "$T/$1.json" --topic "$2" --catalog "$T/cat.json" --config "$T/rcfg.json" --map "$T/$1.$2.map" >/dev/null 2>&1; }

  # 12e. The resolver's pass/fail matrix + recorded mapping.
  ro untyped edu; local ru=$?
  ro good edu;    local rg=$?
  ro extra edu;   local re=$?
  ro missing edu; local rm=$?
  ro undecl edu;  local rd=$?
  ro good bare;   local rb=$?
  local gro; gro=$(jq -r '.[0] | "\(.resolved_ontology)|\(.basis)|\(.valid)"' "$T/good.edu.map" 2>/dev/null)
  if [ "$ru" = 0 ] && [ "$rg" = 0 ] && [ "$re" = 0 ] && [ "$rm" != 0 ] && [ "$rd" != 0 ] && [ "$rb" != 0 ] \
     && [ "$gro" = "k12-educational-publishing@0.1.0|resolved|true" ]; then
    ok "resolver: typed finding resolves+validates; missing/undeclared/unbound fail; map records the mapping"
  else
    bad "resolver matrix wrong (untyped=$ru good=$rg extra=$re missing=$rm undecl=$rd unbound=$rb rec=$gro)"
  fi

  # 12f. Fail-safe: a missing catalog makes the resolver ABORT (never resolve vacuously).
  local fs; $RO "$T/good.json" --topic edu --catalog "$T/nope.json" --config "$T/rcfg.json" >/dev/null 2>&1; fs=$?
  if [ "$fs" != 0 ]; then
    ok "resolver fails safe on a missing catalog (aborts; never resolves vacuously)"
  else
    bad "resolver did not fail safe on a missing catalog (exit $fs)"
  fi

  # 12g. Binding integrity: a topic binding a DISABLED (uncataloged) ontology fails.
  jq '.topics = [{"id":"x","namespace":"x/x","ontologies":["software-engineering"]}]' "$T/rcfg.json" > "$T/bad.json"
  local bind; $RO "$T/good.json" --topic x --catalog "$T/cat.json" --config "$T/bad.json" >/dev/null 2>&1; bind=$?
  if [ "$bind" != 0 ]; then
    ok "a topic binding a disabled/uncataloged ontology fails (binding -> catalog integrity)"
  else
    bad "binding to a disabled ontology did not fail (exit $bind)"
  fi

  # 12h. Pack-enable path end-to-end: the enabled k12 pack is cataloged from its
  #      data pack and a bound topic's finding resolves against it.
  if jq -e '.ontologies[] | select(.id=="k12-educational-publishing" and .core==false)' "$T/cat.json" >/dev/null 2>&1 && [ "$rg" = 0 ]; then
    ok "an enabled ontology data pack is cataloged and a bound topic's finding resolves against it"
  else
    bad "pack-enable path broken (k12 not cataloged or bound finding did not resolve)"
  fi

  # 12i. Always-on generic typing + ambiguity. The generic core (mif-generic) types
  #      ANY topic, including core-only; a type a generic and a bound domain ontology
  #      both declare (technology) is ambiguous without an explicit ontology.id.
  jq '(.ontologies[] | select(.id=="software-engineering") | .enabled) |= true' harness.config.json > "$T/se.cfg"
  scripts/sync-packs.sh "$T/se.cfg" "$T/se.cat" "$T/se.set" >/dev/null 2>&1
  jq '.topics = [{"id":"core","namespace":"x/c"},{"id":"eng","namespace":"x/e","ontologies":["software-engineering"]}]' "$T/se.cfg" > "$T/se.rcfg"
  printf '{"@id":"g","entity":{"name":"REST","entity_type":"concept"}}\n' > "$T/gen.json"
  printf '{"@id":"a","entity":{"name":"Kafka","entity_type":"technology","category":"infrastructure"}}\n' > "$T/amb.json"
  printf '{"@id":"d","ontology":{"id":"software-engineering"},"entity":{"name":"Kafka","entity_type":"technology","category":"infrastructure"}}\n' > "$T/dis.json"
  $RO "$T/gen.json" --topic core --catalog "$T/se.cat" --config "$T/se.rcfg" --map "$T/g.map" >/dev/null 2>&1; local gen=$?
  $RO "$T/amb.json" --topic eng  --catalog "$T/se.cat" --config "$T/se.rcfg" --map "$T/a.map" >/dev/null 2>&1; local amb=$?
  $RO "$T/dis.json" --topic eng  --catalog "$T/se.cat" --config "$T/se.rcfg" --map "$T/d.map" >/dev/null 2>&1; local dis=$?
  local genro; genro=$(jq -r '.[0].resolved_ontology' "$T/g.map" 2>/dev/null)
  if [ "$gen" = 0 ] && [ "$genro" = "mif-generic@1.0.0" ] && [ "$amb" != 0 ] && [ "$dis" = 0 ]; then
    ok "generic core types every topic; a generic/domain type collision is ambiguous without ontology.id"
  else
    bad "generic/ambiguity wrong (core-only generic=$gen ro=$genro ambiguous=$amb disambiguated=$dis)"
  fi

  # 12j. ontology-review.sh reviews/validates coverage across a topic's findings:
  #      correct typed/untyped/invalid counts; --strict fails when invalid mappings exist.
  mkdir -p "$T/reports/edu/findings"
  printf '{"@id":"f-good","entity":%s}\n' "$G" > "$T/reports/edu/findings/good.json"
  printf '{"@id":"f-untyped","content":"x"}\n' > "$T/reports/edu/findings/untyped.json"
  printf '{"@id":"f-missing","entity":{"name":"A","entity_type":"title","subject":"mathematics"}}\n' > "$T/reports/edu/findings/missing.json"
  local rv; rv=$(scripts/ontology-review.sh --topic edu --reports-dir "$T/reports" --config "$T/rcfg.json" --catalog "$T/cat.json" 2>/dev/null | tail -1)
  scripts/ontology-review.sh --topic edu --strict --reports-dir "$T/reports" --config "$T/rcfg.json" --catalog "$T/cat.json" >/dev/null 2>&1; local rvs=$?
  if printf '%s' "$rv" | grep -q "1 typed, 1 untyped, 1 invalid" && [ "$rvs" != 0 ]; then
    ok "ontology-review reports correct typed/untyped/invalid coverage; --strict fails on invalid mappings"
  else
    bad "ontology-review wrong (summary='$rv' strict-exit=$rvs)"
  fi

  # 12k. Authoring: the ontology-manager skill scaffolds a NEW ontology that validates
  #      against the contract and is DISCOVERED by the registry enumeration — proving
  #      ontologies can be created/expanded. Discovery REUSES onto_registry_yaml (run in
  #      a fresh tree holding only the scaffolded file), so it self-maintains if the
  #      registry glob changes; a scaffold to a wrong path/extension yields 0 found.
  local base found RT
  base=$(onto_registry_yaml | grep -c . || true)
  RT="$(mktemp -d)"; mkdir -p "$RT/packs/ontologies/demo-new"
  if .claude/skills/ontology-manager/scripts/scaffold_ontology.sh demo-new 0.1.0 --extends mif-base \
       > "$RT/packs/ontologies/demo-new/demo-new.ontology.yaml" 2>/dev/null \
     && ajv_onto "$RT/packs/ontologies/demo-new/demo-new.ontology.yaml"; then
    found=$( cd "$RT" && onto_registry_yaml | grep -c . || true )
    if [ "$found" -eq 1 ]; then
      ok "ontology-manager scaffolds a NEW valid ontology that onto_registry_yaml discovers (base registry has $base)"
    else
      bad "scaffolded ontology not discovered by onto_registry_yaml in a fresh tree (found=$found)"
    fi
  else
    bad "scaffold_ontology.sh did not produce a contract-valid ontology"
  fi
  rm -rf "$RT"

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5 gate_m6 gate_m7 gate_m8 gate_m9 gate_m10 gate_m11 gate_m12)

for g in "${GATES[@]}"; do "$g"; done

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
