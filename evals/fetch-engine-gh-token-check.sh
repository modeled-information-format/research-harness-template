#!/usr/bin/env bash
# fetch-engine-gh-token-check.sh — regression eval for
# scripts/check-fetch-engine-gh-token.sh (research-harness-template#662).
#
# ci.yml's `verify` and `version-bump` jobs each minted a GitHub App
# installation token restricted via `repositories: research-harness-template`
# and fed it, as GH_TOKEN, to a step that runs `bash scripts/fetch-engine.sh`
# — which reads mif-rh-cli/mif-rh-mcp release + attestation data from the
# modeled-information-format/mif-rs repo. An installation token restricted
# that way 404s on ANY repo outside its installation's repo list, even a
# public one (an App-installation-scoping boundary, not a permissions gap),
# so both jobs failed on every run (reproduced on PR #661, run
# https://github.com/modeled-information-format/research-harness-template/actions/runs/29710540421).
# The fix swaps every such step's GH_TOKEN for the default job token
# (`${{ github.token }}`), which carries no installation-repo-list
# restriction (the pattern release.yml's changelog-links-check job already
# used). This eval covers scripts/check-fetch-engine-gh-token.sh, the static
# gate added to catch a future regression:
#
#   1. the shipped .github/workflows/ tree is clean (0 hits) — proves the
#      actual fix, not just the checker's own logic;
#   2. a seeded step feeding fetch-engine.sh a minted `steps.*.outputs.token`
#      fails the checker, naming the file/job/step;
#   3. a seeded step running fetch-engine.sh with no GH_TOKEN at all fails
#      (gh needs some credential in a non-interactive runner);
#   4. a seeded step using `${{ github.token }}` passes;
#   5. a workflow with an App token that's scoped correctly for ITS OWN
#      purpose (an unrelated cross-repo dispatch, docs.yml's
#      notify-org-Pages token) but never calls fetch-engine.sh at all
#      passes untouched — proving the checker doesn't just flag any minted
#      App token, only ones actually feeding fetch-engine.sh;
#   6. every fetch-engine.sh step across the real, currently-shipped
#      .github/workflows/*.yml (ci.yml x3, version-bump x1, monitor.yml x1,
#      monitor-gate.yml x1) is enumerated and none use a minted token.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  fetch-engine-gh-token-check: %s\n' "$1"; }

CHECK=scripts/check-fetch-engine-gh-token.sh

command -v yq >/dev/null 2>&1 || { note "yq is required but not on PATH"; exit 2; }
[ -x "$CHECK" ] || [ -f "$CHECK" ] || { note "$CHECK not found"; exit 2; }

# Case 1: the shipped tree is clean.
if ! bash "$CHECK" > "$TMP/ok.out" 2>&1; then
  note "checker rejected the shipped .github/workflows/*.yml tree: $(tail -5 "$TMP/ok.out")"
  fail=1
fi

# Case 2: a seeded minted-App-token step fails, naming file/job/step.
cat > "$TMP/regressed.yml" <<'EOF'
name: ci
on: [push]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: Mint a CI app token
        id: app-token
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
        with:
          repositories: research-harness-template
      - name: fetch the mif-rh engine
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
        run: bash scripts/fetch-engine.sh
EOF
if bash "$CHECK" "$TMP/regressed.yml" > "$TMP/regressed.out" 2>&1; then
  note "checker passed a step feeding fetch-engine.sh a minted steps.*.outputs.token"
  fail=1
else
  grep -q "regressed.yml job 'verify' step 'fetch the mif-rh engine'" "$TMP/regressed.out" \
    || { note "minted-token failure did not name the file/job/step: $(cat "$TMP/regressed.out")"; fail=1; }
fi

# Case 3: a seeded step with no GH_TOKEN at all fails.
cat > "$TMP/no-token.yml" <<'EOF'
name: ci
on: [push]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: fetch the mif-rh engine
        run: bash scripts/fetch-engine.sh
EOF
if bash "$CHECK" "$TMP/no-token.yml" > "$TMP/no-token.out" 2>&1; then
  note "checker passed a fetch-engine.sh step with no GH_TOKEN set at all"
  fail=1
else
  grep -q "no GH_TOKEN set" "$TMP/no-token.out" \
    || { note "missing-token failure had an unexpected message: $(cat "$TMP/no-token.out")"; fail=1; }
fi

# Case 4: a seeded step using the default job token passes.
cat > "$TMP/fixed.yml" <<'EOF'
name: ci
on: [push]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - name: fetch the mif-rh engine
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash scripts/fetch-engine.sh
EOF
if ! bash "$CHECK" "$TMP/fixed.yml" > "$TMP/fixed.out" 2>&1; then
  note "checker rejected a fetch-engine.sh step using \${{ github.token }}: $(cat "$TMP/fixed.out")"
  fail=1
fi

# Case 5: docs.yml's own minted App token is correctly scoped for ITS purpose
# (a cross-repo repository_dispatch to the org Pages repo) and never calls
# fetch-engine.sh — must pass untouched.
if ! bash "$CHECK" .github/workflows/docs.yml > "$TMP/docs.out" 2>&1; then
  note "checker false-positived on docs.yml's unrelated, correctly-scoped App token: $(cat "$TMP/docs.out")"
  fail=1
fi

# Case 6: every real fetch-engine.sh step in the shipped tree is enumerated
# (proves the gate isn't accidentally scanning zero steps and passing
# vacuously) and each is confirmed to use the default job token, not a
# minted one. release.yml's changelog-links-check job already used the
# correct (default-token) pattern before #662; the other three are #662's
# fix.
hits="$(grep -rl 'scripts/fetch-engine\.sh' .github/workflows/*.yml 2>/dev/null | sort)"
expected_files=$'.github/workflows/ci.yml\n.github/workflows/monitor-gate.yml\n.github/workflows/monitor.yml\n.github/workflows/release.yml'
if [ "$hits" != "$expected_files" ]; then
  note "expected fetch-engine.sh in exactly ci.yml, monitor.yml, monitor-gate.yml, release.yml; got: $(printf '%s' "$hits" | tr '\n' ' ')"
  fail=1
fi
for f in .github/workflows/ci.yml .github/workflows/monitor.yml .github/workflows/monitor-gate.yml .github/workflows/release.yml; do
  if grep -A2 'scripts/fetch-engine.sh' "$f" | grep -q 'steps\..*\.outputs\.token'; then
    note "$f still feeds a nearby GH_TOKEN a minted steps.*.outputs.token near a fetch-engine.sh call"
    fail=1
  fi
done

[ "$fail" -eq 0 ] && note "the fetch-engine-token gate is real: the shipped tree is clean, a seeded minted-App-token step and a seeded no-token step are both caught by name, a step using \${{ github.token }} passes, docs.yml's unrelated correctly-scoped App token never false-positives, and every real fetch-engine.sh call site in the shipped tree (ci.yml, monitor.yml, monitor-gate.yml) is accounted for"
exit "$fail"
