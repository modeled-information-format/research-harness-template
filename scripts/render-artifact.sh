#!/usr/bin/env bash
# render-artifact.sh — render one typed Artifact (schemas/artifact.schema.json)
# to an output channel (SPEC §6d, §10). Three channels:
#   report — the generic MIF Level-3 markdown report (reports/<topic>/<slug>.md):
#            authoritative YAML frontmatter (the MIF concept) + Markdown body.
#            This is the canonical MIF source of truth and is NEVER exempt; it is
#            write-then-validated through scripts/mif-project.sh. A real
#            falsification verdict (extensions.harness.verification) is REQUIRED,
#            so the falsification gate must run over the synthesised claims BEFORE
#            rendering — pass the resulting verdict as <verification.json>.
#   blog — the first-class PUBLISHED channel; book + channel packs — optional PUBLISHED
#            channels. blog and book now carry MIF **Level-1** frontmatter (a base
#            concept: @context/@type/@id/conceptType/created) — the doc's own
#            identity — so every report output is at least L1 (the report channel is
#            full L3). They remain exempt from the L3 I/O conformance gate (their
#            FORMAT is orthogonal): prose is written from the artifact's synthesised
#            body + public citations only and carries no internal finding identity,
#            so the citation-leak gate stays green.
#
# EXHAUSTIVE by contract: the synthesizer emits one section per surviving finding
# and carries each finding's own evidence (sources, entities, dimension, verdict)
# onto its section, so every channel renders every finding WITH its evidence — the
# same per-finding rigor the diataxis channel performs, not a thin summary.
#
# Since research-harness-template#276 (Story #293, Category B cutover), the
# rendering itself (the DEF jq function library: autolink/deglob/mermaid/secblock,
# and the report/blog/book composers) delegates to the mif-rh engine
# (mif-rh-cli), hard required: install it with scripts/fetch-engine.sh, put
# mif-rh-cli on PATH, or set MIF_RH_CLI. Path/version arithmetic below (SLUG,
# SLUGPATH, VERSION, CREATED) stays plain bash, exactly as before — none of it
# ever used jq. VALID_FROM (research-harness-template#480) is the one exception:
# it reads/writes the report channel's rendered frontmatter via `yq`, since the
# engine itself emits neither `modified` nor `temporal.validFrom` (see below).
#
# Usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [<verification.json>]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
# shellcheck source=scripts/lib/engine.sh
. "$ROOT/scripts/lib/engine.sh"
ENGINE="$(engine_bin "$ROOT")" || exit 5

ART="${1:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
CHANNEL="${2:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
OUT="${3:?usage: render-artifact.sh <artifact.json> <report|blog|book> <out.md> [verification.json]}"
VERIF="${4:-}"
[ -f "$ART" ] || { echo "render: artifact not found: $ART" >&2; exit 2; }

SLUG=$(basename "$OUT"); SLUG="${SLUG%.md}"
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# astro-rehype-relative-markdown-links (the site's cross-link rewriter) slugifies
# each path segment with github-slugger, which is a HEADING-anchor algorithm: it
# strips embedded "." without inserting a separator. Any genre-suffixed filename
# (e.g. "<slug>.engineering.md") therefore gets a mismatched, 404ing rewritten
# href, even though Astro's own content-collection route (which keeps the dot)
# resolves fine. The plugin honors an explicit `slug:` frontmatter field over its
# own computation, so stamp one here — the file's own path relative to the repo
# root, which is exactly the route the content collection already resolves to.
# $OUT itself may be passed absolute (report-synthesizer.md's own examples use
# an absolute $REPORTS_DIR) or relative; normalize to absolute before stripping
# the repo root, so SLUGPATH is always repo-root-relative regardless of how the
# caller passed it. `realpath -m` would do this in one call, but it's a GNU
# coreutils extension — stock macOS/BSD `realpath` rejects `-m` outright, and
# this script must run on a contributor's plain macOS shell, not just CI
# (ubuntu-latest ships GNU coreutils, so that alone wouldn't have caught it).
# This script already `cd`s to the repo root above, so a plain pwd-prefix on a
# relative $OUT is equivalent for every real call site (none pass `../`).
# Deliberately logical `pwd`, not `pwd -P`: callers build $OUT with plain
# $(pwd) (see the absolute-$OUT eval below), so REPO_ROOT must match that same
# logical form -- physical would diverge on a symlinked checkout and silently
# fail this prefix-strip, reproducing the exact bug this block fixes.
REPO_ROOT="$(pwd)"
case "$OUT" in
  /*) OUT_ABS="$OUT" ;;
  *)  OUT_ABS="$REPO_ROOT/$OUT" ;;
esac
OUT_REL="${OUT_ABS#"$REPO_ROOT"/}"
SLUGPATH="$(dirname "$OUT_REL")/$SLUG"

# Version indicator: a genre re-rendered for the same topic overwrites its file
# in place (this harness keeps no automatic history), so a real, extractable
# `version:` field is the primary on-disk record that this is revision N, not
# the first pass (a `modified` != `temporal.validFrom` divergence, stamped
# below, is a secondary signal of the same fact once #480 lands). Read the
# file's OWN prior version (if $OUT already exists) and increment; otherwise
# this is version 1.
VERSION=1
if [ -f "$OUT" ]; then
  # Anchored at column 0: version is always a top-level key here. An indented
  # match (e.g. a nested "ontology: { version: 1.0.0 }" on a hand-authored
  # doc) is a DIFFERENT field and must not be mistaken for this report's own
  # revision counter.
  PREV=$(sed -n '/^---$/,/^---$/p' "$OUT" 2>/dev/null \
    | grep -m1 -E '^version:[[:space:]]*[0-9]+' | grep -oE '[0-9]+')
  [ -n "$PREV" ] && VERSION=$((PREV + 1))
fi

# Canonical MIF Level 3 requires temporal.validFrom in addition to modified
# (research-harness-template#480); the mif-rh engine's render-artifact command
# does not emit either field itself. Stamp them here, the same way VERSION is
# carried forward above: validFrom is the report's OWN first-recorded moment,
# so a re-render must inherit the PRIOR file's validFrom rather than resetting
# it to "now" every time — only a first-ever render sets it to $CREATED.
VALID_FROM="$CREATED"
if [ -f "$OUT" ]; then
  PREV_VALID_FROM="$(yq --front-matter=extract '.temporal.validFrom // ""' "$OUT" 2>/dev/null)"
  [ -n "$PREV_VALID_FROM" ] && [ "$PREV_VALID_FROM" != "null" ] && VALID_FROM="$PREV_VALID_FROM"
fi

RENDER_ARGS=(harness render-artifact "$ART" "$CHANNEL" --slug "$SLUG" --slugpath "$SLUGPATH" --created "$CREATED" --version "$VERSION")
[ -n "$VERIF" ] && [ -f "$VERIF" ] && RENDER_ARGS+=(--verification "$VERIF")

case "$CHANNEL" in
  report)
    RTMPD="$(mktemp -d)"; RTMP="$RTMPD/report.md"; trap 'rm -rf "$RTMPD"' EXIT
    if ! "$ENGINE" "${RENDER_ARGS[@]+"${RENDER_ARGS[@]}"}" "$RTMP" >/dev/null; then
      echo "render: composing the report failed" >&2
      exit 1
    fi
    # CREATED/VALID_FROM are passed as env vars + strenv(), never interpolated
    # directly into the yq expression string — CREATED is always this script's
    # own `date -u` output, but VALID_FROM can carry forward a PRIOR render's
    # value (read via --front-matter=extract above), so it must never be
    # trusted as safe-to-interpolate shell/yq syntax.
    if ! CREATED="$CREATED" VALID_FROM="$VALID_FROM" yq --front-matter=process -i \
          '.modified = strenv(CREATED) | .temporal["@type"] = "TemporalMetadata" | .temporal.validFrom = strenv(VALID_FROM)' \
          "$RTMP"; then
      echo "render: failed to stamp modified/temporal.validFrom into $RTMP frontmatter" >&2
      exit 1
    fi
    if ! scripts/mif-project.sh "$RTMP" >/dev/null 2>&1; then
      echo "render: report does NOT project to a valid MIF L3 finding (not written to $OUT)." >&2
      echo "render: run the falsification gate over the synthesised claims first and pass <verification.json>." >&2
      scripts/mif-project.sh "$RTMP" 2>&1 | sed 's/^/  /' >&2 || true
      exit 1
    fi
    mkdir -p "$(dirname "$OUT")"
    mv "$RTMP" "$OUT"
    echo "render: wrote $OUT (report, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
    ;;
  blog|book)
    # Same temp-then-move discipline as the report channel above (#681): render
    # to a mktemp file, check the engine's exit status explicitly (set -e is NOT
    # in effect — a bare failing invocation would fall through silently), and
    # only mv into $OUT on success. A crashed/interrupted engine must never
    # leave a partially-written file at the published path a topic README links
    # to, and a prior good render at $OUT must survive a failed re-render.
    BTMPD="$(mktemp -d)"; BTMP="$BTMPD/$CHANNEL.md"; trap 'rm -rf "$BTMPD"' EXIT
    if ! "$ENGINE" "${RENDER_ARGS[@]+"${RENDER_ARGS[@]}"}" "$BTMP" >/dev/null; then
      echo "render: composing the $CHANNEL output failed (nothing written to $OUT)" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$OUT")"
    mv "$BTMP" "$OUT"
    echo "render: wrote $OUT ($CHANNEL, $(wc -l < "$OUT" | tr -d ' ') lines) from $ART"
    ;;
  *)
    echo "render: channel must be report|blog|book (got '$CHANNEL')" >&2
    exit 2
    ;;
esac
