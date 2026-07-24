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
# Document-level frontmatter authoring, conformance, and provenance for
# document-shaped deliverables route through mif-docs-plugin (mif-mcp wired in
# .mcp.json, mifProvenance capture in .claude/settings.json) — see
# docs/reference/dependencies.md. This gate's own ajv/yq checks stay scoped to
# the findings/knowledge-graph schema substrate (ADR-0002); they are unchanged.

set -uo pipefail
# Gate scripts never read stdin; detach it (research-harness-template#531)
# so no child can block on an inherited never-EOF pipe (backgrounded
# invocations hand exactly that to every descendant).
exec </dev/null

cd "$(dirname "$0")/.." || exit 2

# gate_m20/gate_m22's whole-registry ontology-integrity scans delegate to the
# mif-rh engine (Story #287, research-harness-template#276) rather than a hand-rolled
# yq+jq registry walk. Only source the resolver function here — the engine binary
# itself is resolved lazily, INSIDE gate_m20/gate_m22 (research-harness-template#567),
# just as the other engine-dependent gates already resolve it only when they run
# (gate_m11 directly, and the gates that shell out to reconcile-session.sh /
# resolve-ontology.sh / ontology-review.sh). Removing the old unconditional
# top-of-script resolution means a `--gates`-scoped run that selects only
# engine-free gates (e.g. gate_workflows) never pays for the engine at all.
# shellcheck source=scripts/lib/engine.sh
. scripts/lib/engine.sh
# shellcheck source=scripts/lib/unreadable-probe.sh
. scripts/lib/unreadable-probe.sh

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
SKIP=0
RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; YELLOW=$'\033[33m'; RST=$'\033[0m'

ok()   { PASS=$((PASS+1)); printf '%s  ok %s %s\n' "$GREEN" "$RST" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '%sFAIL%s %s\n'   "$RED"   "$RST" "$1"; }
skip() { SKIP=$((SKIP+1)); printf '%sSKIP%s %s\n'   "$YELLOW" "$RST" "$1"; }
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
  # Exit-code discipline matters here (research-harness-template#770): git grep
  # exits 0 (match found -> contamination), 1 (no match -> genuinely clean), or
  # >1 for a real error (unsupported pathspec magic, a corrupted/partial
  # checkout, an I/O error, a future bad regex). Only exit 1 may be treated as
  # "clean" -- swallowing every other exit code via `2>/dev/null || true` let a
  # scan that never actually ran report `ok` anyway, with no trace it was
  # skipped. Capture stderr into `hits` instead of discarding it, so the >1
  # branch can surface *why* the scan failed.
  local hits rc
  hits=$(git grep -nE 'f_(tech|competitive|trends|customer|sizing|financial|regulatory)_[0-9]+|reports/[a-z0-9][a-z0-9-]+/findings_' -- \
           ':!COMPLETION-CRITERIA.md' ':!IMPLEMENTATION-PLAN.md' ':!PROGRESS.md' \
           ':!reports' 2>&1)
  rc=$?
  if [ "$rc" -eq 1 ]; then
    ok "no corpus finding IDs or corpus report-slug paths in built artifacts"
  elif [ "$rc" -eq 0 ]; then
    bad "corpus contamination found in built artifacts:"
    printf '%s\n' "$hits" >&2
  else
    bad "git grep failed during corpus contamination scrub (exit $rc), scan did not run:"
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

  # 3e. Regression guard for #383: report-synthesizer's Step 2 genre-template gate
  #     must check the SPECIFIC requested genre pack, not a nonexistent family pack
  #     literally named "reports" (every genre is its own top-level packs[] entry --
  #     that select() always returned empty, so every genre-tagged report silently
  #     fell through to neutral synthesis while frontmatter still claimed the genre
  #     was applied). Also guard against a hardcoded `reports:<genre>` Skill()
  #     namespace -- the actual genre skills in this harness are namespaced by the
  #     pack's source (e.g. `mif-docs:engineering`), never a local `reports:` family.
  #     `Skill(mif-docs:<X>)` is a real #383 regression ONLY when X is a harness
  #     packs[]-registered genre pack incorrectly resolved from its marketplace name
  #     instead of its own packs[].name; it is legitimate (ADR-0018,
  #     research-harness-template#406) when X is one of mif-docs-plugin's own
  #     always-on substrate skills, addressed directly by the plugin's real
  #     registered name -- those never go through packs[]/sync-packs.sh at all, so
  #     the pack:pack convention this guard protects doesn't apply to them.
  local RS=".claude/agents/report-synthesizer.md" rs_fail=""
  grep -qE 'select\(\.name=="reports"' "$RS" && rs_fail="${rs_fail}still greps for a nonexistent 'reports' family pack; "
  grep -qE '`reports`[^`]{0,24}(pack|genre)' "$RS" && rs_fail="${rs_fail}still describes a \`reports\` family pack in prose (review caught this leftover in the frontmatter description, worked example, and axis definition even after Step 2's own check was fixed); "
  grep -qE -- '--arg g "\$GENRE"' "$RS" || rs_fail="${rs_fail}missing the per-genre parameterized jq check; "
  grep -qE 'Skill\(reports:' "$RS" && rs_fail="${rs_fail}still hardcodes a reports: Skill() namespace; "
  # Extract every Skill(mif-docs:<X>) call and flag any X that is not one of
  # mif-docs-plugin's own always-on substrate skills (see comment above).
  if grep -oE 'Skill\(mif-docs:[A-Za-z0-9_-]+\)' "$RS" \
      | grep -vE '^Skill\(mif-docs:(mif-frontmatter|mif-validate|mif-provenance)\)$' \
      | grep -q .; then
    rs_fail="${rs_fail}resolves the Skill() namespace from source.marketplace, e.g. Skill(mif-docs:...) (Copilot review, round 2: the real convention is pack:pack, self-named from packs[].name -- source.marketplace only says where the code is FETCHED from, sync-packs.sh registers every enabled pack under this harness's own plugin namespace regardless of upstream source); "
  fi
  if [ -z "$rs_fail" ]; then
    ok "report-synthesizer.md (#383): genre gate checks the specific requested pack, not a nonexistent 'reports' family; no hardcoded reports: Skill() namespace"
  else
    bad "report-synthesizer.md (#383) regression: $rs_fail"
  fi

  # research-harness-template#645: the SAME #383 mistake, made independently in
  # research-projection.js (#633) and research-deliverables.js (#640) at the
  # genre-skill invocation site, and briefly shipped to main via #643 before
  # being caught and reverted. Genre packs go through packs[]/sync-packs.sh and
  # must invoke pack:pack (self-named from packs[].name); Skill(mif-docs:<X>)
  # is only legitimate for mif-docs-plugin's own always-on substrate skills
  # (mif-frontmatter/mif-validate/mif-provenance), which never go through
  # packs[] at all. Same detection technique as the #383 guard above, applied
  # to both workflow modules' actual source.
  local RD=".claude/workflows/research-deliverables.js" RP=".claude/workflows/research-projection.js" genre_fail=""
  for f in "$RD" "$RP"; do
    if grep -oE 'Skill\(mif-docs:\$\{[A-Za-z0-9_.]+\}\)' "$f" | grep -q .; then
      genre_fail="${genre_fail}${f} interpolates a genre variable into Skill(mif-docs:\${...}) — genre packs are self-named (pack:pack), never namespaced under mif-docs (#645); "
    fi
    if grep -E '"mif-docs:<genre>"|Skill\(mif-docs:<genre>\)' "$f" | grep -vE 'NOT `?Skill\(mif-docs' | grep -q .; then
      genre_fail="${genre_fail}${f} still documents the wrong Skill(mif-docs:<genre>) convention in a comment/schema description (#645); "
    fi
  done
  if [ -z "$genre_fail" ]; then
    ok "research-projection.js/research-deliverables.js (#645): genre-skill invocation stays pack:pack (self-named), never mif-docs:<genre>"
  else
    bad "genre-skill invocation regression (#645): $genre_fail"
  fi

  # research-harness-template#479: render-artifact.sh's report-channel publish
  # is a raw filesystem mv, invisible to mif-docs-plugin's Write/Edit/MultiEdit-
  # only provenance-capture hook. Step 4d's `stamp` call can only ever succeed
  # if the rendered content is re-published through the Write tool first --
  # require that instruction survive, and land strictly between the Step 4b
  # and Step 4d headings (line-number check, not just phrase presence: a
  # regression that moved this step outside that window would otherwise
  # still pass a presence-only check).
  local rs4b_line rs4d_line rs_repub_line rs_write_line rs479_fail=""
  rs4b_line=$(grep -n '^## Step 4b' "$RS" | head -1 | cut -d: -f1)
  rs4d_line=$(grep -n '^## Step 4d' "$RS" | head -1 | cut -d: -f1)
  rs_repub_line=$(grep -n 're-publish the identical' "$RS" | head -1 | cut -d: -f1)
  rs_write_line=$(grep -niE 'Write.*that exact same content back' "$RS" | head -1 | cut -d: -f1)
  if [ -z "$rs4b_line" ] || [ -z "$rs4d_line" ] || [ -z "$rs_repub_line" ] || [ -z "$rs_write_line" ]; then
    rs479_fail="one or more required markers (Step 4b/4d headings, re-publish phrase, Write-back phrase) is missing entirely"
  elif ! { [ "$rs_repub_line" -gt "$rs4b_line" ] && [ "$rs_write_line" -gt "$rs_repub_line" ] && [ "$rs_write_line" -lt "$rs4d_line" ]; }; then
    rs479_fail="the Write-tool re-publish step no longer lands between the Step 4b and Step 4d headings"
  fi
  if [ -z "$rs479_fail" ]; then
    ok "report-synthesizer.md (#479): Write-tool re-publish step present between Step 4b and Step 4d"
  else
    bad "report-synthesizer.md (#479) regression: $rs479_fail -- render-artifact.sh's raw mv needs it there to make Step 4d's stamp reachable."
  fi

  # research-harness-template#671: report-synthesizer's Step 1 survivor-selection
  # loop and Step 4 citation-integrity call must glob the canonical
  # $REPORTS_DIR/findings/ subdirectory that every producer (dimension-analyst,
  # source-chunker) writes to and every other consumer (orchestrator,
  # falsification-analyst, /status, /falsify) reads from. The shipped flat glob
  # ("$REPORTS_DIR"/finding-*.json) matched nothing on a real session: with
  # nullglob unset the loop iterated once over the literal unexpanded pattern,
  # so synthesis saw an empty survivor set and the citation-integrity gate
  # never ran over the real findings.
  local rs671_fail=""
  grep -qE '"\$REPORTS_DIR"/finding-\*\.json' "$RS" \
    && rs671_fail="${rs671_fail}still globs finding-*.json flat under \$REPORTS_DIR instead of the findings/ subdirectory; "
  grep -qE 'for f in "\$REPORTS_DIR"/findings/finding-\*\.json' "$RS" \
    || rs671_fail="${rs671_fail}Step 1 survivor-selection loop no longer iterates \$REPORTS_DIR/findings/finding-*.json; "
  grep -qE 'check-citation-integrity\.sh "\$REPORTS_DIR"/findings/finding-\*\.json' "$RS" \
    || rs671_fail="${rs671_fail}Step 4 citation-integrity call no longer targets \$REPORTS_DIR/findings/finding-*.json; "
  if [ -z "$rs671_fail" ]; then
    ok "report-synthesizer.md (#671): Step 1/Step 4 finding globs target the canonical findings/ subdirectory"
  else
    bad "report-synthesizer.md (#671) regression: $rs671_fail"
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

  # 4b2. The per-topic knowledge graph has a structural conformance gate of its
  #      own (#630): both the schema's bundled sample and the freshly built
  #      sample-session graph must validate against knowledge-graph.schema.json.
  if ajv_plain schemas/knowledge-graph.schema.json schemas/samples/knowledge-graph.sample.json \
     && ajv_plain schemas/knowledge-graph.schema.json "$KG"; then
    ok "knowledge graph validates against knowledge-graph.schema.json"
  else
    bad "knowledge graph failed schema validation against knowledge-graph.schema.json"
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
  local T; T="$(mktemp -d)" || { bad "gate_m5: failed to create a scratch directory (5c)"; return 1; }
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
  T="$(mktemp -d)" || { bad "gate_m5: failed to create a scratch directory (5d2)"; return 1; }
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
  T="$(mktemp -d)" || { bad "gate_m5: failed to create a scratch directory (5d3)"; return 1; }
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
  # ...and the pack must ALSO be fail-closed out of the native enabledPlugins
  # map and the sidecar's enabledPlugins list — the sidecar error alone is not
  # a runtime signal, so an unresolved pack must never surface as enabled
  # (regression test for research-harness-template#669).
  enable_ok=false
  if [ "$(jq -r '.enabledPlugins | has("typo-demo@research-harness") | not' "$T/settings-typo.json")" = "true" ] \
     && [ "$(jq -r '.enabledPlugins | index("typo-demo") == null' "$T/typo.json")" = "true" ]; then
    enable_ok=true
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
  if [ "$sync_ok" = "true" ] && [ "$check_ok" = "true" ] && [ "$enable_ok" = "true" ]; then
    ok "an unresolvable marketplace-ref name surfaces an explicit error and is excluded from enabledPlugins"
  else
    bad "unresolved marketplace-ref regression (sync_ok=$sync_ok check_ok=$check_ok enable_ok=$enable_ok)"
  fi
  rm -rf "$T"

  # 5d4. A bundled pack whose manifest is missing/unreadable is fail-closed the
  #      same way as an unresolved marketplace-ref (Copilot review on
  #      research-harness-template#714): the sidecar records the error, and the
  #      pack is excluded from both the native enabledPlugins map and the
  #      sidecar's enabledPlugins list.
  T="$(mktemp -d)" || { bad "gate_m5: failed to create a scratch directory (5d4)"; return 1; }
  cp .claude/settings.json "$T/settings-ghost.json"
  jq '.packs += [{"name":"ghost-bundled","enabled":true,"source":"bundled"}]' \
     harness.config.json > "$T/ghost.cfg.json"
  if scripts/sync-packs.sh "$T/ghost.cfg.json" "$T/ghost.json" "$T/settings-ghost.json" >/dev/null 2>&1 \
     && [ "$(jq -r '.packs[]|select(.name=="ghost-bundled")|.error' "$T/ghost.json")" != "null" ] \
     && [ "$(jq -r '.enabledPlugins | has("ghost-bundled@research-harness") | not' "$T/settings-ghost.json")" = "true" ] \
     && [ "$(jq -r '.enabledPlugins | index("ghost-bundled") == null' "$T/ghost.json")" = "true" ]; then
    ok "a bundled pack with an unreadable manifest is excluded from enabledPlugins (fail closed)"
  else
    bad "unreadable bundled manifest not fail-closed out of enabledPlugins"
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

  # 7b/7c. The eval suite and the copier-update propagation eval are part of
  # Milestone 7's acceptance, but they are ALSO the documented gate chain's
  # own separate steps (CLAUDE.md) and CI's own separate steps in the same
  # required job (ci.yml runs verify.sh, then run-evals.sh, then
  # copier-update.sh) -- re-running them inside verify.sh executed every
  # eval twice and was 76% of the suite's wall time (269s of 353s, profiled
  # for #531). Default: defer to the separate steps with a loud pointer;
  # VERIFY_INCLUDE_EVALS=1 opts back into the all-in-one behavior for
  # anyone who wants a single self-contained command.
  if [ "${VERIFY_INCLUDE_EVALS:-0}" = "1" ]; then
    if bash evals/run-evals.sh >/dev/null 2>&1; then
      ok "eval suite passes (evals/run-evals.sh)"
    else
      bad "eval suite failed"
      bash evals/run-evals.sh 2>&1 | sed 's/^/      /' >&2
    fi

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
  else
    ok "eval suite + copier-update run as their own gate-chain steps (bash evals/run-evals.sh; bash evals/copier-update.sh) — set VERIFY_INCLUDE_EVALS=1 to run them inside verify.sh (#531)"
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

  # 12l. Namespace-suggestion integrity (#686): every namespace path a COMMITTED
  #      base layer's (schemas/ontologies/) discovery config suggests —
  #      patterns[].suggest_namespace, content_patterns[].namespace/namespaces[],
  #      file_patterns[].namespaces[] — must resolve within the namespace tree
  #      the layer itself declares MERGED with its transitive extends chain
  #      (among base layers). Catches the defect class where a pack declares
  #      children under a bare `semantic:` key while its own discovery suggests
  #      the underscore-prefixed `_semantic/...` mif-base root. Vendored packs
  #      (packs/ontologies/) are lock-pinned; their fixes belong upstream, so
  #      they are out of scope here.
  ns_declared() { # ns_declared <yaml> -> declared namespace paths, one per line
    yq -o=json '.' "$1" 2>/dev/null | jq -r '
      def walk_ns($prefix): to_entries[]
        | ($prefix + [.key]) as $p
        | ($p | join("/")), ((.value.children // {}) | walk_ns($p));
      .namespaces // {} | walk_ns([])' 2>/dev/null
  }
  ns_suggested() { # ns_suggested <yaml> -> discovery-suggested namespace paths
    yq -o=json '.' "$1" 2>/dev/null | jq -r '
      [ ((.discovery.patterns // [])[] | .suggest_namespace),
        ((.discovery.content_patterns // [])[] | .namespace, ((.namespaces // [])[])),
        ((.discovery.file_patterns // [])[] | ((.namespaces // [])[])) ]
      | .[] | select(. != null)' 2>/dev/null
  }
  local NSD; NSD="$(mktemp -d)"
  local base_yaml oid
  while IFS= read -r base_yaml; do
    [ -z "$base_yaml" ] && continue
    oid=$(yq -r '.ontology.id // ""' "$base_yaml" 2>/dev/null)
    [ -z "$oid" ] && continue
    printf '%s\n' "$base_yaml" > "$NSD/file.$oid"
    yq -r '.ontology.extends // [] | .[]' "$base_yaml" 2>/dev/null > "$NSD/ext.$oid"
  done < <(find schemas/ontologies -mindepth 2 -maxdepth 2 -type f -name '*.yaml' | sort)
  local ns_bad=""
  for f in "$NSD"/file.*; do
    oid="${f##*/file.}"
    base_yaml="$(cat "$f")"
    # Transitive extends closure among committed base layers (unknown ids skipped:
    # they are not resolvable here and contribute no namespaces either way).
    local seen=" $oid " queue="$oid" cur ext
    : > "$NSD/declared"
    while [ -n "$queue" ]; do
      cur="${queue%% *}"; queue="${queue#"$cur"}"; queue="${queue# }"
      [ -f "$NSD/file.$cur" ] && ns_declared "$(cat "$NSD/file.$cur")" >> "$NSD/declared"
      if [ -f "$NSD/ext.$cur" ]; then
        while IFS= read -r ext; do
          [ -z "$ext" ] && continue
          case "$seen" in *" $ext "*) ;; *) seen="$seen$ext "; queue="${queue:+$queue }$ext" ;; esac
        done < "$NSD/ext.$cur"
      fi
    done
    sort -u "$NSD/declared" -o "$NSD/declared"
    local sug
    while IFS= read -r sug; do
      [ -z "$sug" ] && continue
      grep -qxF "$sug" "$NSD/declared" || ns_bad="${ns_bad}${oid}:${sug} "
    done < <(ns_suggested "$base_yaml" | sort -u)
  done
  rm -rf "$NSD"
  if [ -z "$ns_bad" ]; then
    ok "every base-layer discovery-suggested namespace resolves in its own+extends declared tree"
  else
    bad "discovery suggests namespaces never declared (own+extends): ${ns_bad}"
  fi

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

  # 14d. Regression: a DOUBLE-QUOTED path argument DIRECTLY on the invocation
  #      (`scripts/falsify.sh "reports/.../findings/f.json"`) within an open
  #      window is allowed -- this is issue #372's own first reported repro
  #      shape; it already passes because of #356's fix (a positive
  #      path-character class that excludes quote characters from the
  #      extracted path, closing both the quoted-VARIABLE-ASSIGNMENT shape
  #      #356 itself reported, `F="reports/..."`, and this quoted-DIRECT-
  #      ARGUMENT shape, incidentally, since both corrupt TOPIC_DIR the same
  #      way). Kept here under #372 since that's the shape #372 reported as
  #      still broken; #356 is the fix that actually makes it pass.
  rm -f "$T/reports/tA/.gate-active"; touch "$T/reports/tA/.gate-active"
  local d_quoted
  d_quoted=$(hd '{"tool_input":{"command":"scripts/falsify.sh \"reports/tA/findings/f.json\" fx"}}')
  if [ "$d_quoted" = allow ]; then
    ok "phase-gate hook (#372's own repro, fixed by #356): a double-quoted path argument within an open window is allowed"
  else
    bad "phase-gate hook #372/#356 regression (quoted=$d_quoted)"
  fi

  # 14e. Regression test for issue #372's REVERTED fix attempt: every one of
  #      these real-invocation shapes must still be DENIED with no window
  #      open. An anchored-to-invocation-position regex tried for #372 (to
  #      stop the false deny in 14f below) was reverted after code review
  #      found it let every one of these bypass the gate silently instead --
  #      including this repo's OWN established `$CLAUDE_PROJECT_DIR/scripts/
  #      falsify.sh` convention (.claude/skills/publish-report/evals/
  #      evals.json). The broad, unanchored substring check restored above
  #      has none of these gaps; this test exists to keep it that way -- any
  #      future attempt to narrow that check must keep every one of these DENY.
  rm -f "$T/reports/tA/.gate-active"
  local -a bypass_cmds=(
    'FOO=bar scripts/falsify.sh reports/tA/findings/f.json fx'
    'command scripts/falsify.sh reports/tA/findings/f.json fx'
    'env scripts/falsify.sh reports/tA/findings/f.json fx'
    'time scripts/falsify.sh reports/tA/findings/f.json fx'
    'sudo scripts/falsify.sh reports/tA/findings/f.json fx'
    'for f in reports/tA/findings/*.json; do scripts/falsify.sh "$f" fx; done'
    'printf "%s\n" "reports/tA/findings/f.json" | xargs -I{} scripts/falsify.sh {} fx'
    'sh -c "scripts/falsify.sh reports/tA/findings/f.json fx"'
    '$CLAUDE_PROJECT_DIR/scripts/falsify.sh reports/tA/findings/f.json fx'
    '${HARNESS_ROOT}/scripts/falsify.sh reports/tA/findings/f.json fx'
    '"scripts/falsify.sh" reports/tA/findings/f.json fx'
    '/bin/bash scripts/falsify.sh reports/tA/findings/f.json fx'
    'env bash scripts/falsify.sh reports/tA/findings/f.json fx'
    'zsh scripts/falsify.sh reports/tA/findings/f.json fx'
  )
  local bypass_fail="" cmd_json d_bypass c
  for c in "${bypass_cmds[@]+"${bypass_cmds[@]}"}"; do
    cmd_json="$(jq -cn --arg c "$c" '{tool_input:{command:$c}}')"
    d_bypass="$(hd "$cmd_json")"
    [ "$d_bypass" = deny ] || bypass_fail="${bypass_fail}[$c -> $d_bypass] "
  done
  if [ -z "$bypass_fail" ]; then
    ok "phase-gate hook (#372 follow-up): every real-invocation bypass shape found in review (env-prefix, command/env/time/sudo, loop, xargs, sh -c, \$VAR-prefixed path, quoted command name, alternate interpreter) is still denied with no window open"
  else
    bad "phase-gate hook bypass regression: $bypass_fail"
  fi

  # 14f. Known, accepted false DENY (issue #372): a command that only
  #      MENTIONS "falsify.sh" as quoted documentation text (e.g. a
  #      `gh issue create --body "..."` heredoc reproducing a bug) is denied
  #      even though it never invokes the script. Narrowing the check to
  #      avoid this was tried and reverted (14e above) -- every attempt let a
  #      REAL invocation through unguarded instead, unbounded worse than this
  #      false deny. This assertion documents the accepted tradeoff so a
  #      future change that "fixes" this by re-narrowing the check is caught
  #      here first, before it can reach 14e's bypass shapes.
  local d_overmatch
  d_overmatch=$(hd '{"tool_input":{"command":"gh issue create --body \"example: scripts/falsify.sh \\\"reports/tA/findings/f.json\\\"\""}}')
  if [ "$d_overmatch" = deny ]; then
    ok "phase-gate hook (#372, known limitation): a doc-text mention of falsify.sh with no window open is denied (accepted false deny, not re-narrowed)"
  else
    bad "phase-gate hook: doc-text mention no longer denied (d=$d_overmatch) -- the check was re-narrowed; re-verify against every 14e bypass shape before accepting this"
  fi

  # 14g. A real, unquoted invocation with no window open is still denied.
  local d_real_noquotes
  d_real_noquotes=$(hd '{"tool_input":{"command":"scripts/falsify.sh reports/tA/findings/f.json fx"}}')
  if [ "$d_real_noquotes" = deny ]; then
    ok "phase-gate hook: a real, unquoted invocation is denied with no window open"
  else
    bad "phase-gate hook: real invocation not denied (d=$d_real_noquotes)"
  fi

  # 14h. Regression test for #384: falsify.sh ITSELF refuses to grade a topic's
  #      session findings without a fresh gate window, independent of the
  #      PreToolUse hook -- this is what makes every 14e bypass shape (env-var
  #      prefix, a loop, an interpreter wrapper, ...) harmless even though the
  #      hook's own substring match misses some of them: the script the
  #      command eventually reaches still refuses to run. A non-findings
  #      target (a report-finding) is never gated, with no window open at all.
  mkdir -p "$T/reports/tA/findings"
  printf '{"@id":"urn:mif:concept:t:f2","title":"x"}\n' > "$T/reports/tA/findings/f2.json"
  printf '{"@id":"urn:mif:concept:t:rf","title":"x"}\n' > "$T/reports/tA/report-finding.json"
  rm -f "$T/reports/tA/.gate-active"
  local fs_no_window_rc
  scripts/falsify.sh "$T/reports/tA/findings/f2.json" >/dev/null 2>&1; fs_no_window_rc=$?
  local fs_report_vd
  fs_report_vd=$(scripts/falsify.sh "$T/reports/tA/report-finding.json" 2>/dev/null | jq -r '.extensions.harness.verification.verdict // empty')
  touch "$T/reports/tA/.gate-active"
  local fs_open_vd
  fs_open_vd=$(scripts/falsify.sh "$T/reports/tA/findings/f2.json" 2>/dev/null | jq -r '.extensions.harness.verification.verdict')
  touch -t 200001010000 "$T/reports/tA/.gate-active"
  local fs_stale_rc
  scripts/falsify.sh "$T/reports/tA/findings/f2.json" >/dev/null 2>&1; fs_stale_rc=$?
  if [ "$fs_no_window_rc" != 0 ] && [ "$fs_report_vd" = "inconclusive" ] && [ "$fs_open_vd" = "inconclusive" ] && [ "$fs_stale_rc" != 0 ]; then
    ok "falsify.sh (#384): refuses to grade a session finding with no/stale gate window open, independent of the hook; grades it once the window is fresh; a report-finding target is never gated"
  else
    bad "falsify.sh (#384) gate check wrong (no-window rc=$fs_no_window_rc report-verdict=$fs_report_vd open-verdict=$fs_open_vd stale rc=$fs_stale_rc)"
  fi

  # 14i. Regression test for a review-caught gap in #384's own fix: a BARE
  #      relative argument invoked with the caller's cwd already INSIDE the
  #      findings/ directory (`cd reports/t/findings && falsify.sh f.json`)
  #      has no "findings/" path segment in the raw argument, so matching
  #      against $FINDING as typed (rather than its resolved absolute form)
  #      missed this shape entirely -- the exact "cd-into-findings" bypass
  #      guard-falsify-gate.sh's own LIMITATIONS block documents as a
  #      hook-miss, reproduced live in review as a SILENT miss in the script
  #      that was supposed to close it independent of the hook.
  local FALSIFY_ABS; FALSIFY_ABS="$(cd scripts && pwd)/falsify.sh"
  rm -f "$T/reports/tA/.gate-active"
  local fs_cd_no_window_rc
  (cd "$T/reports/tA/findings" && "$FALSIFY_ABS" f2.json >/dev/null 2>&1); fs_cd_no_window_rc=$?
  touch "$T/reports/tA/.gate-active"
  local fs_cd_open_vd
  fs_cd_open_vd=$(cd "$T/reports/tA/findings" && "$FALSIFY_ABS" f2.json 2>/dev/null | jq -r '.extensions.harness.verification.verdict')
  if [ "$fs_cd_no_window_rc" != 0 ] && [ "$fs_cd_open_vd" = "inconclusive" ]; then
    ok "falsify.sh (#384 review follow-up): a bare relative arg invoked from inside findings/ is still refused with no window open (resolved to its real absolute path, not matched on the raw argument)"
  else
    bad "falsify.sh cd-into-findings bypass regression (no-window rc=$fs_cd_no_window_rc, fresh-window verdict=$fs_cd_open_vd)"
  fi

  # 14j. Regression test for a second Copilot-caught gap in the SAME fix: a
  #      DOTTED relative argument from inside findings/ (`./f.json`) made a
  #      plain $PWD-prefix resolve to ".../findings/./f.json" -- dirname
  #      twice over that yields TOPIC_DIR=".../findings" (dirname of
  #      "findings/." is "findings" itself), one level too deep, so MARKER
  #      pointed at a path that can never exist. Not a bypass (it fails
  #      CLOSED, refusing even a legitimate call with the window open) but
  #      still wrong -- falsify.sh now `cd`s into the finding's own
  #      directory and reads `pwd` to canonicalize "." before matching.
  rm -f "$T/reports/tA/.gate-active"
  local fs_dotcd_no_window_rc
  (cd "$T/reports/tA/findings" && "$FALSIFY_ABS" ./f2.json >/dev/null 2>&1); fs_dotcd_no_window_rc=$?
  touch "$T/reports/tA/.gate-active"
  local fs_dotcd_open_vd
  fs_dotcd_open_vd=$(cd "$T/reports/tA/findings" && "$FALSIFY_ABS" ./f2.json 2>/dev/null | jq -r '.extensions.harness.verification.verdict')
  if [ "$fs_dotcd_no_window_rc" != 0 ] && [ "$fs_dotcd_open_vd" = "inconclusive" ]; then
    ok "falsify.sh (#384 Copilot review follow-up): a DOTTED relative arg ('./f.json') from inside findings/ resolves to the real topic dir, not one level too deep"
  else
    bad "falsify.sh dotted-relative-path regression (no-window rc=$fs_dotcd_no_window_rc, fresh-window verdict=$fs_dotcd_open_vd)"
  fi

  # 14k. Regression test for a THIRD Copilot-caught gap (review round 2): the
  #      original `*/findings/*.json` pattern matched ANY path containing a
  #      "findings/" segment anywhere, not just a real
  #      reports/<topic>/findings/ session-finding path -- an unrelated path
  #      like /tmp/findings/x.json would be misclassified as gated and
  #      unexpectedly refused. The pattern is now anchored to require a
  #      "reports/" segment before "findings/", matching the hook's own
  #      regex scope. A non-report findings/ path must NEVER be gated, with
  #      no window open at all.
  mkdir -p "$T/unrelated/findings"
  printf '{"@id":"urn:mif:concept:t:uf","title":"x"}\n' > "$T/unrelated/findings/uf.json"
  local fs_unrelated_vd
  fs_unrelated_vd=$(scripts/falsify.sh "$T/unrelated/findings/uf.json" 2>/dev/null | jq -r '.extensions.harness.verification.verdict // empty')
  if [ "$fs_unrelated_vd" = "inconclusive" ]; then
    ok "falsify.sh (#384 Copilot review round 2): an unrelated findings/ path outside reports/<topic>/ is never gated, even with no window open"
  else
    bad "falsify.sh over-broad findings/ match regression (verdict=$fs_unrelated_vd)"
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

  # 19c. evals/release-workflow-immutable-safe.sh must skip in an instance — the
  #      same defect class as 19a's copier-update.sh guard (issue #85 D1), reported
  #      separately as #616: .github/workflows/release.yml only exists in the
  #      template (cutting a Release is the template's own distribution concern),
  #      so this eval failed hard, permanently, in every instantiated clone.
  #      Lock the exact guard condition (a missing copier.yml, the same IS_TEMPLATE
  #      signal scripts/verify.sh's own gate_* functions use, #507).
  if grep -qE '^[[:space:]]*if \[ ! -f copier\.yml \]; then' evals/release-workflow-immutable-safe.sh; then
    ok "release-workflow-immutable-safe.sh guard matches the IS_TEMPLATE instance condition (missing copier.yml)"
  else
    bad "release-workflow-immutable-safe.sh guard does not match '[ ! -f copier.yml ]' — a regressed guard could fail hard in every instance again (#616)"
  fi
  # Behaviorally exercise the guard: copy the real script into a throwaway repo with
  # NO copier.yml (an instance) and confirm it actually SKIPs rather than failing on
  # the also-absent .github/workflows/release.yml. The template path (copier.yml
  # present -> runs the real assertions) is covered by this same eval running fully
  # as part of `bash evals/run-evals.sh` in the template's own CI.
  local rt; rt="$(mktemp -d)"
  mkdir -p "$rt/evals"
  cp evals/release-workflow-immutable-safe.sh "$rt/evals/release-workflow-immutable-safe.sh"
  if ( cd "$rt" && bash evals/release-workflow-immutable-safe.sh 2>/dev/null | grep -q '^release-workflow-immutable-safe: SKIP' ); then
    ok "release-workflow-immutable-safe.sh behaviorally SKIPs in an instance (no copier.yml, no release.yml)"
  else
    bad "release-workflow-immutable-safe.sh did NOT skip in an instance — instance CI would fail (#616)"
  fi
  rm -rf "$rt"
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
  # Resolved lazily here (research-harness-template#567) rather than unconditionally
  # at the top of the script, so a `--gates`-scoped run that doesn't select this
  # gate never hard-requires the engine binary.
  local ENGINE reg_out reg_err reg_n reg_orphans
  ENGINE="$(engine_bin "$(pwd)")" || { bad "gate_m20 needs the mif-rh-cli engine for check-ontology-registry (not found/too old — see the engine: diagnostic above)"; return; }
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
  # the mif-rh engine (mif-rh-cli harness check-ontology-registry). Resolved lazily
  # here (research-harness-template#567) rather than unconditionally at the top of
  # the script, so a `--gates`-scoped run that doesn't select this gate never
  # hard-requires the engine binary.
  local ENGINE reg_out reg_err orphan
  ENGINE="$(engine_bin "$(pwd)")" || { bad "gate_m22 needs the mif-rh-cli engine for check-ontology-registry (not found/too old — see the engine: diagnostic above)"; rm -rf "$T"; return; }
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
  #      index. Only _meta/findings + the *-delta/*-build-spec/*-kiro-{requirements,design,tasks}
  #      build logs stay excluded (research-harness-template#414: the kiro-spec split added the
  #      last three).
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
     && grep -qF "!reports/**/*-kiro-requirements.md" "$cc" \
     && grep -qF "!reports/**/*-kiro-design.md" "$cc" \
     && grep -qF "!reports/**/*-kiro-tasks.md" "$cc" \
     && ! grep -qF "!reports/**/README.md" "$cc" \
     && ! grep -qF "!reports/**/*-falsification-report.md" "$cc" \
     && ! grep -qF "!reports/**/research-progress.md" "$cc" \
     && [ "$(readlink docs/reports 2>/dev/null)" = "../reports" ] \
     && [ "$(readlink src/content/docs 2>/dev/null)" = "../../docs" ]; then
    ok "content.config.ts serves the full deliverable tree via the derived-title loader (README index re-slug; _meta/findings/build-log negations kept; the README/falsification/progress negations removed; both site symlinks)"
  else
    bad "reports binding regressed (need the reportsLoader/deriveTitleFromH1/generateId glob at base './src/content/docs', the README+falsification+research-progress negations REMOVED so they render, _meta/findings/*-delta/*-build-spec/*-kiro-* kept, and the docs/reports + src/content/docs symlinks)"
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
    local edir=reports/example-okf-mif-knowledge-spine all_titled=1 d
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
    # Search the WHOLE _tasks: block, not a fixed line window after it
    # (research-harness-template#733) -- a hardcoded `-A3` broke the instant a
    # task-ordering comment grew past 3 lines, even though the task itself was
    # still present and correctly configured; the block's real end is the
    # next top-level `_message_after_copy:` key, not an arbitrary line count.
    if awk '
        /^_tasks:/ { in_block = 1; next }
        in_block && /^_message_after_copy:/ { in_block = 0 }
        in_block { print }
      ' copier.yml | grep -qF "site-toggle.sh primary reports"; then
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
  local m3 rc3
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
  local mj rcj
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
  local rck
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

  # 24n. Regression (#768): m3, rc3, mj, rcj, and rck (used by 24i/24j/24k
  #      above) must be declared `local`, or they leak into verify.sh's own
  #      global namespace once gate_m24 returns (GATES runs each gate
  #      un-subshelled) — a future gate reusing one of these short, generic
  #      names would then silently inherit gate_m24's last value under
  #      `set -uo pipefail` instead of starting unset. Introspects the live
  #      function body via `declare -f` rather than re-invoking gate_m24, so
  #      it can't recurse into itself.
  local body24n missing24n v24n
  body24n="$(declare -f gate_m24)"
  missing24n=""
  for v24n in m3 rc3 mj rcj rck; do
    if ! printf '%s\n' "$body24n" | grep -E '\blocal\b' | grep -wq "$v24n"; then
      missing24n="$missing24n $v24n"
    fi
  done
  if [ -z "$missing24n" ]; then
    ok "m3/rc3/mj/rcj/rck are declared local in gate_m24 (no unscoped-global leak, #768)"
  else
    bad "gate_m24 leaks unscoped globals — missing 'local' for:$missing24n (#768)"
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
  #
  #      chmod 000 does not deny root -- or any other DAC_OVERRIDE-capable
  #      process, e.g. a root-uid Docker/devcontainer verify.sh run -- the
  #      ability to read the file (research-harness-template#777). Probe
  #      readability after chmod 000 and, if it's still readable, the
  #      fail-closed premise doesn't hold: SKIP the assertion explicitly
  #      rather than silently invalidating it into a false FAIL against a
  #      working, unmodified digest script.
  local out rc bypassed=0
  printf 'x' > "$T/unreadable.txt"; chmod 000 "$T/unreadable.txt"
  [ -r "$T/unreadable.txt" ] && bypassed=1
  if [ "$bypassed" = "0" ]; then
    out="$(scripts/mif-container-digest.sh resource "$T/unreadable.txt" 2>/dev/null)"; rc=$?
  else
    out=""; rc=0
  fi
  chmod 644 "$T/unreadable.txt"
  case "$(m27_classify_unreadable_probe "$bypassed" "$rc" "$out")" in
    skip) skip "resource digest unreadable-file fail-closed check (chmod 000 did not deny read -- running as root or with DAC override; premise does not hold, #777)" ;;
    ok)   ok "resource digest fails closed on an unreadable file (permission denied), not a malformed empty digest" ;;
    *)    bad "resource digest did not fail closed on an unreadable file (rc=$rc out='$out')" ;;
  esac

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
  # `timeout` is GNU coreutils (Linux/CI); stock macOS lacks it but Homebrew
  # coreutils ships it as `gtimeout` (same fallback scripts/write-finding.sh
  # already uses). Unlike write-finding.sh's ajv call, this check exists
  # specifically to bound a known hang regression (see comment above) --
  # running it unwrapped when neither binary is present would silently
  # reintroduce the exact failure mode it guards against, so with neither on
  # PATH this check is skipped (info, not bad/ok) rather than hard-failing
  # or running unbounded, matching 27a's sha256sum/shasum precedent of
  # degrading gracefully instead of hard-failing on an absent optional tool.
  local TMO=""
  if command -v timeout >/dev/null 2>&1; then TMO="timeout 5"
  elif command -v gtimeout >/dev/null 2>&1; then TMO="gtimeout 5"
  fi
  if [ -z "$TMO" ]; then
    info "resolver hang-regression check skipped -- neither 'timeout' nor 'gtimeout' is on PATH (install GNU coreutils, e.g. 'brew install coreutils' on macOS, to run it locally; CI's ubuntu-latest always has 'timeout')"
  else
    $TMO "$RESOLVE" "$T/graph-no-edges.json" "$T/partial-scope.json" --closure >/dev/null 2>&1
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
  # Declared here (not at 29p, where they're used), same rationale as
  # badontmap_topic above: restore_snapshot's cleanup below must be able to
  # reference them unconditionally, not depend on 29p having run.
  local CONTAINER_LOCK_LIB="scripts/lib/container-lock.sh"
  local ontlock_topic_full="gate-m29-771-ontlock-full"
  local ontlock_topic_subset="gate-m29-771-ontlock-subset"
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
    # 29p (issue #771) instrumentation cleanup: restore the real
    # container-lock.sh unconditionally if a backup was ever taken (best
    # effort even if 29p itself never ran or died mid-way), and remove its
    # two synthetic topics.
    if [ -f "$T/container-lock.sh.orig" ]; then
      cp "$T/container-lock.sh.orig" "$CONTAINER_LOCK_LIB" \
        || bad "gate_m29 restore_snapshot: failed to restore $CONTAINER_LOCK_LIB -- real corpus may be left mutated"
    fi
    rm -rf "reports/$ontlock_topic_full" "reports/$ontlock_topic_subset"
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

  # 29j2. Regression test for #382: a STALE lock (mtime older than
  #      CONTAINER_LOCK_STALE_MIN, left behind by e.g. a killed import that
  #      never reached its EXIT trap) is safely STOLEN instead of wedging
  #      every later export/import on the topic forever; a fresh lock is
  #      still denied (mirrors gate_m31's 31a3 for export's own copy of this
  #      shared lock primitive).
  mkdir -p "$TOPIC_DIR/.container.lock"
  touch -t 200001010000 "$TOPIC_DIR/.container.lock"
  "$IMPORT" "$T/c-noop" "$TOPIC" >/dev/null 2>&1
  local rc_stale=$?
  local stale_ok=0
  [ "$rc_stale" -eq 0 ] && [ ! -d "$TOPIC_DIR/.container.lock" ] && stale_ok=1
  rm -rf "$TOPIC_DIR/.container.lock"
  if [ "$stale_ok" -eq 1 ]; then
    ok "container-lock (#382): import steals a STALE .container.lock instead of wedging the topic forever"
  else
    bad "container-lock (#382) import staleness regression (rc=$rc_stale ok=$stale_ok)"
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

  # 29l. Regression (issue #668): the existing-@id lookup must match on the
  #      PARSED @id, never on jq-pretty-printed bytes. Re-serialize the
  #      synthetic finding written in 29f/29g as COMPACT JSON on disk (same
  #      @id, no '": "' spacing -- schema-legal: findings.schema.json
  #      constrains only the @id VALUE, never the byte layout), then
  #      re-import the same @id with different content under a DIFFERENT
  #      resource filename. The earlier byte-pattern grep found no match on
  #      the compact file and fell through to the brand-new-@id branch,
  #      writing a SECOND file for the same @id -- silently creating the
  #      exact duplicate-@id corruption this script otherwise fails closed
  #      on. The fixed lookup must find the compact file and overwrite it IN
  #      PLACE: import succeeds, no compact-dup.json lands, and exactly one
  #      file in the destination carries the @id.
  jq -c . "$TOPIC_DIR/findings/finding.json" > "$T/compact.json" \
    && cp "$T/compact.json" "$TOPIC_DIR/findings/finding.json" \
    || bad "gate_m29 29l: failed to re-serialize finding.json as compact JSON"
  jq '.summary = "gate_m29 compact-json lookup regression test"' "$T/new-finding-v2.json" > "$T/new-finding-v3.json"
  local v3_digest; v3_digest="$(scripts/mif-container-digest.sh resource "$T/new-finding-v3.json")"
  local v3_manifest_digest; v3_manifest_digest="$(printf '%s\n' "$v3_digest" | scripts/mif-container-digest.sh manifest)"
  build_container "$T/c-compact" "$T/new-finding-v3.json" "$v3_digest" "$v3_manifest_digest" "1.0.0" "compact-dup.json"
  got="$("$IMPORT" "$T/c-compact" "$TOPIC" 2>&1)"
  local rc_compact=$?
  local dup_file_count; dup_file_count="$(find "$TOPIC_DIR/findings" -maxdepth 1 -name 'compact-dup.json' | wc -l | tr -d ' ')"
  # Count @id carriers by PARSING each file (jq), not by grepping bytes --
  # a byte-grep count here would be blind to the same compact-JSON layout
  # this regression test exists to cover.
  local id_carrier_count=0 idc_file idc_id
  while IFS= read -r idc_file; do
    idc_id="$(jq -r '."@id" // empty' "$idc_file" 2>/dev/null)"
    [ "$idc_id" = "$new_id" ] && id_carrier_count=$((id_carrier_count + 1))
  done < <(find "$TOPIC_DIR/findings" -maxdepth 1 -name '*.json')
  local compact_summary; compact_summary="$(jq -r '.summary' "$TOPIC_DIR/findings/finding.json" 2>/dev/null)"
  if [ "$rc_compact" -eq 0 ] && [ "$dup_file_count" = "0" ] && [ "$id_carrier_count" = "1" ] && [ "$compact_summary" = "gate_m29 compact-json lookup regression test" ]; then
    ok "a compact-JSON destination file is still found by @id -- overwritten in place, never duplicated (#668)"
  else
    bad "compact-JSON @id lookup regression check failed (rc=$rc_compact, dup=$dup_file_count, carriers=$id_carrier_count, summary=$compact_summary): $got"
  fi

  # 29m. Regression test for issue #679: a RELATIVE <container-dir> must
  #      resolve against the INVOKING cwd, not the repo root -- the script
  #      cd's to $ROOT before parsing argv, so before the fix a relative
  #      path passed from anywhere but the repo root resolved against $ROOT
  #      and failed with a misleading "not a directory"/"manifest not
  #      found". Re-run 29a's known-good no-op container as --dry-run
  #      (writes nothing) from inside $T, addressing it by its RELATIVE
  #      basename.
  local import_abs="$PWD/$IMPORT"
  (cd "$T" && "$import_abs" "c-noop" "$TOPIC" --dry-run) >/dev/null 2>&1
  local rc_relative=$?
  if [ "$rc_relative" -eq 0 ]; then
    ok "a caller-relative <container-dir> resolves against the invoking cwd, not the repo root (#679)"
  else
    bad "caller-relative <container-dir> did not resolve against the invoking cwd (rc=$rc_relative, #679)"
  fi

  # 29n. Regression test for issue #673: step 4's upsert loop must ROLL BACK
  #      earlier resources' committed writes when a LATER resource's write
  #      fails. Fixture: three schema-valid finding resources, in manifest
  #      order -- (1) a brand-new @id (lands via write-finding.sh), (2) an
  #      overwrite-in-place of an existing @id (modified content), (3) a
  #      brand-new @id whose target BASENAME collides with an unrelated
  #      pre-existing file at the destination. Step 2's pre-validation
  #      checks resources by @id only, so resource 3 passes every pre-write
  #      check and fails only inside step 4 (write-finding.sh refuses the
  #      EEXIST collision fail-closed). Before the fix: the import printed
  #      REJECTED but resource 1's file stayed on disk and resource 2's
  #      overwrite survived. After: REJECTED and the corpus is byte-identical
  #      to its pre-import state.
  local collide_file="$TOPIC_DIR/findings/gate-m29-673-collide.json"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-673-collide-existing" '."@id" = $id' \
    "$seed_finding" > "$collide_file" \
    || bad "gate_m29 29n: failed to seed the pre-existing collision file"
  mkdir -p "$T/c-rollback"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-673-a" '."@id" = $id' \
    "$seed_finding" > "$T/c-rollback/gate-m29-673-a.json"
  jq '.summary = "gate_m29 issue-673 overwrite probe"' "$seed_finding" > "$T/c-rollback/gate-m29-673-seed-overwrite.json"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-673-b" '."@id" = $id' \
    "$seed_finding" > "$T/c-rollback/gate-m29-673-collide.json"
  local rb_a_digest rb_ow_digest rb_b_digest rb_manifest_digest
  rb_a_digest="$(scripts/mif-container-digest.sh resource "$T/c-rollback/gate-m29-673-a.json")"
  rb_ow_digest="$(scripts/mif-container-digest.sh resource "$T/c-rollback/gate-m29-673-seed-overwrite.json")"
  rb_b_digest="$(scripts/mif-container-digest.sh resource "$T/c-rollback/gate-m29-673-collide.json")"
  rb_manifest_digest="$(printf '%s\n%s\n%s\n' "$rb_a_digest" "$rb_ow_digest" "$rb_b_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg ad "$rb_a_digest" --arg od "$rb_ow_digest" --arg bd "$rb_b_digest" --arg md "$rb_manifest_digest" --arg topic "$TOPIC" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [
      {mifType: "finding", path: "gate-m29-673-a.json", ontologyType: "technology", digest: $ad},
      {mifType: "finding", path: "gate-m29-673-seed-overwrite.json", ontologyType: "technology", digest: $od},
      {mifType: "finding", path: "gate-m29-673-collide.json", ontologyType: "technology", digest: $bd}
    ],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-rollback/mif-package.json"
  local rb_seed_before rb_collide_before
  rb_seed_before="$(scripts/mif-container-digest.sh resource "$seed_finding")"
  rb_collide_before="$(scripts/mif-container-digest.sh resource "$collide_file")"
  got="$("$IMPORT" "$T/c-rollback" "$TOPIC" 2>&1)"
  local rc_rollback=$?
  local rb_a_present=0
  [ -f "$TOPIC_DIR/findings/gate-m29-673-a.json" ] && rb_a_present=1
  local rb_seed_after rb_collide_after
  rb_seed_after="$(scripts/mif-container-digest.sh resource "$seed_finding")"
  rb_collide_after="$(scripts/mif-container-digest.sh resource "$collide_file")"
  if [ "$rc_rollback" -ne 0 ] && [ "$rb_a_present" = "0" ] \
     && [ "$rb_seed_after" = "$rb_seed_before" ] && [ "$rb_collide_after" = "$rb_collide_before" ] \
     && printf '%s' "$got" | grep -q "rolled back"; then
    ok "a later resource's write failure rolls back earlier resources' step-4 writes -- new file deleted, overwrite restored (#673)"
  else
    bad "step-4 rollback regression check failed (rc=$rc_rollback, a_present=$rb_a_present, seed_restored=$([ "$rb_seed_after" = "$rb_seed_before" ] && echo yes || echo no), collide_intact=$([ "$rb_collide_after" = "$rb_collide_before" ] && echo yes || echo no)): $got"
  fi

  # 29o. Regression test for the rollback-ledger dedupe (Copilot review,
  #      PR #718 on issue #673): a manifest that overwrites the SAME
  #      destination @id twice, then fails on a later resource, must roll
  #      the destination back to its true PRE-IMPORT bytes -- not to this
  #      run's own first intermediate write. Before the dedupe: the second
  #      overwrite took a second backup (of the first overwrite's output),
  #      and cleanup()'s glob-ordered restore replayed it over the first
  #      (true pre-import) backup, leaving the corpus in an intermediate
  #      state while still printing "rolled back".
  local collide718="$TOPIC_DIR/findings/gate-m29-718-collide.json"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-718-collide-existing" '."@id" = $id' \
    "$seed_finding" > "$collide718" \
    || bad "gate_m29 29o: failed to seed the pre-existing collision file"
  mkdir -p "$T/c-dup-rollback"
  jq '.summary = "gate_m29 pr-718 duplicate overwrite probe A"' "$seed_finding" > "$T/c-dup-rollback/gate-m29-718-ow-a.json"
  jq '.summary = "gate_m29 pr-718 duplicate overwrite probe B"' "$seed_finding" > "$T/c-dup-rollback/gate-m29-718-ow-b.json"
  jq --arg id "urn:mif:concept:harness/example-okf-mif-knowledge-spine:gate-m29-718-b" '."@id" = $id' \
    "$seed_finding" > "$T/c-dup-rollback/gate-m29-718-collide.json"
  local dup_a_digest dup_b_digest dup_c_digest dup_manifest_digest
  dup_a_digest="$(scripts/mif-container-digest.sh resource "$T/c-dup-rollback/gate-m29-718-ow-a.json")"
  dup_b_digest="$(scripts/mif-container-digest.sh resource "$T/c-dup-rollback/gate-m29-718-ow-b.json")"
  dup_c_digest="$(scripts/mif-container-digest.sh resource "$T/c-dup-rollback/gate-m29-718-collide.json")"
  dup_manifest_digest="$(printf '%s\n%s\n%s\n' "$dup_a_digest" "$dup_b_digest" "$dup_c_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg ad "$dup_a_digest" --arg bd "$dup_b_digest" --arg cd "$dup_c_digest" --arg md "$dup_manifest_digest" --arg topic "$TOPIC" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [
      {mifType: "finding", path: "gate-m29-718-ow-a.json", ontologyType: "technology", digest: $ad},
      {mifType: "finding", path: "gate-m29-718-ow-b.json", ontologyType: "technology", digest: $bd},
      {mifType: "finding", path: "gate-m29-718-collide.json", ontologyType: "technology", digest: $cd}
    ],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-dup-rollback/mif-package.json"
  local dup_seed_before dup_collide_before
  dup_seed_before="$(scripts/mif-container-digest.sh resource "$seed_finding")"
  dup_collide_before="$(scripts/mif-container-digest.sh resource "$collide718")"
  got="$("$IMPORT" "$T/c-dup-rollback" "$TOPIC" 2>&1)"
  local rc_dup=$?
  local dup_seed_after dup_collide_after
  dup_seed_after="$(scripts/mif-container-digest.sh resource "$seed_finding")"
  dup_collide_after="$(scripts/mif-container-digest.sh resource "$collide718")"
  if [ "$rc_dup" -ne 0 ] \
     && [ "$dup_seed_after" = "$dup_seed_before" ] && [ "$dup_collide_after" = "$dup_collide_before" ] \
     && printf '%s' "$got" | grep -q "rolled back"; then
    ok "a manifest overwriting the same destination twice still rolls back to the true pre-import bytes (PR #718 review, #673)"
  else
    bad "duplicate-destination rollback regression check failed (rc=$rc_dup, seed_restored=$([ "$dup_seed_after" = "$dup_seed_before" ] && echo yes || echo no), collide_intact=$([ "$dup_collide_after" = "$dup_collide_before" ] && echo yes || echo no)): $got"
  fi

  # 29p. Regression test for issue #771: the ontology-map write branch (both
  #      the full-scope overwrite path and the subset-scope merge path) must
  #      call container_lock_refresh on every iteration, exactly like the
  #      doc and finding branches beside it already do -- a destination
  #      ontology-map.json large enough for the subset jq merge to take
  #      non-trivial time must not have its own still-live lock misjudged as
  #      stale and stolen mid-write by a concurrent invocation. A genuinely
  #      slow multi-minute merge isn't practical to simulate end-to-end here
  #      (same rationale as 31a5's direct unit test of the shared
  #      primitive) -- instead this instruments scripts/lib/container-lock.sh
  #      itself: a temporary copy whose container_lock_refresh ALSO appends a
  #      marker line to $REFRESH_MARKER (the override is appended at the end
  #      of the sourced file, so it wins regardless of the original
  #      definition's exact text -- bash keeps the LAST definition when a
  #      file is sourced), then runs two synthetic imports whose manifests
  #      contain ONLY an ontology-map resource -- no finding, no doc
  #      deliverable, the only other resource kinds that call
  #      container_lock_refresh -- one full-scope (fresh destination) and one
  #      subset-scope (existing destination, forcing the jq merge). Both
  #      must produce a marker; before the fix, neither did.
  jq --arg f "$ontlock_topic_full" --arg s "$ontlock_topic_subset" '.topics += [
      {id: $f, title: "gate_m29 771 lock-refresh full-scope test", namespace: ("harness/" + $f), status: "active", ontologies: []},
      {id: $s, title: "gate_m29 771 lock-refresh subset-scope test", namespace: ("harness/" + $s), status: "active", ontologies: []}
    ]' harness.config.json > "$T/config-with-ontlock-topics.json" && cp "$T/config-with-ontlock-topics.json" harness.config.json
  mkdir -p "reports/$ontlock_topic_full/findings" "reports/$ontlock_topic_subset/findings"
  # Step 5 (build-graph.sh) requires at least one finding already at the
  # destination -- an ontology-map-only manifest writes no finding of its
  # own, so without a pre-seeded one the whole import would REJECT on a
  # "no findings found" build-graph failure unrelated to this test's actual
  # subject (the lock refresh), producing a false failure below.
  jq --arg id "urn:mif:concept:harness/$ontlock_topic_full:seed" '."@id" = $id' \
    "$seed_finding" > "reports/$ontlock_topic_full/findings/seed.json"
  jq --arg id "urn:mif:concept:harness/$ontlock_topic_subset:seed" '."@id" = $id' \
    "$seed_finding" > "reports/$ontlock_topic_subset/findings/seed.json"
  # The subset destination pre-exists with one entry NOT in the incoming
  # resource -- makes the merge branch's jq -s pass genuinely do work rather
  # than short-circuiting on a same-content cmp -s skip.
  echo '[{"finding_id":"urn:mif:concept:harness/'"$ontlock_topic_subset"':pre-existing","entity_type":"technology","resolved_ontology":"mif-generic@1.0.0","basis":"declared","valid":true}]' \
    > "reports/$ontlock_topic_subset/ontology-map.json"

  # Both steps below are fail-fast (Copilot review, PR #788), unlike the
  # soft bad-and-continue pattern elsewhere in gate_m29: a failure here means
  # the REAL scripts/lib/container-lock.sh is about to be overwritten with no
  # guaranteed way back (restore_snapshot only restores it from
  # $T/container-lock.sh.orig, which won't exist if the backup below never
  # succeeded) -- returning immediately leaves $CONTAINER_LOCK_LIB untouched
  # instead of risking it getting replaced by a broken/incomplete
  # instrumented copy, and still runs restore_snapshot via the RETURN trap.
  cp "$CONTAINER_LOCK_LIB" "$T/container-lock.sh.orig" \
    || { bad "gate_m29 29p: failed to back up $CONTAINER_LOCK_LIB before instrumenting it"; return 1; }
  cp "$T/container-lock.sh.orig" "$T/container-lock.sh.instrumented"
  cat >> "$T/container-lock.sh.instrumented" <<'LOCKEOF'

# gate_m29 29p instrumentation (issue #771 regression test): this override
# wins over the definition above (bash keeps the LAST function definition
# when a file is sourced), recording every call this run makes without
# depending on matching the primitive's own implementation text.
container_lock_refresh() {
  # Marker is only written when $1 is a real lock dir (Copilot review, PR
  # #788) -- otherwise a call with a bogus/missing dir would still count as
  # "refreshed", masking the exact bug #771 regression-tests for.
  if [ -d "$1" ]; then
    touch "$1" 2>/dev/null || true
    [ -n "${REFRESH_MARKER:-}" ] && printf 'refresh\n' >> "$REFRESH_MARKER" 2>/dev/null || true
  fi
}
LOCKEOF
  cp "$T/container-lock.sh.instrumented" "$CONTAINER_LOCK_LIB" \
    || { bad "gate_m29 29p: failed to install the instrumented $CONTAINER_LOCK_LIB"; return 1; }

  mkdir -p "$T/c-ontlock-full"
  echo '[]' > "$T/c-ontlock-full/ontology-map.json"
  local ontlock_full_digest ontlock_full_manifest_digest
  ontlock_full_digest="$(scripts/mif-container-digest.sh resource "$T/c-ontlock-full/ontology-map.json")"
  ontlock_full_manifest_digest="$(printf '%s\n' "$ontlock_full_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg d "$ontlock_full_digest" --arg md "$ontlock_full_manifest_digest" --arg topic "$ontlock_topic_full" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "full", topic: $topic, selector: null, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [{mifType: "ontology-map", path: "ontology-map.json", ontologyType: null, digest: $d}],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-ontlock-full/mif-package.json"

  mkdir -p "$T/c-ontlock-subset"
  echo '[{"finding_id":"urn:mif:concept:harness/'"$ontlock_topic_subset"':incoming","entity_type":"technology","resolved_ontology":"mif-generic@1.0.0","basis":"declared","valid":true}]' \
    > "$T/c-ontlock-subset/ontology-map.json"
  local ontlock_subset_digest ontlock_subset_manifest_digest
  ontlock_subset_digest="$(scripts/mif-container-digest.sh resource "$T/c-ontlock-subset/ontology-map.json")"
  ontlock_subset_manifest_digest="$(printf '%s\n' "$ontlock_subset_digest" | scripts/mif-container-digest.sh manifest)"
  jq -n --arg d "$ontlock_subset_digest" --arg md "$ontlock_subset_manifest_digest" --arg topic "$ontlock_topic_subset" \
    --arg selector "[\"urn:mif:concept:harness/$ontlock_topic_subset:incoming\"]" '{
    profile: "https://research-harness.dev/schema/mif-container/v1",
    sourceInstance: {namespace: "gate-m29-test", corpusUrl: null},
    exportScope: {type: "subset", topic: $topic, selector: $selector, generatedAt: "2026-07-10T00:00:00Z"},
    ontologyBindings: [{packId: "mif-generic", version: "1.0.0"}],
    resources: [{mifType: "ontology-map", path: "ontology-map.json", ontologyType: null, digest: $d}],
    boundaryReferences: [],
    manifestDigest: $md,
    createdAt: "2026-07-10T00:00:00Z"
  }' > "$T/c-ontlock-subset/mif-package.json"

  local full_marker="$T/refresh-marker-full" subset_marker="$T/refresh-marker-subset"
  rm -f "$full_marker" "$subset_marker"
  REFRESH_MARKER="$full_marker" "$IMPORT" "$T/c-ontlock-full" "$ontlock_topic_full" >/dev/null 2>&1
  local rc_ontlock_full=$?
  REFRESH_MARKER="$subset_marker" "$IMPORT" "$T/c-ontlock-subset" "$ontlock_topic_subset" >/dev/null 2>&1
  local rc_ontlock_subset=$?

  cp "$T/container-lock.sh.orig" "$CONTAINER_LOCK_LIB" \
    || bad "gate_m29 29p: failed to restore the original $CONTAINER_LOCK_LIB after instrumentation"
  rm -rf "reports/$ontlock_topic_full" "reports/$ontlock_topic_subset"

  local full_refreshed=0 subset_refreshed=0
  [ "$rc_ontlock_full" -eq 0 ] && [ -s "$full_marker" ] && full_refreshed=1
  [ "$rc_ontlock_subset" -eq 0 ] && [ -s "$subset_marker" ] && subset_refreshed=1
  if [ "$full_refreshed" -eq 1 ] && [ "$subset_refreshed" -eq 1 ]; then
    ok "ontology-map write branch calls container_lock_refresh every iteration, full-scope and subset-scope alike (#771)"
  else
    bad "ontology-map lock-refresh regression check failed (#771): full rc=$rc_ontlock_full marker=$([ -s "$full_marker" ] && echo yes || echo no); subset rc=$rc_ontlock_subset marker=$([ -s "$subset_marker" ] && echo yes || echo no)"
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
    #
    # research-harness-template#754: a failed restore step must NOT still
    # cause the unconditional `rm -rf "$T"` below to run -- doing so
    # destroyed the only backup of the pre-mutation corpus even though the
    # failure was already detected and reported via `bad`, leaving a user
    # running verify.sh with real, uncommitted findings no recovery path.
    # Track whether any restore step failed and only remove $T once every
    # step has actually succeeded; otherwise leave it in place for manual
    # inspection/recovery.
    local restore_failed=0
    rm -rf "$TOPIC_DIR/findings" \
      || { bad "gate_m30 restore_snapshot: failed to clear $TOPIC_DIR/findings before restoring it -- real corpus may be left mutated"; restore_failed=1; }
    mkdir -p "$TOPIC_DIR/findings" \
      || { bad "gate_m30 restore_snapshot: failed to recreate $TOPIC_DIR/findings before restoring it -- real corpus may be left mutated"; restore_failed=1; }
    cp -r "$T/snapshot/findings/." "$TOPIC_DIR/findings/" \
      || { bad "gate_m30 restore_snapshot: failed to restore $TOPIC_DIR/findings -- real corpus may be left mutated"; restore_failed=1; }
    cp "$T/snapshot/README.md" "$TOPIC_DIR/README.md" \
      || { bad "gate_m30 restore_snapshot: failed to restore $TOPIC_DIR/README.md -- real corpus may be left mutated"; restore_failed=1; }
    cp "$T/snapshot/concordance.json" reports/concordance.json \
      || { bad "gate_m30 restore_snapshot: failed to restore reports/concordance.json -- real corpus may be left mutated"; restore_failed=1; }
    if [ "$had_sameas_proposals" -eq 1 ]; then
      cp "$T/snapshot/concordance-sameas-proposals.json" reports/concordance-sameas-proposals.json \
        || { bad "gate_m30 restore_snapshot: failed to restore reports/concordance-sameas-proposals.json"; restore_failed=1; }
    else
      rm -f reports/concordance-sameas-proposals.json
    fi
    rm -f "$TOPIC_DIR/knowledge-graph.json"
    rm -rf "$TOPIC_DIR/.container.lock"
    if [ "$restore_failed" -eq 0 ]; then
      rm -rf "$T"
    else
      info "gate_m30 restore_snapshot: leaving backup at $T in place after a failed restore step -- inspect/recover it manually, then remove it"
    fi
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

  # 30g. Regression (research-harness-template#754): restore_snapshot's own
  #      backup ($T) must survive a FAILED restore step, not get deleted
  #      unconditionally. Force one restore `cp` (reports/concordance.json)
  #      to fail via a permission error, invoke restore_snapshot directly
  #      with `bad`/`ok`/`info` shadowed to no-ops (so this induced,
  #      expected failure -- restore_snapshot correctly calling `bad` on
  #      it -- does not itself count against this gate's real PASS/FAIL
  #      totals, and its `info` note doesn't leak into the captured
  #      output this probe checks), and assert $T is still present
  #      afterward. The permission bit is
  #      restored, and gate_m30's own trap-driven restore_snapshot (armed
  #      at the top of this function) then runs a real, unobstructed
  #      restore at the true end of the gate, so this probe never leaves
  #      the corpus or the scratch dir behind.
  #
  #      chmod 000 does not deny write to root -- or any other
  #      DAC_OVERRIDE-capable process, e.g. a root-uid Docker/devcontainer
  #      verify.sh run -- so the induced restore `cp` would then SUCCEED, $T
  #      would be deleted, and this probe would false-FAIL against a correct
  #      fix (research-harness-template#777, same premise as gate 27f above).
  #      Probe writability after chmod 000 and, if the file is still
  #      writable, SKIP: the induced-failure premise does not hold.
  chmod 000 reports/concordance.json
  if [ -w reports/concordance.json ]; then
    chmod 644 reports/concordance.json
    skip "restore_snapshot backup-preservation check (chmod 000 did not deny write -- running as root or with DAC override; premise does not hold, #777)"
  else
    local t_survives
    t_survives="$(
      bad() { :; }
      ok() { :; }
      info() { :; }
      restore_snapshot >/dev/null 2>&1
      [ -d "$T" ] && echo yes || echo no
    )"
    chmod 644 reports/concordance.json
    if [ "$t_survives" = "yes" ]; then
      ok "restore_snapshot preserves its own backup ($T) when a restore step fails, instead of deleting it unconditionally"
    else
      bad "restore_snapshot deleted its backup ($T) even though a restore step failed -- unrecoverable corpus mutation risk"
    fi
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
  # research-harness-template#437: the topic's own deliverables (report(s),
  # falsification report, README, goal, artifact) now travel UNCONDITIONALLY
  # -- same count regardless of full vs. subset scope, since they are
  # topic-level documents, not per-finding data. Computed here (not
  # hardcoded) the same way mif-container-export.sh itself enumerates them,
  # so this expectation tracks the topic's real fixture content rather than
  # a number that silently drifts if the bundled example topic's own files
  # change.
  local expected_docs; expected_docs="$(find "$TOPIC_DIR" -maxdepth 1 -name '*.md' \
    \( -name 'report-*.md' -o -name '*-falsification-report.md' \) 2>/dev/null | wc -l | tr -d ' ')"
  local expected_wellknown=0
  [ -f "$TOPIC_DIR/README.md" ] && expected_wellknown=$((expected_wellknown + 1))
  [ -f "$TOPIC_DIR/goal.json" ] && expected_wellknown=$((expected_wellknown + 1))
  [ -f "$TOPIC_DIR/artifact.json" ] && expected_wellknown=$((expected_wellknown + 1))
  local expected_deliverables=$((expected_docs + expected_wellknown))
  got="$("$EXPORT" "$TOPIC" "$T/full-export" 2>&1)"
  local full_resource_count; full_resource_count="$(jq '.resources | length' "$T/full-export/mif-package.json" 2>/dev/null)"
  if printf '%s' "$got" | grep -q "exported $real_finding_count finding(s) (full scope)" \
     && [ "$full_resource_count" = "$((real_finding_count + 1 + expected_deliverables))" ]; then
    ok "full export includes every finding plus the topic's ontology-map.json and its $expected_deliverables own deliverable(s), corpus untouched"
  else
    bad "full export check failed: got='$got' resource_count=$full_resource_count expected_findings=$real_finding_count expected_deliverables=$expected_deliverables"
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

  # 31a3. Regression test for #382: a STALE lock (mtime older than
  #      CONTAINER_LOCK_STALE_MIN, left behind by e.g. a killed export/import
  #      that never reached its EXIT trap) is safely STOLEN rather than
  #      wedging every later export/import on the topic forever -- a fresh
  #      lock is still denied, same as 31a2.
  mkdir -p "$TOPIC_DIR/.container.lock"
  touch -t 200001010000 "$TOPIC_DIR/.container.lock"
  "$EXPORT" "$TOPIC" "$T/stale-lock-export" > /dev/null 2>&1
  local rc_export_stale=$?
  local export_stale_ok=0
  [ "$rc_export_stale" -eq 0 ] && [ -f "$T/stale-lock-export/mif-package.json" ] && [ ! -d "$TOPIC_DIR/.container.lock" ] && export_stale_ok=1
  rm -rf "$T/stale-lock-export" "$TOPIC_DIR/.container.lock"
  mkdir -p "$TOPIC_DIR/.container.lock"
  "$EXPORT" "$TOPIC" "$T/fresh-lock-export" > /dev/null 2>&1
  local rc_export_fresh=$?
  local export_fresh_ok=0
  [ "$rc_export_fresh" -ne 0 ] && [ ! -d "$T/fresh-lock-export" ] && export_fresh_ok=1
  rm -rf "$T/fresh-lock-export"
  rmdir "$TOPIC_DIR/.container.lock" 2>/dev/null
  if [ "$export_stale_ok" -eq 1 ] && [ "$export_fresh_ok" -eq 1 ]; then
    ok "container-lock (#382): a STALE .container.lock is stolen (export proceeds, lock released clean); a FRESH lock still denies"
  else
    bad "container-lock (#382) staleness regression (stale: rc=$rc_export_stale ok=$export_stale_ok; fresh: rc=$rc_export_fresh ok=$export_fresh_ok)"
  fi

  # 31a4. Regression test for #382 review: CONTAINER_LOCK_STALE_MIN="00"
  #      (all-digit but numerically zero) must fall back to the safe default
  #      instead of making `find -mmin -00` match nothing and mis-steal a
  #      FRESH lock -- mirrors evals/run-lock-test.sh's identical case for
  #      RUN_LOCK_STALE_MIN, same underlying validation gap.
  mkdir -p "$TOPIC_DIR/.container.lock"
  CONTAINER_LOCK_STALE_MIN="00" "$EXPORT" "$TOPIC" "$T/zero-stale-export" > /dev/null 2>&1
  local rc_export_zerostale=$?
  local export_zerostale_ok=0
  [ "$rc_export_zerostale" -ne 0 ] && [ ! -d "$T/zero-stale-export" ] && [ -d "$TOPIC_DIR/.container.lock" ] && export_zerostale_ok=1
  rm -rf "$T/zero-stale-export"
  rmdir "$TOPIC_DIR/.container.lock" 2>/dev/null
  if [ "$export_zerostale_ok" -eq 1 ]; then
    ok "container-lock (#382 review follow-up): CONTAINER_LOCK_STALE_MIN=\"00\" falls back to the safe default (a fresh lock still denies, not mis-stolen)"
  else
    bad "container-lock (#382 review follow-up) STALE_MIN=\"00\" regression (rc=$rc_export_zerostale ok=$export_zerostale_ok)"
  fi

  # 31a5. Regression test for #382 review: container_lock_refresh keeps a
  #      genuinely long-running holder's OWN lock from aging into "stale"
  #      territory -- without it, a topic large enough to run past
  #      CONTAINER_LOCK_STALE_MIN would have its own live lock stolen out
  #      from under it by a concurrent invocation. Unit-tested directly
  #      against the sourced library (a real multi-hour export isn't
  #      practical to simulate end-to-end here) by backdating the lock past
  #      the window, refreshing it, then confirming it reads as fresh again
  #      -- and that refresh never resurrects an already-released lock
  #      (mirrors run-lock.sh's own refresh contract). Uses a real
  #      container_lock_acquire to obtain a genuine ownership token
  #      (issue #763's refresh now requires one -- see 31a6 below for the
  #      ownership-mismatch case this signature change exists to catch).
  (
    # shellcheck source=scripts/lib/container-lock.sh
    . scripts/lib/container-lock.sh
    RL_LOCK="$TOPIC_DIR/.refresh-test.lock"
    rm -rf "$RL_LOCK"
    container_lock_acquire "$RL_LOCK" "refresh-test" || exit 1
    RL_TOKEN="$CONTAINER_LOCK_TOKEN"
    touch -t 200001010000 "$RL_LOCK"
    container_lock_fresh "$RL_LOCK" && exit 1          # sanity: backdated lock reads stale first
    container_lock_refresh "$RL_LOCK" "$RL_TOKEN" || exit 1
    container_lock_fresh "$RL_LOCK" || exit 1          # after refresh, reads fresh again
    rm -rf "$RL_LOCK"
    container_lock_refresh "$RL_LOCK" "$RL_TOKEN" 2>/dev/null && exit 1   # must fail, not silently no-op, on a lock that's gone
    [ ! -e "$RL_LOCK" ] || exit 1                      # must not resurrect it
    exit 0
  )
  if [ "$?" -eq 0 ]; then
    ok "container-lock (#382 review follow-up): container_lock_refresh keeps a live holder's lock from aging into stale territory, and never resurrects a released one"
  else
    bad "container-lock (#382 review follow-up) container_lock_refresh regression"
  fi

  # 31a6. Regression test for research-harness-template#763: container_lock_refresh
  #      (and container_lock_release) must detect a lock this run no longer
  #      actually owns -- e.g. a different run stole it via the staleness path,
  #      or reacquired it after this run's own release -- instead of silently
  #      acting on whatever currently occupies $lock_dir. Simulated directly
  #      against the sourced library: "run-a" acquires, is stolen out from
  #      under it by "run-b" (a fresh acquire at the same path, giving it a
  #      DIFFERENT ownership token), and run-a's own stale token must then be
  #      refused by both refresh and release -- leaving run-b's lock intact.
  (
    # shellcheck source=scripts/lib/container-lock.sh
    . scripts/lib/container-lock.sh
    OWN_LOCK="$TOPIC_DIR/.ownership-test.lock"
    rm -rf "$OWN_LOCK"
    container_lock_acquire "$OWN_LOCK" "run-a" || exit 1
    TOK_A="$CONTAINER_LOCK_TOKEN"
    # Simulate run-a losing the lock to a second run (a steal, or a
    # release-then-reacquire by someone else) -- a fresh acquire at the same
    # path stamps a brand-new token.
    rm -rf "$OWN_LOCK"
    container_lock_acquire "$OWN_LOCK" "run-b" || exit 1
    TOK_B="$CONTAINER_LOCK_TOKEN"
    [ "$TOK_A" != "$TOK_B" ] || exit 1   # sanity: the two acquisitions really differ
    # run-a's next refresh, using its now-stale token, must be REFUSED --
    # never silently extend run-b's lock. This is the exact bug #763 reports.
    container_lock_refresh "$OWN_LOCK" "$TOK_A" 2>/dev/null && exit 1
    [ -d "$OWN_LOCK" ] || exit 1
    # A refresh call with NO token at all must also be refused, not treated
    # as "touch whatever is there".
    container_lock_refresh "$OWN_LOCK" "" 2>/dev/null && exit 1
    # run-a's release, using its stale token, must NOT delete run-b's live
    # lock -- destroying another run's mutual exclusion would be worse than
    # the original refresh bug, not better.
    container_lock_release "$OWN_LOCK" "$TOK_A" 2>/dev/null
    [ -d "$OWN_LOCK" ] || exit 1
    current_token="$(cat "$OWN_LOCK/.owner-token" 2>/dev/null)"
    [ "$current_token" = "$TOK_B" ] || exit 1   # still stamped as run-b's, untouched
    # run-b, using its OWN correct token, refreshes and releases normally.
    container_lock_refresh "$OWN_LOCK" "$TOK_B" || exit 1
    container_lock_release "$OWN_LOCK" "$TOK_B"
    [ ! -e "$OWN_LOCK" ] || exit 1
    exit 0
  )
  if [ "$?" -eq 0 ]; then
    ok "container-lock (research-harness-template#763): container_lock_refresh/release refuse to act on a lock this run no longer owns, leaving the real (new) owner's lock intact"
  else
    bad "container-lock (research-harness-template#763) ownership-check regression"
  fi
  rm -rf "$TOPIC_DIR/.refresh-test.lock" "$TOPIC_DIR/.ownership-test.lock"

  # 31a7. Regression test for PR #796 Copilot review: (a) container_lock_refresh
  #      must propagate a `touch` failure as nonzero instead of swallowing it
  #      (`|| true`) -- a lock whose mtime silently fails to extend would be
  #      misjudged as stale and stolen by a concurrent invocation while the
  #      caller believes it is still safely refreshed; and (b)
  #      container_lock_release must treat a MISSING/empty stamped
  #      `.owner-token` as a mismatch when a token is supplied, not as "no
  #      guard needed" -- otherwise a caller holding a real token could
  #      `rm -rf` a live lock that simply never got stamped (older lock dir,
  #      partial stamp, manual lock).
  (
    # shellcheck source=scripts/lib/container-lock.sh
    . scripts/lib/container-lock.sh

    # (a) touch failure must fail the refresh, not swallow it. A file's owner
    #     can update its own mtime even with write bits stripped (POSIX
    #     utimes allows the owner regardless of mode), so chmod alone can't
    #     force `touch` to fail portably here -- shim `touch` on PATH instead
    #     so this works identically on macOS and Linux CI.
    TOUCH_LOCK="$TOPIC_DIR/.touchfail-test.lock"
    rm -rf "$TOUCH_LOCK"
    container_lock_acquire "$TOUCH_LOCK" "touchfail-test" || exit 1
    TOUCH_TOKEN="$CONTAINER_LOCK_TOKEN"
    FAKE_BIN="$(mktemp -d)"
    printf '#!/bin/sh\nexit 1\n' > "$FAKE_BIN/touch"
    chmod +x "$FAKE_BIN/touch"
    ( PATH="$FAKE_BIN:$PATH"; container_lock_refresh "$TOUCH_LOCK" "$TOUCH_TOKEN" ) 2>/dev/null && { rm -rf "$FAKE_BIN" "$TOUCH_LOCK"; exit 1; }
    rm -rf "$FAKE_BIN" "$TOUCH_LOCK"

    # (b) a lock with no stamped token at all must be treated as a mismatch
    #     (release skipped) when the caller supplies a real token -- never
    #     assumed to be "this run's lock, safe to remove" by default.
    UNSTAMPED_LOCK="$TOPIC_DIR/.unstamped-test.lock"
    rm -rf "$UNSTAMPED_LOCK"
    mkdir "$UNSTAMPED_LOCK" || exit 1   # simulate an older/partial lock: no .owner-token written
    container_lock_release "$UNSTAMPED_LOCK" "some-caller-token" 2>/dev/null
    [ -d "$UNSTAMPED_LOCK" ] || exit 1   # must NOT have been removed
    rm -rf "$UNSTAMPED_LOCK"

    # (c) a call missing its token argument entirely (not merely an empty
    #     string -- one fewer positional parameter) must hit the graceful
    #     "no ownership token supplied" refusal, not a `set -u` unbound-
    #     variable abort. This is what actually broke a real CI import run
    #     in this PR's own review: `local token="$2"` (no default) aborted
    #     the whole shell under this file's own `set -uo pipefail` callers
    #     the moment `$2` was unbound, mid-import, after every finding had
    #     already been written (PR #796 review, round 2).
    ARGCOUNT_LOCK="$TOPIC_DIR/.argcount-test.lock"
    rm -rf "$ARGCOUNT_LOCK"
    container_lock_acquire "$ARGCOUNT_LOCK" "argcount-test" || exit 1
    argcount_err="$( ( set -uo pipefail; container_lock_refresh "$ARGCOUNT_LOCK" ) 2>&1 1>/dev/null )"
    argcount_rc=$?
    rm -rf "$ARGCOUNT_LOCK"
    # Both the graceful refusal AND a `set -u` abort exit 1 here (bash's
    # default non-interactive-shell behavior on an unbound-variable error),
    # so the exit code alone can't distinguish them -- assert on the actual
    # stderr text instead: it must be this function's own graceful message,
    # never a raw "unbound variable" shell abort.
    [ "$argcount_rc" -eq 1 ] || exit 1
    case "$argcount_err" in
      *"unbound variable"*) exit 1 ;;
      *"no ownership token supplied"*) : ;;
      *) exit 1 ;;
    esac
    exit 0
  )
  if [ "$?" -eq 0 ]; then
    ok "container-lock (PR #796 review): refresh propagates a touch failure instead of swallowing it, release refuses to remove an unstamped lock when a token is supplied, and a missing token argument is refused gracefully rather than a set -u abort"
  else
    bad "container-lock (PR #796 review) touch-failure/unstamped-token/missing-arg regression"
  fi
  rm -rf "$TOPIC_DIR/.touchfail-test.lock" "$TOPIC_DIR/.unstamped-test.lock"

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
  # 2 requested findings + ontology-map.json + the topic's deliverables,
  # which travel unconditionally regardless of scope (#437, see 31a above).
  if [ "$subset_resource_count" = "$((3 + expected_deliverables))" ] && [ "$subset_scope_type" = "subset" ]; then
    ok "subset export resolves exactly the requested findings plus ontology-map.json and the topic's $expected_deliverables deliverable(s)"
  else
    bad "subset export check failed (resource_count=$subset_resource_count expected=$((3 + expected_deliverables)) scope_type=$subset_scope_type)"
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
  local roundtrip_import_out; roundtrip_import_out="$("$IMPORT" "$T/full-export" "$roundtrip_topic" 2>&1)"
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
    # roundtrip_import_out is included on failure only (PR #796 CI
    # investigation): a bare rc/count/match summary gave no way to tell
    # WHICH of import.sh's 5 steps actually rejected the import when this
    # failed reproducibly in CI but not in any local repro attempted.
    bad "round-trip check failed (rc=$rc_roundtrip count=$roundtrip_count/$real_finding_count ids_match=$([ "$source_ids" = "$dest_ids" ] && echo yes || echo no) ontmap_match=$ontmap_match) -- import output: $roundtrip_import_out"
  fi

  # 31f2. The topic's own deliverables (research-harness-template#437) also
  #       travel on the same round-trip. goal.json is never touched by any
  #       of step 5's rebuilders (build-graph.sh/build-topic-readme.sh/
  #       build-concordance.sh act on findings/ontology-map/concordance,
  #       never goal.json), so it is the one deliverable safe to assert
  #       BYTE-IDENTICAL -- any report deliverable and the falsification
  #       report are likewise untouched by step 5 and checked the same way.
  #       README.md
  #       is NOT checked this way: build-topic-readme.sh's own "build" mode
  #       (step 5) deliberately REGENERATES it from the freshly-imported
  #       corpus (counts, tables) while only PRESERVING the human-authored
  #       Purpose/Key Findings sections from whatever is already at $OUT --
  #       which, thanks to this fix, is now the just-imported README rather
  #       than a stale skeleton. A byte-identical assertion on README.md
  #       would be asserting the WRONG thing (it's supposed to differ in the
  #       mechanical backbone); instead this checks that the source's
  #       curated Key Findings prose specifically survived the rebuild --
  #       proof the imported README participated in step 5, not proof it
  #       was overwritten from scratch. artifact.json is not present in this
  #       bundled example topic (this gate is deliberately read-only against
  #       the real corpus, so one isn't fabricated here) -- its code path is
  #       the same generic doc_dest branch goal.json already exercises, so
  #       goal.json's coverage stands in for it; schemas/mif-container.schema.json's
  #       own ajv checks above (31a-e) already cover the manifest-shape side
  #       of an artifact resource.
  # Scoped to the `report-*.md` convention deliberately, matching export.sh's
  # own inclusion-based glob: only genuine report-channel L3 documents (no
  # top-level `genre:` frontmatter key, per build-topic-readme.sh's
  # file_genre() discriminator) travel as mifType "report". This topic's own
  # kiro-*/build-spec.md/synthesis-*.md files carry an explicit `genre:` key
  # (synthesis-*.md is even `mifExempt: true`) and are a different document
  # family that export.sh does NOT sweep into the container -- validating
  # them via mif-project.sh's L3 findings-schema gate on import would reject
  # them, since they were never produced by report-synthesizer in the first
  # place (discovered chasing a false premise while fixing PR #491's
  # report-validation-gap finding: the original fix applied mif-project.sh to
  # every mifType "report" resource, which regressed on this exact topic
  # before the export-side glob was narrowed to match).
  local one_report; one_report="$(find "$TOPIC_DIR" -maxdepth 1 -name 'report-*.md' \
    2>/dev/null | LC_ALL=C sort | head -1)"
  local one_fals; one_fals="$(find "$TOPIC_DIR" -maxdepth 1 -name '*-falsification-report.md' 2>/dev/null | LC_ALL=C sort | head -1)"
  local report_match="no" fals_match="no" goal_match="no" readme_key_match="no"
  if [ -n "$one_report" ] \
     && diff -q "$one_report" "reports/$roundtrip_topic/$(basename "$one_report")" > /dev/null 2>&1; then
    report_match="yes"
  fi
  if [ -n "$one_fals" ] \
     && diff -q "$one_fals" "reports/$roundtrip_topic/$(basename "$one_fals")" > /dev/null 2>&1; then
    fals_match="yes"
  fi
  if [ -f "$TOPIC_DIR/goal.json" ] \
     && diff -q "$TOPIC_DIR/goal.json" "reports/$roundtrip_topic/goal.json" > /dev/null 2>&1; then
    goal_match="yes"
  fi
  if [ -f "$TOPIC_DIR/README.md" ] && [ -f "reports/$roundtrip_topic/README.md" ]; then
    # Inline equivalent of build-topic-readme.sh's own extract_section(): grab
    # the "## Key Findings" section body (this test intentionally does not
    # source that script, which would execute its whole top-level body).
    local source_key_line
    source_key_line="$(awk '
      /^## Key Findings/ { grab=1; next }
      grab && /^## / { grab=0 }
      grab { print }
    ' "$TOPIC_DIR/README.md" | grep -m1 -E '^- ' || true)"
    # `--` is required: $source_key_line is a markdown bullet, so it always
    # starts with "- " -- without `--` to end option parsing, a grep
    # implementation that treats a leading "-" as a flag (verified: this
    # env's `grep` resolves to ugrep, which does exactly that) silently
    # misparses the whole pattern as invalid options instead of searching
    # for it, and the FROM-EMPTY-STDOUT lookup wouldn't even err loudly --
    # it errors, but "$?" alone won't say why without checking stderr, which
    # is exactly how this was missed until run for real.
    [ -n "$source_key_line" ] \
      && grep -qF -- "$source_key_line" "reports/$roundtrip_topic/README.md" \
      && readme_key_match="yes"
  fi
  if [ "$report_match" = "yes" ] && [ "$fals_match" = "yes" ] && [ "$goal_match" = "yes" ] && [ "$readme_key_match" = "yes" ]; then
    ok "export -> import round-trip also carries the topic's own deliverables: a report, the falsification report, and goal.json land byte-identical; README.md's curated Key Findings prose survives step 5's rebuild (#437)"
  else
    bad "topic-deliverable round-trip failed (report=$report_match falsification-report=$fals_match goal=$goal_match readme-key-findings=$readme_key_match)"
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

  # 31j. Regression test for issue #679: a RELATIVE <output-dir> must
  #      resolve against the INVOKING cwd, not the repo root -- the script
  #      cd's to $ROOT before parsing argv, so before the fix a relative
  #      output dir passed from anywhere else silently landed under the
  #      repo root instead of the caller's cwd, with no error at all.
  local export_abs="$PWD/$EXPORT"
  # Uniquely named per run so the repo-root stray check can't false-positive
  # on (or the cleanup delete) an unrelated pre-existing path of the same name.
  local relout_name="rel-679-out.$$.$RANDOM"
  mkdir -p "$T/callercwd"
  (cd "$T/callercwd" && "$export_abs" "$TOPIC" "$relout_name") >/dev/null 2>&1
  local rc_relout=$?
  local relout_strayed=0
  [ -e "$relout_name" ] && relout_strayed=1
  # Defensive cleanup: the PRE-fix behavior this test exists to catch would
  # have created $relout_name at the repo root -- never leave that behind.
  # Safe because the name is unique to this run, so only this test's own
  # artifact can match.
  rm -rf "$relout_name"
  if [ "$rc_relout" -eq 0 ] && [ -f "$T/callercwd/$relout_name/mif-package.json" ] && [ "$relout_strayed" -eq 0 ]; then
    ok "a caller-relative <output-dir> resolves against the invoking cwd, not the repo root (#679)"
  else
    bad "caller-relative <output-dir> resolution check failed (rc=$rc_relout, at-caller: $([ -f "$T/callercwd/$relout_name/mif-package.json" ] && echo yes || echo no), strayed-to-root: $relout_strayed, #679)"
  fi
}

gate_m32() {
  info "Milestone 32 — mif-docs conformance floor (research-harness-template#413, ADR-0018)"
  # Structurally enforces that document-shaped deliverables produced by this
  # repo's own template content stay MIF-conformant per mif-docs-plugin's own
  # mif-validate, not just self-reported. Scoped to FIXTURE/template content
  # this repo commits — the same fixtures-vs-live-corpus split the rest of
  # verify.sh already draws (an instance's imported reports/ corpus is gated
  # separately by scripts/ontology-review.sh, never here). ADRs are exempt
  # (structured-madr, not mif-validate, per mif-docs-plugin's own ADR-0001 —
  # tracked separately in research-harness-template#435).
  #
  # Two tiers, not one (Copilot review on #439 correctly flagged that an
  # L1-only gate undersells #413's own stated scope, which named provenance):
  #   - EVERY checked file: mif-validate --level 1 (schema shape + lossless
  #     round-trip). This is the floor every document here already clears.
  #   - A file whose frontmatter already declares a `provenance:` block:
  #     ALSO mif-validate --level 3 (proves the declared provenance is
  #     structurally well-formed, not just present). This does NOT prove the
  #     provenance is witnessed — a fresh CI runner has no session ledger to
  #     check against, so "is this witnessed" is inherently a
  #     mif-provenance-in-a-live-session question this gate cannot answer.
  #     What it CAN and does enforce: an asserted provenance block is never
  #     malformed. Coverage grows organically as more docs gain real
  #     provenance through live authoring sessions (#408/#410's own framing),
  #     not as a one-time backfill this gate performs.
  local PLUGIN_CACHE="${MIF_DOCS_PLUGIN_ROOT:-$PWD/.mif-docs-plugin-cache}"
  if [ ! -f "$PLUGIN_CACHE/scripts/mif-validate.mjs" ]; then
    bad "mif-docs-plugin cache NOT FETCHED at $PLUGIN_CACHE — run scripts/fetch-mif-docs-plugin.sh first"
    return
  fi
  if ! command -v node >/dev/null 2>&1; then
    bad "gate_m32: node is required to run mif-validate.mjs but is not on PATH"
    return
  fi

  local fail_count=0 checked_count=0 provenance_checked_count=0 f out

  check_one_doc() {
    local f="$1"
    checked_count=$((checked_count + 1))
    if ! out="$(node "$PLUGIN_CACHE/scripts/mif-validate.mjs" "$f" --level 1 2>&1)"; then
      fail_count=$((fail_count + 1))
      bad "mif-validate L1 FAILED: $f"
      printf '%s\n' "$out" | sed 's/^/      /' >&2
      return
    fi
    if grep -qE '^provenance:' "$f"; then
      provenance_checked_count=$((provenance_checked_count + 1))
      if ! out="$(node "$PLUGIN_CACHE/scripts/mif-validate.mjs" "$f" --level 3 2>&1)"; then
        fail_count=$((fail_count + 1))
        bad "mif-validate L3 FAILED (declares provenance: but it's malformed): $f"
        printf '%s\n' "$out" | sed 's/^/      /' >&2
      fi
    fi
  }

  # Diátaxis docs — confirmed L1-conformant across the whole set (audited
  # research-harness-template#410); enforce it stays that way going forward.
  for f in docs/explanation/*.md docs/how-to/*.md docs/reference/*.md docs/reference/packs/*.md docs/tutorials/*.md; do
    [ -f "$f" ] || continue
    check_one_doc "$f"
  done

  # The committed example-corpus fixture's rendered deliverables — same
  # fixtures-not-live-corpus scoping as gate_m31. Skip navigation/log files
  # that are deliberately not MIF documents (README.md, research-progress.md,
  # *-falsification-report.md — see report-synthesizer.md Step 4c).
  for f in reports/example-okf-mif-knowledge-spine/report-*.md \
           reports/example-okf-mif-knowledge-spine/synthesis-*.md \
           reports/example-okf-mif-knowledge-spine/*-build-spec.md \
           reports/example-okf-mif-knowledge-spine/*-kiro-requirements.md \
           reports/example-okf-mif-knowledge-spine/*-kiro-design.md \
           reports/example-okf-mif-knowledge-spine/*-kiro-tasks.md; do
    [ -f "$f" ] || continue
    check_one_doc "$f"
  done

  # docs/proposals/ — audited research-harness-template#410, all 8 currently
  # pass L1 (7 were already L3; the 8th was fixed to L3 in that story).
  for f in docs/proposals/*/*.md; do
    [ -f "$f" ] || continue
    check_one_doc "$f"
  done

  if [ "$fail_count" -eq 0 ]; then
    ok "mif-docs conformance floor: $checked_count document(s) pass mif-validate --level 1, $provenance_checked_count of those also pass --level 3 (provenance well-formed where declared)"
  else
    bad "mif-docs conformance floor: $fail_count of $checked_count document(s) failed mif-validate"
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

gate_changelog_links() {
  if [ "$IS_TEMPLATE" != 1 ]; then
    info "CHANGELOG footer compare-links (template-only; skipped in instance, #401)"
    return
  fi
  info "CHANGELOG footer compare-links reference only real tags (#397)"

  # Deliberately narrow: only flags an EXISTING link whose compare target(s)
  # aren't real tags (#393's actual defect class). Does NOT require every
  # bracketed heading to already have a link — a version bumped but not yet
  # tagged is CHANGELOG.md's normal resting state between releases, and a
  # gate that flagged that would go red on main every time, blocking
  # unrelated PRs. Reconciling brackets/links once a tag lands is
  # `mif-rh-cli harness reconcile-changelog-links`, run manually (or as a
  # non-blocking release-time check), never enforced here.
  # Restrict to the LAST contiguous run of footer-link-shaped lines: Keep a
  # Changelog's real reference-link footer is always the final such block in
  # the file, so anchoring on the last run (not every matching line anywhere)
  # keeps this safe against an inline `[label]: url`-shaped reference inside
  # a body bullet being mistaken for a footer link.
  local footer real_tags bad_links="" line label targets tag
  footer="$(awk '
    /^\[.*\]: / { buf = buf $0 "\n"; in_run = 1; next }
    { if (in_run) { last = buf }; buf = ""; in_run = 0 }
    END { if (in_run) { last = buf }; printf "%s", last }
  ' CHANGELOG.md)"
  real_tags="$(git tag --list 'v*' 2>/dev/null)"
  if [ -z "$real_tags" ] && [ -n "$footer" ]; then
    bad "no 'v*' git tags visible at all (shallow clone or missing tag history?) — cannot verify any footer compare-link; fetch full tag history and re-run"
    return
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    label="${line#\[}"; label="${label%%]:*}"
    targets="$(printf '%s\n' "$line" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
    [ -n "$targets" ] || continue
    while IFS= read -r tag; do
      [ -n "$tag" ] || continue
      printf '%s\n' "$real_tags" | grep -qxF "$tag" || bad_links="${bad_links}${label}->${tag} "
    done <<<"$targets"
  done <<<"$footer"
  if [ -z "$bad_links" ]; then
    ok "every CHANGELOG footer compare-link references a real tag"
  else
    bad "footer link(s) reference a tag that doesn't exist: $bad_links"
  fi
}

gate_milestone_docs() {
  if [ "$IS_TEMPLATE" != 1 ]; then
    info "Milestone docs drift check (template-only; skipped in instance, #505)"
    return
  fi
  info "Milestone docs stay in sync with verify.sh's own gate registry (drift-prevention, research-harness-template#443)"
  # This repo's own CLAUDE.md (Docs section) names COMPLETION-CRITERIA.md and
  # IMPLEMENTATION-PLAN.md as the definitional source the gate_mN gates map
  # to — GATES=(...) below is the ground truth for how many milestone gates
  # actually exist. Those two docs drifted ~20 milestones stale before this
  # gate existed (research-harness-template#443: COMPLETION-CRITERIA.md's
  # last documented milestone was 13 and IMPLEMENTATION-PLAN.md's last phase
  # was 8, while verify.sh had already grown through gate_m32). This compares
  # the highest gate_mN in the registry against the highest milestone/phase
  # documented in each file, so a future gate_mN added without a matching
  # doc entry fails loudly instead of drifting silently again.
  local highest_gate highest_cc highest_ip
  highest_gate="$(printf '%s\n' "${GATES[@]+"${GATES[@]}"}" | grep -oE '^gate_m[0-9]+$' | grep -oE '[0-9]+$' | sort -n | tail -1)"
  highest_cc="$(grep -oE '^### Milestone [0-9]+' COMPLETION-CRITERIA.md 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
  highest_ip="$(grep -oE '^## Phase [0-9]+' IMPLEMENTATION-PLAN.md 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1)"
  if [ -z "$highest_gate" ]; then
    bad "could not find any gate_mN entry in GATES=(...) — the extraction pattern itself may be broken"
    return
  fi
  if [ "$highest_gate" = "${highest_cc:-}" ] && [ "$highest_gate" = "${highest_ip:-}" ]; then
    ok "verify.sh's highest milestone gate (gate_m$highest_gate) matches the highest documented milestone in COMPLETION-CRITERIA.md and the highest phase in IMPLEMENTATION-PLAN.md"
  else
    bad "milestone docs drifted from verify.sh: highest gate_mN=$highest_gate, highest COMPLETION-CRITERIA.md '### Milestone N'=${highest_cc:-NONE}, highest IMPLEMENTATION-PLAN.md '## Phase N'=${highest_ip:-NONE} — document the new milestone(s)/phase(s) in both files"
  fi
}

gate_is_template_guard_hygiene() {
  if [ "$IS_TEMPLATE" != 1 ]; then
    info "IS_TEMPLATE guard hygiene check (template-only; verify.sh's own authoring concern, not instance content, #507)"
    return
  fi
  info "gate_* functions referencing a copier-excluded doc file carry an IS_TEMPLATE guard (#507)"

  # copier.yml's own _exclude list is the ground truth for which files vanish
  # in every instantiated clone. copier.yml itself is deliberately excluded
  # from this scan: checking for ITS presence is how IS_TEMPLATE (line ~36)
  # gets computed in the first place, not an instance of the bug class this
  # gate looks for. #401 (gate_changelog_links) and #505 (gate_milestone_docs)
  # both unconditionally failed in every instance because they read a
  # copier-excluded doc file with no IS_TEMPLATE guard anywhere in the
  # function body — this re-checks that structurally so a third gate can't
  # reintroduce the same defect silently.
  local excluded_files
  excluded_files="$(awk '
    /^_exclude:/ { in_block = 1; next }
    in_block && /^[^ ]/ { in_block = 0 }
    in_block { print }
  ' copier.yml | grep -oE '"[^"*]+\.[A-Za-z0-9]+"' | tr -d '"' | grep -vxF 'copier.yml')"

  if [ -z "$excluded_files" ]; then
    bad "could not extract any literal excluded doc filename from copier.yml's _exclude list — the extraction pattern itself may be broken"
    return
  fi

  local g body filtered f violations=""
  for g in "${GATES[@]+"${GATES[@]}"}"; do
    [ "$g" = "gate_is_template_guard_hygiene" ] && continue
    body="$(declare -f "$g" 2>/dev/null)" || continue
    # Strip negated pathspec tokens (":!file", e.g. gate_m1's contamination
    # scrub) before scanning — a gate that deliberately EXCLUDES one of these
    # files from a git-grep/diff is the opposite of referencing it as a
    # source and must not be flagged.
    filtered="$(printf '%s' "$body" | sed -E 's/:![A-Za-z0-9_.-]+//g')"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      # Require an actual $IS_TEMPLATE/${IS_TEMPLATE} variable reference, not
      # just the bare word — a comment or log string that merely mentions
      # "IS_TEMPLATE" without gating anything must not count as a guard.
      if grep -qF "$f" <<<"$filtered" && ! grep -qE '\$\{?IS_TEMPLATE\}?' <<<"$body"; then
        violations="${violations}${g} references '$f' with no IS_TEMPLATE guard; "
      fi
    done <<<"$excluded_files"
  done

  if [ -z "$violations" ]; then
    ok "every gate_* function referencing a copier-excluded doc file (${excluded_files//$'\n'/, }) carries an IS_TEMPLATE guard"
  else
    bad "gate(s) reference a copier-excluded doc file with no IS_TEMPLATE guard (same defect class as #401/#505): $violations"
  fi
}

gate_monitoring_workflow_sync() {
  info "Monitoring workflows stay in sync with their pack sources (#517)"
  # The continuous-monitor pack's GitHub Actions workflows ship as pack
  # sources (packs/monitoring/continuous-monitor/workflows/, delivered by
  # copier) and are materialized into .github/workflows/ by
  # scripts/install-monitoring-workflows.sh — the template repo keeps live
  # copies, an instance opts in. Wherever a live copy exists it must be
  # byte-identical to its pack source: a drifted copy means a copier update
  # changed the pack source and the install script wasn't re-run (or a live
  # copy was hand-edited instead of fixing the pack source).
  local src_dir="packs/monitoring/continuous-monitor/workflows"
  if [ ! -d "$src_dir" ]; then
    if [ "${IS_TEMPLATE:-0}" = 1 ]; then
      bad "pack workflow sources missing at $src_dir"
    else
      ok "pack predates shipped workflow sources — nothing to verify"
    fi
    return
  fi
  local src name dest drift=0 missing_in_template=0 found=0
  for src in "$src_dir"/*.yml; do
    [ -e "$src" ] || continue
    found=$((found + 1))
    name="$(basename "$src")"
    dest=".github/workflows/$name"
    if [ -f "$dest" ]; then
      # Escape hatch for a deliberately customized instance copy (e.g. a
      # different cron cadence): the marker takes the file out of the
      # byte-identity contract — the owner keeps their fork current by hand
      # from then on. Never valid in the template itself, whose live copies
      # ARE the pack sources' proof of freshness.
      if grep -q 'harness-workflow: unmanaged' "$dest" 2>/dev/null; then
        if [ "${IS_TEMPLATE:-0}" = 1 ]; then
          bad "$dest carries the 'harness-workflow: unmanaged' marker inside the template — only an instance may unmanage a copy"
          drift=1
        else
          ok "$dest is explicitly unmanaged (customized copy, byte-identity waived)"
        fi
        continue
      fi
      if ! cmp -s "$src" "$dest"; then
        bad "$dest differs from its pack source $src — run scripts/install-monitoring-workflows.sh (or fix the pack source, never the copy; a deliberate instance customization can opt out with a 'harness-workflow: unmanaged' comment)"
        drift=1
      fi
    elif [ "${IS_TEMPLATE:-0}" = 1 ]; then
      # The template's own scheduled monitoring must stay live; an instance
      # with no copy simply hasn't opted in, which is a valid state.
      bad "template is missing live copy $dest of pack source $src"
      missing_in_template=1
    fi
  done
  # A source dir that exists but ships no workflows is a broken pack
  # layout everywhere -- a silent OK here would report "in sync" while
  # there is nothing to be in sync with.
  if [ "$found" -eq 0 ]; then
    bad "$src_dir exists but contains no *.yml workflow sources — broken pack layout"
    return
  fi
  if [ "$drift" -eq 0 ] && [ "$missing_in_template" -eq 0 ]; then
    ok "every installed monitoring workflow is byte-identical to its pack source"
  fi
}

gate_workflows() {
  info "Workflow modules — async-body parse-check (.claude/workflows, #552)"

  # Workflow-runtime modules (vendored per Epic #539, starting with
  # research-goal.js) use the runtime's async-function-body shape: top-level
  # `return`/`await` are legal in the file, so a bare `node --check` rejects
  # a valid module. scripts/check-workflow-syntax.sh reproduces the runtime
  # framing (strip `export`, compile as an async function body) and is the
  # single parse authority; this gate puts it on the required `verify`
  # surface. .claude/workflows/ is NOT copier-excluded, so the same files —
  # and this same gate — hold template-and-instance.
  if ! command -v node >/dev/null 2>&1; then
    bad "gate_workflows: node is required for the workflow parse-check but is not on PATH"
    return
  fi
  if [ -f .claude/workflows/research-goal.js ]; then
    ok ".claude/workflows/research-goal.js ships (vendored research-goal workflow)"
  else
    bad ".claude/workflows/research-goal.js is missing — the vendored research-goal workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-fanout.js ]; then
    ok ".claude/workflows/research-fanout.js ships (vendored research-fanout workflow)"
  else
    bad ".claude/workflows/research-fanout.js is missing — the vendored research-fanout workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-falsify.js ]; then
    ok ".claude/workflows/research-falsify.js ships (vendored research-falsify workflow)"
  else
    bad ".claude/workflows/research-falsify.js is missing — the vendored research-falsify workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-synthesis.js ]; then
    ok ".claude/workflows/research-synthesis.js ships (vendored research-synthesis workflow)"
  else
    bad ".claude/workflows/research-synthesis.js is missing — the vendored research-synthesis workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-projection.js ]; then
    ok ".claude/workflows/research-projection.js ships (vendored research-projection workflow)"
  else
    bad ".claude/workflows/research-projection.js is missing — the vendored research-projection workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-deliverables.js ]; then
    ok ".claude/workflows/research-deliverables.js ships (vendored research-deliverables workflow)"
  else
    bad ".claude/workflows/research-deliverables.js is missing — the vendored research-deliverables workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-augment.js ]; then
    ok ".claude/workflows/research-augment.js ships (vendored research-augment workflow)"
  else
    bad ".claude/workflows/research-augment.js is missing — the vendored research-augment workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-add-dimensions.js ]; then
    ok ".claude/workflows/research-add-dimensions.js ships (vendored research-add-dimensions workflow)"
  else
    bad ".claude/workflows/research-add-dimensions.js is missing — the vendored research-add-dimensions workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-pivot.js ]; then
    ok ".claude/workflows/research-pivot.js ships (vendored research-pivot workflow)"
  else
    bad ".claude/workflows/research-pivot.js is missing — the vendored research-pivot workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-import.js ]; then
    ok ".claude/workflows/research-import.js ships (vendored research-import workflow)"
  else
    bad ".claude/workflows/research-import.js is missing — the vendored research-import workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-coverage-audit.js ]; then
    ok ".claude/workflows/research-coverage-audit.js ships (vendored research-coverage-audit workflow)"
  else
    bad ".claude/workflows/research-coverage-audit.js is missing — the vendored research-coverage-audit workflow must travel template-and-instance"
  fi
  if [ -f .claude/workflows/research-pipeline.js ]; then
    ok ".claude/workflows/research-pipeline.js ships (vendored research-pipeline workflow-of-workflows orchestrator)"
  else
    bad ".claude/workflows/research-pipeline.js is missing — the vendored research-pipeline workflow-of-workflows orchestrator must travel template-and-instance"
  fi
  local out
  if out="$(bash scripts/check-workflow-syntax.sh 2>&1)"; then
    ok "every .claude/workflows/*.js compiles as a Workflow-runtime async function body"
  else
    bad "workflow module failed the async-body parse-check: $(printf '%s' "$out" | grep -v '^  ok ' | head -3 | tr '\n' ' ')"
  fi

  # #618: research-falsify.js crashed on every finding because its own body
  # called new Date() — disallowed inside a Workflow-runtime script (breaks
  # resume determinism). Static, comment-aware grep for the three forbidden
  # runtime globals (new Date(, Date.now(, Math.random() across every
  # vendored module, so a future regression is caught here, not live.
  if out="$(bash scripts/check-workflow-forbidden-globals.sh 2>&1)"; then
    ok "no .claude/workflows/*.js calls new Date()/Date.now()/Math.random() (disallowed inside Workflow-runtime scripts — #618)"
  else
    bad "workflow module calls a forbidden Workflow-runtime global: $(printf '%s' "$out" | grep -v '^  ok ' | head -5 | tr '\n' ' ')"
  fi

  # #628: two concurrent research-projection.js invocations against the same
  # topic (different genre/slug) raced on the SHARED, fixed-name
  # reports/<topic>/artifact.json / report-finding*.json intermediates with
  # no error surfaced -- silent corruption, not a loud failure. The fix is a
  # topic-scoped reports/<topic>/.projection-lock (sourcing the same
  # scripts/lib/container-lock.sh primitive .container.lock already uses)
  # around the Report phase's synthesize-artifact.sh -> render-artifact.sh
  # pipeline. Static, comment-aware, fixed-string grep proving the module's
  # own prompt text still wires the acquire/release calls in, so a future
  # edit that silently drops the guard -- or comments it out -- is caught
  # here rather than live. Comment-aware: full-line `//` comments are
  # stripped first, so a guard disabled by commenting it out no longer
  # satisfies the check. Fixed-string (-F): the acquire/release patterns
  # embed `${RDIR}`, whose `{...}` a BRE grep (notably BSD/macOS grep)
  # mis-parses as an interval, so a plain grep would spuriously MISS the
  # live guard off-CI and fail this gate for the wrong reason.
  local proj=".claude/workflows/research-projection.js"
  local proj_code=""
  [ -f "$proj" ] && proj_code="$(grep -vE '^[[:space:]]*//' "$proj")"
  if [ -f "$proj" ] \
     && printf '%s\n' "$proj_code" | grep -qF 'container_lock_acquire "${RDIR}/.projection-lock"' \
     && printf '%s\n' "$proj_code" | grep -qF 'container_lock_release "${RDIR}/.projection-lock"' \
     && printf '%s\n' "$proj_code" | grep -qF '#628'; then
    ok "research-projection.js's Report phase still wires the reports/<topic>/.projection-lock acquire/release guard (#628)"
  else
    bad "research-projection.js is missing the #628 projection-lock guard (container_lock_acquire/release on reports/<topic>/.projection-lock) -- concurrent projection runs on the same topic will silently corrupt each other's artifact.json again"
  fi

  # #769: the prompt above used to tell the subagent that ANY nonzero exit
  # from container_lock_acquire meant "another projection run currently owns
  # this topic" -- collapsing scripts/lib/container-lock.sh's own two
  # distinct documented codes (3 = held by a live holder/lost the steal race,
  # 1 = mkdir failed for an unrelated reason, e.g. a missing parent dir or a
  # read-only filesystem) into a single "contention" story. A real rc=1
  # filesystem failure would then get misreported as lock contention,
  # misdirecting whoever investigates it. Static, comment-aware, fixed-string
  # grep: proves (a) the old collapsed phrasing is gone and (b) the prompt
  # text now distinguishes rc=3 from rc=1 by name, so a future edit that
  # re-collapses them back into one undifferentiated "nonzero == contention"
  # story is caught here, not live.
  if [ -f "$proj" ] \
     && ! printf '%s\n' "$proj_code" | grep -qF 'a NONZERO exit means another projection run currently owns this topic' \
     && printf '%s\n' "$proj_code" | grep -qF 'rc=3 means' \
     && printf '%s\n' "$proj_code" | grep -qF 'rc=1 means the' \
     && printf '%s\n' "$proj_code" | grep -qF 'mkdir itself failed for an unrelated filesystem reason' \
     && printf '%s\n' "$proj_code" | grep -qF '#769'; then
    ok "research-projection.js's Report phase distinguishes container_lock_acquire's rc=3 (contention) from rc=1 (filesystem error) rather than collapsing every nonzero exit into contention (#769)"
  else
    bad "research-projection.js still collapses container_lock_acquire's distinct rc=3 (contention) and rc=1 (filesystem error) exits into a single 'NONZERO exit means contention' story (#769) -- a real filesystem failure would be misreported as lock contention"
  fi

  # Functional proof, independent of the static grep above: the SAME
  # container-lock.sh primitive under the projection lock's own name
  # genuinely serializes two concurrent holders and releases cleanly,
  # exactly the mechanism the prompt text above instructs the agent to
  # invoke. A fresh scratch dir, not the real corpus -- this is testing the
  # generic library under this consumer's lock name, not any real topic.
  (
    T="$(mktemp -d)" || exit 1
    trap 'rm -rf "$T"' EXIT
    # shellcheck source=scripts/lib/container-lock.sh
    . scripts/lib/container-lock.sh
    LOCK="$T/.projection-lock"
    container_lock_acquire "$LOCK" "projection:engineering" || exit 1
    # A second concurrent acquire (a different genre's invocation) must be
    # DENIED while the first is fresh -- this is the exact race #628
    # reported, now closed.
    container_lock_acquire "$LOCK" "projection:exec-summary" 2>/dev/null && exit 1
    [ -d "$LOCK" ] || exit 1
    container_lock_release "$LOCK"
    [ -d "$LOCK" ] && exit 1
    # Once released, a subsequent (not concurrent) projection run acquires
    # cleanly -- release must not wedge the topic.
    container_lock_acquire "$LOCK" "projection:briefing" || exit 1
    container_lock_release "$LOCK"
    exit 0
  )
  if [ "$?" -eq 0 ]; then
    ok "reports/<topic>/.projection-lock genuinely serializes two concurrent projection runs on one topic and releases cleanly (#628)"
  else
    bad "reports/<topic>/.projection-lock regression (#628): concurrent acquire was not denied, or release/re-acquire did not round-trip cleanly"
  fi
}

gate_engine_lazy_gating() {
  info "verify.sh --gates: a scoped run of a non-engine gate must not require mif-rh-cli (#567)"
  # gate_workflows is an engine-free gate, unlike gate_m11/gate_m20/gate_m22 and
  # the gates that shell out to reconcile-session.sh / resolve-ontology.sh /
  # ontology-review.sh — all of which resolve the mif-rh engine (via engine_bin,
  # see scripts/lib/engine.sh) only when they actually run. A --gates-scoped run
  # that selects only such an engine-free gate must succeed even with no engine
  # binary reachable via any of engine_bin's three resolution paths
  # ($MIF_RH_CLI, PATH, <root>/bin/mif-rh-cli) — regression coverage for
  # research-harness-template#567, where the top of this script unconditionally
  # resolved the engine (and exited 5 if it couldn't) before gate selection was
  # even parsed, hard-failing every scoped run regardless of which gate was
  # actually asked for.
  local hidden_bin=0
  if [ -x bin/mif-rh-cli ]; then
    mv bin/mif-rh-cli bin/mif-rh-cli.gate_engine_lazy_gating.bak
    hidden_bin=1
  fi
  # Resolve bash's absolute path *before* PATH filtering below -- if
  # mif-rh-cli happens to live in the same directory as bash (common when
  # both are in /usr/bin), filtering that directory out of PATH and then
  # invoking the nested verifier via a bare `bash` would fail to resolve
  # bash itself (rc=127), making this gate flaky/false-failing.
  local bash_bin
  bash_bin="${BASH:-$(command -v bash)}"
  local clean_path="" d
  local -a _egl_dirs
  IFS=: read -ra _egl_dirs <<< "$PATH"
  for d in "${_egl_dirs[@]}"; do
    [ -x "$d/mif-rh-cli" ] && continue
    clean_path="${clean_path:+$clean_path:}$d"
  done
  local out rc
  out=$(env -u MIF_RH_CLI PATH="$clean_path" "$bash_bin" scripts/verify.sh --gates 'gate_workflows$' 2>&1); rc=$?
  if [ "$hidden_bin" -eq 1 ]; then
    mv bin/mif-rh-cli.gate_engine_lazy_gating.bak bin/mif-rh-cli
  fi
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'engine: mif-rh-cli not found'; then
    ok "a --gates run selecting only a non-engine gate succeeds with no mif-rh-cli reachable via any resolution path"
  else
    bad "a --gates run selecting only a non-engine gate should not require the engine (rc=$rc); output: ${out//$'\n'/ | }"
  fi
}

# ---------------------------------------------------------------------------
# Gate registry — each milestone appends its function name here.
# ---------------------------------------------------------------------------
GATES=(gate_m1 gate_m2 gate_m3 gate_m4 gate_m5 gate_m6 gate_m7 gate_m8 gate_m9 gate_m10 gate_m11 gate_m12 gate_m13 gate_m14 gate_m15 gate_m16 gate_m17 gate_m18 gate_m19 gate_m20 gate_m21 gate_m22 gate_m23 gate_m24 gate_m25 gate_m26 gate_m27 gate_m28 gate_m29 gate_m30 gate_m31 gate_m32 gate_ontology_lock gate_versions gate_changelog_links gate_milestone_docs gate_is_template_guard_hygiene gate_monitoring_workflow_sync gate_workflows gate_engine_lazy_gating)

# Gate selection + profiling (#531) -- the pre-push gate is only as valuable
# as it is runnable, so local iteration gets a scoped fast path and the
# runtime stays measurable instead of anecdotal:
#   --gates <ERE>     run only gate functions whose NAME matches the pattern
#                     (e.g. --gates 'gate_m3$' or --gates 'monitoring');
#                     the summary line notes the narrowed scope, so a scoped
#                     run can never masquerade as the full suite.
#   VERIFY_PROFILE=1  print per-gate wall seconds as each gate finishes and
#                     the slowest five at the end -- the evidence a future
#                     "verify is slow" report should start from.
GATE_PATTERN=""
if [ "${1:-}" = "--gates" ]; then
  if [ -z "${2:-}" ]; then
    echo "verify.sh: --gates requires a pattern argument (an ERE matched against gate names — see GATES=(...))" >&2
    exit 2
  fi
  GATE_PATTERN="$2"
  # Pre-validate the ERE once so a syntax error gets its own message
  # instead of reading as "matches no gate" (grep exits >=2 on a bad
  # pattern, 0/1 on match/no-match).
  printf '' | grep -qE -- "$GATE_PATTERN" 2>/dev/null
  if [ $? -ge 2 ]; then
    echo "verify.sh: --gates pattern is not a valid extended regular expression: $GATE_PATTERN" >&2
    exit 2
  fi
fi

SELECTED=()
for g in "${GATES[@]+"${GATES[@]}"}"; do
  if [ -z "$GATE_PATTERN" ] || printf '%s' "$g" | grep -qE -- "$GATE_PATTERN"; then
    SELECTED+=("$g")
  fi
done
if [ "${#SELECTED[@]}" -eq 0 ]; then
  echo "verify.sh: --gates '$GATE_PATTERN' matches no gate (see GATES=(...) for names)" >&2
  exit 2
fi

PROFILE_LINES=""
for g in "${SELECTED[@]+"${SELECTED[@]}"}"; do
  if [ "${VERIFY_PROFILE:-0}" = "1" ]; then
    _gate_start="$(date +%s)"
    "$g"
    _gate_secs="$(( $(date +%s) - _gate_start ))"
    printf '  time  %3ss %s\n' "$_gate_secs" "$g"
    PROFILE_LINES="${PROFILE_LINES}${_gate_secs} ${g}"$'\n'
  else
    "$g"
  fi
done

if [ "${VERIFY_PROFILE:-0}" = "1" ]; then
  echo
  echo "--- slowest gates ---"
  printf '%s' "$PROFILE_LINES" | sort -rn | head -5 | while IFS= read -r line; do
    printf '  %ss  %s\n' "${line%% *}" "${line#* }"
  done
fi

echo
SCOPE_NOTE=""
if [ -n "$GATE_PATTERN" ]; then
  SCOPE_NOTE=" [SCOPED RUN: --gates '$GATE_PATTERN' matched ${#SELECTED[@]}/${#GATES[@]} gates — not the full suite]"
fi
SKIP_NOTE=""
[ "$SKIP" -gt 0 ] && SKIP_NOTE=" ($SKIP skipped)"
if [ "$FAIL" -gt 0 ]; then
  printf '%sverify.sh: %d passed, %d FAILED%s%s%s\n' "$RED" "$PASS" "$FAIL" "$RST" "$SKIP_NOTE" "$SCOPE_NOTE"
  exit 1
fi
printf '%sverify.sh: %d passed, 0 failed%s%s%s\n' "$GREEN" "$PASS" "$RST" "$SKIP_NOTE" "$SCOPE_NOTE"
exit 0
