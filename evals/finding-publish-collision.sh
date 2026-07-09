#!/usr/bin/env bash
# finding-publish-collision.sh — contract test for the collision-safe finding
# publish documented in .claude/agents/dimension-analyst.md Step 5 (issue #357:
# two concurrently-running dimension-analysts converging on the same slug used
# to have the second's plain `mv` silently overwrite the first's finding, with
# no error, log line, or trace).
#
# This exercises the ln-based publish algorithm as a standalone helper (the
# algorithm is documented prose+bash for an LLM subagent to execute, not a
# callable script, so this reproduces it faithfully rather than sourcing the
# markdown) and asserts:
#   - a clean first publish succeeds;
#   - a same-slug collision from a DIFFERENT dimension preserves BOTH findings
#     (the exact loss this issue reports — the core invariant this test pins),
#     and logs a COLLISION: line;
#   - a same-slug "collision" from the SAME dimension (a retry/resume) still
#     overwrites (not a foreign collision), but now always logs a NOTE: line
#     so it is never silent either;
#   - a THIRD finding colliding on an already-disambiguated path still lands
#     under a further-uniquified name rather than silently clobbering it;
#   - the staging path's mktemp -d template actually randomizes (a suffixed
#     single-file mktemp template does NOT on BSD/macOS, which would silently
#     reopen this exact race -- caught in code review before this shipped),
#     re-run against the REAL system mktemp when it differs from whatever
#     shadows it on PATH, not just whichever one happens to run first.
#
# Exit 0 = the publish contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  finding-publish-collision: %s\n' "$1"; }

# Mirrors dimension-analyst.md Step 5's documented publish algorithm exactly,
# including the mktemp -d fix: a suffixed single-file template
# (".finding-<slug>.XXXXXX.staging") does NOT randomize on BSD/macOS's stock
# mktemp (verified: it silently returns the X's unreplaced), only on GNU
# coreutils -- mktemp -d with the whole basename as the template is portable.
# NOTE:/COLLISION: lines go to stderr, same as the real analyst instructions.
publish() {
  local slug="$1" dimension="$2" content="$3"
  local STAGE_DIR S DEST ALT ALT2 UNIQ existing_dim
  STAGE_DIR="$(mktemp -d "$REPORTS_DIR/findings/.staging-XXXXXX")"
  S="$STAGE_DIR/finding-$slug.staging"
  printf '%s' "$content" > "$S"
  DEST="$REPORTS_DIR/findings/finding-$slug.json"
  if ln "$S" "$DEST" 2>/dev/null; then
    rm -f "$S"
    rmdir "$STAGE_DIR" 2>/dev/null
    return 0
  fi
  existing_dim="$(jq -r '.extensions.harness.dimension // empty' "$DEST" 2>/dev/null)"
  if [ "$existing_dim" = "$dimension" ]; then
    if mv "$S" "$DEST"; then
      echo "NOTE: slug '$slug' was already published by this same dimension ('$dimension'); overwritten -- if this was a distinct finding (not a retry), it is now lost and needs a more specific slug" >&2
    else
      echo "ERROR: could not overwrite '$DEST' with slug '$slug' -- staged content left at '$S' for manual recovery" >&2
    fi
    rmdir "$STAGE_DIR" 2>/dev/null
    return 0
  fi
  ALT="$REPORTS_DIR/findings/finding-$slug-$dimension.json"
  if ln "$S" "$ALT" 2>/dev/null; then
    rm -f "$S"
    echo "COLLISION: slug '$slug' already published by dimension '$existing_dim'; this finding published as '$slug-$dimension' instead" >&2
  else
    UNIQ="${STAGE_DIR##*-}"
    ALT2="$REPORTS_DIR/findings/finding-$slug-$dimension-$UNIQ.json"
    if mv "$S" "$ALT2"; then
      echo "COLLISION: slug '$slug' already published by dimension '$existing_dim', AND '$slug-$dimension' also collided; this finding published as '$slug-$dimension-$UNIQ' instead" >&2
    else
      echo "ERROR: could not publish finding for slug '$slug' even under a uniquely-suffixed path -- staged content left at '$S' for manual recovery" >&2
    fi
  fi
  rmdir "$STAGE_DIR" 2>/dev/null
  return 0
}

run_publish_cases() {
  REPORTS_DIR="$TMP/reports/topic-a"
  mkdir -p "$REPORTS_DIR/findings"

  # 1. First publish on a clean slug succeeds and its content lands untouched.
  publish rebel-model technical '{"extensions":{"harness":{"dimension":"technical"}},"content":"A"}' 2>/dev/null
  if [ -f "$REPORTS_DIR/findings/finding-rebel-model.json" ] \
     && [ "$(jq -r .content "$REPORTS_DIR/findings/finding-rebel-model.json")" = "A" ]; then
    note "first publish on a clean slug succeeds"
  else
    note "FAIL: first publish did not land"; fail=1
  fi

  # 2. A DIFFERENT dimension colliding on the same slug must not destroy the
  #    first finding -- both must survive, each with its own content intact --
  #    and it must log a COLLISION: line (never silent).
  msg="$(publish rebel-model landscape '{"extensions":{"harness":{"dimension":"landscape"}},"content":"B"}' 2>&1 1>/dev/null)"
  if [ -f "$REPORTS_DIR/findings/finding-rebel-model.json" ] \
     && [ "$(jq -r .content "$REPORTS_DIR/findings/finding-rebel-model.json")" = "A" ] \
     && [ -f "$REPORTS_DIR/findings/finding-rebel-model-landscape.json" ] \
     && [ "$(jq -r .content "$REPORTS_DIR/findings/finding-rebel-model-landscape.json")" = "B" ]; then
    note "cross-dimension slug collision preserves BOTH findings (no silent clobber)"
  else
    note "FAIL: cross-dimension collision lost a finding"; fail=1
  fi
  case "$msg" in
    *"COLLISION: slug 'rebel-model'"*) note "cross-dimension collision logs a COLLISION: line" ;;
    *) note "FAIL: cross-dimension collision did not log anything"; fail=1 ;;
  esac

  # 3. The SAME dimension re-publishing the same slug (a retry/resume) is not a
  #    foreign collision -- it overwrites, since it is the analyst's own prior
  #    work -- but it must ALSO log (a NOTE:), since a genuine second distinct
  #    finding from the same dimension colliding on the same slug is the same
  #    silent-loss failure mode, just scoped to one analyst.
  msg="$(publish rebel-model technical '{"extensions":{"harness":{"dimension":"technical"}},"content":"A-retry"}' 2>&1 1>/dev/null)"
  if [ "$(jq -r .content "$REPORTS_DIR/findings/finding-rebel-model.json")" = "A-retry" ]; then
    note "same-dimension retry overwrites its own prior publish"
  else
    note "FAIL: same-dimension retry did not overwrite"; fail=1
  fi
  case "$msg" in
    *"NOTE: slug 'rebel-model'"*) note "same-dimension overwrite logs a NOTE: line (never silent)" ;;
    *) note "FAIL: same-dimension overwrite did not log anything"; fail=1 ;;
  esac

  # 4. A THIRD finding colliding on the already-disambiguated ALT path
  #    (finding-rebel-model-landscape.json, from case 2) must not silently
  #    clobber it -- it must land under a further-uniquified path instead.
  publish rebel-model landscape '{"extensions":{"harness":{"dimension":"landscape"}},"content":"C"}' 2>/dev/null
  landscape_variants=$(find "$REPORTS_DIR/findings" -name 'finding-rebel-model-landscape*.json' | wc -l | tr -d ' ')
  if [ "$landscape_variants" -ge 2 ] \
     && [ "$(jq -r .content "$REPORTS_DIR/findings/finding-rebel-model-landscape.json")" = "B" ]; then
    note "a third collision on an already-disambiguated path does not clobber it (landscape's B finding still intact)"
  else
    note "FAIL: a third collision clobbered the already-disambiguated finding"; fail=1
  fi

  # 5. No staging files or directories are left behind after any of the above.
  if [ -z "$(find "$REPORTS_DIR/findings" -mindepth 1 -name '.staging-*' 2>/dev/null)" ]; then
    note "no staging directories left behind"
  else
    note "FAIL: a staging directory was left behind"; fail=1
  fi
}

run_publish_cases

# 6. mktemp -d with a template argument produces a DIFFERENT path on each call
#    (portable across BSD and GNU mktemp -- this is the specific property the
#    fix depends on; a suffixed single-file template does NOT have it on BSD).
mktemp_d_randomizes() {
  local d1 d2 base="$1"
  d1="$($base -d "$TMP/.staging-XXXXXX")"
  d2="$($base -d "$TMP/.staging-XXXXXX")"
  local ok=1
  [ "$d1" != "$d2" ] && ok=0
  rmdir "$d1" "$d2" 2>/dev/null
  return "$ok"
}
if mktemp_d_randomizes mktemp; then
  note "mktemp -d randomizes a whole-basename template (via whatever's on PATH)"
else
  note "FAIL: mktemp -d did not randomize -- staging paths would collide"; fail=1
fi

# 6b. Re-run against the REAL system mktemp (not whatever shadows it on PATH)
#     when the two differ -- this is the specific binary the original bug was
#     found against (BSD/macOS's stock mktemp does not randomize a suffixed
#     single-file template; this project's fix instead uses mktemp -d with a
#     whole-basename template, which this proves is safe on that binary too).
#     Skips gracefully when there's nothing to distinguish (e.g. Linux CI,
#     where /bin/mktemp and $PATH's mktemp are the same GNU coreutils binary).
for real in /usr/bin/mktemp /bin/mktemp; do
  if [ -x "$real" ] && [ "$(command -v mktemp)" != "$real" ]; then
    if mktemp_d_randomizes "$real"; then
      note "mktemp -d also randomizes under the real system binary ($real, distinct from PATH's)"
    else
      note "FAIL: mktemp -d did not randomize under $real -- the fix is not actually portable"; fail=1
    fi
    break
  fi
done

# 7. dimension-analyst.md's documented publish step actually uses ln (not a
#    bare mv) and mktemp -d (not a suffixed single-file template) for staging,
#    including the third-collision fallback -- so this test and the markdown
#    instructions cannot silently diverge.
if grep -qE 'ln "\$S" "\$DEST"' .claude/agents/dimension-analyst.md \
   && grep -qE 'mktemp -d "\$REPORTS_DIR/findings/\.staging-XXXXXX"' .claude/agents/dimension-analyst.md \
   && grep -qE 'ALT2="\$REPORTS_DIR/findings/finding-<slug>-<dimension>-\$UNIQ\.json"' .claude/agents/dimension-analyst.md; then
  note "dimension-analyst.md documents the ln-based collision-safe publish, mktemp -d staging, and the third-collision fallback"
else
  note "FAIL: dimension-analyst.md does not document the collision-safe publish algorithm"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "finding-publish-collision: PASS"
  exit 0
fi
echo "finding-publish-collision: FAIL"
exit 1
