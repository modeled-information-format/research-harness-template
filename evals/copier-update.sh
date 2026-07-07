#!/usr/bin/env bash
# copier-update.sh — prove the harness is a living, update-propagating template
# (Milestone 7 acceptance gate, SPEC §7). It instantiates the harness with Copier,
# makes a template change, runs `copier update`, and asserts the change was
# re-applied to the already-instantiated harness — the capability that
# distinguishes Copier from a snapshot template engine.
#
# Requires: copier (pipx install copier) and git. If copier is absent the script
# exits non-zero with an install hint (the milestone genuinely depends on it).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT="$(pwd)"

# Template-only gate. Propagation is a capability of the TEMPLATE; an instance is
# the OUTPUT of propagation, not a propagator. In an instantiated harness copier.yml
# and the .jinja sources have been rendered away at generation, so there is no
# template machinery to exercise — skip cleanly. In the template copier.yml is
# tracked, so this guard is a no-op and the full gate runs. (Kept byte-identical
# template-and-instance so `copier update` never conflicts on this file.)
#
# Skip ONLY when affirmatively in an instance: a git work tree where copier.yml is
# untracked. Outside a git work tree (no git, or a source tarball) we must NOT skip
# — the script genuinely requires git (it runs `git ls-files`/`git init` below), so
# it should fail loudly with that requirement rather than silently pass having
# exercised nothing.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && ! git ls-files --error-unmatch copier.yml >/dev/null 2>&1; then
  echo "copier-update: SKIP — no template machinery tracked (running in an instance, not the template)"
  exit 0
fi

if ! command -v copier >/dev/null 2>&1; then
  echo "copier-update: copier is not installed. Install it with: pipx install copier" >&2
  exit 1
fi

# The instantiated harness's own copier tasks (e.g. site-toggle.sh, Story #302)
# now hard-require the mif-rh engine. Its `engine_bin` resolves relative to
# ITS OWN root, so a fresh copier-generated instance has no engine of its own —
# resolve the REAL installed engine via this repo's root and pin it as an env
# var, which propagates into copier's task subprocesses regardless of their
# cwd (the same fix already applied to evals/ontology-vendoring.sh and
# evals/sync-registry-ontologies.sh for the same class of scripts).
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
REAL_ENGINE="$(engine_bin "$ROOT")" || { echo "copier-update: engine not found" >&2; exit 5; }
export MIF_RH_CLI="$REAL_ENGINE"

# Run copier with its stderr CAPTURED (surfaced on failure, never swallowed — a gate that
# hides its tool's error makes every failure an undiagnosable "flake") and a bounded retry of
# two specific transient races on copier's LOCAL-path clone of the template, both under
# concurrent git/IO load on its temp `.git/objects`:
#   (1) the clone fails to hardlink a loose object — exit 128 "failed to copy file to
#       ... .git/objects/..."; and
#   (2) copier's POST-RUN cleanup rmtree of its temp clone hits "Directory not empty:
#       .../copier._main.new_copy*/.git[...]" (Python 3.14 TemporaryDirectory rmtree race).
#       This fires AFTER copier has already rendered/applied to the destination — only the
#       temp cleanup crashes — so retrying the whole op is wrong (the destination is now
#       dirty -> "Destination repository is dirty"). Treat it as success instead; the
#       caller's own assertions verify the update actually landed.
# Retry (1); pass-through (2); surface everything else immediately.
copier_run() {
  local sub="$1" attempt=1 max=6 rc errf
  errf=$(mktemp) || { echo "copier-update: mktemp failed — cannot capture copier stderr (fail closed)" >&2; return 1; }
  while :; do
    copier "$@" >/dev/null 2>"$errf"; rc=$?
    if [ "$rc" -eq 0 ]; then rm -f "$errf"; return 0; fi
    # (2) Post-apply temp-cleanup race: the render finished; only copier's temp rmtree crashed.
    if grep -qE "Directory not empty:.*copier\._main\.new_copy" "$errf" \
       && ! grep -q "failed to copy file to" "$errf"; then
      echo "  copier: ignored post-update temp-cleanup race on '$sub' (update applied; assertions verify)" >&2
      rm -f "$errf"; return 0
    fi
    # (1) Pre-apply clone hardlink race: the render never happened; retrying is safe.
    if [ "$attempt" -lt "$max" ] && grep -q "failed to copy file to" "$errf"; then
      echo "  copier: transient local-clone race on '$sub' (attempt $attempt/$max) — retrying" >&2
      attempt=$((attempt + 1)); sleep 1; : > "$errf"; continue
    fi
    echo "copier-update: copier $sub failed (rc=$rc) — copier stderr:" >&2
    cat "$errf" >&2; rm -f "$errf"
    return "$rc"
  done
}

TMPL=$(mktemp -d); INST=$(mktemp -d)
trap 'rm -rf "$TMPL" "$INST"' EXIT
GA="git -c user.email=harness@local -c user.name=harness"

# 1. Build a template repo from the harness's tracked files (working-tree content),
#    so the demo reflects the real template, including this milestone's files.
git ls-files -z | tar --null -T - -c | tar -x -C "$TMPL"
cd "$TMPL"
git init -q && $GA add -A && $GA commit -q -m "harness template v1.0.0" && git tag v1.0.0

# 2. Instantiate the harness. --trust: the template runs a post-copy `_tasks` hook
#    (site-toggle.sh activates the clone's reports surface); copier executes tasks
#    only when explicitly trusted.
copier_run copy --trust --defaults --quiet --vcs-ref v1.0.0 "$TMPL" "$INST" || exit 1
[ -f "$INST/.copier-answers.yml" ] || { echo "copier-update: no answers file recorded; update would be impossible" >&2; exit 1; }
[ -f "$INST/docs/harness-instance.md" ] || { echo "copier-update: templated identity file not rendered" >&2; exit 1; }
echo "  copier: instantiated harness (answers recorded, identity rendered)"

# 2b. The archived example topic ships to the clone AS-IS (no rename) as its inherited seed
#     fixture: present under its original name, archived in the manifest, and no legacy
#     `example-topic` placeholder. (The corpus keeps its name everywhere — renaming it inside
#     copier's update render destabilizes copier's temp cleanup; see copier.yml _tasks.)
[ -d "$INST/reports/example-okf-mif-knowledge-spine" ] || { echo "copier-update: example topic not shipped to clone" >&2; exit 1; }
[ ! -d "$INST/reports/example-topic" ] || { echo "copier-update: legacy example-topic corpus leaked into the clone" >&2; exit 1; }
SEED_STATUS=$(jq -r '.topics[] | select(.id=="example-okf-mif-knowledge-spine") | .status' "$INST/harness.config.json" 2>/dev/null)
[ "$SEED_STATUS" = "archived" ] || { echo "copier-update: example topic not archived (got '$SEED_STATUS')" >&2; exit 1; }
echo "  copier: archived example topic shipped to clone (reports/example-okf-mif-knowledge-spine)"

# 3. Make the instance a git repo (copier update needs a clean VCS state).
cd "$INST" && git init -q && $GA add -A && $GA commit -q -m "instantiated harness"

# 4. Make a template change and release it as a new version.
MARK="propagated-by-copier-update-$(git -C "$TMPL" rev-parse --short HEAD)"
printf '\n<!-- %s -->\n' "$MARK" >> "$TMPL/docs/harness-instance.md.jinja"
cd "$TMPL" && $GA commit -q -am "template v1.1.0: propagation marker" && git tag v1.1.0

# 5. Re-apply the template change to the instantiated harness.
# issue #200: remove the derived ontology catalog first, so the update must REGENERATE it —
# proving `copier update` re-runs sync-packs (a stale catalog surviving an update would break
# the fail-closed resolver).
rm -f "$INST/.claude/enabled-packs.json"
cd "$INST"
copier_run update --trust --defaults --quiet || exit 1

# 5b. The update re-ran sync-packs (copier _tasks): the derived ontology catalog is back AND its
#     generator field proves SYNC-PACKS produced it — not a copied placeholder (a bare existence
#     check would pass for either; the generator field is what proves the _task ran). issue #200.
gen=$(jq -r '.generator // ""' "$INST/.claude/enabled-packs.json" 2>/dev/null)
case "$gen" in
  *sync-packs.sh*) echo "  copier: ontology catalog regenerated on update by sync-packs (generator: $gen)" ;;
  *) echo "copier-update: ontology catalog NOT regenerated by sync-packs on update (generator='$gen') — sync-packs.sh missing from copier _tasks (issue #200)" >&2; exit 1 ;;
esac

# 6a. The example topic survives update: copier re-applies the (unchanged) corpus cleanly,
#     so it persists under its name with no duplication and update stays conflict-free.
[ -d "$INST/reports/example-okf-mif-knowledge-spine" ] || { echo "copier-update: example topic lost on update" >&2; exit 1; }
echo "  copier: example topic survived update (reports/example-okf-mif-knowledge-spine)"

# 6. Assert the change propagated.
if grep -q "$MARK" "$INST/docs/harness-instance.md"; then
  echo "  copier: \`copier update\` re-applied the template change to the instantiated harness"
  echo "copier-update: PASS"
  exit 0
fi
echo "copier-update: FAIL — template change did not propagate" >&2
exit 1
