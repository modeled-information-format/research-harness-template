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

# gate_m20/gate_m22's whole-registry ontology-integrity scans delegate to the
# mif-rh engine (Story #287, research-harness-template#276) rather than a hand-rolled
# yq+jq registry walk. Resolved once here since it's used by exactly those two gates.
# shellcheck source=scripts/lib/engine.sh
. scripts/lib/engine.sh
ENGINE="$(engine_bin "$(pwd)")" || exit 5

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
  #     they are meta, not built artifacts. reports/ is excluded too: it
  #     is the corpus/data, not a built artifact, and in an instance it legitimately
  #     holds finding ids (the template's reports/ cleanliness is covered by 8c).
  # git grep handles filenames with spaces and an empty match set safely (it
  # never reads stdin and returns 1 on no match), unlike `git ls-files | xargs grep`.
  local hits
  hits=$(git grep -nE 'f_(tech|competitive|trends|customer|sizing|financial|regulatory)_[0-9]+|reports/[a-z0-9][a-z0-9-]+/findings_' -- \
           ':!COMPLETION-CRITERIA.md' ':!IMPLEMENTATION-PLAN.md' ':!PROGRESS.md' \
 ':!reports' 2>/dev/null || true)
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

  # 4c. The graph viz renders. Render the probe HTML into a temp dir outside the
  #     tree (the gate only asserts the renderer produces non-empty output) so it
  #     never dirties the working tree or clobbers the committed sample fixture.
  local vdir; vdir="$(mktemp -d)" || vdir=""
  if [ -n "$vdir" ] \
     && scripts/build-graph-viz.sh "$KG" "$vdir/kg.html" >/dev/null 2>&1 \
     && [ -s "$vdir/kg.html" ]; then
    ok "graph visualization renders to HTML"
  else
    bad "graph visualization failed"
  fi
  [ -n "$vdir" ] && rm -rf "$vdir"

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
  #     native enabledPlugins (materialized into settings.local.json; here proven on
  #     a temp settings path); disabling removes it. Proven on a currently-disabled
  #     plugin (competitive-analysis), on temp copies.
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

  # 5d2. A declared marketplaces[] entry lets two+ packs share one external
  #      source (type/url/ref) instead of repeating it per pack; a pack-local
  #      ref overrides the marketplace's ref for that pack only.
  T=$(mktemp -d)
  cp .claude/settings.json "$T/settings-mkt.json"
  jq '.marketplaces = [{"name":"demo-mkt","url":"https://example.com/demo-mkt.git","ref":"main-sha"}]
      | .packs += [
          {"name":"mkt-demo-a","enabled":true,"source":{"type":"marketplace-ref","marketplace":"demo-mkt"}},
          {"name":"mkt-demo-b","enabled":true,"source":{"type":"marketplace-ref","marketplace":"demo-mkt","ref":"pack-b-sha"}}
        ]' harness.config.json > "$T/mkt.cfg.json"
  if ajv_plain harness.config.schema.json "$T/mkt.cfg.json" \
     && scripts/sync-packs.sh "$T/mkt.cfg.json" "$T/mkt.json" "$T/settings-mkt.json" >/dev/null 2>&1 \
     && [ "$(jq -r '.packs[]|select(.name=="mkt-demo-a")|.url' "$T/mkt.json")" = "https://example.com/demo-mkt.git" ] \
     && [ "$(jq -r '.packs[]|select(.name=="mkt-demo-a")|.ref' "$T/mkt.json")" = "main-sha" ] \
     && [ "$(jq -r '.packs[]|select(.name=="mkt-demo-b")|.ref' "$T/mkt.json")" = "pack-b-sha" ] \
     && [ "$(jq -r '.enabledPlugins | has("mkt-demo-a@research-harness") and has("mkt-demo-b@research-harness")' "$T/settings-mkt.json")" = "true" ]; then
    ok "marketplaces[] is shared across packs; a pack-local ref overrides it"
  else
    bad "marketplace-ref resolution failed"
  fi
  rm -rf "$T"

  # 5d3. An unresolvable marketplace-ref name (typo, renamed, removed) surfaces
  #      an explicit error in BOTH sync-packs.sh's sidecar and
  #      check-pack-docs.py's external_packs(), instead of silently producing
  #      url:null/ref:null with no diagnostic or a misleading downstream
  #      "cannot resolve its family" message (regression test for the arbiter
  #      review fix on research-harness-template#240).
  T=$(mktemp -d)
  cp .claude/settings.json "$T/settings-typo.json"
  jq '.marketplaces = [{"name":"demo-mkt","url":"https://example.com/demo-mkt.git","ref":"main-sha"}]
      | .packs += [
          {"name":"typo-demo","enabled":true,"source":{"type":"marketplace-ref","marketplace":"demo-mktz"}}
        ]' harness.config.json > "$T/typo.cfg.json"
  sync_ok=false
  if scripts/sync-packs.sh "$T/typo.cfg.json" "$T/typo.json" "$T/settings-typo.json" >/dev/null 2>&1 \
     && [ "$(jq -r '.packs[]|select(.name=="typo-demo")|.url' "$T/typo.json")" = "null" ] \
     && [ "$(jq -r '.packs[]|select(.name=="typo-demo")|.error' "$T/typo.json")" != "null" ]; then
    sync_ok=true
  fi
  # check-pack-docs.py hardcodes REPO relative to its own file location (no
  # config-path argument), so exercise external_packs() directly against a
  # synthetic REPO via importlib rather than running the whole script.
  check_ok=$(python3 - "$T" <<'PY'
import importlib.util, json, sys
from pathlib import Path
T = Path(sys.argv[1])
(T / "harness.config.json").write_text(json.dumps({
    "marketplaces": [{"name": "demo-mkt", "url": "https://example.com/demo-mkt.git"}],
    "packs": [{"name": "typo-demo", "enabled": True,
               "source": {"type": "marketplace-ref", "marketplace": "demo-mktz"}}],
}))
spec = importlib.util.spec_from_file_location("check_pack_docs", "scripts/check-pack-docs.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.REPO = T
ids, errors = m.external_packs()
ok = "typo-demo" not in ids and any("demo-mktz" in e and "typo-demo" in e for e in errors)
print("true" if ok else "false")
PY
)
  if [ "$sync_ok" = "true" ] && [ "$check_ok" = "true" ]; then
    ok "an unresolvable marketplace-ref name surfaces an explicit error, not a silent null"
  else
    bad "unresolved marketplace-ref regression (sync_ok=$sync_ok check_ok=$check_ok)"
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

  # 5f. settings.json is template-managed and byte-identical template-and-instance:
  #     the materialized, per-instance `enabledPlugins` map must NOT live there — it
  #     belongs in the gitignored, instance-local settings.local.json (sync-packs'
  #     default target; the runtime deep-merges the two). Guards against pack
  #     materialization leaking back into the shared settings.json.
  # Match the assignment by default VALUE, tolerant of quoting/whitespace, rather
  # than an exact line (harmless reformatting must not fail the gate).
  if [ "$(jq -r 'has("enabledPlugins")' .claude/settings.json)" = "false" ] \
     && grep -Eq 'SETTINGS=[^[:space:]]*\.claude/settings\.local\.json' scripts/sync-packs.sh; then
    ok "settings.json carries no enabledPlugins; sync-packs materializes it into settings.local.json"
  else
    bad "enabledPlugins must live in settings.local.json (instance-local), not the template-managed settings.json"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 6 — Outputs
# ---------------------------------------------------------------------------
gate_m6() {
  info "Milestone 6 — Outputs"
  local SF="reports/_meta/sample-session/findings"
  local T; T=$(mktemp -d)

  # 6a. blog is the first-class always-on channel skill (flat, in the core). book is now an
  #     OPTIONAL channel pack (packs/channels/book) — not a flat core skill.
  local s smiss=""
  # shellcheck disable=SC2043  # intentionally a one-item list today; kept as a loop so more first-class skills can be appended.
  for s in publish-blog; do
    if [ -f ".claude/skills/$s/SKILL.md" ] && grep -q '^description:' ".claude/skills/$s/SKILL.md"; then :; else
      smiss="${smiss}${s} "
    fi
  done
  # book-author must NOT remain a flat core skill, and must live in the book channel pack.
  [ -f ".claude/skills/book-author/SKILL.md" ] && smiss="${smiss}book-author-still-flat "
  if [ -f "packs/channels/book/skills/book-author/SKILL.md" ] && jq -e '.kind=="channel"' packs/channels/book/.claude-plugin/plugin.json >/dev/null 2>&1; then :; else
    smiss="${smiss}book-pack-missing "
  fi
  if [ -z "$smiss" ]; then
    ok "blog is the first-class flat skill; book is an optional channel pack"
  else
    bad "channel skill layout wrong: $smiss"
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

  # 6c. Both published outputs are citation-leak clean in the BODY. The doc's own
  #     urn:mif:blog:/urn:mif:book: frontmatter @id is its legitimate MIF L1 identity
  #     (not a leak); the body must carry no finding/concept/report identity, corpus
  #     paths, or harness extension tokens.
  local leak="" pf bclose
  for pf in "$T/post.md" "$T/chapter.md"; do
    bclose=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$pf")
    leak="${leak}$(sed -n "$((bclose+1)),\$p" "$pf" | grep -nE 'f_[a-z]+_[0-9]+|urn:mif:(concept|report):|extensions\.harness|reports/[a-z0-9-]+/(findings|_meta)' || true)"
  done
  if [ -z "$leak" ]; then
    ok "both published output bodies are citation-leak clean (no finding/concept/report identity)"
  else
    bad "published output body leaks internal references:"; printf '%s\n' "$leak" >&2
  fi

  # 6d. Every report output is at LEAST MIF Level 1: blog and book frontmatter project
  #     to a valid base MIF concept (schemas/mif/mif.schema.json). The report channel is
  #     full L3 (gate_m10); none of the published channels is bare frontmatter-less prose.
  local l1ok=1 Dl
  for pf in "$T/post.md" "$T/chapter.md"; do
    Dl="$(mktemp -d)"; bclose=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$pf")
    sed -n "2,$((bclose-1))p" "$pf" > "$Dl/fm.yaml"; sed -n "$((bclose+1)),\$p" "$pf" > "$Dl/body.md"
    yq -p=yaml -o=json '.' "$Dl/fm.yaml" 2>/dev/null | jq --rawfile b "$Dl/body.md" '. + {content:$b}' > "$Dl/c.json" 2>/dev/null
    ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s schemas/mif/mif.schema.json -r schemas/mif/definitions/entity-reference.schema.json -d "$Dl/c.json" >/dev/null 2>&1 || l1ok=0
    rm -rf "$Dl"
  done
  if [ "$l1ok" = 1 ]; then
    ok "every report output is >= MIF L1 (blog + book frontmatter project to a valid base concept)"
  else
    bad "a published output is not MIF L1 (frontmatter does not project to a base concept)"
  fi

  # 6e. EXHAUSTIVE coverage: the artifact carries one evidence-carrying section per
  #     surviving finding (no condensation), so every channel renders every finding
  #     with its own evidence — the diataxis-level rigor applied to all report generation.
  local nsec nsurv nsrc
  nsec=$(jq '.sections | length' "$T/artifact.json" 2>/dev/null)
  nsurv=$(jq -s '[.[]|select((.extensions.harness.verification.verdict//"")!="falsified")]|length' "$SF"/*.json 2>/dev/null)
  nsrc=$(jq '[.sections[]|select(has("sources"))]|length' "$T/artifact.json" 2>/dev/null)
  if [ "$nsec" = "$nsurv" ] && [ "${nsec:-0}" -ge 1 ] && [ "$nsrc" = "$nsec" ]; then
    ok "exhaustive: one evidence-carrying section per surviving finding ($nsec sections = $nsurv findings)"
  else
    bad "artifact coverage not exhaustive (sections=$nsec surviving=$nsurv evidence-carrying=$nsrc)"
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
    # 8c. The template repo itself ships clean — the only corpus committed under
    #     reports/ is reports/_meta/ scaffolding (the sample-session gate fixture), the
    #     single ARCHIVED example research topic the template serves straight out of
    #     reports/ (example-okf-mif-knowledge-spine, which clones inherit under the same
    #     name as their seed fixture), and the canonical cross-topic concordance
    #     (reports/concordance.json — deterministic, on the .gitignore allowlist, rebuilt
    #     by scripts/build-concordance.sh over the shipped corpus); everything else under
    #     reports/ is unexpected.
    if [ -z "$(find reports -path 'reports/_meta' -prune -o -path 'reports/example-okf-mif-knowledge-spine' -prune -o -path 'reports/concordance.json' -prune -o -name '*.json' -print 2>/dev/null)" ]; then
      ok "template repo reports/ ships clean (_meta scaffolding + the archived example topic + the cross-topic concordance only)"
    else
      bad "unexpected corpus committed under reports/ (only _meta, the example topic, and reports/concordance.json may ship)"
      find reports -path 'reports/_meta' -prune -o -path 'reports/example-okf-mif-knowledge-spine' -prune -o -path 'reports/concordance.json' -prune -o -name '*.json' -print 2>/dev/null | sed 's/^/      /' >&2
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

  # 8e. Namespace integrity (capability gate — runs in the template AND in a clone).
  #     Every finding under reports/**/findings MUST carry a NON-EMPTY top-level
  #     `.namespace`. build-index.sh / synthesize-artifact.sh / namespace-scoped
  #     `/search` read this field; a finding that omits it projects a `null` namespace
  #     (silently broken namespace queries + a "Findings: Research" artifact fallback).
  #     The dimension-analyst is required to emit it; this is the deterministic gate
  #     that fails closed if it is ever missing, so the bug can never ship silently.
  local ns_missing=0 ns_checked=0 nsf nsv
  while IFS= read -r -d '' nsf; do
    ns_checked=$((ns_checked + 1))
    nsv=$(jq -r 'if (.namespace | type) == "string" then .namespace else "" end' "$nsf" 2>/dev/null)
    [ -n "${nsv//[[:space:]]/}" ] || { ns_missing=$((ns_missing + 1)); echo "      finding lacks a non-empty string .namespace: $nsf" >&2; }
  done < <(find reports -path '*/findings/*.json' ! -name '.*' -print0 2>/dev/null)
  if [ "$ns_missing" -eq 0 ]; then
    ok "every finding carries a top-level .namespace ($ns_checked checked; index never null)"
  else
    bad "$ns_missing/$ns_checked finding(s) lack a top-level .namespace (projects a null namespace — breaks /search, topics rollup, synthesize-artifact)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 9 — Citation feature flag (features.internalCitations, SPEC §7)
# The toggle decides whether internal/document citations (citationType ^internal:
# carrying quoted evidence in note) count as traceable. gate_m1/1c exercises only
# the strict DEFAULT via the web good/bad samples; this gate exercises BOTH states
# of the toggle over a dedicated internal-citation sample, so the enabled branch of
# check-citation-integrity.sh is no longer untested. Configs are ephemeral (mktemp,
# fed via HARNESS_CONFIG) so the repo manifest and reports/ are never touched.
# ---------------------------------------------------------------------------
gate_m9() {
  info "Milestone 9 — Citation feature flag (features.internalCitations)"

  local sample="schemas/samples/citation-internal.sample.json"
  if [ ! -f "$sample" ]; then
    bad "internal-citation sample missing ($sample)"
    return
  fi

  local td cfg_on cfg_off
  td=$(mktemp -d)
  cfg_on="$td/config-internal-on.json"
  cfg_off="$td/config-internal-off.json"
  printf '{"features":{"internalCitations":true}}\n'  > "$cfg_on"
  printf '{"features":{"internalCitations":false}}\n' > "$cfg_off"

  # Enabled: the internal-citation sample is traceable and PASSES.
  if HARNESS_CONFIG="$cfg_on" scripts/check-citation-integrity.sh "$sample" >/dev/null 2>&1; then
    ok "internal-citation sample PASSES when features.internalCitations=true"
  else
    bad "internal-citation sample rejected when features.internalCitations=true"
  fi

  # Strict default (flag false): the same sample has no http(s) URL and the internal
  # branch is off, so it MUST be rejected.
  if HARNESS_CONFIG="$cfg_off" scripts/check-citation-integrity.sh "$sample" >/dev/null 2>&1; then
    bad "internal-citation sample PASSED under strict default (flag false; must be rejected)"
  else
    ok "internal-citation sample REJECTED under strict default (flag false)"
  fi

  rm -rf "$td"
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
    # Only the canonical report channel (reports/<topic>/<topic>.md) is non-exempt.
    # mifExempt channels (<topic>.blog.md, <topic>.book.md) and the continuity log
    # (research-progress.md) are not L3 reports and must not be projected.
    [ "$(basename "$md" .md)" = "$(basename "$(dirname "$md")")" ] || continue
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

  # 11f2 (issue #360). A same-name collision refuses (fail-closed) rather than
  # silently overwriting -- the exact #357 failure mode, on write-finding.sh's
  # different write path. A second, DIFFERENT valid finding writing to the same
  # dest-name must be rejected, the original content must survive untouched, and
  # no .wf-staging-* directory should be left behind either way.
  jq '."@id"="urn:mif:concept:harness/durability-topic:collision"' \
    schemas/samples/finding.sample.json > "$T/finding-collision.json"
  local refused=0 unchanged=0 clean=0
  scripts/write-finding.sh "$T/finding-collision.json" "$T/wf" "finding-ok.json" >/dev/null 2>&1 || refused=1
  [ "$(jq -r '."@id"' "$T/wf/finding-ok.json" 2>/dev/null)" = "$(jq -r '."@id"' "$RD/findings/finding-a.json")" ] && unchanged=1
  [ -z "$(find "$T/wf" -mindepth 1 -name '.wf-staging-*' 2>/dev/null)" ] && clean=1
  if [ "$refused" = 1 ] && [ "$unchanged" = 1 ] && [ "$clean" = 1 ]; then
    ok "write-finding.sh refuses a same-name collision (fail-closed, no silent overwrite, no staging leftovers)"
  else
    bad "write-finding.sh collision handling broken (refused=$refused unchanged=$unchanged staging-clean=$clean)"
  fi

  # 11f2b (PR #365 review). `ln src dest` does NOT fail with EEXIST when dest
  # already exists as a DIRECTORY -- it silently succeeds by linking INSIDE
  # that directory instead, which would defeat collision detection entirely
  # without ever reaching the elif [ -e "$DEST" ] branch. If DEST is already a
  # directory, write-finding.sh must refuse before ever attempting ln, and
  # that directory must survive untouched (no file linked inside it).
  mkdir -p "$T/wf-dircollision/finding-dir.json"
  local dir_refused=0 dir_untouched=0
  scripts/write-finding.sh "$RD/findings/finding-a.json" "$T/wf-dircollision" "finding-dir.json" >/dev/null 2>&1 || dir_refused=1
  [ -d "$T/wf-dircollision/finding-dir.json" ] && [ -z "$(find "$T/wf-dircollision/finding-dir.json" -mindepth 1 2>/dev/null)" ] && dir_untouched=1
  if [ "$dir_refused" = 1 ] && [ "$dir_untouched" = 1 ]; then
    ok "write-finding.sh refuses when dest-name already exists as a directory (ln would link inside it, not fail)"
  else
    bad "write-finding.sh directory-collision handling broken (refused=$dir_refused untouched=$dir_untouched)"
  fi

  # 11f3 (issue #360, #357-review parity). write-finding.sh's ln-based publish
  # must distinguish "DEST already exists" (a real collision, tested above)
  # from any OTHER ln failure (permissions, cross-filesystem, ...) -- #357's
  # own review caught the identical bug (any ln failure misreported as a
  # collision) in a sibling write path, and write-finding.sh already codes the
  # correct elif [ -e "$DEST" ] distinction, but nothing exercised it.
  # Can't reproduce via $FDIR permissions the way #357's eval did for
  # dimension-analyst.md: write-finding.sh's STAGE_DIR is created INSIDE
  # $FDIR (so ln and the destination share a filesystem, per its own header
  # comment), so any $FDIR permission change that would break `ln` also
  # breaks the preceding `mktemp -d` first -- that's the mktemp failure
  # gate_m11 already tests separately (11f, since #360's fix hardened the
  # unchecked-mktemp path too). Instead, isolate the conditional's LOGIC
  # directly: a real non-EEXIST ln failure (a source that never existed to
  # begin with) must be reported as a genuine failure, not misreported as
  # "$DEST already exists" when it plainly does not.
  local ln_ok=1 ln_dest="$T/wf/never-created.json"
  if ln "$T/wf/.nonexistent-source-$$" "$ln_dest" 2>/dev/null; then
    ln_ok=0
  elif [ -e "$ln_dest" ]; then
    ln_ok=0
  fi
  if [ "$ln_ok" = 1 ]; then
    ok "a real ln failure (missing source) leaves DEST absent -- the elif [ -e \"\$DEST\" ] gate in write-finding.sh's publish correctly distinguishes this from a collision"
  else
    bad "ln-failure-vs-collision gate broken (ln_ok=$ln_ok)"
  fi
  # Pin the logic test above to the actual script: the isolated conditional
  # only proves anything if write-finding.sh really codes this shape, not a
  # bare `if ln ...; then ...; else <collision-handling> ...; fi` that would
  # misreport any ln failure as a collision (#357's original bug).
  if grep -qE 'elif \[ -e "\$DEST" \]' scripts/write-finding.sh; then
    ok "write-finding.sh's publish still codes the elif [ -e \"\$DEST\" ] distinction the logic test above pins"
  else
    bad "write-finding.sh no longer codes the ln-failure-vs-collision distinction -- the logic test above is now testing a pattern the real script doesn't use"
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

  # 11j (fail-safe — THE cost guard). A broken validation environment must make
  # reconcile ABORT (non-zero), not read every finding as invalid and emit a
  # re-run-everything plan. Since research-harness-template#276 (Story #287),
  # reconcile-session.sh delegates to the mif-rh engine, which has no external
  # ajv/jq toolchain to shim broken — instead it proves the environment itself
  # by validating a known-good sample finding before trusting any real result
  # (mif-rh's ReconcileEnvironmentBroken). Corrupt an ISOLATED COPY of that
  # sample (never the committed fixture) and call the engine directly with it.
  local bad_out bad_rc BAD_ENGINE
  # shellcheck source=scripts/lib/engine.sh
  . scripts/lib/engine.sh
  BAD_ENGINE="$(engine_bin "$(pwd)")" || exit 5
  jq 'del(.extensions)' schemas/samples/finding.sample.json > "$T/broken-sample.json"
  bad_out=$("$BAD_ENGINE" harness reconcile-session "$RD2" \
    --schema "schemas/findings.schema.json" \
    --ref "schemas/mif/mif.schema.json" \
    --ref "schemas/mif/definitions/entity-reference.schema.json" \
    --sample "$T/broken-sample.json" 2>/dev/null); bad_rc=$?
  if [ "$bad_rc" -eq 3 ] && ! printf '%s' "$bad_out" | grep -qE 'nothing to do|need work'; then
    ok "reconcile fails safe on a broken validation environment (aborts rc=3; never emits a re-run-everything plan)"
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

  # 12d. (RETIRED, #223) The VENDOR.lock verbatim-set assertion is gone: on-demand
  #      vendoring from the canonical registry (ADR-0012) supersedes the seed-time
  #      VENDOR.lock provenance, so there is no longer a verbatim set to assert.
  #      ontologies.lock.json + check-ontology-lock.sh now pin vendored packs.

  # Build a catalog (core + the dedicated edu-fixture TEST ontology) to drive the
  # resolver fixtures. The fixture lives under evals/fixtures/ (it is NOT a
  # distributable example pack), so this matrix never depends on packs/ontologies/
  # churn; the pack-enable path is exercised separately in 12h against a surviving
  # real pack. software-engineering is deliberately ABSENT here (12g binds it
  # expecting an uncataloged failure).
  local T; T="$(mktemp -d)"
  cat > "$T/cat.json" <<'JSON'
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"shared-traits","version":"1.0.0","source":"schemas/ontologies/shared-traits/1.0.0.yaml","core":true},
 {"id":"edu-fixture","version":"0.1.0","source":"evals/fixtures/ontology/edu-fixture.ontology.yaml","core":false}
]}
JSON
  # config: topic 'edu' binds edu-fixture; 'bare' binds nothing
  echo '{"topics":[{"id":"edu","namespace":"x/edu","ontologies":["edu-fixture"]},{"id":"bare","namespace":"x/bare"}]}' > "$T/rcfg.json"
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
     && [ "$gro" = "edu-fixture@0.1.0|resolved|true" ]; then
    ok "resolver: typed finding resolves+validates; missing/undeclared/unbound fail; map records the mapping"
  else
    bad "resolver matrix wrong (untyped=$ru good=$rg extra=$re missing=$rm undecl=$rd unbound=$rb rec=$gro)"
  fi

  # 12e2. Discovery-pattern classification: an UNTYPED finding whose CONTENT matches a bound
  #       ontology's discovery content_pattern is deterministically classified (basis
  #       "discovery"); a finding matching >1 distinct type stays untyped (no silent pick).
  printf '{"@id":"f-disc","content":"This textbook ISBN edition covers algebra"}\n' > "$T/disc.json"
  printf '{"@id":"f-amb","content":"textbook ISBN curriculum program series"}\n' > "$T/amb.json"
  ro disc edu; local rdc=$?; local dco; dco=$(jq -r '.[0]|"\(.entity_type)|\(.basis)"' "$T/disc.edu.map" 2>/dev/null)
  ro amb edu;  local ramb=$?; local aco; aco=$(jq -r '.[0]|"\(.entity_type)|\(.basis)"' "$T/amb.edu.map" 2>/dev/null)
  if [ "$rdc" = 0 ] && [ "$dco" = "title|discovery" ] && [ "$ramb" = 0 ] && [ "$aco" = "null|untyped" ]; then
    ok "discovery classification: content-matched finding -> typed (basis discovery); ambiguous multi-type match stays untyped"
  else
    bad "discovery classification wrong (disc=$rdc/$dco amb=$ramb/$aco)"
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

  # 12h. Pack-enable path end-to-end (sync-packs): enabling a real ontology DATA
  #      PACK in the manifest catalogs it from its data pack, and a bound topic's
  #      finding resolves against it. Exercised against the surviving
  #      software-engineering pack — edu-fixture above is deliberately not a pack, so
  #      the pack-enable mechanism must run against a real one. Uses its OWN catalog
  #      (12g needs software-engineering absent from the matrix catalog, so the two
  #      cannot share a catalog).
  local TP; TP="$(mktemp -d)"
  jq '(.ontologies[] | select(.id=="software-engineering") | .enabled) |= true' harness.config.json > "$TP/cfg.json"
  scripts/sync-packs.sh "$TP/cfg.json" "$TP/cat.json" "$TP/settings.json" >/dev/null 2>&1
  echo '{"topics":[{"id":"eng","namespace":"x/eng","ontologies":["software-engineering"]}]}' > "$TP/rcfg.json"
  printf '{"@id":"f-se","entity":{"name":"Auth Service","entity_type":"component","responsibility":"authenticate users"}}\n' > "$TP/se.json"
  scripts/resolve-ontology.sh "$TP/se.json" --topic eng --catalog "$TP/cat.json" --config "$TP/rcfg.json" --map "$TP/se.map" >/dev/null 2>&1; local rse=$?
  if jq -e '.ontologies[] | select(.id=="software-engineering" and .core==false)' "$TP/cat.json" >/dev/null 2>&1 && [ "$rse" = 0 ]; then
    ok "an enabled ontology data pack is cataloged (sync-packs) and a bound topic's finding resolves against it"
  else
    bad "pack-enable path broken (software-engineering not cataloged or bound finding did not resolve)"
  fi
  rm -rf "$TP"

  # 12i. Always-on generic typing + DEDUP + ambiguity mechanism. The generic core
  #      (mif-generic) types ANY topic, including core-only. Post-spine-relayering the
  #      generic `technology` is declared ONCE (mif-generic) — software-engineering no
  #      longer shadows it — so it resolves UNAMBIGUOUSLY even from a domain topic. The
  #      ambiguity/disambiguation mechanism is exercised with a self-contained collision
  #      ontology that re-declares `technology` (robust to pack churn).
  jq '(.ontologies[] | select(.id=="software-engineering") | .enabled) |= true' harness.config.json > "$T/se.cfg"
  scripts/sync-packs.sh "$T/se.cfg" "$T/se.cat" "$T/se.set" >/dev/null 2>&1
  jq '.topics = [{"id":"core","namespace":"x/c"},{"id":"eng","namespace":"x/e","ontologies":["software-engineering"]}]' "$T/se.cfg" > "$T/se.rcfg"
  printf '{"@id":"g","entity":{"name":"REST","entity_type":"concept"}}\n' > "$T/gen.json"
  printf '{"@id":"t","entity":{"name":"Kafka","entity_type":"technology"}}\n' > "$T/tech.json"
  $RO "$T/gen.json"  --topic core --catalog "$T/se.cat" --config "$T/se.rcfg" --map "$T/g.map" >/dev/null 2>&1; local gen=$?
  $RO "$T/tech.json" --topic eng  --catalog "$T/se.cat" --config "$T/se.rcfg" --map "$T/t.map" >/dev/null 2>&1; local tech=$?
  local genro techro; genro=$(jq -r '.[0].resolved_ontology' "$T/g.map" 2>/dev/null); techro=$(jq -r '.[0].resolved_ontology' "$T/t.map" 2>/dev/null)
  # Self-contained collision: the committed collide-fixture ALSO declares `technology`
  # (relative source path — the resolver resolves catalog sources against repo root).
  cat > "$T/coll.cat" <<'JSON'
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"collide-fixture","version":"0.1.0","source":"evals/fixtures/ontology/collide-fixture.ontology.yaml","core":false}
]}
JSON
  echo '{"topics":[{"id":"col","namespace":"x/col","ontologies":["collide-fixture"]}]}' > "$T/coll.cfg"
  printf '{"@id":"a","entity":{"name":"Kafka","entity_type":"technology"}}\n' > "$T/amb.json"
  printf '{"@id":"d","ontology":{"id":"collide-fixture"},"entity":{"name":"Kafka","entity_type":"technology"}}\n' > "$T/dis.json"
  $RO "$T/amb.json" --topic col --catalog "$T/coll.cat" --config "$T/coll.cfg" --map "$T/a.map" >/dev/null 2>&1; local amb=$?
  $RO "$T/dis.json" --topic col --catalog "$T/coll.cat" --config "$T/coll.cfg" --map "$T/d.map" >/dev/null 2>&1; local dis=$?
  if [ "$gen" = 0 ] && [ "$genro" = "mif-generic@1.0.0" ] && [ "$tech" = 0 ] && [ "$techro" = "mif-generic@1.0.0" ] \
     && [ "$amb" != 0 ] && [ "$dis" = 0 ]; then
    ok 'generic core types every topic; deduped technology resolves unambiguously to mif-generic; a real collision is ambiguous without ontology.id'
  else
    bad "generic/dedup/ambiguity wrong (generic=$gen ro=$genro tech=$tech techro=$techro ambiguous=$amb disambiguated=$dis)"
  fi

  # 12j. ontology-review.sh reviews/validates coverage across a topic's findings:
  #      correct stamped/discovery/untyped/invalid counts; --strict fails when
  #      invalid mappings exist but NOT on discovery-only or untyped findings
  #      (those are backlog, not corruption — --followup tracks them).
  mkdir -p "$T/reports/edu/findings"
  printf '{"@id":"f-good","entity":%s}\n' "$G" > "$T/reports/edu/findings/good.json"
  printf '{"@id":"f-untyped","content":"x"}\n' > "$T/reports/edu/findings/untyped.json"
  printf '{"@id":"f-missing","entity":{"name":"A","entity_type":"title","subject":"mathematics"}}\n' > "$T/reports/edu/findings/missing.json"
  # No entity block, but content matches edu-fixture's discovery pattern (textbook/
  # ISBN/workbook/edition) — resolve-ontology.sh guesses "title" via basis:discovery,
  # never persisted to the finding itself. Must NOT count as stamped (the bug this
  # milestone fixes: discovery guesses were silently folded into "typed").
  printf '{"@id":"f-disc","content":"a great textbook, ISBN included"}\n' > "$T/reports/edu/findings/disc.json"
  local rv; rv=$(scripts/ontology-review.sh --topic edu --reports-dir "$T/reports" --config "$T/rcfg.json" --catalog "$T/cat.json" --followup "$T/followup.json" 2>/dev/null | tail -1)
  scripts/ontology-review.sh --topic edu --strict --reports-dir "$T/reports" --config "$T/rcfg.json" --catalog "$T/cat.json" >/dev/null 2>&1; local rvs=$?
  local fu_total fu_ids
  fu_total=$(jq -r '.total_needs_followup' "$T/followup.json" 2>/dev/null)
  fu_ids=$(jq -r '.topics.edu[].finding_id' "$T/followup.json" 2>/dev/null | sort | tr '\n' ',')
  if printf '%s' "$rv" | grep -q "1 stamped, 1 discovery-only, 1 untyped, 1 invalid" && [ "$rvs" = 1 ] \
     && [ "$fu_total" = 3 ] && [ "$fu_ids" = "f-disc,f-missing,f-untyped," ]; then
    ok "ontology-review reports correct stamped/discovery/untyped/invalid coverage; --strict fails on invalid mappings only; --followup lists exactly the non-stamped findings"
  else
    bad "ontology-review wrong (summary='$rv' strict-exit=$rvs followup-total=$fu_total followup-ids=$fu_ids)"
  fi

  # 12k. Authoring: the ontology-manager skill scaffolds a NEW ontology that validates
  #      against the contract and is DISCOVERED by the registry enumeration — proving
  #      ontologies can be created/expanded. Discovery REUSES onto_registry_yaml (run in
  #      a fresh tree holding only the scaffolded file), so it self-maintains if the
  #      registry glob changes; a scaffold to a wrong path/extension yields 0 found.
  local base found RT
  base=$(onto_registry_yaml | grep -c . || true)
  RT="$(mktemp -d)"; mkdir -p "$RT/packs/ontologies/demo-new"
  if bash .claude/skills/ontology-manager/scripts/scaffold_ontology.sh demo-new 1.0.0 --extends mif-base \
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
# Milestone 13 — Ontological spine (cross-topic concordance) (SPEC §8d)
# One unified, ontology-typed, fail-closed concordance spanning 1..N topics:
# concept nodes stamped with their resolved ontology entity_type + falsification
# verdict; entity nodes merged across topics by urn:mif: @id; all findings present,
# falsified flagged not excluded; every node/edge type ontology-conformant for its
# topic (from/to domains enforced). Purely additive.
# ---------------------------------------------------------------------------
gate_m13() {
  info "Milestone 13 — Ontological spine (concordance)"

  # 13a. The concordance schema validates its sample.
  if ajv_plain schemas/concordance.schema.json schemas/samples/concordance.sample.json; then
    ok "concordance schema validates its sample"
  else
    bad "concordance schema does not validate its sample"
  fi

  # Fixture corpus: 2 topics (edu->edu-fixture, eng->software-engineering). edu finding is a
  # 'title' that belongs_to a 'program'; eng finding is a 'component' (FALSIFIED) that
  # depends_on a 'technology'; both reference a SHARED 'organization' entity.
  local T; T="$(mktemp -d)"
  cat > "$T/cat.json" <<JSON
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"shared-traits","version":"1.0.0","source":"schemas/ontologies/shared-traits/1.0.0.yaml","core":true},
 {"id":"engineering-base","version":"0.1.0","source":"schemas/ontologies/engineering-base/0.1.0.yaml","core":false},
 {"id":"edu-fixture","version":"0.1.0","source":"evals/fixtures/ontology/edu-fixture.ontology.yaml","core":false},
 {"id":"software-engineering","version":"0.5.0","source":"packs/ontologies/software-engineering/software-engineering.ontology.yaml","core":false}
]}
JSON
  echo '{"topics":[{"id":"edu","namespace":"x/edu","ontologies":["edu-fixture"]},{"id":"eng","namespace":"x/eng","ontologies":["software-engineering"]}]}' > "$T/cfg.json"
  mkdir -p "$T/reports/edu/findings" "$T/reports/eng/findings"
  cat > "$T/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"Algebra textbook","extensions":{"harness":{"dimension":"technical","verification":{"verdict":"survived","verdict_basis":"x"}}},"entity":{"name":"Algebra I","entity_type":"title"},"entities":[{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:prog:math"},"name":"Math Program","entityType":"program"},{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:org:acme"},"name":"Acme","entityType":"organization"}],"relationships":[{"type":"belongs_to","target":"urn:mif:entity:prog:math","strength":1}]}
JSON
  cat > "$T/reports/eng/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/eng:f1","title":"Kafka adoption","extensions":{"harness":{"dimension":"technical","verification":{"verdict":"falsified","verdict_basis":"y"}}},"entity":{"name":"Service","entity_type":"component"},"entities":[{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:tech:kafka"},"name":"Kafka","entityType":"technology"},{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:org:acme"},"name":"Acme","entityType":"organization"}],"relationships":[{"type":"depends_on","target":"urn:mif:entity:tech:kafka","strength":1}]}
JSON
  echo '[{"finding_id":"urn:mif:concept:x/edu:f1","entity_type":"title","resolved_ontology":"edu-fixture@0.1.0","basis":"declared","valid":true}]' > "$T/reports/edu/ontology-map.json"
  echo '[{"finding_id":"urn:mif:concept:x/eng:f1","entity_type":"component","resolved_ontology":"engineering-base@0.1.0","basis":"declared","valid":true}]' > "$T/reports/eng/ontology-map.json"

  CONFIG="$T/cfg.json" scripts/build-concordance.sh "$T/reports" "$T/concordance.json" >/dev/null 2>&1
  vw() { scripts/validate-concordance.sh "$1" --config "$T/cfg.json" --catalog "$T/cat.json" >/dev/null 2>&1; }

  # 13b. build-concordance produces a concordance.json that validates against the schema.
  if [ -f "$T/concordance.json" ] && ajv_plain schemas/concordance.schema.json "$T/concordance.json"; then
    ok "build-concordance spans topics and the concordance validates against the schema"
  else
    bad "build-concordance did not produce a schema-valid concordance"
  fi

  # 13c. Conformance is fail-closed: undeclared entityType, undeclared relationship
  #      type, and a from/to domain violation each FAIL validate-concordance.
  jq '(.nodes[] | select(.id|endswith("prog:math")) | .entityType) = "wizard"' "$T/concordance.json" > "$T/u_type.json"
  jq '(.edges[] | select(.via=="relationship" and (.type=="belongs_to")) | .type) = "frobnicate"' "$T/concordance.json" > "$T/u_rel.json"
  jq '(.nodes[] | select(.id|endswith("prog:math")) | .entityType) = "author"' "$T/concordance.json" > "$T/dom.json"
  if vw "$T/concordance.json" && ! vw "$T/u_type.json" && ! vw "$T/u_rel.json" && ! vw "$T/dom.json"; then
    ok "conformance fail-closed: conformant passes; undeclared type / undeclared rel / domain violation each fail"
  else
    bad "conformance not fail-closed (good=$(vw "$T/concordance.json"; echo $?) badtype=$(vw "$T/u_type.json"; echo $?) badrel=$(vw "$T/u_rel.json"; echo $?) dom=$(vw "$T/dom.json"; echo $?))"
  fi

  # 13d. Concept nodes are stamped with their ontology entity_type + verdict.
  local stamp
  stamp=$(jq -r '.nodes[] | select(.id=="urn:mif:concept:x/edu:f1") | "\(.entityType)|\(.verdict)|\(.ontology)"' "$T/concordance.json")
  if [ "$stamp" = "title|survived|edu-fixture@0.1.0" ]; then
    ok "concept nodes are stamped with resolved ontology entity_type + verdict (from ontology-map.json)"
  else
    bad "concept node not stamped (got '$stamp')"
  fi

  # 13e. Falsified findings are FLAGGED, not excluded.
  local fals
  fals=$(jq -r '[.nodes[] | select(.id=="urn:mif:concept:x/eng:f1")] | "\(length)|\(.[0].verdict)|\(.[0].flagged)"' "$T/concordance.json")
  if [ "$fals" = "1|falsified|true" ]; then
    ok "a falsified finding is present as a node, verdict=falsified and flagged (not excluded)"
  else
    bad "falsified handling wrong (got '$fals')"
  fi

  # 13f. Cross-topic merge: the shared entity is ONE node spanning both topics.
  local merged
  merged=$(jq -rc '[.nodes[] | select(.id=="urn:mif:entity:org:acme")] | "\(length)|\(.[0].topics|sort|join(","))"' "$T/concordance.json")
  if [ "$merged" = "1|edu,eng" ]; then
    ok "an entity referenced in two topics is ONE merged node spanning both (urn:mif @id merge)"
  else
    bad "cross-topic entity merge wrong (got '$merged')"
  fi

  # 13g. Deterministic / idempotent.
  CONFIG="$T/cfg.json" scripts/build-concordance.sh "$T/reports" "$T/concordance2.json" >/dev/null 2>&1
  if diff -q "$T/concordance.json" "$T/concordance2.json" >/dev/null 2>&1; then
    ok "build-concordance is deterministic (two runs byte-identical)"
  else
    bad "build-concordance is not deterministic"
  fi

  # 13h. Real-sample guard: the SHIPPED corpus (reports/_meta) — which uses MIF built-in
  #      entity types (Concept/Technology) and MIF-native relationships (supports/
  #      contradicts/derived-from) — builds and CONFORMS. A curated fixture could pass
  #      while real data fails; this pins it to the actual corpus.
  scripts/build-concordance.sh reports/_meta "$T/real.json" >/dev/null 2>&1
  # EVERY shipped finding must survive as a REAL concept node (carrying its verdict, not
  # dropped to an external stub) — even when the topic has no ontology-map.json. Guards
  # against the empty-stream lookup that silently dropped untyped findings.
  local nfind nreal
  nfind=$(find reports/_meta -path '*/findings/*.json' ! -name '.*' ! -name '*.tmp' 2>/dev/null | grep -c . || true)
  nreal=$(jq '[.nodes[] | select(.kind=="concept" and (.external|not) and .verdict != null)] | length' "$T/real.json" 2>/dev/null)
  if [ -s "$T/real.json" ] && [ "$(jq '.nodes|length' "$T/real.json" 2>/dev/null)" -gt 0 ] \
     && [ "$nreal" = "$nfind" ] && [ "$nfind" -gt 0 ] && vw "$T/real.json"; then
    ok "the shipped corpus builds, conforms, and ALL $nfind findings survive as real verdict-carrying nodes"
  else
    bad "the shipped corpus broke (findings $nfind, real concept nodes $nreal, or non-conformant)"
  fi

  # 13i. An unbound topic carrying an unresolved DOMAIN type fails validation, and the
  #      failure NAMES the topic and points to /ontology-review (the remediation path).
  mkdir -p "$T/orphan/orphan-topic/findings"
  printf '%s\n' '{"@id":"urn:mif:concept:o:f","title":"F","extensions":{"harness":{"verification":{"verdict":"survived"}}},"entities":[{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:t:k"},"name":"K","entityType":"title"}]}' > "$T/orphan/orphan-topic/findings/f.json"
  echo '{"topics":[{"id":"orphan-topic","namespace":"o/x"}]}' > "$T/orphan-cfg.json"
  scripts/build-concordance.sh "$T/orphan" "$T/orphan.json" >/dev/null 2>&1
  local omsg orc
  omsg=$(scripts/validate-concordance.sh "$T/orphan.json" --config "$T/orphan-cfg.json" --catalog "$T/cat.json" 2>&1); orc=$?
  if [ "$orc" != 0 ] && printf '%s' "$omsg" | grep -q "orphan-topic" && printf '%s' "$omsg" | grep -q "/ontology-review"; then
    ok "an unresolved-type topic fails validation; the message names the topic and points to /ontology-review"
  else
    bad "validate remedy message wrong (exit=$orc, names-topic/ontology-review missing)"
  fi

  # 13j. Scale: build over a large corpus via the streaming (temp-file/--slurpfile) path
  #      that replaced the argv accumulation. All N findings appear as real,
  #      verdict-carrying concept nodes and the build is byte-identical across runs.
  #      (This exercises the streaming path's correctness + determinism at scale; it does
  #      not by itself reach the platform ARG_MAX ceiling — that is removed structurally
  #      by not accumulating JSON on argv.)
  mkdir -p "$T/big/scale/findings"
  local n=400 i
  i=1; while [ "$i" -le "$n" ]; do
    printf '{"@id":"urn:mif:concept:s:f%d","title":"finding %d","extensions":{"harness":{"verification":{"verdict":"survived"}}},"entities":[{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:org:acme"},"name":"Acme","entityType":"Organization"}]}\n' "$i" "$i" > "$T/big/scale/findings/f$i.json"
    i=$((i+1))
  done
  scripts/build-concordance.sh "$T/big" "$T/big1.json" >/dev/null 2>&1
  scripts/build-concordance.sh "$T/big" "$T/big2.json" >/dev/null 2>&1
  local bigcount
  bigcount=$(jq '[.nodes[] | select(.kind=="concept" and (.external|not) and .verdict != null)] | length' "$T/big1.json" 2>/dev/null)
  if [ "$bigcount" = "$n" ] && diff -q "$T/big1.json" "$T/big2.json" >/dev/null 2>&1; then
    ok "streaming build scales: all $n findings become real verdict-carrying concept nodes; the build is byte-identical across runs"
  else
    bad "scale build wrong (concept nodes $bigcount of $n, or non-deterministic)"
  fi

  # 13k. The MIF-native STRUCTURAL relationship set is harness-owned, not in the
  #      vendored mif-generic contract. Since research-harness-template#276 (Story #287)
  #      it lives in the mif-rh engine (a separate repo), so this gate can no longer grep
  #      a pinned literal out of validate-concordance.sh's own source — it proves the same
  #      guarantee behaviorally instead: two MIF-core node types with no ontology bound (so
  #      the ONLY way an edge between them can pass is via the STRUCTURAL skip) must PASS
  #      for each of the 9 pinned names (silently dropping one would start from/to-enforcing
  #      or rejecting that link) and FAIL for an unlisted made-up name (over-broadening).
  local T13k; T13k="$(mktemp -d)"
  echo '{"ontologies":[]}' > "$T13k/cat.json"
  echo '{"topics":[]}' > "$T13k/cfg.json"
  local sc_names="contradicts depends-on derived-from part-of refines relates-to supersedes supports updates"
  local sc_all_ok=1 sc_name
  for sc_name in $sc_names; do
    echo "{\"nodes\":[{\"id\":\"n1\",\"entityType\":\"Concept\",\"topics\":[]},{\"id\":\"n2\",\"entityType\":\"File\",\"topics\":[]}],\"edges\":[{\"via\":\"relationship\",\"type\":\"$sc_name\",\"source\":\"n1\",\"target\":\"n2\"}]}" > "$T13k/sc.json"
    scripts/validate-concordance.sh "$T13k/sc.json" --config "$T13k/cfg.json" --catalog "$T13k/cat.json" >/dev/null 2>&1 || sc_all_ok=0
  done
  echo '{"nodes":[{"id":"n1","entityType":"Concept","topics":[]},{"id":"n2","entityType":"File","topics":[]}],"edges":[{"via":"relationship","type":"not-a-structural-relation","source":"n1","target":"n2"}]}' > "$T13k/sc-bad.json"
  scripts/validate-concordance.sh "$T13k/sc-bad.json" --config "$T13k/cfg.json" --catalog "$T13k/cat.json" >/dev/null 2>&1
  local sc_bad_rc=$?
  if [ "$sc_all_ok" = 1 ] && [ "$sc_bad_rc" != 0 ]; then
    ok "STRUCTURAL_CORE: all 9 pinned MIF-native relationships skip domain-checking; an unlisted name does not"
  else
    bad "STRUCTURAL_CORE behavior wrong (all 9 pinned passed=$sc_all_ok; unlisted-name rc=$sc_bad_rc, want nonzero)"
  fi
  rm -rf "$T13k"

  rm -rf "$T"
}

gate_m14() {
  info "Milestone 14 — Falsification gate safety (honest default + phase-gate hook)"
  local T; T="$(mktemp -d)"

  # 14a. A finding with NO evidence-fixture entry was not adversarially tested -> the gate
  #      defaults to `inconclusive`, never a false `survived` (which the one-round rule would
  #      make permanent — the contamination a stray, non-gate invocation caused).
  printf '{"@id":"urn:mif:concept:t:f1","title":"x"}\n' > "$T/f.json"
  local vd vph; vd=$(scripts/falsify.sh "$T/f.json" 2>/dev/null | jq -r '.extensions.harness.verification.verdict')
  # The placeholder must OMIT attempted_at so the one-round rule does not lock it — a later
  # real gate can still overwrite it (it isn't permanently blocked, just withheld).
  vph=$(scripts/falsify.sh "$T/f.json" 2>/dev/null | jq -r '.extensions.harness.verification | has("attempted_at")')
  if [ "$vd" = "inconclusive" ] && [ "$vph" = "false" ]; then
    ok "falsify.sh no-fixture is a placeholder 'inconclusive' WITHOUT attempted_at (no false pass, not gate-locked)"
  else
    bad "falsify.sh no-fixture wrong (verdict=$vd has_attempted_at=$vph)"
  fi

  # 14b. An EXPLICIT fixture verdict is recorded unchanged.
  printf '{"urn:mif:concept:t:f1":{"verdict":"survived"}}\n' > "$T/ev.json"
  local vf; vf=$(scripts/falsify.sh "$T/f.json" "$T/ev.json" 2>/dev/null | jq -r '.extensions.harness.verification.verdict')
  if [ "$vf" = "survived" ]; then
    ok "falsify.sh records an explicit fixture verdict unchanged"
  else
    bad "falsify.sh changed an explicit fixture verdict to '$vf'"
  fi

  # 14c. Phase-gate PreToolUse hook: a findings-grade tool-command is DENIED without the
  #      topic's gate window and ALLOWED with it; a report-finding (non-findings target) is a
  #      legit non-gate use (report-synthesizer / publish-report) and is always allowed.
  local HK=".claude/hooks/guard-falsify-gate.sh"
  mkdir -p "$T/reports/tA/findings"
  hd() { local o; o=$(printf '%s' "$1" | CLAUDE_PROJECT_DIR="$T" bash "$HK" 2>/dev/null); [ -z "$o" ] && echo allow || printf '%s' "$o" | jq -r '.hookSpecificOutput.permissionDecision'; }
  local d_no d_yes d_rep d_stale
  rm -f "$T/reports/tA/.gate-active"
  d_no=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/findings/f.json fx"}}')
  touch "$T/reports/tA/.gate-active"
  d_yes=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/findings/f.json fx"}}')
  d_rep=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/report-finding.json fx"}}')
  # A STALE marker (left by a crashed gate) ages out of the freshness window -> denied.
  touch -t 200001010000 "$T/reports/tA/.gate-active"
  d_stale=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/findings/f.json fx"}}')
  # MULTI-TOPIC: one topic's window must not authorize grading another's. tA open, tB closed
  # -> the whole command is denied.
  local d_multi; mkdir -p "$T/reports/tB/findings"; rm -f "$T/reports/tB/.gate-active"
  rm -f "$T/reports/tA/.gate-active"; touch "$T/reports/tA/.gate-active"
  d_multi=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/findings/f.json; scripts/falsify.sh reports/tB/findings/g.json"}}')
  if [ "$d_no" = deny ] && [ "$d_yes" = allow ] && [ "$d_rep" = allow ] && [ "$d_stale" = deny ] && [ "$d_multi" = deny ]; then
    ok "phase-gate hook: denied without the window, allowed within a fresh window, denied on STALE; report-finding allowed; multi-topic denied when any window is closed"
  else
    bad "phase-gate hook wrong (no-window=$d_no fresh=$d_yes report=$d_rep stale=$d_stale multi=$d_multi)"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 15 — Living corpus: goal evolution (SPEC §11). Goal versions are
# content-hashed (stable, lineage-invariant, content-sensitive); reshape reuses
# in-scope findings across versions and computes the research gap; freshness
# flips under source-type decay; the membership mirror projects into the index.
# ---------------------------------------------------------------------------
gate_m15() {
  info "Milestone 15 — Living corpus: goal evolution + finding reuse"
  local T; T="$(mktemp -d)"

  # 15a. Content-hash identity: stable, lineage-invariant, content-sensitive.
  cp reports/_meta/sample-session/goal.json "$T/g.json"
  local h1 h2 hl hc
  h1=$(scripts/goal-version.sh "$T/g.json")
  h2=$(scripts/goal-version.sh "$T/g.json")
  jq '. + {version:"gv-000000000000",supersedes:null,revision:{rationale:"x",changed:[],date:"2026-01-01"}}' "$T/g.json" > "$T/gl.json"
  hl=$(scripts/goal-version.sh "$T/gl.json")
  jq '.goal_statement = "an entirely different decision"' "$T/g.json" > "$T/gc.json"
  hc=$(scripts/goal-version.sh "$T/gc.json")
  if [ "$h1" = "$h2" ] && [ "$h1" = "$hl" ] && [ "$h1" != "$hc" ] && printf '%s' "$h1" | grep -qE '^gv-[0-9a-f]{12}$'; then
    ok "goal-version: $h1 is stable, lineage-invariant, and content-sensitive"
  else
    bad "goal-version wrong (h1=$h1 h2=$h2 lineage=$hl content=$hc)"
  fi

  # 15b. A versioned goal validates against the schema. ajv_plain carries
  #      -c ajv-formats, so revision.date's RFC 3339 format:date is enforced, not
  #      ignored — use the canonical helper rather than re-spelling the flags.
  if ajv_plain schemas/goal.schema.json "$T/gl.json"; then
    ok "a versioned goal (version/supersedes/revision) validates against goal.schema.json"
  else
    bad "versioned goal failed goal.schema.json"
  fi
  # revision.date is RFC 3339 format:date and is ENFORCED (ajv-formats): a non-date
  # string is rejected — it would be silently ignored without the formats plugin.
  jq '.revision.date = "June 1 2026"' "$T/gl.json" > "$T/gbad.json"
  if ajv_plain schemas/goal.schema.json "$T/gbad.json"; then
    bad "a malformed revision.date was accepted (RFC date format not enforced)"
  else
    ok "a malformed revision.date is rejected (RFC 3339 date format enforced)"
  fi

  # 15b'. A real finding carrying the new gathered_under field still validates
  #       against findings.schema.json with the MIF closure registered.
  jq '.extensions.harness.gathered_under = "gv-000000000000"' \
    reports/_meta/sample-session/findings/finding-copier.json > "$T/fgu.json"
  if ajv_mif schemas/findings.schema.json "$T/fgu.json"; then
    ok "a finding carrying extensions.harness.gathered_under validates against findings.schema.json"
  else
    bad "finding with gathered_under failed findings.schema.json"
  fi

  # 15c. Reshape reuse: stage a topic, classify v1, then reshape (drop a dimension,
  #      add one) and confirm findings carry, the out-of-scope one drops, gap = added.
  local P; P="$T/proj"; mkdir -p "$P/reports/tt/findings"
  jq -n '{version:"1.0.0",
          topics:[{id:"tt",title:"T",namespace:"harness/tt",status:"active"}],
          dimensions:[{id:"technical"},{id:"landscape"},{id:"trajectory"}],
          packs:[],
          freshness:{default_days:180,by_citation_type:{documentation:365,website:90}}}' \
    > "$P/harness.config.json"
  cp reports/_meta/sample-session/findings/*.json "$P/reports/tt/findings/"
  cp reports/_meta/sample-session/goal.json "$P/reports/tt/goal.json"
  local V V2 mem stale mem2 gap2
  V=$(scripts/goal-version.sh "$P/reports/tt/goal.json")
  CLAUDE_PROJECT_DIR="$P" scripts/resolve-membership.sh tt "$V" >/dev/null 2>&1
  mem=$(jq '.members | length' "$P/reports/tt/goals/goal-$V.members.json")
  stale=$(jq '.stale | length' "$P/reports/tt/goals/goal-$V.members.json")
  jq '.dimensions = ["technical","landscape","economic"]' "$P/reports/tt/goal.json" > "$P/g2.json"
  V2=$(scripts/goal-version.sh "$P/g2.json"); cp "$P/g2.json" "$P/reports/tt/goal.json"
  CLAUDE_PROJECT_DIR="$P" scripts/resolve-membership.sh tt "$V2" >/dev/null 2>&1
  mem2=$(jq '.members | length' "$P/reports/tt/goals/goal-$V2.members.json")
  gap2=$(jq -r '.gap_dimensions | join(",")' "$P/reports/tt/goals/goal-$V2.members.json")
  if [ "$mem" = 3 ] && [ "$stale" = 3 ] && [ "$mem2" = 2 ] && [ "$gap2" = economic ] && [ "$V" != "$V2" ]; then
    ok "reshape: v1 carries 3 (all stale, no attempted_at); v2 drops the out-of-scope dim to 2; gap=economic"
  else
    bad "reshape reuse wrong (v1 mem=$mem stale=$stale; v2 mem=$mem2 gap=$gap2; V=$V V2=$V2)"
  fi

  # 15d. Freshness flips on a recent attempted_at; the membership mirror projects.
  local FR; FR="$P/reports/tt/findings/finding-copier.json"
  jq --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.extensions.harness.verification.attempted_at = $t' "$FR" > "$FR.tmp" && mv "$FR.tmp" "$FR"
  CLAUDE_PROJECT_DIR="$P" scripts/resolve-membership.sh tt "$V2" >/dev/null 2>&1
  local stale2 proj
  stale2=$(jq '.stale | length' "$P/reports/tt/goals/goal-$V2.members.json")
  CLAUDE_PROJECT_DIR="$P" scripts/build-index.sh "$P/reports/tt/findings" "$P/idx.json" >/dev/null 2>&1
  proj=$(jq --arg v "$V2" '[.findings[] | select(.goal_versions | index($v))] | length' "$P/idx.json")
  if [ "$stale2" -lt "$mem2" ] && [ "$proj" = "$mem2" ]; then
    ok "freshness flips on a fresh attempted_at (stale $stale2 < members $mem2); mirror projects goal_versions[] ($proj)"
  else
    bad "freshness/mirror wrong (stale2=$stale2 mem2=$mem2 projected=$proj)"
  fi

  # 15e. The CORE LOOP (the reuse-and-stop guarantee): a new gap finding stamped
  #      gathered_under=v2 joins members on re-resolve and CLOSES the gap; then
  #      excluding it (as goal-writer does) PERSISTS — re-resolve does not re-add it
  #      and its dimension returns to the gap. This is the path /start --update walks.
  jq -n --arg v "$V2" '{"@id":"urn:mif:concept:harness:econ-1","title":"econ","namespace":"harness/tt",
    citations:[{"@type":"Citation",citationType:"website",citationRole:"supports",title:"e",url:"https://e.example"}],
    extensions:{harness:{dimension:"economic",
      verification:{verdict:"survived",verdict_basis:"x",attempted_at:(now|todateiso8601)},
      gathered_under:$v}}}' > "$P/reports/tt/findings/finding-econ.json"
  CLAUDE_PROJECT_DIR="$P" scripts/resolve-membership.sh tt "$V2" >/dev/null 2>&1
  local M="$P/reports/tt/goals/goal-$V2.members.json" gap_closed econ_in gu
  gap_closed=$(jq -r '.gap_dimensions | join(",")' "$M")
  econ_in=$(jq '[.members[] | select(. == "urn:mif:concept:harness:econ-1")] | length' "$M")
  gu=$(jq -r '.extensions.harness.gathered_under' "$P/reports/tt/findings/finding-econ.json")
  # Now exclude it as goal-writer would, and re-resolve — exclusion must persist.
  jq '.members -= ["urn:mif:concept:harness:econ-1"] | .excluded += ["urn:mif:concept:harness:econ-1"]' \
    "$M" > "$M.tmp" && mv "$M.tmp" "$M"
  CLAUDE_PROJECT_DIR="$P" scripts/resolve-membership.sh tt "$V2" >/dev/null 2>&1
  local econ_excluded gap_reopened
  econ_excluded=$(jq '.excluded | index("urn:mif:concept:harness:econ-1") != null' "$M")
  gap_reopened=$(jq -r '.gap_dimensions | join(",")' "$M")
  if [ -z "$gap_closed" ] && [ "$econ_in" = 1 ] && [ "$gu" = "$V2" ] \
     && [ "$econ_excluded" = true ] && [ "$gap_reopened" = economic ]; then
    ok "core loop: gap finding joins members and closes the gap (gathered_under=$gu); exclusion persists on re-resolve"
  else
    bad "core loop wrong (gap_closed='$gap_closed' econ_in=$econ_in gu=$gu excluded=$econ_excluded reopened='$gap_reopened')"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 16 — Diátaxis channel MIF Level-1 frontmatter (SPEC §6d, §10)
# The `diataxis` channel pack emits MIF Level-1 concept frontmatter — a base MIF
# v1.0 concept (schemas/mif/mif.schema.json) plus the diataxis_type marker,
# validated by schemas/diataxis-doc.schema.json. It carries stable typed identity
# but NOT the L3 additions (provenance/citations/entities/verdict) that
# findings.schema.json requires; the report channel stays the canonical L3 source
# of truth, so the channel remains mif.exempt. The frontmatter holds the doc's own
# urn:mif:doc: identity; the body prose must carry no internal-research identity.
# ---------------------------------------------------------------------------
gate_m16() {
  info "Milestone 16 — Diátaxis channel MIF Level-1 frontmatter"

  # 16a. The diataxis-doc L1 schema validates its sample (base concept + diataxis_type).
  if ajv_mif schemas/diataxis-doc.schema.json schemas/samples/diataxis-doc.sample.json; then
    ok "diataxis-doc schema validates its sample (MIF L1 concept + diataxis_type)"
  else
    bad "diataxis-doc schema does not validate its sample"
  fi

  # 16b. Render the whole findings corpus to a Diátaxis tree and assert EVERY emitted
  #      doc (1) projects to a valid MIF L1 concept (diataxis-doc.schema.json — base
  #      concept, NOT findings/L3), (2) carries exactly one diataxis_type marker + one
  #      body H1, (3) keeps its body free of internal urn:mif: identity, and — when
  #      markdownlint is available — (4) lints clean. AND that the set is COMPLETE, not
  #      a stub: a reference page per surviving finding, a per-dimension explanation and
  #      how-to, and the tutorials + top index. Rendered to a temp dir.
  local SF T f close D l1=1 dx=1 body=1 lint=1 have_ml=0 total=0 nfind ndim nref nexp nhow ntut complete=1 ix
  SF="reports/_meta/sample-session/findings"
  command -v markdownlint-cli2 >/dev/null 2>&1 && have_ml=1
  T="$(mktemp -d)"
  if packs/channels/diataxis/scripts/render-diataxis.sh "$SF" "$T/docs" sample >/dev/null 2>&1; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      total=$((total+1)); D="$(mktemp -d)"
      close=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$f")
      sed -n "2,$((close-1))p" "$f" > "$D/fm.yaml"
      sed -n "$((close+1)),\$p" "$f" > "$D/body.md"
      yq -p=yaml -o=json '.' "$D/fm.yaml" > "$D/fm.json" 2>/dev/null
      jq --rawfile b "$D/body.md" '(if ((.content//"")=="") then .content=($b|sub("^\\s+";"")|sub("\\s+$";"")) else . end)' \
        "$D/fm.json" > "$D/c.json" 2>/dev/null
      ajv_mif schemas/diataxis-doc.schema.json "$D/c.json" || l1=0
      # diataxis_type counted in the FRONTMATTER slice; the single body H1 counted
      # fence-aware in the BODY (a '#' inside a finding's fenced code block must not count).
      # exactly one diataxis_type marker, NO frontmatter title: key (a title: plus the
      # body H1 trips markdownlint MD025 — enforced here so it cannot regress when
      # markdownlint is unavailable), and exactly one fence-aware body H1.
      { [ "$(grep -cE '^diataxis_type:' "$D/fm.yaml")" = 1 ] \
        && [ "$(grep -cE '^title:' "$D/fm.yaml")" = 0 ] \
        && [ "$(awk '/^[ \t]*(```|~~~)/{fc=!fc} (!fc && /^# /){c++} END{print c+0}' "$D/body.md")" = 1 ]; } || dx=0
      # body carries no internal-research identity in ANY of its disallowed forms.
      grep -qE 'urn:mif:|f_[a-z]+_[0-9]+|extensions\.harness|reports/[a-z0-9-]+/(findings|_meta)' "$D/body.md" && body=0
      [ "$have_ml" = 1 ] && { markdownlint-cli2 --config .markdownlint-cli2.jsonc "$f" >/dev/null 2>&1 || lint=0; }
      rm -rf "$D"
    done < <(find "$T/docs" -name '*.md')
    # Counts over SURVIVING findings only (the renderer excludes falsified), so a
    # fully-falsified dimension does not make the expected per-dimension counts diverge.
    nfind=$(jq -s '[.[]|select((.extensions.harness.verification.verdict//"")!="falsified")]|length' "$SF"/*.json)
    ndim=$(jq -rs '[.[]|select((.extensions.harness.verification.verdict//"")!="falsified")|.extensions.harness.dimension//"general"]|unique|length' "$SF"/*.json)
    nref=$(find "$T/docs/reference" -name '*.md' ! -name index.md 2>/dev/null | grep -c .)
    nexp=$(find "$T/docs/explanation" -name '*.md' ! -name index.md 2>/dev/null | grep -c .)
    nhow=$(find "$T/docs/how-to" -name '*.md' ! -name index.md 2>/dev/null | grep -c .)
    ntut=$(find "$T/docs/tutorials" -name '*.md' ! -name index.md ! -name getting-started.md 2>/dev/null | grep -c .)
    [ "$nref" = "$nfind" ] || complete=0
    [ "$nexp" = "$ndim" ] || complete=0
    [ "$nhow" = "$ndim" ] || complete=0
    [ "$ntut" = "$ndim" ] || complete=0
    for ix in index.md reference/index.md explanation/index.md how-to/index.md tutorials/index.md tutorials/getting-started.md; do
      [ -f "$T/docs/$ix" ] || complete=0
    done
    if [ "$l1" = 1 ] && [ "$dx" = 1 ] && [ "$body" = 1 ] && [ "$lint" = 1 ] && [ "$complete" = 1 ] && [ "$total" -ge 1 ]; then
      ok "diataxis: $total docs all MIF L1 + one diataxis_type/body-H1 + body urn-free$([ "$have_ml" = 1 ] && echo " + lint clean"); complete set ($nref ref = $nfind findings; $nexp exp + $nhow how-to + $ntut tutorials per $ndim dims; all 6 index/landing pages present)"
    else
      bad "diataxis render check failed (l1=$l1 diataxis/h1=$dx body=$body lint=$lint complete=$complete[ref=$nref/find=$nfind exp=$nexp how=$nhow tut=$ntut/dim=$ndim] docs=$total)"
    fi
  else
    bad "diataxis render check: render failed"
  fi
  rm -rf "$T"
}

gate_m17() {
  info "Milestone 17 — topic README freshness (deterministic metadata stays current vs substrate)"

  # readme_fresh <project_dir> <topic>  -> 0 fresh, 1 stale/missing.
  # `build` mode preserves authored prose by reading the OUTPUT path, so copy the
  # live README to a temp path, rebuild ONTO that copy (Purpose / Key Findings /
  # Created preserved), and diff ignoring the always-today metadata line
  # ("**Created:** X | **Updated:** Y"). Empty diff modulo that line => the
  # deterministic metadata already matches disk. Deliberately NOT `--check`: that
  # also fails on un-synthesized Key Findings, a SEPARATE concern from staleness
  # (and would red-flag every mid-research instance).
  readme_fresh() {
    local proj="$1" topic="$2" rd d rc
    rd="$proj/reports/$topic/README.md"
    [ -f "$rd" ] || return 1
    d="$(mktemp -d)"
    cp "$rd" "$d/README.md"
    if ! CLAUDE_PROJECT_DIR="$proj" bash scripts/build-topic-readme.sh "$topic" \
         --out "$d/README.md" >/dev/null 2>&1; then
      rm -rf "$d"; return 1
    fi
    if diff <(grep -v '^\*\*Created:\*\* ' "$rd") \
            <(grep -v '^\*\*Created:\*\* ' "$d/README.md") >/dev/null 2>&1; then
      rc=0
    else
      rc=1
    fi
    rm -rf "$d"; return "$rc"
  }

  # 17a. Hermetic fixture: a freshly built README is fresh; mutating the substrate
  #      (a new finding -> changed counts/tables) makes it stale. Proves the gate
  #      detects drift in BOTH directions, independent of any real topic on disk.
  local proj fok=1
  proj="$(mktemp -d)"
  mkdir -p "$proj/reports/t/findings"
  cat > "$proj/harness.config.json" <<'JSON'
{ "version": "1.0.0", "topics": [ { "id": "t", "title": "T", "namespace": "harness/t", "status": "active" } ] }
JSON
  _mk_finding() { # _mk_finding <path> <id> <dim> <verdict>
    cat > "$1" <<JSON
{ "@id": "urn:mif:concept:t:$2", "title": "$2", "summary": "Summary of $2.",
  "created": "2026-06-01", "tags": ["t"],
  "citations": [ { "url": "https://example.com/$2" } ],
  "extensions": { "harness": { "dimension": "$3",
    "verification": { "verdict": "$4" } } } }
JSON
  }
  _mk_finding "$proj/reports/t/findings/f1.json" f1 technical survived
  _mk_finding "$proj/reports/t/findings/f2.json" f2 technical weakened
  CLAUDE_PROJECT_DIR="$proj" bash scripts/build-topic-readme.sh t >/dev/null 2>&1 || fok=0
  readme_fresh "$proj" t || fok=0                 # built => fresh
  _mk_finding "$proj/reports/t/findings/f3.json" f3 landscape survived
  readme_fresh "$proj" t && fok=0                 # substrate drifted => must be stale
  rm -rf "$proj"
  if [ "$fok" = 1 ]; then
    ok "README freshness gate detects drift (built README fresh; a new finding makes it stale)"
  else
    bad "README freshness gate logic wrong (fresh-when-built or stale-after-mutation not detected)"
  fi

  # 17b. Every registered topic that HAS a README on disk must be metadata-fresh
  #      vs its substrate — the CI backstop for out-of-band edits the hook misses.
  local topic any=0
  while IFS= read -r topic; do
    [ -n "$topic" ] || continue
    [ -f "reports/$topic/README.md" ] || continue
    any=1
    if readme_fresh "$PWD" "$topic"; then
      ok "topic README fresh vs substrate: $topic"
    else
      bad "topic README STALE vs substrate — rebuild: scripts/build-topic-readme.sh $topic"
    fi
  done < <(jq -r '.topics[].id' harness.config.json 2>/dev/null)
  [ "$any" = 0 ] && ok "no topic READMEs on disk to freshness-check (none built yet)"

  # 17c. The shell-write mutation paths the PostToolUse README hook never observes
  #      (verdicts/quarantine via falsify, a report rendered via shell redirect)
  #      must each carry the deterministic README rebuild, or the README drifts
  #      stale after /falsify or publish-report exactly as issue #84 describes.
  #      17b's real-topic loop is inert in the bare template, so assert the wiring
  #      is documented where the fix lives.
  if grep -qE 'build-topic-readme\.sh' .claude/commands/falsify.md \
     && grep -qE 'build-topic-readme\.sh' .claude/skills/publish-report/SKILL.md; then
    ok "shell-write mutation paths reconcile the README (falsify.md + publish-report rebuild it)"
  else
    bad "a shell-write mutation path is missing its README rebuild (falsify.md / publish-report)"
  fi

  # 17d. Prose preservation is robust to a cosmetically-perturbed heading. The
  #      auto-rebuild hook now runs build mode on EVERY mutation, so if heading
  #      matching were byte-exact a trailing space / CR on '## Key Findings' would
  #      silently overwrite synthesis-grade prose with the deterministic draft.
  #      Author a synthesis line under a trailing-space heading, rebuild, assert it
  #      survives.
  local pp pres=1 rd
  pp="$(mktemp -d)"
  mkdir -p "$pp/reports/t/findings"
  cat > "$pp/harness.config.json" <<'JSON'
{ "version": "1.0.0", "topics": [ { "id": "t", "title": "T", "namespace": "harness/t", "status": "active" } ] }
JSON
  _mk_finding "$pp/reports/t/findings/f1.json" f1 technical survived
  CLAUDE_PROJECT_DIR="$pp" bash scripts/build-topic-readme.sh t >/dev/null 2>&1 || pres=0
  rd="$pp/reports/t/README.md"
  # Replace the canonical heading with a trailing-space variant + an authored line.
  awk '
    /^## Key Findings$/ { print "## Key Findings "; print ""; print "- SYNTH: cross-finding insight."; skip=1; next }
    skip && /^## / { skip=0 }
    skip { next }
    { print }
  ' "$rd" > "$rd.x" && mv "$rd.x" "$rd"
  CLAUDE_PROJECT_DIR="$pp" bash scripts/build-topic-readme.sh t >/dev/null 2>&1 || pres=0
  grep -q 'SYNTH: cross-finding insight' "$rd" || pres=0
  rm -rf "$pp"
  if [ "$pres" = 1 ]; then
    ok "build preserves authored Key Findings across rebuild despite a trailing-space heading (no synthesis clobber)"
  else
    bad "build clobbered authored Key Findings on rebuild (heading-match preservation too strict)"
  fi
}

gate_m18() {
  info "Milestone 18 — supervising a running orchestrator (idle/stall guidance + Phase 1 heartbeat)"

  # 18a. start.md and resume.md tell a supervisor how to wait: the live signal of
  #      progress is the growing findings/*.json count, and an idle notification or
  #      a quiet research-progress.md is NOT a stall.
  local f
  for f in .claude/commands/start.md .claude/commands/resume.md; do
    if grep -qiE 'Monitoring a running session' "$f" \
       && grep -qiE 'idle' "$f" \
       && grep -qE 'findings/\*\.json' "$f"; then
      ok "$(basename "$f"): documents monitoring a running session (findings-count signal, idle != stall)"
    else
      bad "$(basename "$f"): missing 'Monitoring a running session' guidance (findings-count signal + idle-is-not-stall)"
    fi
  done

  # 18b. orchestrator.md emits a coarse Phase 1 heartbeat to research-progress.md
  #      so a supervisor sees progress between Session Initialized and Dimensions Complete.
  if grep -qE 'fan-out started' .claude/agents/orchestrator.md; then
    ok "orchestrator.md: emits a Phase 1 fan-out heartbeat to research-progress.md"
  else
    bad "orchestrator.md: no Phase 1 fan-out heartbeat (supervisor has no marker during Phase 1)"
  fi
}

gate_m19() {
  info "Milestone 19 — instance-safe CI: template-only propagation gate + idempotent progress-log headings (issue #85)"

  # 19a. The propagation gate (evals/copier-update.sh) must skip in an instance —
  #      it fails deterministically there otherwise (D1), aborting CI before the
  #      lint gate runs. Assert the guard is present and its predicate (a tracked
  #      copier.yml) agrees with THIS context.
  # Lock the EXACT guard condition, not merely "a git ls-files call exists": the
  # work-tree probe AND the negated tracked-copier.yml test. A regressed guard that
  # dropped the `!` or the `&&` would no longer match.
  if grep -qE 'git rev-parse --is-inside-work-tree' evals/copier-update.sh \
     && grep -qE '&& ! git ls-files --error-unmatch copier\.yml' evals/copier-update.sh; then
    ok "copier-update.sh guard matches the exact instance condition (work-tree AND copier.yml untracked)"
  else
    bad "copier-update.sh guard does not match '&& ! git ls-files ... copier.yml' — a regressed guard could pass (issue #85 D1)"
  fi
  # Behaviorally exercise the guard: copy the real script into a throwaway git repo
  # with NO tracked copier.yml (an instance) and confirm it actually SKIPs. This
  # catches a logic regression (lost `!`/`&&`) even when the strings are present —
  # copier-update.sh `cd`s to its own dir, so it operates on this temp repo. The
  # template path (copier.yml tracked -> runs, not skip) is covered by the separate
  # `copier update propagation` CI step, which PASSes only by running fully.
  local t; t="$(mktemp -d)"
  mkdir -p "$t/evals"
  cp evals/copier-update.sh "$t/evals/copier-update.sh"
  ( cd "$t" && git init -q && echo x > f && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm i ) >/dev/null 2>&1
  if ( cd "$t" && bash evals/copier-update.sh 2>/dev/null | grep -q '^copier-update: SKIP' ); then
    ok "copier-update.sh behaviorally SKIPs in an instance (git repo, copier.yml untracked)"
  else
    bad "copier-update.sh did NOT skip in an instance — instance CI would fail (issue #85 D1)"
  fi
  rm -rf "$t"

  # 19b. orchestrator.md emits the progress-log title H1 in exactly ONE place (file
  #      creation), so a multi-session research-progress.md never gains a second H1
  #      (MD025) or a duplicate heading (MD024); and uses no fixed cross-session
  #      snapshot heading that would collide across sessions (D2).
  local h1
  h1=$(grep -cE '^[[:space:]]*# Research Progress: \{topic\}' .claude/agents/orchestrator.md)
  if [ "$h1" -eq 1 ]; then
    ok "orchestrator.md emits the progress-log H1 in exactly one place (no per-session H1 duplication)"
  else
    bad "orchestrator.md emits the progress-log H1 in $h1 places (must be 1 — duplicate H1 -> MD025 on multi-session topics; issue #85 D2)"
  fi
  if grep -qE '^[[:space:]]*## (Findings Summary|Next Steps)[[:space:]]*$' .claude/agents/orchestrator.md; then
    bad "orchestrator.md still uses a fixed '## Findings Summary'/'## Next Steps' heading (collides across sessions -> MD024)"
  else
    ok "orchestrator.md uses no fixed cross-session snapshot heading (date-qualified summary instead)"
  fi
}

gate_m20() {
  info "Milestone 20 — cross-pack relationship reference integrity"
  # gate_m12 validates each ontology in isolation and cannot see a relationship
  # endpoint that names a type living in ANOTHER pack — the intended cross-pack
  # edges (e.g. security's `realizes`/`mitigates_threat` -> software-engineering's
  # security-incident/security-threat). Assert every relationship from/to across ALL
  # registry ontologies resolves to a type declared in SOME registry ontology, so a
  # future rename can't silently dangle an edge.
  #
  # Since research-harness-template#276 (Story #287), this whole-registry scan
  # delegates to the mif-rh engine (mif-rh-cli harness check-ontology-registry).
  local reg_out reg_err reg_n reg_orphans
  reg_err="$(mktemp)"
  reg_out=$("$ENGINE" harness check-ontology-registry --root "$(pwd)" 2>"$reg_err")
  if [ $? -gt 1 ]; then
    bad "check-ontology-registry errored (exit>1): $(cat "$reg_err")"
    rm -f "$reg_err"
    return
  fi
  rm -f "$reg_err"
  reg_n=$(printf '%s\n' "$reg_out" | sed -n 's/^ontology-registry: \([0-9]*\) type(s).*/\1/p')
  reg_orphans=$(printf '%s\n' "$reg_out" | sed -n 's/^ontology-registry: relationship-endpoint orphans: //p')
  if [ "$reg_orphans" = "none" ]; then
    ok "every cross-pack relationship endpoint resolves to a declared entity type ($reg_n types across the registry)"
  else
    bad "relationship endpoint(s) declared in no registry ontology: ${reg_orphans}"
  fi
}

gate_m21() {
  info "Milestone 21 — layered ontology spine (transitive extends + upstream boundary)"
  # The engineering-base layer (core=false) is reached via a descendant's `extends`
  # chain, NOT by being always-on. Prove BOTH directions against a self-contained
  # catalog (relative sources; engineering-base present-but-not-core):
  #   POSITIVE — a topic binding only software-engineering resolves `component`, a type
  #              declared by engineering-base (an ANCESTOR), and the map records
  #              engineering-base as the resolver — transitive `extends` works.
  #   NEGATIVE — a topic binding a NON-engineering pack (edu-fixture, which extends
  #              mif-base, not engineering-base) does NOT resolve `component` — the
  #              engineering vocabulary does NOT leak into the generic core. This is the
  #              upstream-submission boundary: engineering-base is a domain extension,
  #              not part of the always-on MIF generic core.
  local T; T="$(mktemp -d)"
  cat > "$T/cat.json" <<'JSON'
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"shared-traits","version":"1.0.0","source":"schemas/ontologies/shared-traits/1.0.0.yaml","core":true},
 {"id":"engineering-base","version":"0.1.0","source":"schemas/ontologies/engineering-base/0.1.0.yaml","core":false},
 {"id":"edu-fixture","version":"0.1.0","source":"evals/fixtures/ontology/edu-fixture.ontology.yaml","core":false},
 {"id":"software-engineering","version":"0.5.0","source":"packs/ontologies/software-engineering/software-engineering.ontology.yaml","core":false}
]}
JSON
  echo '{"topics":[{"id":"eng","namespace":"x/e","ontologies":["software-engineering"]},{"id":"edu","namespace":"x/d","ontologies":["edu-fixture"]}]}' > "$T/cfg.json"
  printf '{"@id":"c","entity":{"entity_type":"component","name":"AuthSvc","responsibility":"auth"}}\n' > "$T/comp.json"
  scripts/resolve-ontology.sh "$T/comp.json" --topic eng --catalog "$T/cat.json" --config "$T/cfg.json" --map "$T/eng.map" >/dev/null 2>&1; local pos=$?
  scripts/resolve-ontology.sh "$T/comp.json" --topic edu --catalog "$T/cat.json" --config "$T/cfg.json" --map "$T/edu.map" >/dev/null 2>&1; local neg=$?
  local ro; ro=$(jq -r '.[0].resolved_ontology' "$T/eng.map" 2>/dev/null)
  if [ "$pos" = 0 ] && [ "$ro" = "engineering-base@0.1.0" ] && [ "$neg" != 0 ]; then
    ok "transitive extends: a child topic resolves an ancestor-layer type; a non-engineering topic does NOT (engineering vocab stays out of the generic core)"
  else
    bad "spine boundary wrong (positive=$pos resolved=$ro negative=$neg — expect pos=0 ro=engineering-base@0.1.0 neg!=0)"
  fi
  rm -rf "$T"
}

gate_m22() {
  info "Milestone 22 — entity-type subsumption (enforced substitutability)"
  # `subtype_of` makes a finer type substitutable for its supertype at a relationship
  # endpoint (Liskov). software-security `security-control` subtype_of engineering-base
  # `control`; the cross-cutting `governs` edge (control/policy -> component/artifact)
  # must therefore ACCEPT a security-control source and REJECT a non-subtype source.
  # Also: every subtype_of parent across the registry must be a declared type.
  # software-security is a domain pack vendored on demand (ADR-0012/#224) and is not
  # in the always-enabled set, so this gate vendors its subtype_of exemplar itself.
  if [ ! -f packs/ontologies/software-security/software-security.ontology.yaml ]; then
    # Fail closed and surface fetch-ontology's own diagnostic: swallowing it (|| true)
    # lets a vendoring failure (offline / registry down / checksum mismatch) fall through
    # to a misleading "subsumption wrong" verdict below, hiding the real cause — exactly
    # the "a gate that hides its tool's error makes every failure undiagnosable" anti-pattern.
    if ! scripts/fetch-ontology.sh software-security; then
      bad "gate_m22: could not vendor software-security exemplar (fetch-ontology.sh failed — see error above)"
      return
    fi
  fi
  local T; T="$(mktemp -d)"
  cat > "$T/cat.json" <<'JSON'
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"shared-traits","version":"1.0.0","source":"schemas/ontologies/shared-traits/1.0.0.yaml","core":true},
 {"id":"engineering-base","version":"0.1.0","source":"schemas/ontologies/engineering-base/0.1.0.yaml","core":false},
 {"id":"software-security","version":"0.2.0","source":"packs/ontologies/software-security/software-security.ontology.yaml","core":false}
]}
JSON
  echo '{"topics":[{"id":"sec","namespace":"x/s","ontologies":["software-security"]}]}' > "$T/cfg.json"
  # node n2 = component (resolves via engineering-base ancestor), n1 = security-control,
  # n3 = malware (NOT a subtype of control). governs edge source varies.
  local nodes='[{"id":"n1","entityType":"security-control","topics":["sec"],"kind":"concept","external":false,"verdict":"survived"},{"id":"n2","entityType":"component","topics":["sec"],"kind":"concept","external":false,"verdict":"survived"},{"id":"n3","entityType":"malware","topics":["sec"],"kind":"concept","external":false,"verdict":"survived"}]'
  echo "{\"nodes\":$nodes,\"edges\":[{\"via\":\"relationship\",\"type\":\"governs\",\"source\":\"n1\",\"target\":\"n2\"}]}" > "$T/good.json"
  echo "{\"nodes\":$nodes,\"edges\":[{\"via\":\"relationship\",\"type\":\"governs\",\"source\":\"n3\",\"target\":\"n2\"}]}" > "$T/bad.json"
  vw22() { scripts/validate-concordance.sh "$1" --config "$T/cfg.json" --catalog "$T/cat.json" >/dev/null 2>&1; }
  vw22 "$T/good.json"; local g=$?
  vw22 "$T/bad.json"; local b=$?
  # subtype_of parent integrity across the whole registry. Since
  # research-harness-template#276 (Story #287), this whole-registry scan delegates to
  # the mif-rh engine (mif-rh-cli harness check-ontology-registry).
  local reg_out reg_err orphan
  reg_err="$T/m22-registry.err"
  reg_out=$("$ENGINE" harness check-ontology-registry --root "$(pwd)" 2>"$reg_err")
  if [ $? -gt 1 ]; then
    bad "check-ontology-registry errored (exit>1): $(cat "$reg_err")"
    rm -rf "$T"
    return
  fi
  orphan=$(printf '%s\n' "$reg_out" | sed -n 's/^ontology-registry: subtype_of-parent orphans: //p')
  if [ "$g" = 0 ] && [ "$b" != 0 ] && [ "$orphan" = "none" ]; then
    ok "subtype_of enforced: a security-control satisfies a control-typed edge; a non-subtype does not; every subtype_of parent is declared"
  else
    bad "subsumption wrong (substitutable-good=$g should=0; non-subtype-bad=$b should!=0; orphan-parents=[${orphan}])"
  fi
  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 23 — site projection (reports as a first-class Starlight surface +
# config-driven feature flags). The Astro/Starlight site renders reports/ for human
# reading; harness.config.json `.site` is the control plane astro.config.mjs reads at
# build time (so neither template nor clone hand-edits astro.config.mjs). The template
# serves the archived example topic (example-okf-mif-knowledge-spine; docs-primary) and
# a copier hook activates reports-primary in a clone.
# ---------------------------------------------------------------------------
gate_m23() {
  info "Milestone 23 — site projection (reports surface + feature flags)"

  # 23a. The content loader binds BOTH docs/ and reports/ into the single Starlight `docs`
  #      collection via a `glob()` WRAPPED to derive a Starlight title for reports/ deliverables
  #      that carry none (README, synthesis, falsification report, research-progress) — so the
  #      FULL topic deliverable tree renders (ADR-0009) instead of being excluded. The base
  #      stays `./src/content/docs` (the relative-links plugin relies on it) and reports/ is
  #      reached via the committed `docs/reports` symlink. README is re-slugged to the topic
  #      index. Only _meta/findings + the *-delta/*-build-spec build logs stay excluded.
  #      Regression guard: the three deliverable negations MUST be absent (so they serve), the
  #      loader markers + kept negations + both symlinks MUST be present.
  local cc=src/content.config.ts
  if grep -qF "glob(" "$cc" \
     && grep -qF "base: './src/content/docs'" "$cc" \
     && grep -qF "reportsLoader(" "$cc" \
     && grep -qF "deriveTitleFromH1" "$cc" \
     && grep -qF "generateId" "$cc" \
     && grep -qF "!reports/_meta/**" "$cc" \
     && grep -qF "!reports/**/findings/**" "$cc" \
     && grep -qF "!reports/**/*-delta.md" "$cc" \
     && grep -qF "!reports/**/*-build-spec.md" "$cc" \
     && ! grep -qF "!reports/**/README.md" "$cc" \
     && ! grep -qF "!reports/**/*-falsification-report.md" "$cc" \
     && ! grep -qF "!reports/**/research-progress.md" "$cc" \
     && [ "$(readlink docs/reports 2>/dev/null)" = "../reports" ] \
     && [ "$(readlink src/content/docs 2>/dev/null)" = "../../docs" ]; then
    ok "content.config.ts serves the full deliverable tree via the derived-title loader (README index re-slug; _meta/findings/build-log negations kept; the README/falsification/progress negations removed; both site symlinks)"
  else
    bad "reports binding regressed (need the reportsLoader/deriveTitleFromH1/generateId glob at base './src/content/docs', the README+falsification+research-progress negations REMOVED so they render, _meta/findings/*-delta/*-build-spec kept, and the docs/reports + src/content/docs symlinks)"
  fi

  # 23b. astro.config.mjs reads harness.config.json and GATES each site enhancement on
  #      .site.plugins / .site.primarySurface — integrations are config-driven, not hardcoded.
  #      It also builds the reports sidebar as ONE link per topic README index (reportTopics,
  #      not a per-report autogenerate tree), strips the duplicate body H1 of derived-title
  #      pages (remarkStripReportH1), and registers the Sidebar override that adds the topic
  #      filter. The override component must exist.
  local ac=astro.config.mjs
  if grep -qF "harness.config.json" "$ac" \
     && grep -qF "primarySurface" "$ac" \
     && grep -qF "plugins.mermaid" "$ac" \
     && grep -qF "plugins.llmsTxt" "$ac" \
     && grep -qF "plugins.imageZoom" "$ac" \
     && grep -qF "plugins.linksValidator" "$ac" \
     && grep -qF "remarkStripReportH1" "$ac" \
     && grep -qF "reportTopics(" "$ac" \
     && grep -qF "Sidebar:" "$ac" \
     && [ -f src/components/Sidebar.astro ]; then
    ok "astro.config.mjs gates site plugins + primarySurface, builds an index-only reports sidebar (reportTopics), strips derived-title H1, and registers the Sidebar filter override"
  else
    bad "astro.config.mjs must read harness.config.json, gate each site plugin + primarySurface, build the index-only reports sidebar (reportTopics), strip the derived-title H1 (remarkStripReportH1), and register src/components/Sidebar.astro"
  fi

  # 23c. The manifest (with the optional .site block) validates against the schema.
  if ajv_plain harness.config.schema.json harness.config.json; then
    ok "harness.config.json validates against its schema (incl. the site block)"
  else
    bad "harness.config.json does not validate against harness.config.schema.json"
  fi

  # 23d. Template-only invariants: the template serves the single archived example
  #      research topic straight out of reports/ (example-okf-mif-knowledge-spine — its
  #      findings + rendered genre reports) so the reports surface is demonstrated, yet
  #      stays docs-primary, and the copier hook activates reports-primary in a clone.
  #      gate 8c enforces reports/ ships only this example topic + _meta scaffolding.
  if [ "$IS_TEMPLATE" = 1 ]; then
    if [ -f reports/example-okf-mif-knowledge-spine/README.md ] \
       && ls reports/example-okf-mif-knowledge-spine/report-*.md >/dev/null 2>&1; then
      ok "template serves the archived example topic (example-okf-mif-knowledge-spine: README + genre reports)"
    else
      bad "template must serve the example topic (reports/example-okf-mif-knowledge-spine/{README.md,report-*.md})"
    fi
    # The full deliverable tree renders: synthesis, falsification report, and research-progress
    # each exist and start with an H1, so the derived-title loader gives them a Starlight title
    # (they are no longer excluded). This is the positive counterpart to the 23a negation removal.
    local edir=reports/example-okf-mif-knowledge-spine all_titled=1
    for d in "$edir"/synthesis-*.md "$edir"/*-falsification-report.md "$edir"/research-progress.md; do
      { [ -f "$d" ] && grep -qE '^#[[:space:]]+' "$d"; } || all_titled=0
    done
    if [ "$all_titled" = 1 ]; then
      ok "template serves the full deliverable tree (synthesis + falsification report + research-progress each render via a derivable H1 title)"
    else
      bad "example topic deliverables must each exist with an H1 so the derived-title loader renders them (synthesis, falsification report, research-progress)"
    fi
    if [ "$(jq -r '.site.primarySurface // empty' harness.config.json)" = "docs" ]; then
      ok "template pins site.primarySurface = docs (docs-primary despite shipping the example report)"
    else
      bad "template site.primarySurface must be 'docs' (the example report would otherwise auto-flip it to reports)"
    fi
    if grep -A3 '_tasks:' copier.yml | grep -qF "site-toggle.sh primary reports"; then
      ok "copier _tasks activates reports-primary in a clone (site-toggle.sh primary reports)"
    else
      bad "copier.yml must run 'site-toggle.sh primary reports' in _tasks to activate the clone reports surface"
    fi
    # 23f. The org Pages auto-redeploy is wired: docs.yml fires the source-updated
    #      repository_dispatch the org Pages deploy listens for (so a merge republishes).
    #      Template-only — a clone excludes .github/workflows/ (copier _exclude).
    if grep -qF "event_type=source-updated" .github/workflows/docs.yml \
       && grep -qF "modeled-information-format.github.io/dispatches" .github/workflows/docs.yml; then
      ok "docs.yml notifies the org Pages to redeploy on push (source-updated dispatch)"
    else
      bad "docs.yml must dispatch source-updated to the org Pages repo so a merge auto-republishes"
    fi
  fi

  # 23e. The Reports surface has a stable landing the splash and sidebar point at: the
  #      /reports/ index page (empty-safe, lists the instance's own report topics) and a
  #      splash link to it. Runs in both contexts (src/, docs/, astro.config travel to
  #      clones). Guards against the landing being unreachable from `/`.
  if [ -f src/pages/reports.astro ] \
     && grep -qF "link: /reports/" docs/index.mdx \
     && grep -qF 'link: "/reports/"' astro.config.mjs; then
    ok "reports landing surfaced: /reports/ index page + splash link + sidebar Overview"
  else
    bad "reports landing not surfaced (need src/pages/reports.astro, a docs/index.mdx link to /reports/, and the sidebar Overview link)"
  fi
}

gate_m24() {
  info "Milestone 24 — fail-closed ontology-completeness gate + auto-reconciled spine (ADR-0011)"
  local T; T="$(mktemp -d)"
  mkdir -p "$T/reports/edu/findings"
  # A shippable (survived) but UNTYPED finding + its untyped map record.
  cat > "$T/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"Untyped survivor","extensions":{"harness":{"dimension":"d","verification":{"verdict":"survived","verdict_basis":"x"}}}}
JSON
  echo '[{"finding_id":"urn:mif:concept:x/edu:f1","entity_type":null,"resolved_ontology":null,"basis":"untyped","valid":true}]' > "$T/reports/edu/ontology-map.json"

  # 24a. An untyped shippable finding BLOCKS synthesis (exit 1) and points to /ontology-review.
  local msg rc
  msg=$(scripts/check-shippable-typing.sh "$T/reports/edu" 2>&1); rc=$?
  if [ "$rc" = 1 ] && printf '%s' "$msg" | grep -q "/ontology-review"; then
    ok "an untyped shippable finding blocks synthesis (fail closed) and points to /ontology-review --enrich"
  else
    bad "untyped shippable finding did not block (rc=$rc)"
  fi

  # 24a-ii. A shippable finding whose ontology-map record is basis:"discovery" (a
  #         content-pattern GUESS resolve-ontology.sh never wrote back to the finding
  #         itself — no real entity block on disk) MUST block exactly like untyped, not
  #         pass vacuously just because valid==true. This is the gap the discovery-
  #         followup fix closes: previously $r.basis was only checked against
  #         "untyped"/"unresolved", so a discovery-only shippable finding shipped with
  #         no durable ontology stamp.
  echo '[{"finding_id":"urn:mif:concept:x/edu:f1","entity_type":"title","resolved_ontology":"edu-fixture@0.1.0","basis":"discovery","valid":true}]' > "$T/reports/edu/ontology-map.json"
  jq '.extensions.harness.verification.verdict="survived"' "$T/reports/edu/findings/f1.json" > "$T/f.tmp" && mv "$T/f.tmp" "$T/reports/edu/findings/f1.json"
  local dmsg drc
  dmsg=$(scripts/check-shippable-typing.sh "$T/reports/edu" 2>&1); drc=$?
  if [ "$drc" = 1 ] && printf '%s' "$dmsg" | grep -q "discovery"; then
    ok "a discovery-only (unstamped) shippable finding blocks synthesis (fail closed), not just untyped/unresolved"
  else
    bad "discovery-only shippable finding did not block (rc=$drc, msg='$dmsg')"
  fi
  echo '[{"finding_id":"urn:mif:concept:x/edu:f1","entity_type":null,"resolved_ontology":null,"basis":"untyped","valid":true}]' > "$T/reports/edu/ontology-map.json"

  # 24b. The SAME finding FALSIFIED does NOT block (only survived|weakened gate).
  jq '.extensions.harness.verification.verdict="falsified"' "$T/reports/edu/findings/f1.json" > "$T/f.tmp" && mv "$T/f.tmp" "$T/reports/edu/findings/f1.json"
  if scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; then
    ok "a falsified untyped finding does not block synthesis (only shippable verdicts gate)"
  else
    bad "a falsified finding wrongly blocked synthesis"
  fi

  # 24c. A fully-typed shippable corpus PASSES the gate, and the spine builds + conforms
  #      (reuse the gate_m13 catalog/cfg fixture shape: edu->edu-fixture, a 'title' belongs_to a 'program').
  local T2; T2="$(mktemp -d)"
  cat > "$T2/cat.json" <<JSON
{"ontologies":[
 {"id":"mif-generic","version":"1.0.0","source":"schemas/ontologies/mif-generic/1.0.0.yaml","core":true},
 {"id":"mif-base","version":"1.0.0","source":"schemas/ontologies/mif-base/1.0.0.yaml","core":true},
 {"id":"shared-traits","version":"1.0.0","source":"schemas/ontologies/shared-traits/1.0.0.yaml","core":true},
 {"id":"edu-fixture","version":"0.1.0","source":"evals/fixtures/ontology/edu-fixture.ontology.yaml","core":false}
]}
JSON
  echo '{"topics":[{"id":"edu","namespace":"x/edu","ontologies":["edu-fixture"]}]}' > "$T2/cfg.json"
  mkdir -p "$T2/reports/edu/findings"
  cat > "$T2/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"Algebra textbook","entity":{"name":"Algebra I","entity_type":"title"},"entities":[{"@type":"EntityReference","entity":{"@id":"urn:mif:entity:prog:math"},"name":"Math","entityType":"program"}],"relationships":[{"type":"belongs_to","target":"urn:mif:entity:prog:math","strength":1}],"extensions":{"harness":{"dimension":"d","verification":{"verdict":"survived","verdict_basis":"x"}}}}
JSON
  echo '[{"finding_id":"urn:mif:concept:x/edu:f1","entity_type":"title","resolved_ontology":"edu-fixture@0.1.0","basis":"declared","valid":true}]' > "$T2/reports/edu/ontology-map.json"
  scripts/build-concordance.sh "$T2/reports" "$T2/concordance.json" >/dev/null 2>&1
  if scripts/check-shippable-typing.sh "$T2/reports/edu" >/dev/null 2>&1 \
     && [ -f "$T2/concordance.json" ] && ajv_plain schemas/concordance.schema.json "$T2/concordance.json" \
     && scripts/validate-concordance.sh "$T2/concordance.json" --config "$T2/cfg.json" --catalog "$T2/cat.json" >/dev/null 2>&1; then
    ok "a fully-typed shippable corpus passes the gate and its concordance builds + conforms"
  else
    bad "typed corpus path failed (gate/build/validate-concordance)"
  fi
  rm -rf "$T2"

  # 24d. Wiring (static): orchestrator Phase 4 runs the typing gate + builds/validates the
  #      spine BEFORE spawning the synthesizer (the gate is useless if synthesis can bypass it).
  local lg lb lv lsynth
  lg=$(grep -n 'check-shippable-typing.sh' .claude/agents/orchestrator.md | head -1 | cut -d: -f1)
  lb=$(grep -n 'build-concordance.sh' .claude/agents/orchestrator.md | head -1 | cut -d: -f1)
  lv=$(grep -n 'validate-concordance.sh' .claude/agents/orchestrator.md | head -1 | cut -d: -f1)
  lsynth=$(grep -n 'subagent_type: "report-synthesizer"' .claude/agents/orchestrator.md | head -1 | cut -d: -f1)
  if [ -n "$lg" ] && [ -n "$lb" ] && [ -n "$lv" ] && [ -n "$lsynth" ] \
     && [ "$lg" -lt "$lsynth" ] && [ "$lb" -lt "$lsynth" ] && [ "$lv" -lt "$lsynth" ]; then
    ok "orchestrator Phase 4 runs the typing gate + concordance build/validate before spawning the synthesizer"
  else
    bad "orchestrator does not wire the typing gate + spine before synthesis (gate=$lg build=$lb val=$lv synth=$lsynth)"
  fi

  # 24e. An UNPARSEABLE finding fails closed (blocks), not silently skipped — its
  #      verdict/type are unknowable. f1 is set falsified (skipped) so the corrupt file is
  #      the only variable under test; the map from 24a still exists so the gate reaches the loop.
  cat > "$T/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"falsified","extensions":{"harness":{"verification":{"verdict":"falsified"}}}}
JSON
  printf '{ not valid json ' > "$T/reports/edu/findings/corrupt.json"
  if ! scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; then
    ok "an unparseable shippable-or-unknown finding fails closed (blocks), not silently skipped"
  else
    bad "an unparseable finding did not block — fail-open hole in the fail-closed gate"
  fi

  # 24f. A present-but-UNPARSEABLE ontology-map.json fails closed (cannot prove typing), not
  #      vacuously pass. Without the map-parse guard, every per-finding lookup errors to "" so a
  #      shippable survivor would PASS — the exact vacuous-pass class this gate exists to refuse.
  cat > "$T/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"survivor","extensions":{"harness":{"verification":{"verdict":"survived"}}}}
JSON
  rm -f "$T/reports/edu/findings/corrupt.json"
  printf '[ { not valid json ' > "$T/reports/edu/ontology-map.json"
  if ! scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; then
    ok "a present-but-unparseable ontology-map fails closed (cannot prove typing), not vacuously pass"
  else
    bad "a corrupt ontology-map passed the gate vacuously — fail-open hole in the fail-closed gate"
  fi

  # 24g. Discovery scans the flat reports/<topic>/finding-*.json layout too (matching
  #      reconcile-session.sh's list_findings) — a flat untyped survivor is gated, not bypassed.
  rm -f "$T/reports/edu/findings/f1.json"
  echo '[{"finding_id":"urn:mif:concept:x/edu:flat","entity_type":null,"resolved_ontology":null,"basis":"untyped","valid":true}]' > "$T/reports/edu/ontology-map.json"
  cat > "$T/reports/edu/finding-flat.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:flat","title":"flat untyped survivor","extensions":{"harness":{"verification":{"verdict":"survived"}}}}
JSON
  if ! scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; then
    ok "a flat reports/<topic>/finding-*.json is gated too (union discovery; cannot bypass)"
  else
    bad "a flat finding-*.json bypassed the typing gate (discovery divergence from reconcile)"
  fi
  rm -f "$T/reports/edu/finding-flat.json"

  # 24h. A valid-JSON but wrong-SHAPE ontology-map (not a record array) fails closed too —
  #      a `type=="array"` guard, not just a parse check, since a non-array errors every lookup.
  echo '{"not":"an array"}' > "$T/reports/edu/ontology-map.json"
  cat > "$T/reports/edu/findings/f1.json" <<'JSON'
{"@id":"urn:mif:concept:x/edu:f1","title":"survivor","extensions":{"harness":{"verification":{"verdict":"survived"}}}}
JSON
  scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; rc=$?
  if [ "$rc" = 3 ]; then
    ok "a wrong-shape (non-array) ontology-map fails closed (exit 3), not vacuously pass"
  else
    bad "a wrong-shape ontology-map did not fail closed (rc=$rc)"
  fi

  # 24i. The exit-3 (unreadable map) path prints the SAME /ontology-review unblock footer as
  #      the exit-1 blocker — the operator needs the remediation most when the map can't be read.
  rm -f "$T/reports/edu/ontology-map.json"
  m3=$(scripts/check-shippable-typing.sh "$T/reports/edu" 2>&1); rc3=$?
  if [ "$rc3" = 3 ] && printf '%s' "$m3" | grep -q "/ontology-review"; then
    ok "the exit-3 (unreadable map) path names the /ontology-review unblock footer"
  else
    bad "exit-3 path missing the /ontology-review unblock footer (rc=$rc3)"
  fi

  # 24j. A shippable finding with NO @id blocks AND names the FILE in the blocker line (not a
  #      bare empty id), so the operator can locate exactly the file to fix.
  echo '[]' > "$T/reports/edu/ontology-map.json"
  rm -f "$T/reports/edu/findings/f1.json"
  echo '{"title":"no id","extensions":{"harness":{"verification":{"verdict":"survived"}}}}' > "$T/reports/edu/findings/noid.json"
  mj=$(scripts/check-shippable-typing.sh "$T/reports/edu" 2>&1); rcj=$?
  if [ "$rcj" = 1 ] && printf '%s' "$mj" | grep -q "noid.json"; then
    ok "a no-@id shippable finding blocks and names the file (not a bare empty id)"
  else
    bad "no-@id blocker did not name the file (rc=$rcj)"
  fi

  # 24k. A flat-only layout (reports/<topic>/finding-*.json, NO findings/ subdir) is gated, not
  #      rejected with exit 2 — discovery matches reconcile's list_findings (which needs no findings/).
  rm -rf "$T/reports/edu/findings"
  echo '[{"finding_id":"urn:mif:concept:x/edu:flat","entity_type":null,"resolved_ontology":null,"basis":"untyped","valid":true}]' > "$T/reports/edu/ontology-map.json"
  echo '{"@id":"urn:mif:concept:x/edu:flat","extensions":{"harness":{"verification":{"verdict":"survived"}}}}' > "$T/reports/edu/finding-flat.json"
  scripts/check-shippable-typing.sh "$T/reports/edu" >/dev/null 2>&1; rck=$?
  if [ "$rck" = 1 ]; then
    ok "a flat-only layout (no findings/ subdir) is gated (exit 1), not rejected with exit 2"
  else
    bad "flat-only layout not gated (rc=$rck; want 1)"
  fi

  # 24l. reconcile's untyped_shippable mirrors the gate: an UNPARSEABLE finding is counted (the
  #      gate blocks it), so state.json never reports 0 while synthesis is actually withheld.
  rm -f "$T/reports/edu/finding-flat.json"
  mkdir -p "$T/reports/edu/findings"
  printf '{ not valid json ' > "$T/reports/edu/findings/corrupt.json"
  echo '[]' > "$T/reports/edu/ontology-map.json"
  echo '{"@type":"Concordance","nodes":[],"edges":[]}' > "$T/reports/concordance.json"
  scripts/reconcile-session.sh "$T/reports/edu" >/dev/null 2>&1
  if [ "$(jq -r '.concordance.untyped_shippable' "$T/reports/edu/state.json" 2>/dev/null)" = "1" ]; then
    ok "reconcile untyped_shippable counts an unparseable finding (matches the gate's fail-closed block)"
  else
    bad "reconcile undercounted an unparseable finding vs the gate"
  fi

  # 24m. reconcile's untyped_shippable ALSO counts a discovery-only (guessed, unstamped)
  #      shippable finding — mirrors the gate's 24a-ii fix; a valid==true discovery record
  #      must not read as 0 while the gate itself would block it.
  rm -f "$T/reports/edu/findings/corrupt.json"
  printf '{"@id":"urn:mif:concept:x/edu:disc","extensions":{"harness":{"verification":{"verdict":"survived"}}}}' > "$T/reports/edu/findings/disc.json"
  echo '[{"finding_id":"urn:mif:concept:x/edu:disc","entity_type":"title","resolved_ontology":"edu-fixture@0.1.0","basis":"discovery","valid":true}]' > "$T/reports/edu/ontology-map.json"
  scripts/reconcile-session.sh "$T/reports/edu" >/dev/null 2>&1
  if [ "$(jq -r '.concordance.untyped_shippable' "$T/reports/edu/state.json" 2>/dev/null)" = "1" ]; then
    ok "reconcile untyped_shippable also counts a discovery-only (unstamped) shippable finding"
  else
    bad "reconcile undercounted a discovery-only shippable finding vs the gate"
  fi

  rm -rf "$T"
}

gate_m25() {
  info "Milestone 25 — cross-topic corpus atlas (synthesize-corpus.sh)"
  local T; T="$(mktemp -d)"; mkdir -p "$T/reports"
  cat > "$T/reports/concordance.json" <<'JSON'
{"@type":"Concordance","nodes":[
 {"id":"urn:mif:concept:a:f1","kind":"concept","label":"Claim one","topics":["a"],"entityType":"concept","ontology":"mif-generic@1.0.0","verdict":"survived","flagged":false},
 {"id":"urn:mif:concept:b:f2","kind":"concept","label":"Disproven claim","topics":["b"],"entityType":"concept","ontology":"mif-generic@1.0.0","verdict":"falsified","flagged":true},
 {"id":"urn:mif:entity:org:acme","kind":"entity","label":"Acme","entityType":"organization","topics":["a","b"]}
],"edges":[
 {"source":"urn:mif:concept:a:f1","target":"urn:mif:concept:b:f2","type":"contradicts","via":"relationship","strength":0.7},
 {"source":"urn:mif:concept:a:f1","target":"urn:mif:entity:org:acme","type":"mentions","via":"entity","strength":null},
 {"source":"urn:mif:concept:b:f2","target":"urn:mif:entity:org:acme","type":"mentions","via":"entity","strength":null}
]}
JSON
  scripts/synthesize-corpus.sh "$T/reports" >/dev/null 2>&1

  # 25a. corpus-map projects topics, verdict distribution, cross-topic entity reuse,
  #      contradictions, and the FULL record (falsified flagged as disproven, not excluded).
  local got
  got=$(jq -rc '{t:(.topics|sort), v:.verdict_distribution, e:[.entity_reuse[]|{l:.label,tc:.topic_count,d:.degree}], c:[.contradictions[].type], dp:[.disproven[].label]}' "$T/reports/_corpus/corpus-map.json" 2>/dev/null)
  if [ "$got" = '{"t":["a","b"],"v":{"falsified":1,"survived":1},"e":[{"l":"Acme","tc":2,"d":2}],"c":["contradicts"],"dp":["Disproven claim"]}' ]; then
    ok "corpus-map projects topics, verdicts, cross-topic entity reuse, contradictions, and the disproven record"
  else
    bad "corpus-map projection wrong: $got"
  fi

  # 25b. The atlas keeps the WHOLE record — a falsified finding appears under What Was Disproven
  #      (the per-topic synthesizer drops it; the atlas must not).
  if grep -qF "## What Was Disproven" "$T/reports/_corpus/corpus-synthesis.md" \
     && grep -qF "Disproven claim" "$T/reports/_corpus/corpus-synthesis.md"; then
    ok "the atlas surfaces the falsified finding under 'What Was Disproven' (full-record, not survivors-only)"
  else
    bad "the atlas dropped the disproven finding"
  fi

  # 25c. Deterministic: two builds byte-identical (no wall-clock).
  cp "$T/reports/_corpus/corpus-map.json" "$T/m1"; cp "$T/reports/_corpus/corpus-synthesis.md" "$T/d1"
  scripts/synthesize-corpus.sh "$T/reports" >/dev/null 2>&1
  if diff -q "$T/m1" "$T/reports/_corpus/corpus-map.json" >/dev/null 2>&1 \
     && diff -q "$T/d1" "$T/reports/_corpus/corpus-synthesis.md" >/dev/null 2>&1; then
    ok "synthesize-corpus is deterministic (two builds byte-identical)"
  else
    bad "synthesize-corpus is not deterministic"
  fi

  # 25d. --check is fail-closed on the seeded draft, passes once Insights are authored, and the
  #      build fails closed when the concordance is missing.
  local rc_draft rc_auth rc_miss
  scripts/synthesize-corpus.sh "$T/reports" --check >/dev/null 2>&1; rc_draft=$?
  awk '/_Draft/{print "- Authored cross-topic insight."; next} {print}' "$T/reports/_corpus/corpus-synthesis.md" > "$T/auth.md" && mv "$T/auth.md" "$T/reports/_corpus/corpus-synthesis.md"
  scripts/synthesize-corpus.sh "$T/reports" --check >/dev/null 2>&1; rc_auth=$?
  rm -f "$T/reports/concordance.json"; scripts/synthesize-corpus.sh "$T/reports" >/dev/null 2>&1; rc_miss=$?
  if [ "$rc_draft" != 0 ] && [ "$rc_auth" = 0 ] && [ "$rc_miss" != 0 ]; then
    ok "--check fails on the draft, passes once authored; build fails closed on a missing concordance"
  else
    bad "corpus --check/fail-closed wrong (draft=$rc_draft auth=$rc_auth miss=$rc_miss)"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 26 — MIF Container manifest schema (Epic #275, Story #308)
# ---------------------------------------------------------------------------
gate_m26() {
  info "Milestone 26 — MIF Container manifest schema (schemas/mif-container.schema.json)"
  local T; T="$(mktemp -d)"

  # 26a. The schema validates a full-export sample (resources + an ontology binding,
  #      an EMPTY boundaryReferences[] -- required and present, not omitted, but
  #      empty because a full export excludes nothing by definition), a
  #      zero-finding-topic sample (empty resources[]/boundaryReferences[], feature-spec
  #      edge case "Zero-finding topic exported"), and a subset-export sample carrying
  #      the boundaryReferences[] example (AC6/AC7).
  if ajv_plain schemas/mif-container.schema.json schemas/samples/mif-container-full.sample.json; then
    ok "mif-container schema validates a full-export sample manifest"
  else
    bad "mif-container schema does not validate the full-export sample"
  fi
  if ajv_plain schemas/mif-container.schema.json schemas/samples/mif-container-empty.sample.json; then
    ok "mif-container schema validates a zero-resource (empty topic) sample manifest"
  else
    bad "mif-container schema does not validate the zero-resource sample"
  fi
  if ajv_plain schemas/mif-container.schema.json schemas/samples/mif-container-subset.sample.json; then
    ok "mif-container schema validates a subset-export sample manifest carrying a boundaryReferences[] entry"
  else
    bad "mif-container schema does not validate the subset-export sample"
  fi

  # 26b. Fail-closed at the structural level (feature-spec AC9): an unrecognized
  #      profile value, and a manifest missing its mandatory manifestDigest, must
  #      each be independently rejected -- never accepted as best-effort.
  jq '.profile = "https://example.org/some-other-profile/v9"' \
    schemas/samples/mif-container-full.sample.json > "$T/bad-profile.json"
  jq 'del(.manifestDigest)' \
    schemas/samples/mif-container-full.sample.json > "$T/bad-digest.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/bad-profile.json"; then
    ok "mif-container schema fails closed on an unrecognized profile value"
  else
    bad "mif-container schema accepted an unrecognized profile value"
  fi
  if ! ajv_plain schemas/mif-container.schema.json "$T/bad-digest.json"; then
    ok "mif-container schema fails closed on a missing manifestDigest"
  else
    bad "mif-container schema accepted a manifest missing manifestDigest"
  fi

  # 26c. Regression coverage for three review-caught structural loopholes (a schema
  #      that only ever validated its own intended-good fixtures would not have
  #      caught any of these): a null selector must not satisfy subset's "selector
  #      required" clause; a resource's mifType and ontologyType must be coupled, not
  #      independently free; and a full export must not carry a boundaryReferences[]
  #      entry.
  jq '.exportScope.selector = null' \
    schemas/samples/mif-container-subset.sample.json > "$T/subset-null-selector.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/subset-null-selector.json"; then
    ok "mif-container schema rejects a subset export with a null selector (not just an absent one)"
  else
    bad "mif-container schema accepted a subset export with selector: null"
  fi

  jq '.resources[0].ontologyType = null' \
    schemas/samples/mif-container-full.sample.json > "$T/finding-null-ontology-type.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/finding-null-ontology-type.json"; then
    ok "mif-container schema requires a non-null ontologyType on a finding resource"
  else
    bad "mif-container schema accepted a finding resource with ontologyType: null"
  fi

  jq '.resources[1].mifType = "concordance" | .resources[1].ontologyType = "concept"' \
    schemas/samples/mif-container-full.sample.json > "$T/concordance-nonnull-ontology-type.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/concordance-nonnull-ontology-type.json"; then
    ok "mif-container schema forbids a non-null ontologyType on an ontology-map/concordance resource"
  else
    bad "mif-container schema accepted a concordance resource with a non-null ontologyType"
  fi

  # An ontology-map/concordance resource that OMITS ontologyType entirely must be
  # rejected too, not just one carrying an explicit non-null value -- the field's
  # own description claims it "must be null ... enforced below, not just
  # descriptively," which is false unless ontologyType is also required.
  jq 'del(.resources[1].ontologyType)' \
    schemas/samples/mif-container-full.sample.json > "$T/ontology-map-missing-ontology-type.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/ontology-map-missing-ontology-type.json"; then
    ok "mif-container schema requires ontologyType (as null) on an ontology-map/concordance resource, not just its non-null value"
  else
    bad "mif-container schema accepted an ontology-map resource omitting ontologyType entirely"
  fi

  jq '.exportScope.type = "full" | .exportScope.selector = null' \
    schemas/samples/mif-container-subset.sample.json > "$T/full-with-boundary-refs.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/full-with-boundary-refs.json"; then
    ok "mif-container schema rejects a full export carrying a boundaryReferences[] entry"
  else
    bad "mif-container schema accepted a full export with a non-empty boundaryReferences[]"
  fi

  # Copilot review on PR #368 caught three more structural loopholes: boundaryReferences
  # was optional at the top level, so a full export could omit it entirely and never hit
  # the maxItems:0 constraint; exportScope.selector's description claimed "null for
  # full/incremental" but nothing enforced it; and resources[].path had no traversal/
  # absolute-path guard despite being a future write-target for import.
  jq 'del(.boundaryReferences)' \
    schemas/samples/mif-container-full.sample.json > "$T/full-omits-boundary-refs.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/full-omits-boundary-refs.json"; then
    ok "mif-container schema rejects a manifest that omits boundaryReferences entirely (not just a non-empty one)"
  else
    bad "mif-container schema accepted a manifest omitting boundaryReferences"
  fi

  jq '.exportScope.selector = "should-not-be-allowed"' \
    schemas/samples/mif-container-full.sample.json > "$T/full-nonnull-selector.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/full-nonnull-selector.json"; then
    ok "mif-container schema rejects a non-null selector on a full/incremental export"
  else
    bad "mif-container schema accepted a non-null selector on a full export"
  fi

  jq '.resources[0].path = "../../etc/passwd"' \
    schemas/samples/mif-container-full.sample.json > "$T/path-traversal.json"
  jq '.resources[0].path = "/abs/path.json"' \
    schemas/samples/mif-container-full.sample.json > "$T/path-absolute.json"
  if ! ajv_plain schemas/mif-container.schema.json "$T/path-traversal.json" \
     && ! ajv_plain schemas/mif-container.schema.json "$T/path-absolute.json"; then
    ok "mif-container schema rejects a resource path containing '..' or an absolute path"
  else
    bad "mif-container schema accepted a directory-traversal or absolute resource path"
  fi

  # 26d. Coverage restored: a subset export whose selector matches zero resources is
  #      valid (an empty resources[] is not itself an error for a subset export, only
  #      the selector's own presence is required -- distinct from 26a's zero-finding
  #      FULL-export case).
  jq '.resources = [] | .boundaryReferences = []' \
    schemas/samples/mif-container-subset.sample.json > "$T/subset-zero-resources.json"
  if ajv_plain schemas/mif-container.schema.json "$T/subset-zero-resources.json"; then
    ok "mif-container schema validates a subset export whose selector matched zero resources"
  else
    bad "mif-container schema does not validate a zero-resource subset export"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 27 — MIF Container digest engine (Epic #275, Story #312)
# ---------------------------------------------------------------------------
gate_m27() {
  info "Milestone 27 — MIF Container digest engine (scripts/mif-container-digest.sh)"
  local T; T="$(mktemp -d)"

  # 27a. Per-resource digest: correct sha256, and deterministic (same file
  #      hashed twice yields the same digest).
  local d1 d2 expect_hex expect
  d1="$(scripts/mif-container-digest.sh resource schemas/samples/mif-container-full.sample.json)"
  d2="$(scripts/mif-container-digest.sh resource schemas/samples/mif-container-full.sample.json)"
  if command -v sha256sum >/dev/null 2>&1; then
    expect_hex="$(sha256sum schemas/samples/mif-container-full.sample.json | awk '{print $1}')"
  else
    expect_hex="$(shasum -a 256 schemas/samples/mif-container-full.sample.json | awk '{print $1}')"
  fi
  expect="sha256:${expect_hex}"
  if [ "$d1" = "$d2" ] && [ "$d1" = "$expect" ]; then
    ok "resource digest is deterministic and matches sha256sum/shasum directly"
  else
    bad "resource digest wrong or non-deterministic (d1=$d1 d2=$d2 expect=$expect)"
  fi

  # 27b. Content-sensitivity: a changed file produces a different digest.
  printf 'x' > "$T/a.txt"
  printf 'y' > "$T/b.txt"
  local da db
  da="$(scripts/mif-container-digest.sh resource "$T/a.txt")"
  db="$(scripts/mif-container-digest.sh resource "$T/b.txt")"
  if [ "$da" != "$db" ]; then
    ok "resource digest is content-sensitive (different bytes -> different digest)"
  else
    bad "resource digest did not change for different file content"
  fi

  # 27c. Manifest digest determinism (NFR-1, Task #314): two independently-built
  #      manifests over an identical resource set, presented in different orders,
  #      produce a byte-identical manifest digest.
  local m1 m2
  m1="$(printf 'sha256:aaaa\nsha256:bbbb\nsha256:cccc\n' | scripts/mif-container-digest.sh manifest)"
  m2="$(printf 'sha256:cccc\nsha256:aaaa\nsha256:bbbb\n' | scripts/mif-container-digest.sh manifest)"
  if [ "$m1" = "$m2" ]; then
    ok "manifest digest is order-independent (sorted before hashing, per NFR-1)"
  else
    bad "manifest digest depends on input order (m1=$m1 m2=$m2)"
  fi

  # 27d. Zero-finding topic (empty resources[]): the manifest digest is still
  #      defined, over the empty set -- matching schemas/samples/mif-container-
  #      empty.sample.json's manifestDigest (sha256 of the empty string).
  local mempty
  mempty="$(printf '' | scripts/mif-container-digest.sh manifest)"
  local expect_empty
  expect_empty="$(jq -r '.manifestDigest' schemas/samples/mif-container-empty.sample.json)"
  if [ "$mempty" = "$expect_empty" ]; then
    ok "manifest digest over zero resources matches the empty-topic sample fixture's manifestDigest"
  else
    bad "manifest digest over zero resources ($mempty) does not match the empty sample fixture ($expect_empty)"
  fi

  # 27e. Fail-closed: a missing file is a named error (exit != 0), never a
  #      silently-wrong or empty digest.
  scripts/mif-container-digest.sh resource "$T/does-not-exist.json" >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    ok "resource digest fails closed on a missing file (exit != 0)"
  else
    bad "resource digest did not fail on a missing file"
  fi

  # 27f. Fail-closed: a file that exists but can't be read (permission denied)
  #      must also be a named error, never the malformed "sha256:" (empty hex)
  #      line at exit 0 that a command-substitution-inside-printf swallow bug
  #      previously produced.
  local out rc
  printf 'x' > "$T/unreadable.txt"; chmod 000 "$T/unreadable.txt"
  out="$(scripts/mif-container-digest.sh resource "$T/unreadable.txt" 2>/dev/null)"; rc=$?
  chmod 644 "$T/unreadable.txt"
  if [ "$rc" -ne 0 ] && [ "$out" != "sha256:" ]; then
    ok "resource digest fails closed on an unreadable file (permission denied), not a malformed empty digest"
  else
    bad "resource digest did not fail closed on an unreadable file (rc=$rc out='$out')"
  fi

  # 27g. Extra positional arguments are rejected, not silently dropped -- a
  # `resource f1 f2` invocation must not quietly hash only f1.
  scripts/mif-container-digest.sh resource \
    schemas/samples/mif-container-full.sample.json \
    schemas/samples/mif-container-subset.sample.json >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    ok "resource digest rejects extra positional arguments instead of silently hashing only the first"
  else
    bad "resource digest silently accepted extra positional arguments"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Milestone 28 — MIF Container export-scope resolver (Epic #275, Story #315)
# ---------------------------------------------------------------------------
gate_m28() {
  info "Milestone 28 — MIF Container export-scope resolver (scripts/mif-container-resolve-scope.sh)"
  local T; T="$(mktemp -d)"
  local RESOLVE="scripts/mif-container-resolve-scope.sh"
  local GRAPH="reports/_meta/sample-session/knowledge-graph.json"

  # 28a. Full scope, no closure: every concept-to-concept relationship edge is
  #      already satisfied (no concept boundary references), but the entity-
  #      mention edges still surface as boundaryReferences -- entities are
  #      never a packageable resource, so both edge sources (relationships[]
  #      AND the entity/ontology-typed edges) get walked, per the feature-spec
  #      edge case that a marker omitted at either level reproduces the exact
  #      silent-drop failure AD-4 exists to prevent.
  printf '%s\n' '["urn:mif:concept:harness:kg-cookiecutter-0002","urn:mif:concept:harness:kg-copier-0001","urn:mif:concept:harness:kg-distribution-0003"]' > "$T/full-scope.json"
  local got
  got="$("$RESOLVE" "$GRAPH" "$T/full-scope.json" | jq -c '{resourceIds: (.resourceIds|sort), concept_boundaries: [.boundaryReferences[] | select(.target|test("^urn:mif:concept:"))], entity_boundary_count: [.boundaryReferences[] | select(.target|test("^urn:mif:entity:"))] | length}')"
  if [ "$got" = '{"resourceIds":["urn:mif:concept:harness:kg-cookiecutter-0002","urn:mif:concept:harness:kg-copier-0001","urn:mif:concept:harness:kg-distribution-0003"],"concept_boundaries":[],"entity_boundary_count":4}' ]; then
    ok "full scope: all concept relationships satisfied, entity mentions still walked and marked"
  else
    bad "full scope result wrong: $got"
  fi

  # 28b. Partial scope, no closure: a referenced-but-out-of-scope concept
  #      becomes an explicit boundaryReferences[] entry, never silently
  #      dropped -- resourceIds stays exactly the initial set.
  printf '%s\n' '["urn:mif:concept:harness:kg-cookiecutter-0002"]' > "$T/partial-scope.json"
  got="$("$RESOLVE" "$GRAPH" "$T/partial-scope.json" | jq -c '{resourceIds, out_of_scope: [.boundaryReferences[] | select(.reason=="out-of-scope" and (.target|test("^urn:mif:concept:")))]}')"
  if [ "$got" = '{"resourceIds":["urn:mif:concept:harness:kg-cookiecutter-0002"],"out_of_scope":[{"target":"urn:mif:concept:harness:kg-copier-0001","reason":"out-of-scope"}]}' ]; then
    ok "partial scope without closure marks the excluded concept as an out-of-scope boundary reference"
  else
    bad "partial-scope-no-closure result wrong: $got"
  fi

  # 28c. Partial scope WITH --closure: dependency closure takes precedence
  #      over marking (AD-4) -- the resolver transitively expands scope to
  #      every concept reachable via relationship edges, so kg-copier-0001 is
  #      now INCLUDED, not marked. Entity mentions are still never closure-
  #      included (not a packageable resource) and remain boundary references.
  got="$("$RESOLVE" "$GRAPH" "$T/partial-scope.json" --closure | jq -c '{resourceIds: (.resourceIds|sort), concept_boundaries: [.boundaryReferences[] | select(.target|test("^urn:mif:concept:"))]}')"
  if [ "$got" = '{"resourceIds":["urn:mif:concept:harness:kg-cookiecutter-0002","urn:mif:concept:harness:kg-copier-0001","urn:mif:concept:harness:kg-distribution-0003"],"concept_boundaries":[]}' ]; then
    ok "closure expands scope to every transitively-reachable concept, closure takes precedence over marking (AD-4)"
  else
    bad "closure expansion result wrong: $got"
  fi

  # 28d/28e. Reason classification: a different-namespace concept id is
  #      "cross-topic" even though it can never appear as a node in a single-
  #      topic graph (build-graph.sh only ever sees one topic); a same-
  #      namespace id that simply isn't a node anywhere is "unresolvable".
  #      The namespace check MUST run before the node-presence check, or
  #      every cross-topic reference misclassifies as unresolvable (a real
  #      bug this suite caught and fixed during development).
  jq '.edges += [
        {"source":"urn:mif:concept:harness:kg-cookiecutter-0002","target":"urn:mif:concept:other-topic:some-finding","type":"supports","strength":0.5,"via":"relationship"},
        {"source":"urn:mif:concept:harness:kg-cookiecutter-0002","target":"urn:mif:concept:harness:does-not-exist","type":"supports","strength":0.5,"via":"relationship"}
      ]' "$GRAPH" > "$T/graph-edge-cases.json"
  got="$("$RESOLVE" "$T/graph-edge-cases.json" "$T/partial-scope.json" | jq -c '[.boundaryReferences[] | select(.target=="urn:mif:concept:other-topic:some-finding" or .target=="urn:mif:concept:harness:does-not-exist") | {target, reason}] | sort_by(.target)')"
  if [ "$got" = '[{"target":"urn:mif:concept:harness:does-not-exist","reason":"unresolvable"},{"target":"urn:mif:concept:other-topic:some-finding","reason":"cross-topic"}]' ]; then
    ok "boundary reason classifies a different-namespace target as cross-topic and a same-namespace missing target as unresolvable"
  else
    bad "boundary reason classification wrong: $got"
  fi

  # 28f. Zero in-scope findings (a subset selector matching nothing) is valid,
  #      not an error -- empty resourceIds[] and boundaryReferences[].
  printf '[]\n' > "$T/empty-scope.json"
  got="$("$RESOLVE" "$GRAPH" "$T/empty-scope.json" | jq -c .)"
  if [ "$got" = '{"resourceIds":[],"boundaryReferences":[]}' ]; then
    ok "an empty in-scope set resolves to empty resourceIds and boundaryReferences, not an error"
  else
    bad "empty-scope result wrong: $got"
  fi

  # 28g. Fail-closed: missing arguments, a missing graph file, and a
  #      malformed (non-array) ids file are named errors (exit != 0), never a
  #      silent empty/wrong result.
  "$RESOLVE" >/dev/null 2>&1
  local rc_noargs=$?
  "$RESOLVE" "$T/does-not-exist.json" "$T/full-scope.json" >/dev/null 2>&1
  local rc_missing=$?
  printf '{}\n' > "$T/bad-ids.json"
  "$RESOLVE" "$GRAPH" "$T/bad-ids.json" >/dev/null 2>&1
  local rc_badids=$?
  if [ "$rc_noargs" -ne 0 ] && [ "$rc_missing" -ne 0 ] && [ "$rc_badids" -ne 0 ]; then
    ok "resolver fails closed on missing arguments, a missing graph file, and a non-array ids file"
  else
    bad "resolver did not fail closed (rc_noargs=$rc_noargs rc_missing=$rc_missing rc_badids=$rc_badids)"
  fi

  # 28h. Regression: a graph missing .edges[] must fail fast (a named error),
  #      never hang. A prior version of this resolver's --closure fixpoint
  #      loop looped forever on this exact input: a failed jq call left
  #      new_count empty, and comparing an empty string with -eq threw a
  #      bash arithmetic error on every pass without ever breaking the loop
  #      (the script runs under -uo pipefail, not -e). Bounded by `timeout`
  #      so a regression here fails this gate instead of hanging verify.sh.
  jq 'del(.edges)' "$GRAPH" > "$T/graph-no-edges.json"
  if ! command -v timeout >/dev/null 2>&1; then
    bad "resolver hang-regression check requires 'timeout' on PATH, which is not available -- cannot verify fail-fast behavior"
  else
    timeout 5 "$RESOLVE" "$T/graph-no-edges.json" "$T/partial-scope.json" --closure >/dev/null 2>&1
    local rc_noedges=$?
    if [ "$rc_noedges" -ne 0 ] && [ "$rc_noedges" -ne 124 ]; then
      ok "resolver fails fast (not hangs) on a graph missing .edges[] under --closure"
    else
      bad "resolver hung or did not fail closed on a graph missing .edges[] (rc=$rc_noedges, 124=timeout)"
    fi
  fi

  # 28i. Regression: a malformed-but-concept-prefixed target (no second
  #      colon, e.g. "urn:mif:concept:noslug") must still appear in
  #      boundaryReferences, classified "unresolvable" -- not silently
  #      vanish. jq's capture() produces ZERO outputs (not null) on a
  #      non-match, which previously dropped the whole map() element; fixed
  #      by switching to scan()'s always-an-array semantics.
  jq '.edges += [{"source":"urn:mif:concept:harness:kg-cookiecutter-0002","target":"urn:mif:concept:noslug","type":"supports","strength":0.5,"via":"relationship"}]' "$GRAPH" > "$T/graph-malformed-target.json"
  got="$("$RESOLVE" "$T/graph-malformed-target.json" "$T/partial-scope.json" | jq -c '.boundaryReferences[] | select(.target=="urn:mif:concept:noslug")')"
  if [ "$got" = '{"target":"urn:mif:concept:noslug","reason":"unresolvable"}' ]; then
    ok "a malformed-but-concept-prefixed target is classified unresolvable, not silently dropped from boundaryReferences"
  else
    bad "malformed-target regression check failed: got '$got'"
  fi

  # 28j. Regression: a malformed FIRST element in the in-scope set must not
  #      poison the topic-namespace inference for the rest of the set. A
  #      prior version sampled only scope[0]; here scope[0] fails to match
  #      the concept-id pattern, so the topic namespace must fall back to the
  #      second (well-formed) element instead of "" -- a same-topic target
  #      genuinely out of scope must still classify out-of-scope, not
  #      cross-topic.
  printf '%s\n' '["not-a-concept-id","urn:mif:concept:harness:kg-cookiecutter-0002"]' > "$T/scope-bad-first.json"
  got="$("$RESOLVE" "$GRAPH" "$T/scope-bad-first.json" | jq -c '.boundaryReferences[] | select(.target=="urn:mif:concept:harness:kg-copier-0001")')"
  if [ "$got" = '{"target":"urn:mif:concept:harness:kg-copier-0001","reason":"out-of-scope"}' ]; then
    ok "a malformed first in-scope element does not poison topic-namespace inference for the rest of the set"
  else
    bad "bad-first-element regression check failed: got '$got'"
  fi

  # 28k. Regression: duplicate ids in the input in-scope set are deduplicated
  #      in resourceIds even without --closure (the closure path's own
  #      `unique` incidentally covered this before; the non-closure path did
  #      not).
  printf '%s\n' '["urn:mif:concept:harness:kg-cookiecutter-0002","urn:mif:concept:harness:kg-cookiecutter-0002"]' > "$T/scope-dupes.json"
  got="$("$RESOLVE" "$GRAPH" "$T/scope-dupes.json" | jq -c '.resourceIds')"
  if [ "$got" = '["urn:mif:concept:harness:kg-cookiecutter-0002"]' ]; then
    ok "duplicate ids in the in-scope input are deduplicated in resourceIds, with or without --closure"
  else
    bad "dedup regression check failed: got '$got'"
  fi

  rm -rf "$T"
}

# ---------------------------------------------------------------------------
# Milestone 29 — MIF Container fail-closed import gate (Epic #275, Story #318)
# ---------------------------------------------------------------------------
gate_m29() {
  info "Milestone 29 — MIF Container fail-closed import gate (scripts/mif-container-import.sh)"
  local IMPORT="scripts/mif-container-import.sh"
  local TOPIC="example-okf-mif-knowledge-spine"
  local TOPIC_DIR="reports/$TOPIC"
  local T; T="$(mktemp -d)" || { bad "gate_m29: failed to create a scratch directory"; return 1; }
  local got

  # This gate imports into the real registered sample topic (the import gate
  # has no sandboxed-corpus mode -- it resolves harness.config.json/reports/
  # from the repo root like every other harness script). Snapshot every file
  # it can touch and restore it on EVERY exit path (trap, not just the happy
  # path), so a gate failure never leaves the real corpus mutated.
  #
  # Every backup below is guarded (issue #377): an unchecked backup failure
  # here would make restore_snapshot()'s own restoring `cp` silently no-op
  # too (the "backup" it's copying from was never written), permanently
  # leaving the corpus mutated by this gate's own test run -- the same
  # failure mode gate_m31's equivalent backups were hardened against
  # (Story #328's review pass).
  mkdir -p "$T/snapshot/findings" \
    || { bad "gate_m29: failed to create the snapshot scratch directory"; rm -rf "$T"; return 1; }
  cp -r "$TOPIC_DIR/findings/." "$T/snapshot/findings/" \
    || { bad "gate_m29: failed to back up $TOPIC_DIR/findings before mutating it"; rm -rf "$T"; return 1; }
  cp "$TOPIC_DIR/README.md" "$T/snapshot/README.md" \
    || { bad "gate_m29: failed to back up $TOPIC_DIR/README.md before mutating it"; rm -rf "$T"; return 1; }
  cp reports/concordance.json "$T/snapshot/concordance.json" \
    || { bad "gate_m29: failed to back up reports/concordance.json before mutating it"; rm -rf "$T"; return 1; }
  # reports/concordance-sameas-proposals.json (Story #324) is a GLOBAL
  # (not per-topic) file step 5 writes whenever an import upserts anything
  # (including these test invocations) -- it did not exist before this
  # story and is gitignored, so "restore" here means "remove it", not
  # "restore content".
  local had_sameas_proposals=0
  [ -f reports/concordance-sameas-proposals.json ] && {
    had_sameas_proposals=1
    cp reports/concordance-sameas-proposals.json "$T/snapshot/concordance-sameas-proposals.json" \
      || { bad "gate_m29: failed to back up reports/concordance-sameas-proposals.json"; rm -rf "$T"; return 1; }
  }
  # harness.config.json backup + a pre-declared synthetic topic name (issue
  # #376's destination-ontology-map regression test, 29k): a fresh synthetic
  # topic, not the real $TOPIC, is the destination there specifically so a
  # deliberately-corrupted ontology-map.json never touches the real corpus --
  # this gate's own snapshot/restore above never backs up ontology-map.json
  # at all (no prior test here ever needed to mutate the real topic's copy),
  # so writing corrupt content directly to $TOPIC_DIR/ontology-map.json would
  # have no restore path if this gate exited before an explicit undo ran.
  # Declared here (not at 29k, where it's used), same rationale as gate_m31's
  # roundtrip_topic/malformed_topic: restore_snapshot()'s cleanup below must
  # be able to reference it unconditionally, not depend on 29k having run.
  cp harness.config.json "$T/snapshot/harness.config.json" \
    || { bad "gate_m29: failed to back up harness.config.json before mutating it"; rm -rf "$T"; return 1; }
  local badontmap_topic="gate-m29-badontmap-test"
  restore_snapshot() {
    # Every restore below is checked (Copilot review, PR #385): unlike the
    # guarded BACKUP calls above (issue #377), a restore step failing here
    # runs inside the EXIT/RETURN trap itself, so there is no caller left to
    # propagate a non-zero return to -- `bad` is the only way to surface
    # "the real corpus may still be mutated" instead of silently proceeding
    # as if the restore succeeded. Every step still runs regardless (this is
    # best-effort cleanup, not a fail-fast sequence): one failed restore
    # should not skip restoring everything else.
    rm -rf "$TOPIC_DIR/findings"
    mkdir -p "$TOPIC_DIR/findings"
    cp -r "$T/snapshot/findings/." "$TOPIC_DIR/findings/" \
      || bad "gate_m29 restore_snapshot: failed to restore $TOPIC_DIR/findings -- real corpus may be left mutated"
    cp "$T/snapshot/README.md" "$TOPIC_DIR/README.md" \
      || bad "gate_m29 restore_snapshot: failed to restore $TOPIC_DIR/README.md -- real corpus may be left mutated"
    cp "$T/snapshot/concordance.json" reports/concordance.json \
      || bad "gate_m29 restore_snapshot: failed to restore reports/concordance.json -- real corpus may be left mutated"
    if [ "$had_sameas_proposals" -eq 1 ]; then
      cp "$T/snapshot/concordance-sameas-proposals.json" reports/concordance-sameas-proposals.json \
        || bad "gate_m29 restore_snapshot: failed to restore reports/concordance-sameas-proposals.json"
    else
      rm -f reports/concordance-sameas-proposals.json
    fi
    cp "$T/snapshot/harness.config.json" harness.config.json \
      || bad "gate_m29 restore_snapshot: failed to restore harness.config.json -- real corpus may be left mutated"
    rm -rf "reports/$badontmap_topic"
    rm -f "$TOPIC_DIR/knowledge-graph.json"
    rm -rf "$TOPIC_DIR/.container.lock"
    rm -rf "$T"
    # Deregister the EXIT copy of this trap once the restore has actually
    # run: EXIT is a last-resort net for a fatal error INSIDE this function
    # (e.g. an unbound-variable abort under this script's own `set -u`,
    # which terminates the whole script without ever reaching gate_m29's
    # normal return -- a RETURN-only trap would miss that case). But once
    # gate_m29 DOES return normally, its `local` variables ($T, $TOPIC_DIR)
    # stop existing in the calling scope; a lingering EXIT trap firing much
    # later, at verify.sh's true end, would reference those now-undefined
    # locals and abort the ENTIRE script on "T: unbound variable" -- a real
    # regression this exact line was written to catch, then briefly
    # reintroduced by leaving this trap registered past its useful window.
    trap - EXIT
  }
  trap restore_snapshot RETURN EXIT

  local seed_finding; seed_finding="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | head -1)"
  local seed_digest; seed_digest="$(scripts/mif-container-digest.sh resource "$seed_finding")"
  local seed_manifest_digest; seed_manifest_digest="$(printf '%s\n' "$seed_digest" | scripts/mif-container-digest.sh manifest)"

  build_container() { # build_container <dir> <resource-file> <digest> <manifest-digest> <ontology-version> [<resource-filename>]
    # resource-filename defaults to "finding.json"; sub-tests that write a
    # genuinely NEW @id (as opposed to matching the seed finding's existing
    # @id) must each pass a distinct name -- the real script's destination
    # filename for a new @id is basename(resources[].path), so two "new"
    # sub-tests sharing the default name would collide with each other at
    # the shared $FINDINGS_DIR (write-finding.sh correctly refuses that
    # collision, which looks like an unrelated import failure if the two
    # sub-tests' fixtures aren't actually distinct resources).
    local rname="${6:-finding.json}"
    mkdir -p "$1"
    cp "$2" "$1/$rname"
    jq -n --arg d "$3" --arg md "$4" --arg ov "$5" --arg topic "$TOPIC" --arg rname "$rname" '{
      profile: "https://research-harness.dev/schema/mif-container/v1",
      sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
      exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
      ontologyBindings: [{packId: "mif-generic", version: $ov}],
      resources: [{mifType: "finding", path: $rname, ontologyType: "technology", digest: $d}],
      boundaryReferences: [],
      manifestDigest: $md,
      createdAt: "2026-07-10T00:00:00Z"
    }' > "$1/mif-package.json"
  }

  # 29a. A container carrying the topic's own unmodified finding content is a
  #      true idempotent no-op (NFR-4): 0 written, matched by @id AND digest.
  build_container "$T/c-noop" "$seed_finding" "$seed_digest" "$seed_manifest_digest" "1.0.0"
  got="$("$IMPORT" "$T/c-noop" "$TOPIC" 2>&1)"
  if printf '%s' "$got" | grep -q "0 written, 1 already up to date"; then
    ok "re-importing a finding's own unmodified content is a true idempotent no-op"
  else
    bad "idempotent no-op check failed: $got"
  fi

  # 29b. Per-resource digest mismatch rejects the ENTIRE import before any
  #      write (NFR-2) -- never a partial/best-effort write.
  build_container "$T/c-baddigest" "$seed_finding" "sha256:0000000000000000000000000000000000000000000000000000000000000000" "$seed_manifest_digest" "1.0.0"
  "$IMPORT" "$T/c-baddigest" "$TOPIC" >/dev/null 2>&1
  local rc_baddigest=$?
  if [ "$rc_baddigest" -ne 0 ] && [ -z "$(git status --porcelain "$TOPIC_DIR/findings" 2>/dev/null)" ]; then
    ok "a per-resource digest mismatch rejects the entire import, nothing written"
  else
    bad "digest-mismatch import was not rejected cleanly (rc=$rc_baddigest)"
  fi

  # 29c. Ontology-binding version mismatch rejects the entire import (NFR-3)
  #      -- never a silent best-effort re-type.
  build_container "$T/c-badonto" "$seed_finding" "$seed_digest" "$seed_manifest_digest" "9.9.9"
  "$IMPORT" "$T/c-badonto" "$TOPIC" >/dev/null 2>&1
  local rc_badonto=$?
  if [ "$rc_badonto" -ne 0 ] && [ -z "$(git status --porcelain "$TOPIC_DIR/findings" 2>/dev/null)" ]; then
    ok "an ontology-binding version mismatch rejects the entire import, nothing written"
  else
    bad "ontology-mismatch import was not rejected cleanly (rc=$rc_badonto)"
  fi

  # 29d. --dry-run runs every validation step and writes nothing (AC11).
  #      Checked as a content snapshot immediately before/after the --dry-run
  #      call itself, not against `git status`/HEAD: a prior test's own
  #      legitimate rebuild (29a's no-op still runs step 5) can leave
  #      README.md/concordance.json genuinely different from committed HEAD
  #      (a deterministic rebuild is not guaranteed byte-identical to a
  #      possibly-stale committed copy) or an untracked knowledge-graph.json
  #      behind -- none of that is evidence --dry-run itself wrote anything.
  #      Only a change relative to the state right before THIS call counts.
  local before_hash after_hash before_count after_count
  (cat "$TOPIC_DIR/README.md" reports/concordance.json; find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | LC_ALL=C sort | while IFS= read -r f; do cat "$f"; done) > "$T/before-snapshot.txt"
  before_hash="$(scripts/mif-container-digest.sh resource "$T/before-snapshot.txt" 2>/dev/null)"
  before_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
  "$IMPORT" "$T/c-noop" "$TOPIC" --dry-run >/dev/null 2>&1
  local rc_dryrun=$?
  (cat "$TOPIC_DIR/README.md" reports/concordance.json; find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | LC_ALL=C sort | while IFS= read -r f; do cat "$f"; done) > "$T/after-snapshot.txt"
  after_hash="$(scripts/mif-container-digest.sh resource "$T/after-snapshot.txt" 2>/dev/null)"
  after_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
  if [ "$rc_dryrun" -eq 0 ] && [ "$before_count" = "$after_count" ] && [ "$before_hash" = "$after_hash" ]; then
    ok "--dry-run validates without writing anything (findings/README/concordance content unchanged before/after)"
  else
    bad "--dry-run wrote something or failed (rc=$rc_dryrun, findings $before_count -> $after_count)"
  fi

  # 29e. Importing into an unregistered topic fails closed immediately.
  "$IMPORT" "$T/c-noop" "not-a-real-topic" >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    ok "importing into an unregistered topic fails closed"
  else
    bad "import accepted an unregistered topic"
  fi

  # 29f. A brand-new @id is written as a new finding file, and 29g. a
  #      re-import of that SAME @id with different content overwrites in
  #      place -- never a duplicate file (NFR-4, "safely re-runnable").
  local new_id="urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-synthetic"
  jq --arg id "$new_id" '."@id" = $id' "$seed_finding" > "$T/new-finding.json"
  local new_digest; new_digest="$(scripts/mif-container-digest.sh resource "$T/new-finding.json")"
  local new_manifest_digest; new_manifest_digest="$(printf '%s\n' "$new_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-new" "$T/new-finding.json" "$new_digest" "$new_manifest_digest" "1.0.0"
  got="$("$IMPORT" "$T/c-new" "$TOPIC" 2>&1)"
  local new_file_count; new_file_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name 'finding.json' | wc -l | tr -d ' ')"
  if printf '%s' "$got" | grep -q "1 written, 0 already up to date" && [ "$new_file_count" = "1" ]; then
    ok "a brand-new @id is written as a new finding file"
  else
    bad "new-finding write check failed: $got (file_count=$new_file_count)"
  fi

  jq '.summary = "gate_m29 overwrite-in-place test"' "$T/new-finding.json" > "$T/new-finding-v2.json"
  local updated_digest; updated_digest="$(scripts/mif-container-digest.sh resource "$T/new-finding-v2.json")"
  local updated_manifest_digest; updated_manifest_digest="$(printf '%s\n' "$updated_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-updated" "$T/new-finding-v2.json" "$updated_digest" "$updated_manifest_digest" "1.0.0"
  got="$("$IMPORT" "$T/c-updated" "$TOPIC" 2>&1)"
  new_file_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name 'finding.json' | wc -l | tr -d ' ')"
  local updated_summary; updated_summary="$(jq -r '.summary' "$TOPIC_DIR/findings/finding.json" 2>/dev/null)"
  if printf '%s' "$got" | grep -q "1 written, 0 already up to date" && [ "$new_file_count" = "1" ] && [ "$updated_summary" = "gate_m29 overwrite-in-place test" ]; then
    ok "re-importing the same @id with different content overwrites in place, never a duplicate"
  else
    bad "overwrite-in-place check failed: $got (file_count=$new_file_count, summary=$updated_summary)"
  fi

  # 29h. Regression: an @id containing regex-special characters (schema-legal
  #      -- schemas/mif/mif.schema.json only constrains @id to a "^urn:mif:"
  #      prefix) must be matched LITERALLY, not as a BRE pattern. An earlier
  #      version interpolated $rid unescaped into a bare `grep` pattern,
  #      which could match the wrong existing finding or fail to match its
  #      own. Re-importing the SAME special-char @id unchanged must still be
  #      a true no-op (proves the literal match finds itself correctly, not
  #      just that it avoids false positives).
  local special_id="urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-special.chars[test]"
  jq --arg id "$special_id" '."@id" = $id' "$seed_finding" > "$T/special-finding.json"
  local special_digest; special_digest="$(scripts/mif-container-digest.sh resource "$T/special-finding.json")"
  local special_manifest_digest; special_manifest_digest="$(printf '%s\n' "$special_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-special" "$T/special-finding.json" "$special_digest" "$special_manifest_digest" "1.0.0" "special-finding.json"
  "$IMPORT" "$T/c-special" "$TOPIC" >/dev/null 2>&1
  got="$("$IMPORT" "$T/c-special" "$TOPIC" 2>&1)"
  if printf '%s' "$got" | grep -q "0 written, 1 already up to date"; then
    ok "an @id containing regex-special characters is matched literally (idempotent no-op on re-import)"
  else
    bad "special-char @id regression check failed: $got"
  fi

  # 29i. Regression: bulk pre-validation (step 2) rejects a multi-resource
  #      manifest where ANY finding fails findings.schema.json BEFORE step 4
  #      writes anything -- not even the resources that WOULD have been
  #      valid. An earlier version validated each finding one at a time
  #      inside the step-4 write loop, so a later resource's schema failure
  #      left earlier resources in the same manifest already durably
  #      written -- a real partial write all 5 review passes converged on.
  mkdir -p "$T/c-multi"
  cp "$seed_finding" "$T/c-multi/good.json"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-multi-good" '."@id" = $id' "$seed_finding" > "$T/c-multi/good-tmp.json" && mv "$T/c-multi/good-tmp.json" "$T/c-multi/good.json"
  echo '{"@id": "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-multi-bad", "notAValidFinding": true}' > "$T/c-multi/bad.json"
  local multi_good_digest; multi_good_digest="$(scripts/mif-container-digest.sh resource "$T/c-multi/good.json")"
  local multi_bad_digest; multi_bad_digest="$(scripts/mif-container-digest.sh resource "$T/c-multi/bad.json")"
  local multi_manifest_digest; multi_manifest_digest="$(printf '%s\n%s\n' "$multi_good_digest" "$multi_bad_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg gd "$multi_good_digest" --arg bd "$multi_bad_digest" --arg md "$multi_manifest_digest" --arg topic "$TOPIC" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [
      {mifType: "finding", path: "good.json", ontologyType: "technology", digest: $gd},
      {mifType: "finding", path: "bad.json", ontologyType: "technology", digest: $bd}
    ],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-multi/mif-package.json"
  "$IMPORT" "$T/c-multi" "$TOPIC" >/dev/null 2>&1
  local rc_multi=$?
  local multi_written; multi_written="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name 'good.json' -o -name 'bad.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc_multi" -ne 0 ] && [ "$multi_written" = "0" ]; then
    ok "a multi-resource manifest with one invalid finding rejects the WHOLE import -- not even the valid resource is written"
  else
    bad "multi-resource partial-write regression check failed (rc=$rc_multi, written=$multi_written)"
  fi

  # 29j. Regression: a concurrent invocation against the same topic fails
  #      closed on the mkdir-based lock (feature-spec AC12) instead of
  #      racing steps 4/5.
  mkdir -p "$TOPIC_DIR/.container.lock"
  "$IMPORT" "$T/c-noop" "$TOPIC" >/dev/null 2>&1
  local rc_locked=$?
  rmdir "$TOPIC_DIR/.container.lock" 2>/dev/null
  if [ "$rc_locked" -ne 0 ]; then
    ok "a held lock rejects a concurrent invocation against the same topic (AC12)"
  else
    bad "import did not fail closed against an already-held lock"
  fi

  # 29k. Regression test for issue #376's destination pre-validation: a
  #      SUBSET manifest whose DESTINATION ontology-map.json is corrupted
  #      (not a JSON array) must reject the WHOLE import before any write --
  #      not crash mid-write-loop after the manifest's own good finding has
  #      already landed. An earlier version of the #376 merge only validated
  #      the INCOMING ontology-map resource in step 2, discovering a corrupt
  #      DESTINATION only live inside step 4, after step 4 had already
  #      durably written every 'finding' resource in the same manifest.
  #      Destination is a fresh synthetic topic, never the real $TOPIC --
  #      see the rationale on badontmap_topic's declaration above.
  jq --arg id "$badontmap_topic" '.topics += [{id: $id, title: "gate_m29 bad-ontology-map test", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$T/config-with-badontmap-topic.json" && cp "$T/config-with-badontmap-topic.json" harness.config.json
  mkdir -p "reports/$badontmap_topic/findings"
  echo '{"not": "an array"}' > "reports/$badontmap_topic/ontology-map.json"
  mkdir -p "$T/c-badontmap"
  local badontmap_finding_id="urn:mif:concept:harness/$badontmap_topic:good"
  jq --arg id "$badontmap_finding_id" '."@id" = $id' "$seed_finding" > "$T/c-badontmap/good.json"
  echo '[{"finding_id": "'"$badontmap_finding_id"'", "entity_type": "technology", "resolved_ontology": "mif-generic@1.0.0", "basis": "declared", "valid": true}]' > "$T/c-badontmap/ontology-map.json"
  local badontmap_good_digest badontmap_ontmap_digest badontmap_manifest_digest
  badontmap_good_digest="$(scripts/mif-container-digest.sh resource "$T/c-badontmap/good.json")"
  badontmap_ontmap_digest="$(scripts/mif-container-digest.sh resource "$T/c-badontmap/ontology-map.json")"
  badontmap_manifest_digest="$(printf '%s\n%s\n' "$badontmap_good_digest" "$badontmap_ontmap_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg gd "$badontmap_good_digest" --arg od "$badontmap_ontmap_digest" --arg md "$badontmap_manifest_digest" \
    --arg topic "$badontmap_topic" --arg selector "[\"$badontmap_finding_id\"]" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "subset", topic: $topic, selector: $selector, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [
      {mifType: "finding", path: "good.json", ontologyType: "technology", digest: $gd},
      {mifType: "ontology-map", path: "ontology-map.json", ontologyType: null, digest: $od}
    ],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-badontmap/mif-package.json"
  "$IMPORT" "$T/c-badontmap" "$badontmap_topic" >/dev/null 2>&1
  local rc_badontmap=$?
  local badontmap_written; badontmap_written="$(find "reports/$badontmap_topic/findings" -maxdepth 1 -name 'good.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc_badontmap" -ne 0 ] && [ "$badontmap_written" = "0" ]; then
    ok "a corrupt (non-array) destination ontology-map.json rejects the WHOLE subset import before any write (#376)"
  else
    bad "destination ontology-map pre-validation check failed (rc=$rc_badontmap, finding_written=$badontmap_written)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 30 — MIF Container origin tagging + reconciliation (Epic #275, Story #324)
# ---------------------------------------------------------------------------
gate_m30() {
  info "Milestone 30 — MIF Container origin tagging + reconciliation policy"
  local IMPORT="scripts/mif-container-import.sh"
  local DETECT="scripts/mif-container-detect-sameas.sh"
  local TOPIC="example-okf-mif-knowledge-spine"
  local TOPIC_DIR="reports/$TOPIC"
  local T; T="$(mktemp -d)" || { bad "gate_m30: failed to create a scratch directory"; return 1; }
  local got

  # Every backup below is guarded (issue #377), same rationale as gate_m29
  # and gate_m31: an unchecked backup failure here would make
  # restore_snapshot()'s own restoring `cp` silently no-op too, permanently
  # leaving the corpus mutated by this gate's own test run.
  mkdir -p "$T/snapshot/findings" \
    || { bad "gate_m30: failed to create the snapshot scratch directory"; rm -rf "$T"; return 1; }
  cp -r "$TOPIC_DIR/findings/." "$T/snapshot/findings/" \
    || { bad "gate_m30: failed to back up $TOPIC_DIR/findings before mutating it"; rm -rf "$T"; return 1; }
  cp "$TOPIC_DIR/README.md" "$T/snapshot/README.md" \
    || { bad "gate_m30: failed to back up $TOPIC_DIR/README.md before mutating it"; rm -rf "$T"; return 1; }
  cp reports/concordance.json "$T/snapshot/concordance.json" \
    || { bad "gate_m30: failed to back up reports/concordance.json before mutating it"; rm -rf "$T"; return 1; }
  local had_sameas_proposals=0
  [ -f reports/concordance-sameas-proposals.json ] && {
    had_sameas_proposals=1
    cp reports/concordance-sameas-proposals.json "$T/snapshot/concordance-sameas-proposals.json" \
      || { bad "gate_m30: failed to back up reports/concordance-sameas-proposals.json"; rm -rf "$T"; return 1; }
  }
  restore_snapshot() {
    # Every restore below is checked (Copilot review, PR #385) -- same
    # rationale as gate_m29's identical restore_snapshot(): a restore step
    # runs inside the EXIT/RETURN trap itself, so `bad` is the only way to
    # surface a failed restore instead of silently proceeding as if it
    # succeeded. Every step still runs regardless of an earlier one failing.
    rm -rf "$TOPIC_DIR/findings"
    mkdir -p "$TOPIC_DIR/findings"
    cp -r "$T/snapshot/findings/." "$TOPIC_DIR/findings/" \
      || bad "gate_m30 restore_snapshot: failed to restore $TOPIC_DIR/findings -- real corpus may be left mutated"
    cp "$T/snapshot/README.md" "$TOPIC_DIR/README.md" \
      || bad "gate_m30 restore_snapshot: failed to restore $TOPIC_DIR/README.md -- real corpus may be left mutated"
    cp "$T/snapshot/concordance.json" reports/concordance.json \
      || bad "gate_m30 restore_snapshot: failed to restore reports/concordance.json -- real corpus may be left mutated"
    if [ "$had_sameas_proposals" -eq 1 ]; then
      cp "$T/snapshot/concordance-sameas-proposals.json" reports/concordance-sameas-proposals.json \
        || bad "gate_m30 restore_snapshot: failed to restore reports/concordance-sameas-proposals.json"
    else
      rm -f reports/concordance-sameas-proposals.json
    fi
    rm -f "$TOPIC_DIR/knowledge-graph.json"
    rm -rf "$TOPIC_DIR/.container.lock"
    rm -rf "$T"
    trap - EXIT
  }
  trap restore_snapshot RETURN EXIT

  local seed_finding; seed_finding="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | head -1)"
  local seed_id; seed_id="$(jq -r '."@id"' "$seed_finding")"

  build_container() { # build_container <dir> <resource-file> <digest> <manifest-digest>
    mkdir -p "$1"
    cp "$2" "$1/finding.json"
    jq -n --arg d "$3" --arg md "$4" --arg topic "$TOPIC" '{
      profile: "https://research-harness.dev/schema/mif-container/v1",
      sourceInstance: {namespace: "gate-m30-test-instance", corpusUrl: null},
      exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
      ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
      resources: [{mifType: "finding", path: "finding.json", ontologyType: "technology", digest: $d}],
      boundaryReferences: [],
      manifestDigest: $md,
      createdAt: "2026-07-10T00:00:00Z"
    }' > "$1/mif-package.json"
  }

  # 30a. Reconciliation: an incoming re-import of an existing @id with a
  #      DIFFERENT verification verdict, gathered_under, and provenance must
  #      NOT overwrite those three fields (AD-6: origin-scoped) -- the
  #      destination's own values survive even though the rest of the
  #      content (summary) DOES take the incoming value.
  jq '.extensions.harness.verification.verdict = "falsified"
      | .extensions.harness.verification.verdict_basis = "gate-m30 foreign verdict, must not survive"
      | .extensions.harness.gathered_under = "gv-000000000000"
      | .provenance.trustLevel = "low_confidence"
      | .summary = "gate-m30 reconciliation test: this field SHOULD reconcile"' \
    "$seed_finding" > "$T/foreign-finding.json"
  local foreign_digest; foreign_digest="$(scripts/mif-container-digest.sh resource "$T/foreign-finding.json")"
  local foreign_manifest_digest; foreign_manifest_digest="$(printf '%s\n' "$foreign_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-foreign" "$T/foreign-finding.json" "$foreign_digest" "$foreign_manifest_digest"
  local orig_verdict orig_gathered orig_trust
  orig_verdict="$(jq -r '.extensions.harness.verification.verdict' "$seed_finding")"
  orig_gathered="$(jq -r '.extensions.harness.gathered_under // "null"' "$seed_finding")"
  orig_trust="$(jq -r '.provenance.trustLevel // "null"' "$seed_finding")"
  got="$("$IMPORT" "$T/c-foreign" "$TOPIC" 2>&1)"
  local result_file; result_file="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' -exec grep -Fl "\"@id\": \"$seed_id\"" {} + 2>/dev/null | head -1)"
  local new_verdict new_gathered new_trust new_summary
  new_verdict="$(jq -r '.extensions.harness.verification.verdict' "$result_file")"
  new_gathered="$(jq -r '.extensions.harness.gathered_under // "null"' "$result_file")"
  new_trust="$(jq -r '.provenance.trustLevel // "null"' "$result_file")"
  new_summary="$(jq -r '.summary' "$result_file")"
  if [ "$new_verdict" = "$orig_verdict" ] && [ "$new_gathered" = "$orig_gathered" ] \
     && [ "$new_trust" = "$orig_trust" ] \
     && [ "$new_summary" = "gate-m30 reconciliation test: this field SHOULD reconcile" ]; then
    ok "verification verdict, gathered_under, and provenance stay origin-scoped (destination's own values survive); other fields reconcile toward the incoming value"
  else
    bad "reconciliation policy violated: verdict $orig_verdict->$new_verdict, gathered_under $orig_gathered->$new_gathered, trust $orig_trust->$new_trust, summary='$new_summary'"
  fi

  # 30b. Reconciliation: tags[] reconciles toward a UNION, not a replace --
  #      a tag present on only one side must survive on both.
  jq '.tags = ["gate-m30-foreign-tag"] + (.tags // [])' "$seed_finding" > "$T/tags-finding.json"
  local tags_digest; tags_digest="$(scripts/mif-container-digest.sh resource "$T/tags-finding.json")"
  local tags_manifest_digest; tags_manifest_digest="$(printf '%s\n' "$tags_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-tags" "$T/tags-finding.json" "$tags_digest" "$tags_manifest_digest"
  local orig_tags_count; orig_tags_count="$(jq '.tags // [] | length' "$seed_finding")"
  "$IMPORT" "$T/c-tags" "$TOPIC" >/dev/null 2>&1
  result_file="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' -exec grep -Fl "\"@id\": \"$seed_id\"" {} + 2>/dev/null | head -1)"
  local has_foreign_tag has_orig_tags
  has_foreign_tag="$(jq '(.tags // []) | index("gate-m30-foreign-tag") != null' "$result_file")"
  has_orig_tags="$(jq --argjson n "$orig_tags_count" '((.tags // []) | length) >= $n' "$result_file")"
  if [ "$has_foreign_tag" = "true" ] && [ "$has_orig_tags" = "true" ]; then
    ok "tags[] reconciles toward a union of both sides, never a replace"
  else
    bad "tags union check failed (has_foreign_tag=$has_foreign_tag has_orig_tags=$has_orig_tags)"
  fi

  # 30c. Candidate sameAs detection: importing a finding whose label
  #      normalizes identically to an existing DIFFERENT-@id finding's label
  #      surfaces a proposal in reports/concordance-sameas-proposals.json --
  #      it must NOT rewrite either @id or merge anything.
  local seed_title; seed_title="$(jq -r '.title' "$seed_finding")"
  local dup_id="urn:mif:concept:harness/${TOPIC}:gate-m30-sameas-synthetic"
  mkdir -p "$T/c-dup"
  jq --arg id "$dup_id" --arg t "  $seed_title  " '."@id" = $id | .title = $t' "$seed_finding" > "$T/c-dup/dup-finding.json"
  local dup_digest; dup_digest="$(scripts/mif-container-digest.sh resource "$T/c-dup/dup-finding.json")"
  local dup_manifest_digest; dup_manifest_digest="$(printf '%s\n' "$dup_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg d "$dup_digest" --arg md "$dup_manifest_digest" --arg topic "$TOPIC" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m30-test-instance", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [{mifType: "finding", path: "dup-finding.json", ontologyType: "technology", digest: $d}],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-dup/mif-package.json"
  "$IMPORT" "$T/c-dup" "$TOPIC" >/dev/null 2>&1
  got="$(jq -c --arg a "$seed_id" --arg b "$dup_id" '.proposals[] | select((.a==$a and .b==$b) or (.a==$b and .b==$a))' reports/concordance-sameas-proposals.json 2>/dev/null)"
  local seed_still_seed_id dup_written_separately
  seed_still_seed_id="$(jq -r '."@id"' "$seed_finding" 2>/dev/null)"
  dup_written_separately="$([ -f "$TOPIC_DIR/findings/dup-finding.json" ] && jq -r '."@id"' "$TOPIC_DIR/findings/dup-finding.json" 2>/dev/null)"
  if [ -n "$got" ] && [ "$seed_still_seed_id" = "$seed_id" ] && [ "$dup_written_separately" = "$dup_id" ]; then
    ok "a candidate sameAs match (whitespace/case-normalized label) surfaces as a proposal; both findings remain distinct files under their own @id, never merged"
  else
    bad "sameAs proposal check failed: got='$got' seed_id_after='$seed_still_seed_id' dup_id_after='$dup_written_separately'"
  fi

  # 30d. The detector never modifies concordance.json itself -- it is
  #      read-only, detection-only (never a merge).
  local concordance_before concordance_after
  concordance_before="$(scripts/mif-container-digest.sh resource reports/concordance.json)"
  "$DETECT" reports/concordance.json >/dev/null 2>&1
  concordance_after="$(scripts/mif-container-digest.sh resource reports/concordance.json)"
  if [ "$concordance_before" = "$concordance_after" ]; then
    ok "the sameAs detector never modifies concordance.json -- detection only, never a merge"
  else
    bad "sameAs detector unexpectedly modified concordance.json"
  fi

  # 30e. Fail-closed: a missing/unreadable concordance file is a named error.
  "$DETECT" "$T/does-not-exist.json" >/dev/null 2>&1
  if [ "$?" -ne 0 ]; then
    ok "sameAs detector fails closed on a missing concordance file"
  else
    bad "sameAs detector did not fail on a missing concordance file"
  fi

  # 30f. Regression: reconciliation's merge draws on the DESTINATION's own
  #      on-disk content (Story #324), which step 2's incoming-bytes-only
  #      pre-check cannot see -- a corrupt destination finding (.tags not
  #      an array, so the union's `+` throws a jq type error) must still be
  #      caught in step 2's bulk pre-check, rejecting the WHOLE import
  #      (including an entirely independent, valid, brand-new-@id resource
  #      in the SAME manifest) before step 4 writes anything. This is the
  #      exact partial-write shape review caught in this reconciliation
  #      change: merge-validation moved into step 2 fixes it the same way
  #      29i's fix did for per-finding schema validation.
  local corrupt_target; corrupt_target="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' ! -name "$(basename "$seed_finding")" | sort | head -1)"
  local corrupt_id; corrupt_id="$(jq -r '."@id"' "$corrupt_target")"
  local corrupt_tmp; corrupt_tmp="$(mktemp)"
  jq '.tags = "not-an-array"' "$corrupt_target" > "$corrupt_tmp" && mv "$corrupt_tmp" "$corrupt_target"
  mkdir -p "$T/c-corrupt"
  cp "$seed_finding" "$T/c-corrupt/corrupt-target.json"
  jq --arg id "$corrupt_id" '."@id" = $id | .summary = "gate-m30 corrupt-destination regression: incoming side is valid"' "$seed_finding" > "$T/c-corrupt/corrupt-target-tmp.json" && mv "$T/c-corrupt/corrupt-target-tmp.json" "$T/c-corrupt/corrupt-target.json"
  local corrupt_incoming_real_digest; corrupt_incoming_real_digest="$(scripts/mif-container-digest.sh resource "$T/c-corrupt/corrupt-target.json")"
  local other_new_id="urn:mif:concept:harness/${TOPIC}:gate-m30-corrupt-independent-new"
  jq --arg id "$other_new_id" '."@id" = $id' "$seed_finding" > "$T/c-corrupt/independent-new.json"
  local other_new_digest; other_new_digest="$(scripts/mif-container-digest.sh resource "$T/c-corrupt/independent-new.json")"
  local corrupt_manifest_digest; corrupt_manifest_digest="$(printf '%s\n%s\n' "$corrupt_incoming_real_digest" "$other_new_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg cd "$corrupt_incoming_real_digest" --arg nd "$other_new_digest" --arg md "$corrupt_manifest_digest" --arg topic "$TOPIC" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m30-test-instance", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [
      {mifType: "finding", path: "corrupt-target.json", ontologyType: "technology", digest: $cd},
      {mifType: "finding", path: "independent-new.json", ontologyType: "technology", digest: $nd}
    ],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-corrupt/mif-package.json"
  "$IMPORT" "$T/c-corrupt" "$TOPIC" >/dev/null 2>&1
  local rc_corrupt=$?
  local independent_written; independent_written="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name 'independent-new.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$rc_corrupt" -ne 0 ] && [ "$independent_written" = "0" ]; then
    ok "a corrupt destination finding (reconciliation merge throws) rejects the WHOLE import -- not even an independent valid new-@id resource in the same manifest is written"
  else
    bad "corrupt-destination partial-write regression check failed (rc=$rc_corrupt, independent_written=$independent_written)"
  fi
}

# ---------------------------------------------------------------------------
# Milestone 31 — MIF Container export builder + /export /import commands (Epic #275, Story #328)
# ---------------------------------------------------------------------------
gate_m31() {
  info "Milestone 31 — MIF Container export builder (scripts/mif-container-export.sh)"
  local EXPORT="scripts/mif-container-export.sh"
  local IMPORT="scripts/mif-container-import.sh"
  local TOPIC="example-okf-mif-knowledge-spine"
  local TOPIC_DIR="reports/$TOPIC"
  local T; T="$(mktemp -d)" || { bad "gate_m31: failed to create a scratch directory"; return 1; }
  local got

  # This gate is READ-ONLY against the real corpus for 31a-31e (export never
  # writes to reports/<topic>/), but 31f performs a real round-trip import
  # into a FRESH synthetic topic this gate registers and tears down itself
  # -- never reports/example-okf-mif-knowledge-spine/findings -- so no
  # snapshot/restore of the real topic is needed here, only of
  # harness.config.json (which 31f temporarily appends a topic to) and the
  # global reports/concordance.json + reports/concordance-sameas-proposals.json
  # the round-trip import's own step 5 touches.
  #
  # Every backup `cp` below is guarded: an unchecked backup failure here
  # (review finding, Story #328) would make restore_state()'s own restoring
  # `cp` silently no-op too (the "backup" it's copying from was never
  # written), permanently leaving 31f's synthetic-topic mutation in the
  # REAL tracked harness.config.json/concordance.json -- a failure this gate
  # exists specifically to prevent, not risk itself.
  cp harness.config.json "$T/harness.config.json.orig" \
    || { bad "gate_m31: failed to back up harness.config.json before mutating it"; rm -rf "$T"; return 1; }
  cp reports/concordance.json "$T/concordance.json.orig" \
    || { bad "gate_m31: failed to back up reports/concordance.json before mutating it"; rm -rf "$T"; return 1; }
  local had_sameas_proposals=0
  [ -f reports/concordance-sameas-proposals.json ] && {
    had_sameas_proposals=1
    cp reports/concordance-sameas-proposals.json "$T/concordance-sameas-proposals.json.orig" \
      || { bad "gate_m31: failed to back up reports/concordance-sameas-proposals.json"; rm -rf "$T"; return 1; }
  }
  local roundtrip_topic="gate-m31-roundtrip-test"
  # Declared here (not at 31h, where it's used) so restore_state()'s own
  # cleanup below can reference it unconditionally -- both synthetic topics
  # are pre-declared before the trap is set, so the trap never depends on
  # having reached a specific sub-test to know what to clean up (Copilot
  # review, PR #378: an earlier version only cleaned up gate-m31-malformed-test
  # via an unconditional `rm -rf` at the very end of 31h's own code, which an
  # unexpected early exit between creating it and reaching that line -- a
  # future refactor, an external signal -- could skip, leaving it behind
  # despite restore_state()'s trap claiming to fully restore state).
  local malformed_topic="gate-m31-malformed-test"
  restore_state() {
    # Every restore below is checked (Copilot review, PR #385) -- same
    # rationale as gate_m29/gate_m30's restore_snapshot(): a restore step
    # runs inside the EXIT/RETURN trap itself, so `bad` is the only way to
    # surface a failed restore instead of silently proceeding as if it
    # succeeded. Every step still runs regardless of an earlier one failing.
    cp "$T/harness.config.json.orig" harness.config.json \
      || bad "gate_m31 restore_state: failed to restore harness.config.json -- real corpus may be left mutated"
    cp "$T/concordance.json.orig" reports/concordance.json \
      || bad "gate_m31 restore_state: failed to restore reports/concordance.json -- real corpus may be left mutated"
    if [ "$had_sameas_proposals" -eq 1 ]; then
      cp "$T/concordance-sameas-proposals.json.orig" reports/concordance-sameas-proposals.json \
        || bad "gate_m31 restore_state: failed to restore reports/concordance-sameas-proposals.json"
    else
      rm -f reports/concordance-sameas-proposals.json
    fi
    rm -rf "reports/$roundtrip_topic"
    rm -rf "reports/$malformed_topic"
    # This gate's $EXPORT calls against the REAL $TOPIC (not the synthetic
    # topics above) now acquire $TOPIC_DIR/.container.lock (issue #375) --
    # same defensive cleanup gate_m29/gate_m30's restore_snapshot() already
    # does for that lock, needed here too now that export shares it.
    rm -rf "$TOPIC_DIR/.container.lock"
    rm -rf "$T"
    trap - EXIT
  }
  trap restore_state RETURN EXIT

  # 31a. Full export: every finding in the topic, corpus untouched.
  local real_finding_count; real_finding_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
  got="$("$EXPORT" "$TOPIC" "$T/full-export" 2>&1)"
  local full_resource_count; full_resource_count="$(jq '.resources | length' "$T/full-export/mif-package.json" 2>/dev/null)"
  if printf '%s' "$got" | grep -q "exported $real_finding_count finding(s) (full scope)" \
     && [ "$full_resource_count" = "$((real_finding_count + 1))" ]; then
    ok "full export includes every finding plus the topic's ontology-map.json, corpus untouched"
  else
    bad "full export check failed: got='$got' resource_count=$full_resource_count expected_findings=$real_finding_count"
  fi
  if [ -z "$(git status --porcelain "$TOPIC_DIR" 2>/dev/null)" ]; then
    ok "export never modifies reports/<topic>/ (AC10)"
  else
    bad "export left reports/<topic>/ dirty"
    git status --porcelain "$TOPIC_DIR" >&2
  fi

  # 31a2. Regression: a held lock rejects a concurrent export invocation
  #      instead of racing (issue #375) -- mirrors gate_m29's 29j test for
  #      import's own identical lock; export's new lock (this diff) had no
  #      equivalent coverage.
  mkdir -p "$TOPIC_DIR/.container.lock"
  "$EXPORT" "$TOPIC" "$T/locked-export" > /dev/null 2>&1
  local rc_export_locked=$?
  rmdir "$TOPIC_DIR/.container.lock" 2>/dev/null
  if [ "$rc_export_locked" -ne 0 ] && [ ! -d "$T/locked-export" ]; then
    ok "a held lock rejects a concurrent export invocation, not just import (issue #375)"
  else
    bad "export did not fail closed against an already-held lock (rc=$rc_export_locked)"
  fi

  # 31b. The exported manifest validates against schemas/mif-container.schema.json.
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/mif-container.schema.json -d "$T/full-export/mif-package.json" > /dev/null 2>&1
  if [ "$?" -eq 0 ]; then
    ok "the exported manifest is schema-valid"
  else
    bad "the exported manifest failed schema validation"
  fi

  # 31c. Subset export: a small selector produces the right resource count
  #      and boundary references, never touching the corpus.
  local subset_ids; subset_ids="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' | LC_ALL=C sort | head -2 | xargs -I{} jq -r '."@id"' {})"
  printf '%s\n' "$subset_ids" | jq -R -s 'split("\n") | map(select(length>0))' > "$T/subset-ids.json"
  "$EXPORT" "$TOPIC" "$T/subset-export" --subset "$T/subset-ids.json" > /dev/null 2>&1
  local subset_resource_count; subset_resource_count="$(jq '.resources | length' "$T/subset-export/mif-package.json" 2>/dev/null)"
  local subset_scope_type; subset_scope_type="$(jq -r '.exportScope.type' "$T/subset-export/mif-package.json" 2>/dev/null)"
  if [ "$subset_resource_count" = "3" ] && [ "$subset_scope_type" = "subset" ]; then
    ok "subset export resolves exactly the requested findings plus ontology-map.json"
  else
    bad "subset export check failed (resource_count=$subset_resource_count scope_type=$subset_scope_type)"
  fi

  # 31d. A selector matching zero findings is a VALID export (schema's own
  #      resources[] description; matches gate_m28's 28f precedent for the
  #      resolver itself), not an error -- ontologyBindings still falls back
  #      to the topic's full set so the manifest stays schema-valid.
  echo '[]' > "$T/empty-ids.json"
  "$EXPORT" "$TOPIC" "$T/empty-export" --subset "$T/empty-ids.json" > /dev/null 2>&1
  local rc_empty=$?
  local empty_bindings_count; empty_bindings_count="$(jq '.ontologyBindings | length' "$T/empty-export/mif-package.json" 2>/dev/null)"
  ajv validate --spec=draft2020 --strict=false -c ajv-formats \
    -s schemas/mif-container.schema.json -d "$T/empty-export/mif-package.json" > /dev/null 2>&1
  local rc_empty_valid=$?
  if [ "$rc_empty" -eq 0 ] && [ "$rc_empty_valid" -eq 0 ] && [ "${empty_bindings_count:-0}" -gt 0 ]; then
    ok "a subset selector matching zero findings is a valid export, not an error"
  else
    bad "empty-scope export check failed (rc=$rc_empty valid_rc=$rc_empty_valid bindings=$empty_bindings_count)"
  fi

  # 31e. Fail-closed: an unregistered topic and a non-empty output directory.
  "$EXPORT" "not-a-real-topic-$$" "$T/out-unreg" > /dev/null 2>&1
  local rc_unreg=$?
  mkdir -p "$T/out-nonempty"; touch "$T/out-nonempty/pre-existing-file"
  "$EXPORT" "$TOPIC" "$T/out-nonempty" > /dev/null 2>&1
  local rc_nonempty=$?
  if [ "$rc_unreg" -ne 0 ] && [ "$rc_nonempty" -ne 0 ] && [ -f "$T/out-nonempty/pre-existing-file" ] \
     && [ ! -f "$T/out-nonempty/mif-package.json" ]; then
    ok "export fails closed on an unregistered topic and a non-empty output directory, without touching the latter's existing content"
  else
    bad "export fail-closed check failed (rc_unreg=$rc_unreg rc_nonempty=$rc_nonempty)"
  fi

  # 31f. Round-trip: export the whole topic, register a FRESH synthetic
  #      topic, import the export into it, and confirm every finding
  #      landed with the same content (byte-identical @id set) AND that
  #      ontology-map.json itself landed at the destination -- not just
  #      that its @id set matches. An earlier version of this test only
  #      checked @id-set equality, which stayed green while
  #      mif-container-import.sh silently dropped ontology-map.json on
  #      import entirely (Story #328 review finding) -- a false-green this
  #      assertion is specifically here to prevent recurring.
  jq --arg id "$roundtrip_topic" '.topics += [{id: $id, title: "gate_m31 roundtrip", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$T/config-with-roundtrip-topic.json" && cp "$T/config-with-roundtrip-topic.json" harness.config.json
  mkdir -p "reports/$roundtrip_topic/findings"
  "$IMPORT" "$T/full-export" "$roundtrip_topic" > /dev/null 2>&1
  local rc_roundtrip=$?
  local roundtrip_count; roundtrip_count="$(find "reports/$roundtrip_topic/findings" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  local source_ids dest_ids
  source_ids="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json' -exec jq -r '."@id"' {} + 2>/dev/null | LC_ALL=C sort)"
  dest_ids="$(find "reports/$roundtrip_topic/findings" -maxdepth 1 -name '*.json' -exec jq -r '."@id"' {} + 2>/dev/null | LC_ALL=C sort)"
  local ontmap_match="no"
  if [ -f "reports/$roundtrip_topic/ontology-map.json" ] \
     && diff -q <(jq -S . "$TOPIC_DIR/ontology-map.json") <(jq -S . "reports/$roundtrip_topic/ontology-map.json") > /dev/null 2>&1; then
    ontmap_match="yes"
  fi
  if [ "$rc_roundtrip" -eq 0 ] && [ "$roundtrip_count" = "$real_finding_count" ] && [ "$source_ids" = "$dest_ids" ] && [ "$ontmap_match" = "yes" ]; then
    ok "export -> import round-trip into a fresh topic reproduces the exact same @id set AND ontology-map.json"
  else
    bad "round-trip check failed (rc=$rc_roundtrip count=$roundtrip_count/$real_finding_count ids_match=$([ "$source_ids" = "$dest_ids" ] && echo yes || echo no) ontmap_match=$ontmap_match)"
  fi

  # 31g. Regression test for a real review-found data-loss bug: importing a
  #      SUBSET export into an already-populated destination topic must NOT
  #      shrink the destination's ontology-map.json to just the subset's
  #      entries -- $roundtrip_topic is already fully populated from 31f, so
  #      re-importing the 2-finding $T/subset-export (built in 31c) into it
  #      must leave ontology-map.json exactly as the full import left it.
  local ontmap_before_subset_import; ontmap_before_subset_import="$(jq -S . "reports/$roundtrip_topic/ontology-map.json" 2>/dev/null)"
  "$IMPORT" "$T/subset-export" "$roundtrip_topic" > /dev/null 2>&1
  local rc_subset_import=$?
  local ontmap_after_subset_import; ontmap_after_subset_import="$(jq -S . "reports/$roundtrip_topic/ontology-map.json" 2>/dev/null)"
  if [ "$rc_subset_import" -eq 0 ] && [ "$ontmap_before_subset_import" = "$ontmap_after_subset_import" ] \
     && [ -n "$ontmap_before_subset_import" ]; then
    ok "importing a subset export into an already-populated topic leaves the destination's ontology-map.json untouched (no data loss)"
  else
    bad "subset import ontology-map preservation check failed (rc=$rc_subset_import, map changed: $([ "$ontmap_before_subset_import" = "$ontmap_after_subset_import" ] && echo no || echo YES))"
  fi

  # 31h. Regression test for issue #376: prove the subset import actually
  #      UPSERTS missing/differing entries, not just no-ops when the incoming
  #      content already matches the destination -- 31g's re-import above
  #      never has to change anything, because the subset's entries were
  #      already identical to what the full import wrote in 31f, so it stays
  #      green under both the old skip-only behavior and a real merge. Strip
  #      $roundtrip_topic's ontology-map.json entries for the subset's own
  #      finding_ids out first, so restoring them actually requires a merge,
  #      then re-run the same subset import and confirm (a) the stripped
  #      entries come back with exactly the incoming content, and (b) every
  #      OTHER entry outside the subset is untouched.
  local ontmap_others_before; ontmap_others_before="$(jq --slurpfile ids "$T/subset-ids.json" -S \
    '[.[] | select((.finding_id | IN($ids[0][])) | not)] | sort_by(.finding_id)' \
    "reports/$roundtrip_topic/ontology-map.json")"
  # Both steps of the strip below are explicitly checked (not `&&`-chained
  # unchecked): a silent failure here would leave the destination un-stripped,
  # making the re-import below a true no-op and every assertion after it
  # trivially pass -- a false green on the very test meant to catch the merge
  # logic not working, exactly the failure mode this regression test exists
  # to prevent.
  local strip_ok=1
  jq --slurpfile ids "$T/subset-ids.json" \
    '[.[] | select((.finding_id | IN($ids[0][])) | not)]' \
    "reports/$roundtrip_topic/ontology-map.json" > "$T/ontmap-stripped.json" || strip_ok=0
  if [ "$strip_ok" -eq 1 ]; then
    cp "$T/ontmap-stripped.json" "reports/$roundtrip_topic/ontology-map.json" || strip_ok=0
  fi
  "$IMPORT" "$T/subset-export" "$roundtrip_topic" > /dev/null 2>&1
  local rc_merge_restore=$?
  local ontmap_restored_subset ontmap_others_after subset_entries_expected
  ontmap_restored_subset="$(jq --slurpfile ids "$T/subset-ids.json" -S \
    '[.[] | select(.finding_id | IN($ids[0][]))] | sort_by(.finding_id)' \
    "reports/$roundtrip_topic/ontology-map.json" 2>/dev/null)"
  ontmap_others_after="$(jq --slurpfile ids "$T/subset-ids.json" -S \
    '[.[] | select((.finding_id | IN($ids[0][])) | not)] | sort_by(.finding_id)' \
    "reports/$roundtrip_topic/ontology-map.json" 2>/dev/null)"
  subset_entries_expected="$(jq -S 'sort_by(.finding_id)' "$T/subset-export/ontology-map.json" 2>/dev/null)"
  if [ "$strip_ok" -eq 1 ] && [ "$rc_merge_restore" -eq 0 ] && [ "$ontmap_restored_subset" = "$subset_entries_expected" ] \
     && [ "$ontmap_others_after" = "$ontmap_others_before" ] && [ -n "$ontmap_others_before" ]; then
    ok "subset import upserts its own in-scope ontology-map entries back in by finding_id, without disturbing untouched destination entries (#376)"
  else
    bad "subset import upsert-restore check failed (strip_ok=$strip_ok rc=$rc_merge_restore restored_match=$([ "$ontmap_restored_subset" = "$subset_entries_expected" ] && echo yes || echo no) others_match=$([ "$ontmap_others_after" = "$ontmap_others_before" ] && echo yes || echo no))"
  fi

  # 31i. A malformed (invalid-JSON) finding file must make export fail
  #      closed, not silently undercount and report success -- a synthetic
  #      topic isolated from the real corpus (using the $malformed_topic
  #      declared above, alongside $roundtrip_topic), torn down
  #      unconditionally by restore_state() -- not by an explicit `rm -rf`
  #      at the end of this block, which an early exit between creating it
  #      and reaching that line could skip (the exact gap Copilot review
  #      flagged, PR #378).
  mkdir -p "reports/$malformed_topic/findings"
  printf '{not valid json' > "reports/$malformed_topic/findings/bad.json"
  echo '[]' > "reports/$malformed_topic/ontology-map.json"
  jq --arg id "$malformed_topic" '.topics += [{id: $id, title: "gate_m31 malformed-finding test", namespace: ("harness/" + $id), status: "active", ontologies: []}]' \
    harness.config.json > "$T/config-with-malformed-topic.json" && cp "$T/config-with-malformed-topic.json" harness.config.json
  "$EXPORT" "$malformed_topic" "$T/malformed-export" > /dev/null 2>&1
  local rc_malformed=$?
  if [ "$rc_malformed" -ne 0 ] && [ ! -d "$T/malformed-export" ]; then
    ok "export fails closed on a malformed (invalid-JSON) finding file, not a silent undercount"
  else
    bad "malformed-finding export check failed (rc=$rc_malformed, output dir created: $([ -d "$T/malformed-export" ] && echo yes || echo no))"
  fi
}

gate_ontology_lock() {
  info "Ontology vendoring — pinned-lock integrity (ADR-0012)"
  # On-demand vendored domain ontologies must match their pinned sha256 (no local
  # drift; fixes go upstream). No ontologies.lock.json = vendoring not adopted in
  # this clone = nothing to verify = clean pass.
  local out rc
  out="$(scripts/check-ontology-lock.sh 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "vendored ontologies match the lock (or on-demand vendoring not adopted)"
  else
    bad "vendored ontology drift / missing pin (scripts/check-ontology-lock.sh)"
    printf '%s\n' "$out" | sed 's/^/      /' >&2
  fi

  # Only in the template repo itself ($IS_TEMPLATE): ontologies.lock.json must
  # never be git-tracked here. A committed lock freezes the registry's
  # sha256 at that commit; every later `copier update` for every instance
  # re-runs fetch-ontology.sh against this frozen pin while reconstructing
  # the pre-update baseline, so it fails closed the moment the live registry
  # moves even once, regardless of the instance's own actual pin state.
  if [ "$IS_TEMPLATE" = 1 ]; then
    if git ls-files --error-unmatch ontologies.lock.json >/dev/null 2>&1; then
      bad "ontologies.lock.json is git-tracked in the template itself — untrack it (git rm --cached), it must stay instance-derived"
    else
      ok "ontologies.lock.json is not tracked in the template (instance-derived, as intended)"
    fi
  fi
}

gate_versions() {
  info "Version consistency — change-driven model (ADR-0010)"

  # The harness versions by CHANGE, not lockstep: harness.config.json is the single
  # release pointer, the marketplace catalog tracks it, and every other stamp moves
  # only when its own component changes (so versions are legitimately heterogeneous —
  # e.g. an independently-versioned skill). The invariants that DO hold:
  #   - the template version is well-formed semver,
  #   - the marketplace catalog equals the template version,
  #   - every SKILL.md / plugin.json stamp is well-formed semver (a botched bump,
  #     e.g. a truncated or emptied stamp, fails here even though presence passes 2c-fm).
  local tpl mkt
  tpl="$(jq -r '.version // empty' harness.config.json 2>/dev/null)"
  if printf '%s' "$tpl" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    ok "harness.config.json .version is valid semver ($tpl)"
  else
    bad "harness.config.json .version is not semver: '${tpl:-MISSING}'"
  fi

  if [ -f .claude-plugin/marketplace.json ]; then
    mkt="$(jq -r '.metadata.version // empty' .claude-plugin/marketplace.json 2>/dev/null)"
    if [ -n "$tpl" ] && [ "$mkt" = "$tpl" ]; then
      ok "marketplace catalog .metadata.version tracks the template release ($mkt)"
    else
      bad "marketplace .metadata.version ('${mkt:-MISSING}') must equal the template version ('${tpl:-MISSING}')"
    fi
  fi

  local bad_stamp="" f v
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    v="$(sed -n 's/^version:[[:space:]]*//p' "$f" | head -1 | tr -d '"'"'"' ')"
    printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || bad_stamp="${bad_stamp}${f}('${v:-MISSING}') "
  done < <(find .claude/skills packs -name SKILL.md 2>/dev/null | sort)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    v="$(jq -r '.version // empty' "$f" 2>/dev/null)"
    printf '%s' "$v" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || bad_stamp="${bad_stamp}${f}('${v:-MISSING}') "
  done < <(find packs -name plugin.json 2>/dev/null | sort)
  if [ -z "$bad_stamp" ]; then
    ok "every SKILL.md / plugin.json version stamp is well-formed semver"
  else
    bad "malformed version stamps: $bad_stamp"
  fi
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5 gate_m6 gate_m7 gate_m8 gate_m9 gate_m10 gate_m11 gate_m12 gate_m13 gate_m14 gate_m15 gate_m16 gate_m17 gate_m18 gate_m19 gate_m20 gate_m21 gate_m22 gate_m23 gate_m24 gate_m25 gate_m26 gate_m27 gate_m28 gate_m29 gate_m30 gate_m31 gate_ontology_lock gate_versions)

for g in "${GATES[@]}"; do "$g"; done

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
