#!/usr/bin/env bash
# check-fetch-engine-gh-token.sh — static regression gate for
# research-harness-template#662.
#
# scripts/fetch-engine.sh only ever reads PUBLIC release + attestation data
# from modeled-information-format/mif-rs — a repo no CI/CD workflow step in
# THIS repo otherwise touches. A GitHub App installation token restricted to
# a `repositories:` list (or one whose `owner`/`repositories` inputs are both
# omitted, which `actions/create-github-app-token` then scopes to exactly the
# CURRENT repo) hard-404s on any repo outside that list, even a public one —
# that is a boundary of App installation scoping, not a permissions gap a
# wider `permission-*` input can fix (#662's root cause; reproduced on PR
# #661, runs https://github.com/modeled-information-format/research-harness-template/actions/runs/29710540421).
# The fix is to give every `bash scripts/fetch-engine.sh` step the default
# job token (`${{ github.token }}`), which carries no such
# installation-repo-list restriction (the same pattern release.yml's
# changelog-links-check job already used). This gate proves every such step,
# across every workflow in .github/workflows/, still does that — so a future
# edit can't silently reintroduce the #662 regression by wiring a minted (and
# therefore potentially repo-restricted) App token back in.
#
# Usage: check-fetch-engine-gh-token.sh [file...]   (default: every
#        .github/workflows/*.yml in this repo)
# Exit 0 = every fetch-engine.sh step uses a safe token. Exit 1 = a step
# feeds it a minted App token, or none at all. Exit 2 = tooling missing.
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
        *steps.*outputs.token*)
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh is fed a minted App token (${token_val}) — App installation tokens 404 on any repo outside their installation scope, even a public one (#662). Use \${{ github.token }} instead." >&2
          fail=1
          ;;
        "")
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh runs with no GH_TOKEN set — gh needs some credential in a non-interactive runner." >&2
          fail=1
          ;;
        *"github.token"*|*"secrets.GITHUB_TOKEN"*)
          # Safe: the default job token, never installation-repo-list restricted.
          ;;
        *)
          echo "check-fetch-engine-gh-token: ${f} job '${job}' step '${name_val}': fetch-engine.sh's GH_TOKEN (${token_val}) is neither the default job token nor a recognized minted-App-token pattern — verify by hand that it isn't installation-repo-list restricted." >&2
          fail=1
          ;;
      esac
    done
  done < <(yq '.jobs // {} | keys | .[]' "$f")
done

exit "$fail"
