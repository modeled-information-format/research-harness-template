#!/usr/bin/env bash
# write-finding.sh — write a finding into <findings-dir> ONLY after it validates
# against schemas/findings.schema.json (stage + ajv + atomic rename). On failure
# nothing lands in findings/. This is the write half of crash-safe resume (SPEC §4):
# a finding is visible on disk iff it is valid, so reconcile-session.sh never sees a
# half-written finding and never counts a partial as done.
#
# Usage: write-finding.sh <source.json> <findings-dir> <dest-name.json>
#   exit 0 = validated and renamed into place; non-zero = rejected, nothing written.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:?usage: write-finding.sh <source.json> <findings-dir> <dest-name.json>}"
FDIR="${2:?findings-dir required}"
NAME="${3:?dest-name.json required}"
[ -f "$SRC" ] || { echo "write-finding: source not found: $SRC" >&2; exit 2; }
# NAME must be a bare filename: a '/' or '..' would let the stage/rename escape
# the findings dir.
case "$NAME" in
  ""|*/*|*..*) echo "write-finding: dest-name must be a bare filename (no '/' or '..'): $NAME" >&2; exit 2 ;;
esac
mkdir -p "$FDIR"

# Stage in a per-invocation-unique directory (mktemp -d with the WHOLE BASENAME as
# the template, on the SAME filesystem as the destination so the final publish can
# be a hard link): a suffixed single-file template does not randomize on stock
# BSD/macOS mktemp (verified in #357's review; it silently returns the X's
# unreplaced), only GNU coreutils handles a trailing suffix. The old staging path
# was namespaced by NAME alone, so two concurrent callers writing the same NAME
# could clobber each other's staged content before either published (issue #360) --
# a per-invocation directory closes that regardless of what NAME is.
STAGE_DIR="$(mktemp -d "$FDIR/.wf-staging-XXXXXX")" || {
  # Checked explicitly: under `set -uo pipefail` (no -e), an unchecked failure
  # here leaves STAGE_DIR as an empty string, not "unset" -- so the next line's
  # "$STAGE_DIR/$NAME" would silently become "/$NAME", staging (and later
  # cleaning up with rm -f) an absolute path at the filesystem root instead of
  # failing. Fail loudly instead of ever reaching that state.
  echo "write-finding: failed to create staging directory under $FDIR" >&2
  exit 2
}
STAGE="$STAGE_DIR/$NAME"
cp "$SRC" "$STAGE"
if ! ajv validate --spec=draft2020 --strict=false -c ajv-formats \
      -s "$ROOT/schemas/findings.schema.json" \
      -r "$ROOT/schemas/mif/mif.schema.json" \
      -r "$ROOT/schemas/mif/definitions/entity-reference.schema.json" \
      -d "$STAGE" >/dev/null 2>&1; then
  rm -f "$STAGE"
  rmdir "$STAGE_DIR" 2>/dev/null
  echo "write-finding: $NAME does NOT validate — refused; nothing written to $FDIR" >&2
  exit 1
fi

# Publish via ln (a hard link), not mv: ln fails atomically with EEXIST if the
# destination already exists, so a same-name collision is detected race-free
# instead of silently overwritten (the exact #357 failure mode, on a different
# write path). This primitive takes its destination NAME from the caller, so
# unlike dimension-analyst.md's Step 5 (which owns slug generation and can
# republish under a disambiguated name), the correct behavior on collision here
# is a fail-closed refusal -- silently renaming would violate the caller's
# explicit naming, and this primitive's own documented contract is that it
# "lands in findings/ only after full-schema validation" and nothing lands
# on any failure (docs/reference/contracts.md).
DEST="$FDIR/$NAME"
# ln into an EXISTING DIRECTORY does not fail with EEXIST -- it silently
# succeeds by linking INSIDE that directory (as "$DEST/$(basename "$STAGE")",
# i.e. nested one level deeper than intended), which would defeat the whole
# collision-detection design without ever hitting the elif branch below. Guard
# against it explicitly before attempting the link; this is the one pre-check
# taken before the atomic ln (rather than relying on ln's own failure) because
# a directory unexpectedly occupying DEST is not the concurrent-writer race
# this design protects against -- it is refused the same way any other
# unwritable-destination collision is.
if [ -d "$DEST" ]; then
  rm -f "$STAGE"
  rmdir "$STAGE_DIR" 2>/dev/null
  echo "write-finding: $NAME already exists as a directory at $DEST — refused (ln would link inside it rather than fail); nothing written" >&2
  exit 1
fi
if ln "$STAGE" "$DEST" 2>/dev/null; then
  rm -f "$STAGE"
elif [ -e "$DEST" ]; then
  rm -f "$STAGE"
  rmdir "$STAGE_DIR" 2>/dev/null
  echo "write-finding: $NAME already exists at $DEST — refused (no silent overwrite); nothing written" >&2
  exit 1
else
  rmdir "$STAGE_DIR" 2>/dev/null
  echo "write-finding: validated but failed to publish: $DEST (ln failed for a reason other than an existing destination)" >&2
  exit 1
fi
rmdir "$STAGE_DIR" 2>/dev/null
echo "write-finding: wrote $FDIR/$NAME (validated)"
