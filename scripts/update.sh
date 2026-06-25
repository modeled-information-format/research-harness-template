#!/usr/bin/env bash
# update.sh — the ONLY supported way a clone updates from the template.
#
# Fail-closed provenance gate in FRONT of `copier update` (issue #94). Copier
# exposes no pre-fetch hook and runs template `_tasks`/`_migrations` under
# `--trust`, so the gate must run BEFORE Copier is ever invoked, and the update
# must be PINNED to the exact commit the gate verified (no floating "latest").
#
# Trust model — reuses the EXACT primitive of .github/workflows/release.yml,
# SECURITY.md, and CI (one verification primitive everywhere):
#   1. Resolve the target tag and pin it to a concrete commit SHA.
#   2. Reproduce the release artifact from that tree, byte-for-byte the way
#      release.yml builds it: `git archive --format=tar --prefix=<name>-<tag>/ \
#      <sha> | gzip -n`.
#   3. Verify its SLSA build-provenance attestation, pinned to THIS repo AND the
#      release workflow identity:
#        gh attestation verify <artifact> --repo <owner/repo> \
#          --signer-workflow <owner/repo>/.github/workflows/release.yml
#      Any miss -> non-zero exit, Copier is NEVER invoked.
#   4. On success: `copier update --vcs-ref <verified-sha>` — Copier checks out
#      exactly the verified SHA (closes the TOCTOU gap; a git SHA is a content
#      hash, so the checkout is the verified bytes by construction).
#
# The pinned trust root is the `--signer-workflow` identity baked into THIS file.
# update.sh is template-managed, so a hostile update could rewrite it — but the
# CURRENT (trusted) update.sh verifies the incoming tag against the current pinned
# identity BEFORE applying it, so an update not signed by the release workflow is
# rejected before it can replace the verifier. The root is established once at
# clone (TOFU) and cannot be silently weakened by an update.
#
# Reproducibility note: `git archive | gzip -n` is deterministic for a given git
# version + platform, but tar header format and the gzip OS byte can differ across
# platforms (release.yml documents the same caveat). If verification fails ONLY
# because your local toolchain produces different bytes, that is a reproducibility
# mismatch, not a provenance failure — see docs/how-to/update-your-harness.md.
#
# Usage:  bash scripts/update.sh [--target <tag>] [-- <extra copier args>]
#   exit 0 = verified and applied; non-zero = verification miss / precondition
#   failure (nothing applied).

set -euo pipefail

ANSWERS=".copier-answers.yml"
TARGET_TAG=""        # explicit override; default = latest tag (Copier's default)
COPIER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --target) [ $# -ge 2 ] || { echo "update.sh: --target requires a tag" >&2; exit 2; }; TARGET_TAG="$2"; shift 2 ;;
    --) shift; COPIER_ARGS=("$@"); break ;;
    *) echo "update.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

for t in git gh copier gzip yq; do command -v "$t" >/dev/null 2>&1 || { echo "update.sh: '$t' is required" >&2; exit 2; }; done
[ -f "$ANSWERS" ] || { echo "update.sh: $ANSWERS not found — run from a clone instantiated by copier" >&2; exit 2; }

# A copier update requires a clean work tree (it computes and re-applies a diff).
# Hard-fail on a dirty tree rather than silently stashing user work.
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "update.sh: working tree has uncommitted changes — commit or stash them first (copier update needs a clean tree)" >&2
  exit 2
fi

# Trust root — PINNED to the upstream template repo + its release-workflow identity.
# It is NOT derived from .copier-answers.yml: `_src_path` is mutable, so deriving trust
# from it would let an update (or a user) silently repoint the root to another repo and
# still get a "verified" result. A fork that re-releases under its own org edits these
# two constants (a visible, reviewed change); everyone else inherits the upstream root.
PINNED_REPO="modeled-information-format/research-harness-template"
SIGNER_WORKFLOW="${PINNED_REPO}/.github/workflows/release.yml"
REMOTE="https://github.com/${PINNED_REPO}.git"
NAME="${PINNED_REPO##*/}"

# Read _src_path only to sanity-check the clone's recorded origin against the pinned root
# (informational — trust does not depend on it).
src_path=$(yq -r '._src_path // ""' "$ANSWERS" 2>/dev/null | head -1)
case "${src_path#gh:}" in
  "$PINNED_REPO"|"$PINNED_REPO".git|https://github.com/"$PINNED_REPO"*|"") : ;;
  *) echo "update.sh: WARNING: clone _src_path ('$src_path') differs from the pinned trust root '$PINNED_REPO'; verifying against the pinned root regardless." >&2 ;;
esac

# Resolve the target tag (default: latest by version) and pin it to a COMMIT SHA.
if [ -z "$TARGET_TAG" ]; then
  TARGET_TAG=$(git ls-remote --tags --refs "$REMOTE" 2>/dev/null \
    | sed -n 's#.*refs/tags/##p' | sort -V | tail -1)
  [ -n "$TARGET_TAG" ] || { echo "update.sh: no tags found at $REMOTE" >&2; exit 1; }
fi
# Peel annotated tags to the underlying commit (^{}); fall back to the ref itself for a
# lightweight tag (which already points at a commit). `--vcs-ref` needs a commit, not a
# tag object.
SHA=$(git ls-remote "$REMOTE" "refs/tags/${TARGET_TAG}^{}" | awk '{print $1}' | head -1)
[ -n "$SHA" ] || SHA=$(git ls-remote "$REMOTE" "refs/tags/${TARGET_TAG}" | awk '{print $1}' | head -1)
[ -n "$SHA" ] || { echo "update.sh: tag '$TARGET_TAG' not found at $REMOTE" >&2; exit 1; }

echo "update.sh: target ${PINNED_REPO}@${TARGET_TAG} -> ${SHA}"

# Fetch the target tree so we can reproduce the release artifact locally.
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
git -C "$WORK" fetch -q --depth 1 "$REMOTE" "$SHA"

# Reproduce the artifact EXACTLY as .github/workflows/release.yml does.
ARTIFACT="${WORK}/${NAME}-${TARGET_TAG}.tar.gz"
git -C "$WORK" archive --format=tar --prefix="${NAME}-${TARGET_TAG}/" "$SHA" | gzip -n > "$ARTIFACT"

# THE GATE: verify SLSA provenance, pinned to this repo AND the release workflow.
echo "update.sh: verifying build-provenance attestation (fail-closed)…"
if ! gh attestation verify "$ARTIFACT" \
      --repo "$PINNED_REPO" \
      --signer-workflow "$SIGNER_WORKFLOW"; then
  echo "update.sh: provenance verification FAILED for ${PINNED_REPO}@${TARGET_TAG} — refusing to update (nothing applied)" >&2
  exit 1
fi
echo "update.sh: provenance verified — applying update pinned to ${SHA}"

# Apply, pinned to the verified SHA (TOCTOU-closed). --trust is now earned.
# (bash 3.2-safe expansion of a possibly-empty array under `set -u`.)
copier update --vcs-ref "$SHA" --trust ${COPIER_ARGS[@]+"${COPIER_ARGS[@]}"}
