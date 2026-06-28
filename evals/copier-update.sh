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
copier copy --trust --defaults --quiet --vcs-ref v1.0.0 "$TMPL" "$INST" >/dev/null 2>&1 || {
  echo "copier-update: copier copy failed" >&2; exit 1; }
[ -f "$INST/.copier-answers.yml" ] || { echo "copier-update: no answers file recorded; update would be impossible" >&2; exit 1; }
[ -f "$INST/docs/harness-instance.md" ] || { echo "copier-update: templated identity file not rendered" >&2; exit 1; }
echo "  copier: instantiated harness (answers recorded, identity rendered)"

# 3. Make the instance a git repo (copier update needs a clean VCS state).
cd "$INST" && git init -q && $GA add -A && $GA commit -q -m "instantiated harness"

# 4. Make a template change and release it as a new version.
MARK="propagated-by-copier-update-$(git -C "$TMPL" rev-parse --short HEAD)"
printf '\n<!-- %s -->\n' "$MARK" >> "$TMPL/docs/harness-instance.md.jinja"
cd "$TMPL" && $GA commit -q -am "template v1.1.0: propagation marker" && git tag v1.1.0

# 5. Re-apply the template change to the instantiated harness.
cd "$INST"
copier update --trust --defaults --quiet >/dev/null 2>&1 || { echo "copier-update: copier update failed" >&2; exit 1; }

# 6. Assert the change propagated.
if grep -q "$MARK" "$INST/docs/harness-instance.md"; then
  echo "  copier: \`copier update\` re-applied the template change to the instantiated harness"
  echo "copier-update: PASS"
  exit 0
fi
echo "copier-update: FAIL — template change did not propagate" >&2
exit 1
