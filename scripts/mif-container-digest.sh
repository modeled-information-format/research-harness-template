#!/usr/bin/env bash
# mif-container-digest.sh — the MIF Container digest engine (Story #312).
#
# SHA-256 over each resource's canonical bytes (Task #313), plus a
# manifest-level digest computed over the sorted list of resource digests
# (Task #314, NFR-1 determinism) -- ADR-0017 AD-2, deliberately rejecting
# Data Package's opt-in MD5-default hash. Pure shell + coreutils (sha256sum
# or shasum), no new dependency per ADR-0017 AD-7.
#
# Usage:
#   mif-container-digest.sh resource <file>
#     Prints sha256:<64-hex> over the file's raw bytes.
#
#   mif-container-digest.sh manifest [< digests]
#     Reads resource digests one per line from stdin (each "sha256:<hex>",
#     matching schemas/mif-container.schema.json's format), sorts them
#     lexically, and hashes the sorted, newline-joined list. Two
#     independently-built manifests over identical resource sets produce a
#     byte-identical digest regardless of build order. Empty stdin (a
#     zero-resource export) is a valid input, not an error -- it hashes the
#     empty string.
set -uo pipefail

sha256_bytes() { # sha256_bytes < bytes  -> prints the raw 64-hex digest (no prefix)
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "mif-container-digest: neither sha256sum nor shasum found on PATH" >&2
    return 5
  fi
}

cmd_resource() {
  local file="${1:?usage: mif-container-digest.sh resource <file>}"
  [ -f "$file" ] || { echo "mif-container-digest: not a file: $file" >&2; return 2; }
  printf 'sha256:%s\n' "$(sha256_bytes < "$file")"
}

cmd_manifest() {
  # Sort first (byte order, matching the digest strings' own hex charset),
  # THEN strip the "sha256:" prefix -- sorting the bare hex instead of the
  # prefixed string would give the same order here since every line shares
  # the identical prefix, but working from the prefixed form is what a
  # caller piping schemas/mif-container.schema.json's own resources[].digest
  # values in verbatim actually has on hand.
  sort | sed 's/^sha256://' | sha256_bytes | sed 's/^/sha256:/'
}

case "${1:-}" in
  resource) shift; cmd_resource "$@" ;;
  manifest) shift; cmd_manifest ;;
  *)
    echo "usage: mif-container-digest.sh resource <file> | manifest [< digests]" >&2
    exit 2
    ;;
esac
