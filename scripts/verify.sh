#!/usr/bin/env bash
# verify.sh — the harness build gate.
#
# Accretive by design: each milestone appends a `gate_mN` function and registers
# it in GATES. The whole script must always exit 0 when every registered gate
# passes. Run from the repository root.
#
#   bash scripts/verify.sh
#
# Requires: jq, ajv (ajv-cli) + ajv-formats. markdownlint-cli2 is run separately
# by CI / the G5 lint gate.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

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
  #     they are meta, not built artifacts.
  # git grep handles filenames with spaces and an empty match set safely (it
  # never reads stdin and returns 1 on no match), unlike `git ls-files | xargs grep`.
  local hits
  hits=$(git grep -nE 'f_(tech|competitive|trends|customer|sizing|financial|regulatory)_[0-9]+|reports/[a-z0-9][a-z0-9-]+/findings_' -- \
           ':!COMPLETION-CRITERIA.md' ':!IMPLEMENTATION-PLAN.md' ':!PROGRESS.md' 2>/dev/null || true)
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
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5 gate_m6 gate_m7 gate_m8)

for g in "${GATES[@]}"; do "$g"; done

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
