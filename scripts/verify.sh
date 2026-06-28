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
    #     reports/ is reports/_meta/ scaffolding (the sample-session gate fixture) plus
    #     the single ARCHIVED example research topic the template serves straight out of
    #     reports/ (example-okf-mif-knowledge-spine). On clone, scripts/seed-example-topic.sh
    #     strips the `example-` prefix; everything else under reports/ is unexpected.
    if [ -z "$(find reports -path 'reports/_meta' -prune -o -path 'reports/example-okf-mif-knowledge-spine' -prune -o -name '*.json' -print 2>/dev/null)" ]; then
      ok "template repo reports/ ships clean (_meta scaffolding + the archived example topic only)"
    else
      bad "unexpected corpus committed under reports/ (only _meta and the example topic may ship)"
      find reports -path 'reports/_meta' -prune -o -path 'reports/example-okf-mif-knowledge-spine' -prune -o -name '*.json' -print 2>/dev/null | sed 's/^/      /' >&2
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

  # 12d. NOTHING is vendor-locked. The MIF contract is first-class and evolves in-repo
  #      (it travels back to MIF), so no file may be verbatim/checksum-gated — a re-locked
  #      file would freeze the contract and block that evolution. Assert the verbatim set
  #      is EMPTY. (VENDOR.lock is retained for provenance: source/commit + seed checksums.)
  local verbatim_set
  # A missing/unreadable/invalid lock, or one whose `.files` is absent/not an array, must
  # NOT read as an empty (== "nothing locked") set and pass vacuously — fail closed. Then
  # extract the verbatim set under `jq -e` so a jq error is a failure, never an empty pass.
  if ! jq -e '.files | type == "array"' schemas/mif/VENDOR.lock >/dev/null 2>&1; then
    bad "VENDOR.lock missing, invalid JSON, or has no .files array — provenance broken (cannot assert the verbatim set)"
  elif ! verbatim_set=$(jq -er '[.files[] | select(.verbatim) | .path] | sort | join(",")' schemas/mif/VENDOR.lock); then
    bad "VENDOR.lock: could not extract the verbatim set (jq error) — fail closed"
  elif [ -z "$verbatim_set" ]; then
    ok "VENDOR.lock: nothing is verbatim-locked — the contract is first-class editable"
  else
    bad "VENDOR.lock: file(s) verbatim-locked but nothing should be: [$verbatim_set]"
  fi

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

  # 13k. The MIF-native STRUCTURAL relationship set is now harness-owned in
  #      validate-concordance.sh (moved out of the vendored mif-generic contract). Pin it:
  #      silently dropping a name would stop treating that link as structural (and start
  #      from/to-enforcing it, or reject it); adding one would over-broaden the skip.
  local expected_sc actual_sc
  expected_sc='["contradicts","depends-on","derived-from","part-of","refines","relates-to","supersedes","supports","updates"]'
  actual_sc=$(grep -E "^STRUCTURAL_CORE=" scripts/validate-concordance.sh | sed "s/^STRUCTURAL_CORE=//; s/^'//; s/'$//" | jq -cS 'sort' 2>/dev/null)
  if [ "$actual_sc" = "$expected_sc" ]; then
    ok "STRUCTURAL_CORE pinned to the 9 MIF-native structural relationships (harness-owned, not in the vendored contract)"
  else
    bad "STRUCTURAL_CORE drifted from the pinned MIF-native set: $actual_sc"
  fi

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
  # future rename can't silently dangle an edge. (Membership via grep -Fxq, not comm
  # — comm needs both inputs in its own byte collation, which a locale-aware `sort`
  # does not guarantee for type names mixing `-` and `_`.)
  local types rels orphans n r
  # LC_ALL=C: byte collation so `sort -u` cannot treat distinct names that differ
  # only in punctuation (e.g. `a-b` vs `a_b`) as equal and drop one as a "duplicate".
  types=$(for y in schemas/ontologies/*/*.yaml packs/ontologies/*/*.ontology.yaml; do
    [ -f "$y" ] && yq -o=json '.' "$y" 2>/dev/null | jq -r '.entity_types[]?.name // empty'
  done | LC_ALL=C sort -u)
  rels=$(for y in packs/ontologies/*/*.ontology.yaml; do
    [ -f "$y" ] && yq -o=json '.' "$y" 2>/dev/null | jq -r '(.relationships // {}) | to_entries[] | (.value.from[]?, .value.to[]?)'
  done | LC_ALL=C sort -u)
  orphans=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '%s\n' "$types" | grep -Fxq -- "$r" || orphans="${orphans}${r} "
  done <<< "$rels"
  n=$(printf '%s\n' "$types" | grep -c .)
  if [ -z "$orphans" ]; then
    ok "every cross-pack relationship endpoint resolves to a declared entity type ($n types across the registry)"
  else
    bad "relationship endpoint(s) declared in no registry ontology: ${orphans}"
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
  # subtype_of parent integrity across the whole registry.
  local parents types orphan="" p
  parents=$(for y in schemas/ontologies/*/*.yaml packs/ontologies/*/*.ontology.yaml; do
    [ -f "$y" ] && yq -o=json '.' "$y" 2>/dev/null | jq -r '.entity_types[]?.subtype_of[]? // empty'
  done | LC_ALL=C sort -u)
  types=$(for y in schemas/ontologies/*/*.yaml packs/ontologies/*/*.ontology.yaml; do
    [ -f "$y" ] && yq -o=json '.' "$y" 2>/dev/null | jq -r '.entity_types[]?.name // empty'
  done | LC_ALL=C sort -u)
  while IFS= read -r p; do [ -n "$p" ] || continue; printf '%s\n' "$types" | grep -Fxq -- "$p" || orphan="${orphan}${p} "; done <<< "$parents"
  if [ "$g" = 0 ] && [ "$b" != 0 ] && [ -z "$orphan" ]; then
    ok "subtype_of enforced: a security-control satisfies a control-typed edge; a non-subtype does not; every subtype_of parent is declared"
  else
    bad "subsumption wrong (substitutable-good=$g should=0; non-subtype-bad=$b should!=0; orphan-parents=[${orphan:-none}])"
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
     && grep -qF "/research-harness-template/reports/" docs/index.mdx \
     && grep -qF 'link: "/reports/"' astro.config.mjs; then
    ok "reports landing surfaced: /reports/ index page + splash link + sidebar Overview"
  else
    bad "reports landing not surfaced (need src/pages/reports.astro, a docs/index.mdx link to /research-harness-template/reports/, and the sidebar Overview link)"
  fi
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5 gate_m6 gate_m7 gate_m8 gate_m9 gate_m10 gate_m11 gate_m12 gate_m13 gate_m14 gate_m15 gate_m16 gate_m17 gate_m18 gate_m19 gate_m20 gate_m21 gate_m22 gate_m23)

for g in "${GATES[@]}"; do "$g"; done

echo
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s\n' "$RED" "$PASS" "$FAIL" "$RST"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s\n' "$GREEN" "$PASS" "$RST"
exit 0
