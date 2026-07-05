#!/usr/bin/env bash
# engine.sh — locate the mif-rh engine binary (ADR-0016).
#
# Sourced by the classification scripts. Resolution order:
#   1. $MIF_RH_CLI          — explicit override (developers, source builds)
#   2. mif-rh-cli on PATH   — operator-installed
#   3. <repo>/bin/mif-rh-cli — installed by scripts/fetch-engine.sh (attested)
# Classification hard-requires the engine: there is no bash fallback. A
# missing or too-old binary is a loud failure naming the fix, never a
# silently different code path.

ENGINE_MIN_VERSION="0.3.1"

engine_bin() {
  local root="$1" candidate=""
  if [ -n "${MIF_RH_CLI:-}" ]; then
    candidate="$MIF_RH_CLI"
  elif command -v mif-rh-cli >/dev/null 2>&1; then
    candidate="$(command -v mif-rh-cli)"
  elif [ -x "${root}/bin/mif-rh-cli" ]; then
    candidate="${root}/bin/mif-rh-cli"
  fi
  if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
    echo "engine: mif-rh-cli not found (need >= v${ENGINE_MIN_VERSION})." >&2
    echo "engine: install it with scripts/fetch-engine.sh (attested download)," >&2
    echo "engine: put mif-rh-cli on PATH, or set MIF_RH_CLI to the binary." >&2
    return 5
  fi
  local version
  version="$("$candidate" --version 2>/dev/null | awk '{print $NF}')"
  if [ -z "$version" ]; then
    echo "engine: ${candidate} did not report a version" >&2
    return 5
  fi
  if [ "$(printf '%s\n%s\n' "$version" "$ENGINE_MIN_VERSION" | sort -V | head -1)" != "$ENGINE_MIN_VERSION" ]; then
    echo "engine: mif-rh-cli v${version} is older than the required v${ENGINE_MIN_VERSION}; re-run scripts/fetch-engine.sh" >&2
    return 5
  fi
  printf '%s\n' "$candidate"
}
