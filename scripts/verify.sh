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

  # 5a. Every bundled pack is a plugin: plugin.json validates against the pack
  #     contract and the pack has a flat skills/ dir.
  local p pbad=""
  for p in market-research trend-modeling reports channels; do
    local mf="packs/$p/.claude-plugin/plugin.json"
    if [ -f "$mf" ] && ajv_plain schemas/pack.schema.json "$mf" \
       && [ -d "packs/$p/skills" ] \
       && [ -n "$(find "packs/$p/skills" -mindepth 2 -name SKILL.md 2>/dev/null)" ]; then :; else
      pbad="${pbad}${p} "
    fi
  done
  if [ -z "$pbad" ]; then
    ok "four bundled packs are valid plugins (manifest + flat skills)"
  else
    bad "invalid/incomplete packs: $pbad"
  fi

  # 5b. Skills are flat within each pack (skills/<name>/SKILL.md, no grouping).
  local nested
  nested=$(find packs/*/skills -mindepth 2 -name SKILL.md 2>/dev/null | grep -vE '^packs/[^/]+/skills/[^/]+/SKILL\.md$' || true)
  if [ -z "$nested" ]; then
    ok "pack skills are flat (packs/<pack>/skills/<name>/SKILL.md)"
  else
    bad "non-flat pack skills: $nested"
  fi

  # 5c. Enabling a pack through the manifest adds its namespaced skills to Claude
  #     Code's native enabledPlugins (settings.json); disabling removes them.
  #     Proven on temp config + temp settings copies (no mutation of the real ones).
  local T; T=$(mktemp -d)
  cp .claude/settings.json "$T/settings-on.json"
  cp .claude/settings.json "$T/settings-off.json"
  jq '(.packs[] | select(.name=="market-research") | .enabled) |= true' harness.config.json > "$T/on.cfg.json"
  jq '(.packs[] | select(.name=="market-research") | .enabled) |= false' harness.config.json > "$T/off.cfg.json"
  scripts/sync-packs.sh "$T/on.cfg.json"  "$T/on.json"  "$T/settings-on.json"  >/dev/null 2>&1
  scripts/sync-packs.sh "$T/off.cfg.json" "$T/off.json" "$T/settings-off.json" >/dev/null 2>&1
  local skills_added plugin_on plugin_off
  # the namespaced skills appear in the resolved set...
  skills_added=$(jq -r '[.packs[]|select(.name=="market-research")|.skills[]] | index("market-research:competitive-analysis") != null' "$T/on.json" 2>/dev/null)
  # ...and the pack is in / out of Claude Code's NATIVE enabledPlugins.
  plugin_on=$(jq -r '.enabledPlugins | has("market-research@research-harness")' "$T/settings-on.json" 2>/dev/null)
  plugin_off=$(jq -r '.enabledPlugins | has("market-research@research-harness") | not' "$T/settings-off.json" 2>/dev/null)
  if [ "$skills_added" = "true" ] && [ "$plugin_on" = "true" ] && [ "$plugin_off" = "true" ]; then
    ok "enabling a pack adds its namespaced skills to native enabledPlugins; disabling removes them"
  else
    bad "pack toggle failed (skills_added=$skills_added plugin_on=$plugin_on plugin_off=$plugin_off)"
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

  # 5e. Bundled packs are registered in the marketplace.
  local m mmiss=""
  for m in market-research trend-modeling reports channels; do
    jq -e --arg n "$m" '.plugins | any(.name == $n)' .claude-plugin/marketplace.json >/dev/null 2>&1 || mmiss="${mmiss}${m} "
  done
  if [ -z "$mmiss" ]; then
    ok "all bundled packs registered in marketplace.json"
  else
    bad "packs missing from marketplace.json: $mmiss"
  fi
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5)

for g in "${GATES[@]}"; do "$g"; done

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
