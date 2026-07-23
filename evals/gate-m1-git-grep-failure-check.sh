#!/usr/bin/env bash
# gate-m1-git-grep-failure-check.sh — regression eval for
# research-harness-template#770.
#
# gate_m1's corpus-contamination scrub used to run its `git grep` through
# `2>/dev/null || true`, so ANY git-grep failure -- not just its documented
# "no match" exit-1 case -- was silently reported as a clean scan (`hits`
# ends up empty either way, and `[ -z "$hits" ]` can't tell "no match" from
# "the scan never ran"). This eval stubs `git grep` to fail with git's own
# real-error exit status (2, e.g. an unsupported pathspec-magic version or an
# I/O error) and asserts gate_m1 reports the failure loudly instead of a
# false "ok".
#
# Exit 0 = the gate correctly fails (and says why) on a real git-grep error.
# Exit 1 = the #770 bug reproduces: the gate reported a clean scan anyway.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  gate-m1-git-grep-failure-check: %s\n' "$1"; }

REAL_GIT="$(command -v git)" || { note "no git on PATH"; exit 2; }

# A stub `git` that fails only `git grep` (with a real git-grep error status,
# not the "no match" status 1), and passes every other subcommand straight
# through to the real git so the rest of gate_m1 (and verify.sh's own git
# usage, if any) behaves normally.
STUBDIR="$TMP/stub-bin"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "grep" ]; then
  echo "fatal: stubbed git-grep failure (simulated pathspec-magic/I-O error)" >&2
  exit 2
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$STUBDIR/git"

out="$TMP/scoped.out"
PATH="$STUBDIR:$PATH" bash scripts/verify.sh --gates 'gate_m1$' >"$out" 2>&1
rc=$?

if grep -q 'no corpus finding IDs or corpus report-slug paths in built artifacts' "$out"; then
  note "gate_m1 reported a CLEAN scan despite a stubbed git-grep failure (the #770 bug)"
  fail=1
fi
grep -qi 'stubbed git-grep failure' "$out" || {
  note "gate_m1 gave no indication the scrub itself failed (stderr was swallowed)"
  fail=1
}
[ "$rc" -ne 0 ] || {
  note "verify.sh --gates 'gate_m1\$' exited 0 despite the stubbed git-grep failure"
  fail=1
}

[ "$fail" -eq 0 ] && note "gate_m1 fails loudly (not silently 'ok') when git grep itself errors"
exit "$fail"
