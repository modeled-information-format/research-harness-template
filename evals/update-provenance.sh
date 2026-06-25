#!/usr/bin/env bash
# update-provenance.sh — eval for scripts/update.sh (issue #94).
#
# Proves the fail-closed provenance gate WITHOUT a network or real Sigstore: a
# hermetic local "upstream" git repo serves the target tag; `gh` and `copier` are
# stubbed. Asserts:
#   1. verification MISS  -> update.sh exits non-zero AND copier is never invoked.
#   2. verification PASS   -> copier is invoked, pinned to the verified SHA.
#   3. a dirty work tree   -> refused before any verification.
#
# Run: bash evals/update-provenance.sh   (exit 0 = all assertions hold)

set -uo pipefail
UPDATE_SH="$(cd "$(dirname "$0")/.." && pwd)/scripts/update.sh"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
no()  { echo "FAIL: $1"; fail=$((fail+1)); }

ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT

# --- hermetic upstream: a repo with a tagged commit, served from a bare clone ---
UP_SRC="$ROOT/upstream"; mkdir -p "$UP_SRC"
git -C "$UP_SRC" init -q
git -C "$UP_SRC" config user.email t@t.t; git -C "$UP_SRC" config user.name t
echo "template content v9" > "$UP_SRC/file.txt"
git -C "$UP_SRC" add -A; git -C "$UP_SRC" commit -q -m v9
# ANNOTATED tag: `git ls-remote refs/tags/v9.9.9` returns the tag-OBJECT sha; update.sh
# must peel it (^{}) to the COMMIT sha, which is what copier --vcs-ref needs.
git -C "$UP_SRC" tag -a v9.9.9 -m "release v9.9.9"
UP="$ROOT/upstream.git"; git clone -q --bare "$UP_SRC" "$UP"
SHA=$(git -C "$UP" rev-parse 'v9.9.9^{commit}')   # the peeled COMMIT sha

# --- stubs: git (redirect the github URL to the local bare repo), gh, copier ----
BIN="$ROOT/bin"; mkdir -p "$BIN"
cat > "$BIN/git" <<SH
#!/usr/bin/env bash
UP="$UP"; SHA="$SHA"
args=("\$@"); rewritten=()
for a in "\${args[@]}"; do
  case "\$a" in https://github.com/*|gh:*|git@github.com:*) a="\$UP";; esac
  rewritten+=("\$a")
done
# fetching a bare SHA from a local repo needs the tag ref; fetch it explicitly.
case "\$* " in
  *" fetch "*)
    # find the -C dir
    d="."; for ((i=0;i<\${#args[@]};i++)); do [ "\${args[i]}" = "-C" ] && d="\${args[i+1]}"; done
    exec /usr/bin/git -C "\$d" fetch -q --depth 1 "\$UP" "refs/tags/v9.9.9:refs/tags/v9.9.9" ;;
  *) exec /usr/bin/git "\${rewritten[@]}" ;;
esac
SH
cat > "$BIN/gh" <<SH
#!/usr/bin/env bash
# GH_VERIFY env controls the gate outcome: "fail" (default) or "pass".
if [ "\$1" = attestation ]; then
  [ "\${GH_VERIFY:-fail}" = pass ] && { echo "stub: verified"; exit 0; }
  echo "stub: attestation verification failed" >&2; exit 1
fi
exit 0
SH
cat > "$BIN/copier" <<SH
#!/usr/bin/env bash
echo "copier \$*" > "$ROOT/copier_invoked"
SH
# Note: we do NOT stub yq/sort/awk — update.sh uses the real ones (found on PATH after
# $BIN). Only git/gh/copier are stubbed.
chmod +x "$BIN"/*

mk_clone() { # -> a clean clone dir with .copier-answers.yml
  local c="$ROOT/clone"; rm -rf "$c"; mkdir -p "$c"
  git -C "$c" init -q; git -C "$c" config user.email t@t.t; git -C "$c" config user.name t
  printf '_src_path: gh:modeled-information-format/research-harness-template\n_commit: v0.1.0\n' > "$c/.copier-answers.yml"
  git -C "$c" add -A; git -C "$c" commit -q -m init
  echo "$c"
}

run() { ( cd "$1" && PATH="$BIN:$PATH" GH_VERIFY="$2" bash "$UPDATE_SH" ); }

# 1. verification MISS -> non-zero, copier never invoked
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
run "$C" fail >/dev/null 2>&1; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ]; } \
  && ok "verification miss -> exit $rc, copier NOT invoked (fail-closed)" \
  || no "verification miss not fail-closed (rc=$rc, copier_invoked=$( [ -f "$ROOT/copier_invoked" ] && echo yes || echo no ))"

# 2. verification PASS -> copier invoked, pinned to the SHA
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
run "$C" pass >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $SHA" "$ROOT/copier_invoked" 2>/dev/null; then
  ok "verification pass -> copier invoked pinned to verified SHA"
else
  no "verification pass path wrong (rc=$rc, invoked='$(cat "$ROOT/copier_invoked" 2>/dev/null)')"
fi

# 3. dirty work tree (tracked, uncommitted change) -> refused before verification
C=$(mk_clone); echo "edited" >> "$C/.copier-answers.yml"; rm -f "$ROOT/copier_invoked"
run "$C" pass >/dev/null 2>&1; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ]; } \
  && ok "dirty work tree refused (exit $rc, copier NOT invoked)" \
  || no "dirty work tree not refused (rc=$rc)"

echo "update-provenance: $pass passed, $fail failed"
[ "$fail" = 0 ]
