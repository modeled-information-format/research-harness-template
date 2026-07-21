#!/usr/bin/env bash
# author-ontology-open-pr-scoped.sh — regression eval for
# research-harness-template#670.
#
# `scripts/author-ontology.sh --open-pr` concierges a draft PR against a
# long-lived, reused sibling ontologies clone ($MIF_ONTOLOGIES_REPO or
# ../ontologies). Two defects used to compound there:
#
#   1. The `cp` of the draft into the clone was a standalone statement with
#      no exit-status guard — under `set -uo pipefail` (no -e) a failed copy
#      fell straight through into branch/commit/push/`gh pr create`, opening
#      a PR branch with no new ontology file in it at all.
#   2. The commit was staged with `git add -A`, sweeping the ENTIRE working
#      tree of the reused clone — leftovers from a prior interrupted run, or
#      any stray in-progress edit — into an automated commit pushed upstream
#      as a draft PR whose title/body claims only the new ontology was added.
#
# This eval drives the real --open-pr flow against a throwaway git clone
# (with a local bare "origin"), a stub mif-rh-cli engine, and a stub `gh`,
# and proves:
#
#   1. Happy path: with a leftover untracked draft AND a stray tracked
#      modification planted in the clone, the concierge commit contains
#      EXACTLY the new draft + regenerated ontologies/index.json — the
#      leftover stays untracked, the stray modification stays unstaged —
#      and the branch is pushed and `gh pr create` is invoked.
#   2. Failed copy: when the cp into the clone fails (read-only target
#      dir), the script exits nonzero, creates no branch, and never
#      reaches `gh pr create`.
#
# Exit 0 iff both hold; each failing case names itself.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  author-ontology-open-pr-scoped: %s\n' "$1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/author-ontology-scoped.XXXXXX")"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# --- stubs -------------------------------------------------------------------
mkdir -p "$TMP/bin"

# Stub engine: satisfies engine_bin's version gate and writes a minimal draft
# with one entity type to whatever --out it is given.
cat > "$TMP/bin/mif-rh-cli" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "mif-rh-cli 99.0.0"; exit 0; }
out=""; prev=""
for a in "$@"; do [ "$prev" = "--out" ] && out="$a"; prev="$a"; done
[ -n "$out" ] || exit 1
cat > "$out" <<'YAML'
ontology:
  id: eval-stub
entity_types:
  - name: todo-stub-type
YAML
STUB
chmod +x "$TMP/bin/mif-rh-cli"

# Stub gh: records that `pr create` was reached and succeeds.
cat > "$TMP/bin/gh" <<STUB
#!/bin/sh
echo "\$@" >> "$TMP/gh-called"
exit 0
STUB
chmod +x "$TMP/bin/gh"

# --- throwaway ontologies clone + local bare origin --------------------------
ONT="$TMP/ont"
mkdir -p "$ONT/ontologies" "$ONT/scripts"
git -C "$ONT" init -q -b main
git -C "$ONT" config user.email eval@example.invalid
git -C "$ONT" config user.name "eval"
echo '{"schema":"mif-ontology-index/v1","ontologies":[]}' > "$ONT/ontologies/index.json"
echo "# ontologies" > "$ONT/README.md"
# Fake index generator so the regenerated index is part of the expected commit.
cat > "$ONT/scripts/gen-ontology-index.sh" <<'GEN'
#!/usr/bin/env bash
echo '{"schema":"mif-ontology-index/v1","regenerated":true}' > "$(dirname "$0")/../ontologies/index.json"
GEN
chmod +x "$ONT/scripts/gen-ontology-index.sh"
git -C "$ONT" add -A && git -C "$ONT" commit -q -m "init"
git init -q --bare "$TMP/remote.git"
git -C "$ONT" remote add origin "$TMP/remote.git"

# Plant the reused-clone hazards #670 is about: an untracked leftover from a
# "prior interrupted run" and a stray uncommitted edit to a tracked file.
echo "ontology: {id: leftover}" > "$ONT/ontologies/leftover-prior-run.ontology.yaml"
echo "stray in-progress edit" >> "$ONT/README.md"

run_script() { # $1 = new-id
  MIF_ONTOLOGIES_REPO="$ONT" MIF_RH_CLI="$TMP/bin/mif-rh-cli" PATH="$TMP/bin:$PATH" \
    bash scripts/author-ontology.sh "$1" some-topic --out "$TMP/$1.draft.yaml" --open-pr \
    >"$TMP/$1.out" 2>&1
}

# --- case 1: scoped commit on the happy path ---------------------------------
if run_script evaltmp-scope; then
  committed="$(git -C "$ONT" show --name-only --format= feat/ontology-evaltmp-scope | sort)"
  expected="$(printf 'ontologies/evaltmp-scope.ontology.yaml\nontologies/index.json\n')"
  if [ "$committed" != "$expected" ]; then
    note "case 1: commit is not scoped to the draft + index; committed: ${committed//$'\n'/ }"
    fail=1
  fi
  if ! git -C "$ONT" status --porcelain | grep -q '^?? ontologies/leftover-prior-run.ontology.yaml'; then
    note "case 1: leftover untracked file was swept into the commit"
    fail=1
  fi
  if ! git -C "$ONT" status --porcelain | grep -q '^ M README.md'; then
    note "case 1: stray tracked modification was staged/committed"
    fail=1
  fi
  if ! git -C "$TMP/remote.git" rev-parse --verify -q refs/heads/feat/ontology-evaltmp-scope >/dev/null; then
    note "case 1: branch was not pushed to origin"
    fail=1
  fi
  if ! grep -q 'pr create' "$TMP/gh-called" 2>/dev/null; then
    note "case 1: gh pr create was never invoked"
    fail=1
  fi
else
  note "case 1: --open-pr concierge failed unexpectedly:"
  sed 's/^/    /' "$TMP/evaltmp-scope.out"
  fail=1
fi

# --- case 2: failed cp aborts before branch/commit/push/PR -------------------
git -C "$ONT" checkout -q main
rm -f "$TMP/gh-called"
chmod 555 "$ONT/ontologies"
if run_script evaltmp-cpfail; then
  note "case 2: script exited 0 despite the copy into the clone failing"
  fail=1
fi
chmod 755 "$ONT/ontologies"
if git -C "$ONT" rev-parse --verify -q refs/heads/feat/ontology-evaltmp-cpfail >/dev/null; then
  note "case 2: a branch was created even though the cp failed"
  fail=1
fi
if [ -e "$TMP/gh-called" ]; then
  note "case 2: gh pr create was reached even though the cp failed"
  fail=1
fi

exit "$fail"
