#!/usr/bin/env bash
# mif-container-digest.sh — the MIF Container digest engine (Story #312).
#
# SHA-256 over each resource's canonical bytes (Task #313), plus a
# manifest-level digest computed over the sorted list of resource digests
# (Task #314, NFR-1 determinism) -- ADR-0017 AD-2, deliberately rejecting
# Data Package's opt-in MD5-default hash. Pure shell + coreutils (sha256sum
# or shasum), no new dependency per ADR-0017's Secondary Decision Driver 2
# ("jq/ajv-cli, already required by scripts/verify.sh, must be sufficient").
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
  [ "$#" -eq 1 ] || { echo "usage: mif-container-digest.sh resource <file>" >&2; return 2; }
  local file="$1"
  [ -f "$file" ] || { echo "mif-container-digest: not a file: $file" >&2; return 2; }
  # Assign-then-printf, not `printf '...' "$(sha256_bytes < "$file")"` directly:
  # a command substitution used as a bare printf argument discards its own exit
  # status (printf's success is what the function returns), so a sha256_bytes
  # failure -- unreadable file, or neither sha256sum nor shasum on PATH -- was
  # silently swallowed and printed as a malformed "sha256:" line at exit 0.
  local hex
  hex="$(sha256_bytes < "$file")" || return $?
  printf 'sha256:%s\n' "$hex"
}

cmd_manifest() {
  [ "$#" -eq 0 ] || { echo "usage: mif-container-digest.sh manifest [< digests]" >&2; return 2; }
  # LC_ALL=C pins byte-order collation, matching every other determinism-
  # critical sort in this repo (scripts/update.sh, scripts/build-topic-
  # readme.sh) -- an unpinned `sort`'s order can vary by the running locale,
  # which would silently break the "byte-identical regardless of build order"
  # guarantee NFR-1 (Task #314) requires. Hash the sorted, still-prefixed
  # lines directly: stripping and re-adding "sha256:" around the hash costs
  # two extra subprocess forks for no behavioral difference, since every line
  # already shares the identical prefix and therefore sorts identically either
  # way.
  { LC_ALL=C sort | sha256_bytes; } | sed 's/^/sha256:/'
}

case "${1:-}" in
  resource) shift; cmd_resource "$@" ;;
  manifest) shift; cmd_manifest "$@" ;;
  *)
    echo "usage: mif-container-digest.sh resource <file> | manifest [< digests]" >&2
    exit 2
    ;;
esac
