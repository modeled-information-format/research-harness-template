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

ENGINE_VERSION="0.6.0"   # pinned; bump alongside scripts/lib/engine.sh's
# ENGINE_MIN_VERSION and every stated mif-rh-cli floor: docs/reference/dependencies.md,
# docs/reference/contracts.md, docs/tutorials/getting-started.md
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

tmp="$(mktemp -d "${TMPDIR:-/tmp}/fetch-engine.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$DEST"

# Both engine binaries ship in the same release: the CLI (classification,
# ADR-0016) and the MCP server (read-only agent surface, ADR-0014/0015).
for bin in mif-rh-cli mif-rh-mcp; do
  artifact="${bin}-${ENGINE_VERSION}-${platform}"
  echo "fetch-engine: downloading ${artifact} from ${ENGINE_REPO} v${ENGINE_VERSION}"
  gh release download "v${ENGINE_VERSION}" --repo "$ENGINE_REPO" \
    --pattern "$artifact" --dir "$tmp"

  echo "fetch-engine: verifying build provenance (fail-closed)"
  gh attestation verify "${tmp}/${artifact}" \
    --repo "$ENGINE_REPO" \
    --signer-workflow "$SIGNER"

  install -m 0755 "${tmp}/${artifact}" "${DEST}/${bin}"
  echo "fetch-engine: installed ${DEST}/${bin} (v${ENGINE_VERSION}, attested)"
done
