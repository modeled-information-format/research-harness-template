#!/usr/bin/env bash
# pre-push-tag-skip.sh — regression eval for research-harness-template#648.
#
# `.githooks/pre-push` used to run scripts/check-version-bump.sh
# unconditionally on every push, with no awareness of the standard git
# pre-push stdin protocol (`local_ref local_sha remote_ref remote_sha`
# lines) that distinguishes a branch push from a tag push. Pushing a release
# tag at the exact commit where the release pointer was just bumped fails
# the check, because "the last actual git tag release" it resolves against
# is the about-to-be-pushed tag itself — a paradox inherent to releasing,
# not a real versioning violation (reproduced live during the v0.16.21
# release, forcing a `--no-verify` bypass).
#
# This eval invokes the real hook script directly (not `git push`) with
# fabricated stdin matching git's real pre-push protocol, against a stub
# scripts/check-version-bump.sh that records whether it was ever invoked.
# It proves:
#
#   1. A tag-only push (single tag ref) never invokes the version-bump
#      check at all, and the hook exits 0.
#   2. A tag-deletion push (local ref literally "(delete)", remote ref a
#      tag) is treated the same way — never invokes the check.
#   3. A branch push still invokes the check exactly as before: the hook
#      exits 0 when the stub passes and exits 1 (with the failure message)
#      when the stub fails — unchanged pre-existing behaviour, not weakened
#      by this fix.
#   4. A push that mixes a branch ref and a tag ref in one invocation still
#      invokes the check (not "every ref is a tag").
#
# Exit 0 iff all four hold; each failing case names itself.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

HOOK="$ROOT/.githooks/pre-push"
fail=0
note() { printf '  pre-push-tag-skip: %s\n' "$1"; }

if [ ! -x "$HOOK" ] && [ ! -f "$HOOK" ]; then
  note "$HOOK not found"
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pre-push-tag-skip.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Build a throwaway git repo that looks enough like the real one for the
# hook's own preflight checks (show-toplevel, scripts/check-version-bump.sh
# presence, origin/main) to pass, without touching the real repo or network.
REPO="$TMP/repo"
mkdir -p "$REPO/scripts"
git init -q "$REPO" 2>/dev/null
git -C "$REPO" config user.email "eval@example.com"
git -C "$REPO" config user.name "eval"
# core.hooksPath must not leak in from the eval-runner's own global config
# (it would install the very hook this eval is exercising, or another
# unrelated one, on every git command below).
git -C "$REPO" config core.hooksPath .git/hooks
echo init > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m init

# A bare "origin" so `git fetch origin main` and `git rev-parse --verify
# origin/main` both succeed without hitting the network.
ORIGIN="$TMP/origin.git"
git init -q --bare "$ORIGIN" 2>/dev/null
git -C "$REPO" remote add origin "$ORIGIN"
git -C "$REPO" push -q origin HEAD:main 2>/dev/null
git -C "$REPO" fetch -q origin main 2>/dev/null

STUB_LOG="$TMP/stub-invoked.log"
write_stub() { # write_stub <exit-code>
  cat > "$REPO/scripts/check-version-bump.sh" <<EOF
#!/usr/bin/env bash
echo "invoked" >> "$STUB_LOG"
exit $1
EOF
  chmod +x "$REPO/scripts/check-version-bump.sh"
}

run_hook_with_stdin() { # run_hook_with_stdin <stdin-text>
  : > "$STUB_LOG"
  printf '%s' "$1" | bash "$HOOK" > "$TMP/hook-stdout.log" 2>&1
  echo $?
}

sha="$(git -C "$REPO" rev-parse HEAD)"

# --- Case 1: tag-only push never invokes the check ------------------------
write_stub 1   # stub would FAIL if invoked — proves it is never called
rc=$(cd "$REPO" && run_hook_with_stdin "refs/tags/v0.16.21 $sha refs/tags/v0.16.21 $sha
")
if [ "$rc" -ne 0 ]; then
  note "case 1 (tag-only push): hook exited $rc, expected 0"
  fail=1
elif [ -s "$STUB_LOG" ]; then
  note "case 1 (tag-only push): check-version-bump.sh was invoked, expected skip"
  fail=1
fi

# --- Case 2: tag-deletion push never invokes the check ---------------------
write_stub 1
rc=$(cd "$REPO" && run_hook_with_stdin "(delete) 0000000000000000000000000000000000000000 refs/tags/v0.16.21 $sha
")
if [ "$rc" -ne 0 ]; then
  note "case 2 (tag deletion): hook exited $rc, expected 0"
  fail=1
elif [ -s "$STUB_LOG" ]; then
  note "case 2 (tag deletion): check-version-bump.sh was invoked, expected skip"
  fail=1
fi

# --- Case 3a: branch push still invokes the check, and a passing check ----
#             still lets the push through (unchanged prior behaviour).
write_stub 0
rc=$(cd "$REPO" && run_hook_with_stdin "refs/heads/main $sha refs/heads/main $sha
")
if [ "$rc" -ne 0 ]; then
  note "case 3a (branch push, check passes): hook exited $rc, expected 0"
  fail=1
elif [ ! -s "$STUB_LOG" ]; then
  note "case 3a (branch push, check passes): check-version-bump.sh was never invoked"
  fail=1
fi

# --- Case 3b: branch push, a failing check still blocks the push ----------
write_stub 1
rc=$(cd "$REPO" && run_hook_with_stdin "refs/heads/main $sha refs/heads/main $sha
")
if [ "$rc" -ne 1 ]; then
  note "case 3b (branch push, check fails): hook exited $rc, expected 1"
  fail=1
elif [ ! -s "$STUB_LOG" ]; then
  note "case 3b (branch push, check fails): check-version-bump.sh was never invoked"
  fail=1
fi

# --- Case 4: mixed branch+tag push still invokes the check -----------------
write_stub 0
rc=$(cd "$REPO" && run_hook_with_stdin "refs/heads/main $sha refs/heads/main $sha
refs/tags/v0.16.21 $sha refs/tags/v0.16.21 $sha
")
if [ "$rc" -ne 0 ]; then
  note "case 4 (mixed branch+tag push): hook exited $rc, expected 0"
  fail=1
elif [ ! -s "$STUB_LOG" ]; then
  note "case 4 (mixed branch+tag push): check-version-bump.sh was never invoked, expected it to run (not every ref is a tag)"
  fail=1
fi

[ "$fail" -eq 0 ] && note "tag-only/tag-deletion pushes skip the check; branch and mixed pushes still run it"
exit "$fail"
