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

ENGINE_MIN_VERSION="0.7.0"

engine_bin() {
  local root="$1" candidate="" source=""
  if [ -n "${MIF_RH_CLI:-}" ]; then
    candidate="$MIF_RH_CLI"
    source="override"
  elif command -v mif-rh-cli >/dev/null 2>&1; then
    candidate="$(command -v mif-rh-cli)"
    source="path"
  elif [ -x "${root}/bin/mif-rh-cli" ]; then
    candidate="${root}/bin/mif-rh-cli"
    source="repo-local"
  fi
  if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
    echo "engine: mif-rh-cli not found (need >= v${ENGINE_MIN_VERSION})." >&2
    echo "engine: install it with scripts/fetch-engine.sh (attested download)," >&2
    echo "engine: put mif-rh-cli on PATH, or set MIF_RH_CLI to the binary." >&2
    return 5
  fi
  local version
  version="$("$candidate" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -z "$version" ]; then
    echo "engine: ${candidate} did not report a semver version" >&2
    return 5
  fi
  # POSIX per-component compare; sort -V is unavailable on some BSD sorts.
  if ! awk -v have="$version" -v need="$ENGINE_MIN_VERSION" 'BEGIN {
        n1 = split(have, h, "."); n2 = split(need, n, ".");
        for (i = 1; i <= 3; i++) {
          if (h[i] + 0 > n[i] + 0) exit 0;
          if (h[i] + 0 < n[i] + 0) exit 1;
        }
        exit 0;
      }'; then
    # The remedy differs by WHICH resolution path actually supplied the
    # stale candidate (research-harness-template#767): re-running
    # fetch-engine.sh only ever touches ${root}/bin/mif-rh-cli, so telling
    # the user to do that when the candidate came from $MIF_RH_CLI or a
    # PATH-installed binary is a guaranteed no-op — the same stale
    # candidate wins again on the very next run, with no diagnostic ever
    # naming the real cause.
    echo "engine: mif-rh-cli v${version} is older than the required v${ENGINE_MIN_VERSION}." >&2
    case "$source" in
      override)
        echo "engine: this candidate came from \$MIF_RH_CLI=${candidate} (explicit override)." >&2
        echo "engine: update that binary, or unset MIF_RH_CLI and re-run scripts/fetch-engine.sh." >&2
        ;;
      path)
        echo "engine: this candidate came from PATH (${candidate}), which takes priority" >&2
        echo "engine: over any repo-local install — re-running scripts/fetch-engine.sh will" >&2
        echo "engine: NOT fix this by itself, since it only ever writes ${root}/bin/mif-rh-cli." >&2
        echo "engine: update/remove the PATH copy, or set MIF_RH_CLI to force a specific binary," >&2
        echo "engine: e.g.: scripts/fetch-engine.sh && MIF_RH_CLI=\"${root}/bin/mif-rh-cli\" <command>" >&2
        ;;
      repo-local)
        echo "engine: this candidate came from ${root}/bin/mif-rh-cli (scripts/fetch-engine.sh's" >&2
        echo "engine: install location); re-run scripts/fetch-engine.sh to fetch v${ENGINE_MIN_VERSION}+." >&2
        ;;
    esac
    return 5
  fi
  printf '%s\n' "$candidate"
}
