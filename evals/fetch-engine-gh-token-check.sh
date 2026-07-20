#!/usr/bin/env bash
# fetch-engine-gh-token-check.sh — regression eval for
# scripts/check-fetch-engine-gh-token.sh (research-harness-template#662/#666).
#
# ci.yml's `verify`/`version-bump` jobs (and, via their pack sources,
# monitor.yml/monitor-gate.yml) originally fed scripts/fetch-engine.sh's
# cross-repo read of mif-rs a GitHub App installation token restricted to
# this repo alone — installation tokens 404 on any repo outside their scope,
# even a public one, so both jobs failed on every run (#662, reproduced on
# PR #661). A first attempt at a fix (#666) swapped GH_TOKEN for the ambient
# default job token instead — a real least-privilege regression: it
# substitutes this org's purpose-built, read-only App identity (ADR-011)
# for the ambient job credential, when the actual bug was just that the
# mint step's own `repositories:` input needed mif-rs added to it (the `ci`
# app is already installed org-wide). This eval covers the corrected
# scripts/check-fetch-engine-gh-token.sh, which now enforces the RIGHT
# invariant:
#
#   1. the shipped .github/workflows/ tree is clean (0 hits) — proves the
#      actual fix, not just the checker's own logic;
#   2. a seeded step feeding fetch-engine.sh the ambient github.token fails
#      (the #666 regression pattern), naming the file/job/step;
#   3. a seeded step running fetch-engine.sh with no GH_TOKEN at all fails;
#   4. a seeded step using a minted App token whose mint step's
#      repositories: input includes mif-rs passes;
#   5. a seeded step using a minted App token whose mint step's
#      repositories: does NOT include mif-rs fails (the original #662 404
#      pattern), naming the mint step;
#   6. a workflow with an App token that's scoped correctly for ITS OWN
#      purpose (an unrelated cross-repo dispatch, docs.yml's
#      notify-org-Pages token) but never calls fetch-engine.sh at all
#      passes untouched;
#   7. every fetch-engine.sh step across the real, currently-shipped
#      .github/workflows/*.yml (ci.yml, version-bump, monitor.yml,
#      monitor-gate.yml, release.yml) is enumerated and each resolves to a
#      mint step whose repositories: includes mif-rs.
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

# Case 2: a seeded step using the ambient github.token fails (the #666 regression).
cat > "$TMP/ambient.yml" <<'EOF'
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
if bash "$CHECK" "$TMP/ambient.yml" > "$TMP/ambient.out" 2>&1; then
  note "checker passed a step feeding fetch-engine.sh the ambient github.token"
  fail=1
else
  grep -q "ambient default job token" "$TMP/ambient.out" \
    || { note "ambient-token failure had an unexpected message: $(cat "$TMP/ambient.out")"; fail=1; }
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

# Case 4: a seeded step using a correctly-scoped minted App token passes.
cat > "$TMP/fixed.yml" <<'EOF'
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
          repositories: research-harness-template,mif-rs
      - name: fetch the mif-rh engine
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
        run: bash scripts/fetch-engine.sh
EOF
if ! bash "$CHECK" "$TMP/fixed.yml" > "$TMP/fixed.out" 2>&1; then
  note "checker rejected a fetch-engine.sh step using a minted token scoped to include mif-rs: $(cat "$TMP/fixed.out")"
  fail=1
fi

# Case 5: a seeded step using a minted App token NOT scoped to mif-rs fails
# (the original #662 404 pattern), naming the mint step.
cat > "$TMP/underscoped.yml" <<'EOF'
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
if bash "$CHECK" "$TMP/underscoped.yml" > "$TMP/underscoped.out" 2>&1; then
  note "checker passed a minted token not scoped to mif-rs (the original #662 404 pattern)"
  fail=1
else
  grep -q "app-token" "$TMP/underscoped.out" \
    || { note "under-scoped-mint failure did not name the mint step: $(cat "$TMP/underscoped.out")"; fail=1; }
fi

# Case 6: docs.yml's own minted App token is correctly scoped for ITS purpose
# (a cross-repo repository_dispatch to the org Pages repo) and never calls
# fetch-engine.sh — must pass untouched.
if ! bash "$CHECK" .github/workflows/docs.yml > "$TMP/docs.out" 2>&1; then
  note "checker false-positived on docs.yml's unrelated, correctly-scoped App token: $(cat "$TMP/docs.out")"
  fail=1
fi

# Case 7: every real fetch-engine.sh step in the shipped tree is enumerated
# and each resolves to a mint step scoped to include mif-rs.
hits="$(grep -rl 'scripts/fetch-engine\.sh' .github/workflows/*.yml 2>/dev/null | sort)"
expected_files=$'.github/workflows/ci.yml\n.github/workflows/monitor-gate.yml\n.github/workflows/monitor.yml\n.github/workflows/release.yml'
if [ "$hits" != "$expected_files" ]; then
  note "expected fetch-engine.sh in exactly ci.yml, monitor.yml, monitor-gate.yml, release.yml; got: $(printf '%s' "$hits" | tr '\n' ' ')"
  fail=1
fi

[ "$fail" -eq 0 ] && note "the fetch-engine-token gate is real: the shipped tree is clean, an ambient-token step and a no-token step both fail by name, a correctly mif-rs-scoped minted token passes, an under-scoped minted token fails naming its mint step, docs.yml's unrelated correctly-scoped App token never false-positives, and every real fetch-engine.sh call site in the shipped tree (ci.yml, monitor.yml, monitor-gate.yml, release.yml) is accounted for"
exit "$fail"
