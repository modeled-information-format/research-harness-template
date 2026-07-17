#!/usr/bin/env bash
# release-workflow-immutable-safe.sh — regression test for #537.
#
# `release.yml` must never upload an asset to an already-published release
# (`gh release upload` after the release exists) — GitHub immutable releases
# reject that with HTTP 422 ("Cannot upload assets to an immutable release"),
# and deleting the release to retry permanently burns its tag (this already
# happened once here: v0.8.0's tag was burned and had to be re-cut as
# v0.8.1). Assert the workflow:
#
#   1. triggers on the tag push itself (`push: tags: v*.*.*`), not
#      `release: types: [published]`
#   2. never runs `gh release upload` (the post-publish anti-pattern that
#      caused #537)
#   3. creates the release via `gh release create` with the built artifact
#      attached in that same call
#
# Exit 0 iff all three hold; each check names exactly which one failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

WF=".github/workflows/release.yml"
fail=0

if [ ! -f "$WF" ]; then
  echo "FAIL: ${WF} not found"
  exit 1
fi

# 1. Tag-push trigger present: a `tags:` key nested under `on: push:`
#    specifically — not just any `tags:` line anywhere in the file (e.g. an
#    unrelated job-level key or a future comment), which would let this
#    check pass even if the workflow stopped triggering on tag pushes.
#    Plain-POSIX awk only (no \s, no gensub — this must run under macOS's
#    BSD awk as well as gawk).
on_block=$(awk '
  /^on:/ { capture=1; next }
  capture && /^[A-Za-z_-]+:/ { exit }
  capture { print }
' "$WF")

if ! printf '%s\n' "$on_block" | awk '
  function indent(line,    i) {
    i = 0
    while (i < length(line) && substr(line, i + 1, 1) == " ") i++
    return i
  }
  {
    if (!in_push && match($0, /^ *push:/)) { in_push = 1; push_indent = indent($0); next }
    if (in_push && $0 !~ /^[ ]*$/ && indent($0) <= push_indent) { in_push = 0 }
    if (in_push && match($0, /^ *tags:/)) { found = 1 }
  }
  END { exit !found }
'; then
  echo "FAIL: ${WF} has no 'tags:' key nested under 'on: push:' — the release must fire on the tag push itself, not on 'release: published'"
  fail=1
fi

# 2. No post-publish upload — the exact anti-pattern #537 reports. Strip
#    comment lines first so the *documentation* naming the anti-pattern
#    (this eval's own header included) doesn't trip its own check.
if grep -vE '^\s*#' "$WF" | grep -q 'gh release upload'; then
  echo "FAIL: ${WF} still runs 'gh release upload' — this 422s against an immutable release (#537)"
  fail=1
fi

# 3. gh release create attaches the built artifact in the same call that
#    creates the release, rather than creating it bare and uploading after.
if ! grep -qE 'gh release create .*\$\{\{ steps\.build\.outputs\.artifact \}\}' "$WF"; then
  echo "FAIL: ${WF}'s 'gh release create' does not attach the built artifact in the same call"
  fail=1
fi

if [ "${fail}" -eq 0 ]; then
  echo "PASS: release.yml creates the release with the attested asset attached in one call, no post-publish upload"
fi
exit "${fail}"
