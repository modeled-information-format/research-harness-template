#!/usr/bin/env bash
# Fetch and verify the mif-rh engine binary (ADR-0016).
#
# Downloads the pinned mif-rh-cli release for this platform from the mif-rs
# repository, verifies its build provenance fail-closed with
# `gh attestation verify`, and installs it to <repo>/bin/mif-rh-cli.
# Nothing is installed if verification fails.
#
# Usage: fetch-engine.sh [--version <X.Y.Z>] [--dest <dir>]
set -euo pipefail

ENGINE_VERSION="0.3.1"   # pinned; bump alongside docs/reference/dependencies.md
ENGINE_REPO="modeled-information-format/mif-rs"
SIGNER="modeled-information-format/mif-rs/.github/workflows/release.yml"

DEST=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) ENGINE_VERSION="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    *) echo "fetch-engine: unknown argument $1" >&2; exit 2;;
  esac
done

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DEST:-${repo_root}/bin}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)  platform="linux-amd64" ;;
  Linux-aarch64) platform="linux-arm64" ;;
  Darwin-arm64)  platform="macos-arm64" ;;
  Darwin-x86_64) platform="macos-amd64" ;;
  *) echo "fetch-engine: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

artifact="mif-rh-cli-${ENGINE_VERSION}-${platform}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fetch-engine.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "fetch-engine: downloading ${artifact} from ${ENGINE_REPO} v${ENGINE_VERSION}"
gh release download "v${ENGINE_VERSION}" --repo "$ENGINE_REPO" \
  --pattern "$artifact" --dir "$tmp"

echo "fetch-engine: verifying build provenance (fail-closed)"
gh attestation verify "${tmp}/${artifact}" \
  --repo "$ENGINE_REPO" \
  --signer-workflow "$SIGNER"

mkdir -p "$DEST"
install -m 0755 "${tmp}/${artifact}" "${DEST}/mif-rh-cli"
echo "fetch-engine: installed ${DEST}/mif-rh-cli (v${ENGINE_VERSION}, attested)"
