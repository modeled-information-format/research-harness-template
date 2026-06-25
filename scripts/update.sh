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

# Run from the clone root regardless of the caller's CWD (mirrors scripts/verify.sh), so
# `bash /path/to/scripts/update.sh` works and .copier-answers.yml resolves from anywhere.
cd "$(dirname "$0")/.." || { echo "update.sh: cannot locate clone root" >&2; exit 2; }

ANSWERS=".copier-answers.yml"
TARGET_TAG=""        # explicit override; default = latest tag (Copier's default)
COPIER_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "update.sh: --target requires a tag" >&2; exit 2; }
      case "$2" in ""|*[!A-Za-z0-9._+-]*) echo "update.sh: invalid --target tag '$2'" >&2; exit 2 ;; esac
      TARGET_TAG="$2"; shift 2 ;;
    --) shift; COPIER_ARGS=("$@"); break ;;
    *) echo "update.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# A caller MUST NOT override the verified ref through passthrough args — that would defeat
# the verify-then-pin guarantee and could apply unverified content. (Length-guarded,
# fully-quoted expansion — safe under `set -u` on bash 3.2, no re-split/globbing.)
if [ "${#COPIER_ARGS[@]}" -gt 0 ]; then
  for a in "${COPIER_ARGS[@]}"; do
    case "$a" in
      -r|--vcs-ref|--vcs-ref=*) echo "update.sh: --vcs-ref/-r cannot be passed through — it pins the verified commit" >&2; exit 2 ;;
    esac
  done
fi

for t in git gh copier gzip yq awk; do command -v "$t" >/dev/null 2>&1 || { echo "update.sh: '$t' is required" >&2; exit 2; }; done
[ -f "$ANSWERS" ] || { echo "update.sh: $ANSWERS not found — run from a clone instantiated by copier" >&2; exit 2; }

# A copier update needs a git clone (it diffs against the recorded base). Check this
# explicitly so a non-git copy gets a clear error instead of the dirty-tree message below
# (`git diff` in a non-repo exits non-zero and would be misreported as "uncommitted changes").
git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "update.sh: not a git repository — copier update needs a git clone (see docs/how-to/instantiate-the-harness.md)" >&2; exit 2; }

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

# Read the clone's recorded source (to detect/heal drift from the pinned root).
src_path=$(yq -r '._src_path // ""' "$ANSWERS" 2>/dev/null) \
  || { echo "update.sh: could not parse $ANSWERS (invalid YAML?) — fix the answers file before updating" >&2; exit 2; }
{ [ -n "$src_path" ] && [ "$src_path" != "null" ]; } \
  || { echo "update.sh: $ANSWERS has no top-level _src_path — not a copier-generated clone" >&2; exit 2; }
PINNED_SRC="gh:${PINNED_REPO}"

# Resolve the target tag (default: latest by version) and pin it to a COMMIT SHA.
if [ -z "$TARGET_TAG" ]; then
  # Latest tag by version. `sort -V` is GNU-only (absent on macOS/BSD), so fall back to a
  # zero-padded decorate-sort-undecorate on v<major>.<minor>.<patch> tags.
  # Let git's stderr surface (no 2>/dev/null) so a network/auth/TLS failure is
  # diagnosable instead of a silent abort; a clean run with no tags is handled below.
  TARGET_TAG=$(git ls-remote --tags --refs "$REMOTE" | sed -n 's#.*refs/tags/##p' \
    | { if printf '%s\n' 1.0.0 1.0.10 | sort -V >/dev/null 2>&1; then sort -V
        else awk '{v=$0; sub(/^v/,"",v); split(v,a,"."); printf "%010d.%010d.%010d\t%s\n", a[1]+0,a[2]+0,a[3]+0,$0}' | sort | cut -f2
        fi; } | tail -1) \
    || { echo "update.sh: could not list tags at $REMOTE (network/auth/TLS?)" >&2; exit 1; }
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
WORK=$(mktemp -d "${TMPDIR:-/tmp}/update.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
# Fetch by TAG REF (not the raw SHA): SHA1-in-want / fetching unadvertised objects is
# disabled on many remotes. The tag ref brings its commit; we then archive the peeled SHA.
git -C "$WORK" fetch -q --depth 1 "$REMOTE" "refs/tags/${TARGET_TAG}"

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

# Apply, pinned to the verified SHA (TOCTOU-closed). --trust is now earned. Pass the
# extra args fully quoted (length-guarded for bash 3.2 + set -u) so an arg with spaces or
# glob characters reaches Copier intact.
#
# Copier applies from `_src_path` (it has no source override) and hard-refuses a dirty
# destination, so we do NOT rewrite the answers file first. We don't need to: `--vcs-ref`
# is a git SHA — content-addressed — so Copier applies exactly the bytes we verified no
# matter which path `_src_path` names; and a clone whose `_src_path` lags an org move (the
# zircote -> modeled-information-format transfer) still resolves, because GitHub redirects
# the old path to the new repo, which contains that SHA. The `_src_path` heal happens
# AFTER, below.
if [ "${#COPIER_ARGS[@]}" -gt 0 ]; then
  copier update --vcs-ref "$SHA" --trust "${COPIER_ARGS[@]}"
else
  copier update --vcs-ref "$SHA" --trust
fi

# Heal a drifted `_src_path` AFTER the update so future runs target the pinned upstream
# directly instead of leaning on the org-move redirect. This must come after `copier
# update` (which hard-refuses a dirty tree); the rewrite lands in the same diff the user
# reviews and commits alongside the update. Skipped when already pinned (the steady state).
if [ "$src_path" != "$PINNED_SRC" ]; then
  # Surgical single-line rewrite via awk (already required) — preserves the file's header
  # comment and other answers; avoids a perl dependency and yq's reformatting.
  awk -v s="_src_path: ${PINNED_SRC}" '/^_src_path:/{print s; next} {print}' "$ANSWERS" > "$ANSWERS.tmp" \
    && mv "$ANSWERS.tmp" "$ANSWERS" \
    || { echo "update.sh: failed to normalize _src_path in $ANSWERS" >&2; rm -f "$ANSWERS.tmp"; exit 2; }
  # Confirm the rewrite actually landed — never claim a pin we didn't make (e.g. if there
  # was no top-level `_src_path:` line for awk to replace).
  grep -qx "_src_path: ${PINNED_SRC}" "$ANSWERS" \
    || { echo "update.sh: could not pin _src_path in $ANSWERS (no top-level _src_path line)" >&2; exit 2; }
  echo "update.sh: pinned _src_path -> ${PINNED_SRC} (was '${src_path}')"
fi
