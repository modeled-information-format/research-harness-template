#!/usr/bin/env bash
# write-finding-stage-cleanup.sh — contract test that scripts/write-finding.sh
# never leaks its per-invocation staging directory, on ANY exit path (issue
# #683: the generic ln-failure branch rmdir'd the staging dir WITHOUT first
# removing the staged file inside it; rmdir only succeeds on an empty
# directory and its failure was swallowed by 2>/dev/null, so every generic ln
# failure — disk-full, a permissions/ACL denial, a filesystem that disallows
# hard links — leaked one .wf-staging-* directory plus the copied finding,
# permanently and silently, with no cleanup pass anywhere to reclaim them).
#
# Asserts, per exit path:
#   - a clean publish lands the finding and leaves no .wf-staging-* behind;
#   - a validation refusal (invalid source) leaves no .wf-staging-* behind;
#   - an EEXIST collision refusal leaves no .wf-staging-* behind;
#   - a GENERIC ln failure (reproduced deterministically by shadowing ln on
#     PATH with a stub that always fails while DEST does not exist — the
#     exact "[ -e $DEST ] is false" condition of the #683 branch) exits
#     non-zero, leaves DEST absent, and leaves no .wf-staging-* behind.
#     Before the #683 fix this last case failed every time it was reached.
#
# Exit 0 = the cleanup contract holds on every path. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  write-finding-stage-cleanup: %s\n' "$1"; }

VALID_SRC="evals/fixtures/sample-corpus/findings/lc-bandwidth.json"
FDIR="$TMP/findings"

no_staging_leftovers() {
  [ -z "$(find "$FDIR" -mindepth 1 -name '.wf-staging-*' 2>/dev/null)" ]
}

# 1. Clean publish: lands, and no staging dir is left behind.
if bash scripts/write-finding.sh "$VALID_SRC" "$FDIR" ok.json >/dev/null 2>&1 \
   && [ -f "$FDIR/ok.json" ] && no_staging_leftovers; then
  note "clean publish lands the finding and leaves no staging dir"
else
  note "FAIL: clean publish left staging residue or did not land"; fail=1
fi

# 2. Validation refusal: nothing lands, no staging dir left behind.
printf '%s' '{"not":"a finding"}' > "$TMP/invalid.json"
bash scripts/write-finding.sh "$TMP/invalid.json" "$FDIR" bad.json >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$FDIR/bad.json" ] && no_staging_leftovers; then
  note "validation refusal writes nothing and leaves no staging dir"
else
  note "FAIL: validation refusal leaked staging residue (rc=$rc)"; fail=1
fi

# 3. EEXIST collision refusal: the existing finding survives untouched, and no
#    staging dir is left behind.
bash scripts/write-finding.sh "$VALID_SRC" "$FDIR" ok.json >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ -f "$FDIR/ok.json" ] && no_staging_leftovers; then
  note "EEXIST collision refusal leaves no staging dir"
else
  note "FAIL: EEXIST collision refusal leaked staging residue (rc=$rc)"; fail=1
fi

# 4. GENERIC ln failure (the #683 branch): shadow ln with a stub that always
#    fails, so `ln "$STAGE" "$DEST"` fails while [ -e "$DEST" ] stays false —
#    deterministically reaching the final else branch without needing a real
#    disk-full/EPERM/EXDEV condition. The staged file must be removed and the
#    staging dir rmdir'd; before the fix the rm was skipped, the rmdir failed
#    silently on the non-empty dir, and both leaked.
STUB="$TMP/stub-bin"
mkdir -p "$STUB"
printf '#!/bin/sh\nexit 1\n' > "$STUB/ln"
chmod +x "$STUB/ln"
PATH="$STUB:$PATH" bash scripts/write-finding.sh "$VALID_SRC" "$FDIR" ln-fail.json >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$FDIR/ln-fail.json" ] && no_staging_leftovers; then
  note "generic ln failure exits non-zero, writes nothing, and leaves no staging dir (#683)"
else
  note "FAIL: generic ln failure leaked a staging dir or its staged file (rc=$rc; the #683 leak)"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "write-finding-stage-cleanup: PASS"
  exit 0
fi
echo "write-finding-stage-cleanup: FAIL"
exit 1
