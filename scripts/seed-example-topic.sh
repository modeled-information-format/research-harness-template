#!/usr/bin/env bash
# seed-example-topic.sh — clone seed fixture (SPEC §7).
#
# The template serves ONE archived example research topic straight out of reports/:
# `example-okf-mif-knowledge-spine` (a worked OKF + MIF knowledge-spine corpus). On
# instantiation a clone should START with it, but with the `example-` prefix stripped
# (`okf-mif-knowledge-spine`) so it reads as the clone's own seed, not a template demo.
#
# This script is wired as a copier `_task`, which copier runs on BOTH `copier copy` and
# `copier update` (with --trust). It is therefore IDEMPOTENT and SELF-CLEANING:
#   - first run (copy):   rename example-…  -> okf-…, rewrite the topic token in every
#                         corpus file (ids, namespaces, paths, frontmatter) + the manifest.
#   - later runs (update): copier re-ships the `example-`-prefixed copy; discard it so the
#                         clone keeps only its instance-owned renamed seed. THIS is what
#                         keeps `copier update` conflict-free (the renamed seed is never
#                         re-touched by copier; the transient prefixed copy is removed).
# It NO-OPS in the template repo itself (clones exclude copier.yml), so the template keeps
# serving its `example-`-prefixed showcase and its own gates can run this harmlessly.
#
# Usage: bash scripts/seed-example-topic.sh   (run from the harness root or via copier)

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

OLD="example-okf-mif-knowledge-spine"
NEW="okf-mif-knowledge-spine"
SRC="reports/$OLD"
DST="reports/$NEW"
CFG="harness.config.json"

# Guard: no-op in the TEMPLATE (clones exclude copier.yml). Keeps the served example
# intact and lets template-side gates invoke this script without side effects.
if [ -f copier.yml ]; then
  echo "seed-example-topic: template repo (copier.yml present) — no-op"
  exit 0
fi

# rewrite_corpus_tokens (below) writes each file's replacement to a same-directory temp
# and atomically renames it into place — the corpus file is never partially written. To
# honor the repo rule that reports/ holds only tracked data artifacts, an EXIT trap sweeps
# any temp an interrupted run could orphan, so nothing derived is left under reports/.
trap 'find reports -name "*.seedtmp" -type f -delete 2>/dev/null || true' EXIT

# Normalize the manifest: the renamed topic exists, is archived, and no stale
# `example-`-prefixed duplicate survives a copier re-merge. Idempotent.
normalize_config() {
  [ -f "$CFG" ] || return 0
  local tmp; tmp=$(mktemp)
  if jq --arg old "$OLD" --arg new "$NEW" '
        .topics = (
          (.topics // [])
          | map(
              # Fresh seed: rename the OLD entry and stamp the seed identity.
              if .id == $old
              then (.id = $new | .namespace = ("harness/" + $new) | .status = "archived")
              # Already-NEW entry (a prior/partial seed, or a manifest that already
              # names NEW): normalize idempotently — backfill a MISSING namespace/status
              # so it is always well-formed, but never clobber a value the clone owner
              # deliberately set (e.g. flipping it back to active).
              elif .id == $new
              then (.namespace = (if (.namespace // "") == "" then ("harness/" + $new) else .namespace end)
                    | .status = (if (.status // "") == "" then "archived" else .status end))
              else . end)
          | reduce .[] as $t ([]; if any(.[]; .id == $t.id) then . else . + [$t] end)
        )
      ' "$CFG" > "$tmp"; then
    mv "$tmp" "$CFG"
  else
    rm -f "$tmp"; echo "seed-example-topic: failed to normalize $CFG" >&2; exit 1
  fi
}

# Replace the topic token in every file under DST. Portable (no `sed -i`): temp+rename
# per file. The token is unique and contains no sed-delimiter chars.
rewrite_corpus_tokens() {
  local f tmp
  while IFS= read -r -d '' f; do
    tmp="$f.seedtmp"
    if sed "s#$OLD#$NEW#g" "$f" > "$tmp"; then
      mv "$tmp" "$f" || { echo "seed-example-topic: token rewrite failed on $f" >&2; exit 1; }
    else
      rm -f "$tmp"; echo "seed-example-topic: token rewrite failed on $f" >&2; exit 1
    fi
  done < <(find "$DST" -type f -print0)
}

if [ -d "$DST" ]; then
  # Already seeded. Discard any prefixed copy copier re-shipped on update.
  if [ -d "$SRC" ]; then
    rm -rf "$SRC"
    echo "seed-example-topic: discarded re-shipped $SRC (clone owns $DST)"
  fi
  # Self-heal a first run interrupted between the dir rename and re-tokenization. The
  # fresh-seed path rewrites tokens BEFORE normalize_config stamps the manifest, so a
  # manifest that does NOT yet name $NEW means a prior migration never finished and the
  # corpus may still carry $OLD tokens. Gate on that manifest state — NOT on the mere
  # presence of an $OLD token — so a corpus file that LEGITIMATELY mentions the literal
  # $OLD (e.g. a provenance note) is never rewritten on a routine `copier update` (a
  # completed migration already names $NEW and is skipped). rewrite is idempotent.
  if [ -f "$CFG" ] && ! jq -e --arg new "$NEW" '(.topics // []) | any(.id == $new)' "$CFG" >/dev/null 2>&1; then
    rewrite_corpus_tokens
    echo "seed-example-topic: completed an interrupted migration under $DST"
  fi
  normalize_config
  echo "seed-example-topic: $DST already present — normalized"
  exit 0
fi

if [ -d "$SRC" ]; then
  mv "$SRC" "$DST" || { echo "seed-example-topic: could not move $SRC -> $DST" >&2; exit 1; }
  rewrite_corpus_tokens
  normalize_config
  echo "seed-example-topic: seeded $DST (renamed from $OLD; archived)"
  exit 0
fi

echo "seed-example-topic: nothing to seed (neither $SRC nor $DST present)"
exit 0
