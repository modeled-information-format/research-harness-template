#!/usr/bin/env bash
# install-hooks.sh — wire up .githooks/ via core.hooksPath, without
# clobbering a hooksPath a contributor already configured on purpose.
# Called from package.json's postinstall; always exits 0 (best-effort,
# never fails the install).
set -uo pipefail

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

current="$(git config --local --get core.hooksPath 2>/dev/null || true)"
if [ -z "$current" ]; then
  git config --local core.hooksPath .githooks
elif [ "$current" != ".githooks" ]; then
  echo "install-hooks: core.hooksPath is already set to '$current', leaving it alone (not wiring .githooks)" >&2
fi
exit 0
