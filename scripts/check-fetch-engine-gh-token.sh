#!/usr/bin/env bash
# check-fetch-engine-gh-token.sh — static regression gate for
# research-harness-template#662/#666.
#
# scripts/fetch-engine.sh reads mif-rh-cli/mif-rh-mcp release + attestation
# data from modeled-information-format/mif-rs — a repo most callers of it
# never otherwise touch. The ORIGINAL #662 bug was a GitHub App installation
# token minted with `repositories:` restricted to the current repo alone,
# which hard-404s on any repo outside that list, even a public one in the
# same org — an App-installation-scoping boundary, not a permission-*
# shortfall.
#
# #666 first "fixed" this by swapping every such step's GH_TOKEN for the
# ambient default job token (`${{ github.token }}`). That is a real security
# regression, not a fix: it substitutes a purpose-built, narrowly-scoped
# read-only App identity (this org's whole ADR-011 least-privilege-Apps
# model) for the workflow's own ambient credential, for no reason other than
# "it also happens to work." The actual bug was simpler than that: the `ci`
# app (`mif-ci`) is already installed org-wide (repository_selection: all),
# so the fix is just to WIDEN the minted token's own `repositories:` input
# to include `mif-rs` — same least-privilege App token, correctly scoped.
#
# This gate proves every `bash scripts/fetch-engine.sh` step, across every
# workflow in .github/workflows/, is fed a MINTED App token (never the
# ambient job token, never nothing) whose own mint step's `repositories:`
# input actually includes `mif-rs` — so a future edit can't silently
# reintroduce either failure mode (the original 404, or the ambient-token
# regression) without this gate catching it.
#
# Usage: check-fetch-engine-gh-token.sh [file...]   (default: every
#        .github/workflows/*.yml in this repo)
# Exit 0 = every fetch-engine.sh step uses a correctly-scoped minted App
# token. Exit 1 = a step feeds it the ambient job token, no token at all, or
# a minted token not scoped to mif-rs. Exit 2 = tooling missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v yq >/dev/null 2>&1 || { echo "check-fetch-engine-gh-token: yq is required but not on PATH" >&2; exit 2; }

files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  shopt -s nullglob
  files=(.github/workflows/*.yml)
  shopt -u nullglob
fi

fail=0

for f in "${files[@]}"; do
  [ -f "$f" ] || continue

  while IFS= read -r job; do
    [ -n "$job" ] || continue
    step_count="$(yq ".jobs[\"${job}\"].steps // [] | length" "$f")"
    for ((i = 0; i < step_count; i++)); do
      run_val="$(yq ".jobs[\"${job}\"].steps[${i}].run // \"\"" "$f")"
      case "$run_val" in
        *scripts/fetch-engine.sh*) ;;
        *) continue ;;
      esac

      name_val="$(yq ".jobs[\"${job}\"].steps[${i}].name // \"(unnamed step)\"" "$f")"
      token_val="$(yq ".jobs[\"${job}\"].steps[${i}].env.GH_TOKEN // \"\"" "$f")"

      case "$token_val" in
        *"github.token"*|*"secrets.GITHUB_TOKEN"*)
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh is fed the ambient default job token (${token_val}) instead of a purpose-built, read-only App token — a least-privilege regression (#662/#666), not a fix. Mint a token scoped to include mif-rs instead." >&2
          fail=1
          continue
          ;;
        "")
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh runs with no GH_TOKEN set — gh needs some credential in a non-interactive runner." >&2
          fail=1
          continue
          ;;
      esac

      # Must reference a minted step's output: steps.<id>.outputs.token
      step_id="$(printf '%s' "$token_val" | sed -nE 's/.*steps\.([A-Za-z0-9_-]+)\.outputs\.token.*/\1/p')"
      if [ -z "$step_id" ]; then
        echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh's GH_TOKEN (${token_val}) is neither the ambient job token nor a recognized minted steps.*.outputs.token reference." >&2
        fail=1
        continue
      fi

      # Find that step (by id) in the same job and check its repositories: input.
      mint_repos="$(yq ".jobs[\"${job}\"].steps[] | select(.id == \"${step_id}\") | .with.repositories // \"\"" "$f")"
      case "$mint_repos" in
        *mif-rs*) ;;
        *)
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': its minted token (step '${step_id}') is not scoped to include mif-rs (repositories: '${mint_repos}') — this is exactly the #662 404. Add mif-rs to that mint step's repositories: input." >&2
          fail=1
          ;;
      esac
    done
  done < <(yq '.jobs // {} | keys | .[]' "$f")
done

exit "$fail"
