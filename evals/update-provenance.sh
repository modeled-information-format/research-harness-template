#!/usr/bin/env bash
# update-provenance.sh — eval for scripts/update.sh (issue #94).
#
# Proves the fail-closed provenance gate WITHOUT a network or real Sigstore: a
# hermetic local "upstream" git repo serves the target tag; `gh` and `copier` are
# stubbed. Asserts:
#   1. local+release verification MISS -> update.sh exits non-zero AND copier is never invoked.
#   2. local verification PASS         -> copier is invoked, pinned to the verified SHA.
#   3. local MISS + release PASS + metadata+content match -> fallback succeeds, copier invoked.
#   4. local MISS + release PASS + metadata mismatch -> fallback refused.
#   5. local MISS + release PASS + content mismatch -> fallback refused.
#   6. a dirty work tree -> refused before any verification.
# And every attestation/download call remains pinned to the expected repo/workflow/asset.
#
# Run: bash evals/update-provenance.sh   (exit 0 = all assertions hold)

set -uo pipefail
UPDATE_SH="$(cd "$(dirname "$0")/.." && pwd)/scripts/update.sh"
pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
no()  { echo "FAIL: $1"; fail=$((fail+1)); }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/update-eval.XXXXXX"); trap 'rm -rf "$ROOT"' EXIT
DRIFTED_SRC="gh:zircote/research-harness-template"

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
# Some environments set safe.bareRepository=explicit; opt in for local bare-repo ops.
SHA=$(git -c safe.bareRepository=all -C "$UP" rev-parse 'v9.9.9^{commit}')   # the peeled COMMIT sha
ASSET="research-harness-template-v9.9.9.tar.gz"
mkdir -p "$ROOT/release"
git -C "$UP_SRC" archive --format=tar --prefix="research-harness-template-v9.9.9/" "$SHA" \
  | gzip > "$ROOT/release/$ASSET"

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
    exec /usr/bin/git -c safe.bareRepository=all -C "\$d" fetch -q --depth 1 "\$UP" "refs/tags/v9.9.9:refs/tags/v9.9.9" ;;
  *) exec /usr/bin/git -c safe.bareRepository=all "\${rewritten[@]}" ;;
esac
SH
cat > "$BIN/gh" <<SH
#!/usr/bin/env bash
# GH_LOCAL_VERIFY / GH_RELEASE_VERIFY control attestation outcomes independently.
ROOT="$ROOT"; ASSET="$ASSET"
PINNED_REPO="modeled-information-format/research-harness-template"
SIGNER_WORKFLOW="\${PINNED_REPO}/.github/workflows/release.yml"
if [ "\$1" = "attestation" ] && [ "\$2" = "verify" ]; then
  f="\$3"
  repo=""; workflow=""
  for ((i=4;i<=\$#;i++)); do
    a="\${!i}"
    case "\$a" in
      --repo) j=\$((i+1)); repo="\${!j}" ;;
      --signer-workflow) j=\$((i+1)); workflow="\${!j}" ;;
    esac
  done
  [ "\$repo" = "\$PINNED_REPO" ] || { echo "stub: wrong --repo '\$repo'" >&2; exit 1; }
  [ "\$workflow" = "\$SIGNER_WORKFLOW" ] || { echo "stub: wrong --signer-workflow '\$workflow'" >&2; exit 1; }
  case "\$f" in
    *.local.tar.gz) mode="\${GH_LOCAL_VERIFY:-fail}" ;;
    *"/\$ASSET"|"\$ASSET") mode="\${GH_RELEASE_VERIFY:-fail}" ;;
    *) mode=fail ;;
  esac
  [ "\$mode" = pass ] && { echo "stub: verified"; exit 0; }
  echo "stub: attestation verification failed" >&2; exit 1
fi
if [ "\$1" = "release" ] && [ "\$2" = "download" ]; then
  dir="."
  repo=""; pattern=""
  for ((i=1;i<=\$#;i++)); do
    a="\${!i}"
    if [ "\$a" = "--dir" ]; then j=\$((i+1)); dir="\${!j}"; fi
    if [ "\$a" = "--repo" ]; then j=\$((i+1)); repo="\${!j}"; fi
    if [ "\$a" = "--pattern" ]; then j=\$((i+1)); pattern="\${!j}"; fi
  done
  [ "\$3" = "v9.9.9" ] || { echo "stub: wrong release tag '\$3'" >&2; exit 1; }
  [ "\$repo" = "\$PINNED_REPO" ] || { echo "stub: wrong download --repo '\$repo'" >&2; exit 1; }
  [ "\$pattern" = "\$ASSET" ] || { echo "stub: wrong download --pattern '\$pattern'" >&2; exit 1; }
  mkdir -p "\$dir"
  cp "\$ROOT/release/\$ASSET" "\$dir/\$ASSET"
  exit 0
fi
exit 1
SH
cat > "$BIN/copier" <<SH
#!/usr/bin/env bash
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "stub: copier refuses dirty work tree" >&2
  exit 1
fi
echo "copier \$*" > "$ROOT/copier_invoked"
# Simulate real copier update: it rewrites .copier-answers.yml itself, including the
# current drifted _src_path line. This plus the clean-tree refusal makes the eval
# sensitive to update.sh moving the _src_path heal before copier update.
if [ -f .copier-answers.yml ]; then
  awk -v drifted_src="$DRIFTED_SRC" '/^_src_path:/{print "_src_path: " drifted_src; next}
       /^_commit:/{print "_commit: v9.9.9"; next}
       {print}' .copier-answers.yml > .copier-answers.yml.t \
    && mv .copier-answers.yml.t .copier-answers.yml
fi
SH
# Note: we do NOT stub yq/sort/awk — update.sh uses the real ones (found on PATH after
# $BIN). Only git/gh/copier are stubbed.
chmod +x "$BIN"/*

mk_clone() { # -> a clean clone dir with .copier-answers.yml and update.sh copied in
  local c="$ROOT/clone"; rm -rf "$c"; mkdir -p "$c/scripts"
  cp "$UPDATE_SH" "$c/scripts/update.sh"   # update.sh runs from within the clone (it cd's to its own ../)
  git -C "$c" init -q; git -C "$c" config user.email t@t.t; git -C "$c" config user.name t
  # Drifted origin (pre-org-move): a successful update must heal _src_path to the pinned root.
  printf '_src_path: %s\n_commit: v0.1.0\n' "$DRIFTED_SRC" > "$c/.copier-answers.yml"
  git -C "$c" add -A; git -C "$c" commit -q -m init
  echo "$c"
}

# Invoke the clone's own copy from an unrelated CWD — proves update.sh cd's to its clone
# root regardless of where it's called from.
run() {
  (
    cd "$ROOT" && PATH="$BIN:$PATH" \
    GH_LOCAL_VERIFY="$2" GH_RELEASE_VERIFY="$3" \
    bash "$1/scripts/update.sh"
  )
}

# 1. local+release verification MISS -> non-zero, copier never invoked
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
ERR="$ROOT/test1.err"
run "$C" fail fail >/dev/null 2>"$ERR"; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ] && grep -q "provenance verification FAILED" "$ERR"; } \
  && ok "verification miss -> exit $rc, copier NOT invoked (fail-closed)" \
  || no "verification miss not fail-closed (rc=$rc, copier_invoked=$( [ -f "$ROOT/copier_invoked" ] && echo yes || echo no ), err='$(cat "$ERR" 2>/dev/null)')"

# 2. local verification PASS -> copier invoked pinned to the SHA, AND _src_path healed
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
run "$C" pass fail >/dev/null 2>"$ROOT/test2.err"; rc=$?
if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $SHA" "$ROOT/copier_invoked" 2>/dev/null \
   && grep -q '^_src_path: gh:modeled-information-format/research-harness-template$' "$C/.copier-answers.yml" \
   && grep -q '^_commit: v9.9.9$' "$C/.copier-answers.yml"; then
  ok "verification pass -> copier pinned to verified SHA; copier rewrote answers and update.sh healed drifted _src_path after the clean update"
else
  no "verification pass path wrong (rc=$rc, invoked='$(cat "$ROOT/copier_invoked" 2>/dev/null)', src_path='$(grep _src_path "$C/.copier-answers.yml" 2>/dev/null)')"
fi

# 3. local MISS + release PASS + metadata+content match -> fallback succeeds
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
run "$C" fail pass >/dev/null 2>&1; rc=$?
if [ "$rc" = 0 ] && grep -q -- "--vcs-ref $SHA" "$ROOT/copier_invoked" 2>/dev/null; then
  ok "fallback path: release attestation + metadata+content match -> copier pinned to verified SHA"
else
  no "fallback path failed unexpectedly (rc=$rc, invoked='$(cat "$ROOT/copier_invoked" 2>/dev/null)')"
fi

# 4. local MISS + release PASS + metadata mismatch -> refused
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
MISMATCH="$ROOT/mismatch"; rm -rf "$MISMATCH"; mkdir -p "$MISMATCH/research-harness-template-v9.9.9"
cp "$UP_SRC/file.txt" "$MISMATCH/research-harness-template-v9.9.9/file.txt"
# Intentionally flip the exec bit while keeping the file content/path the same so the
# fallback's mode/type guard (not the content diff) is what refuses the artifact.
chmod 755 "$MISMATCH/research-harness-template-v9.9.9/file.txt"
tar -C "$MISMATCH" -cf - research-harness-template-v9.9.9 | gzip > "$ROOT/release/$ASSET"
ERR="$ROOT/test4.err"
run "$C" fail pass >/dev/null 2>"$ERR"; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ] && grep -q "release asset mode string does not match pinned commit" "$ERR"; } \
  && ok "fallback metadata mismatch refused (exit $rc, copier NOT invoked)" \
  || no "fallback metadata mismatch not refused (rc=$rc, copier_invoked=$( [ -f "$ROOT/copier_invoked" ] && echo yes || echo no ), err='$(cat "$ERR" 2>/dev/null)')"

# restore valid release artifact for the next test
git -C "$UP_SRC" archive --format=tar --prefix="research-harness-template-v9.9.9/" "$SHA" \
  | gzip > "$ROOT/release/$ASSET"

# 5. local MISS + release PASS + content mismatch -> refused
C=$(mk_clone); rm -f "$ROOT/copier_invoked"
MISMATCH="$ROOT/mismatch"; rm -rf "$MISMATCH"; mkdir -p "$MISMATCH/research-harness-template-v9.9.9"
echo "tampered content" > "$MISMATCH/research-harness-template-v9.9.9/file.txt"
tar -C "$MISMATCH" -cf - research-harness-template-v9.9.9 | gzip > "$ROOT/release/$ASSET"
ERR="$ROOT/test5.err"
run "$C" fail pass >/dev/null 2>"$ERR"; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ] && grep -q "release asset content does not match pinned commit" "$ERR"; } \
  && ok "fallback content mismatch refused (exit $rc, copier NOT invoked)" \
  || no "fallback content mismatch not refused (rc=$rc, copier_invoked=$( [ -f "$ROOT/copier_invoked" ] && echo yes || echo no ), err='$(cat "$ERR" 2>/dev/null)')"
# restore valid release artifact for the remaining test
git -C "$UP_SRC" archive --format=tar --prefix="research-harness-template-v9.9.9/" "$SHA" \
  | gzip > "$ROOT/release/$ASSET"

# 6. dirty work tree (tracked, uncommitted change) -> refused before verification
C=$(mk_clone); echo "edited" >> "$C/.copier-answers.yml"; rm -f "$ROOT/copier_invoked"
ERR="$ROOT/test6.err"
run "$C" pass fail >/dev/null 2>"$ERR"; rc=$?
{ [ "$rc" != 0 ] && [ ! -f "$ROOT/copier_invoked" ] && grep -q "working tree has uncommitted changes" "$ERR"; } \
  && ok "dirty work tree refused (exit $rc, copier NOT invoked)" \
  || no "dirty work tree not refused (rc=$rc, err='$(cat "$ERR" 2>/dev/null)')"

echo "update-provenance: $pass passed, $fail failed"
[ "$fail" = 0 ]
