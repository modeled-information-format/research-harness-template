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

: "${ENGINE_MIN_VERSION:=0.7.0}"

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
  # Capture the full semver, including any pre-release suffix (e.g. -rc1,
  # -alpha.2) and any build-metadata suffix (e.g. +build.5) — a bare
  # X.Y.Z-only capture silently discards them, which makes a pre-release
  # binary compare as == to the release of the same X.Y.Z instead of
  # correctly ranking below it (issue #779).
  version="$("$candidate" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?' | head -1)"
  if [ -z "$version" ]; then
    echo "engine: ${candidate} did not report a semver version" >&2
    return 5
  fi
  # Build metadata MUST be ignored for precedence purposes
  # (https://semver.org/#spec-item-10) — strip any trailing +... on both
  # sides before any comparison.
  version="${version%%+*}"
  local min_version="${ENGINE_MIN_VERSION%%+*}"
  local release="${version%%-*}" prerelease="" need_release="${min_version%%-*}" need_prerelease=""
  case "$version" in *-*) prerelease="${version#*-}" ;; esac
  case "$min_version" in *-*) need_prerelease="${min_version#*-}" ;; esac
  # POSIX per-component compare; sort -V is unavailable on some BSD sorts.
  # Semver precedence (https://semver.org/#spec-item-11): compare the X.Y.Z
  # release triplet first; if it's tied, a version WITH a pre-release suffix
  # always ranks below one without (a pre-release is by definition not yet
  # the finalized release it names); if both carry a pre-release, compare
  # dot-separated identifiers left to right per spec-item-11's own rules —
  # numeric identifiers compare numerically and always rank below
  # non-numeric ones, non-numeric identifiers compare ASCII-lexically, and
  # a larger set of fields has higher precedence when all preceding fields
  # are equal — rather than a single lexicographic string compare, which
  # would wrongly rank e.g. "rc10" below "rc2".
  if ! awk -v have="$release" -v need="$need_release" \
         -v have_pre="$prerelease" -v need_pre="$need_prerelease" '
      function is_num(s) { return s ~ /^[0-9]+$/ }
      function cmp_id(a, b,    a_num, b_num) {
        a_num = is_num(a); b_num = is_num(b);
        if (a_num && b_num) { return (a + 0 > b + 0) - (a + 0 < b + 0); }
        if (a_num && !b_num) return -1;
        if (!a_num && b_num) return 1;
        return (a > b) - (a < b);
      }
      function cmp_pre(p1, p2,    n1, n2, i, lim, c, a1, a2) {
        n1 = split(p1, a1, "."); n2 = split(p2, a2, ".");
        lim = (n1 < n2 ? n1 : n2);
        for (i = 1; i <= lim; i++) {
          c = cmp_id(a1[i], a2[i]);
          if (c != 0) return c;
        }
        return (n1 > n2) - (n1 < n2);
      }
      BEGIN {
        n1 = split(have, h, "."); n2 = split(need, n, ".");
        for (i = 1; i <= 3; i++) {
          if (h[i] + 0 > n[i] + 0) exit 0;
          if (h[i] + 0 < n[i] + 0) exit 1;
        }
        if (have_pre == "" ) exit 0;             # release (or equal-or-later) beats any pre-release requirement
        if (need_pre == "") exit 1;              # have is a pre-release of the exact required release -> too low
        if (cmp_pre(have_pre, need_pre) >= 0) exit 0;
        exit 1;
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
