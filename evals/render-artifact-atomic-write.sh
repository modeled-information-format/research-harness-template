#!/usr/bin/env bash
# render-artifact-atomic-write.sh — regression test for issue #681: the
# blog/book channel case in scripts/render-artifact.sh used to hand the engine
# the REAL $OUT path with no exit-status check (`set -e` is not in effect in
# that script), so an engine that crashed or errored partway through writing
# left a partially-written file at the exact published path the topic README
# links to — silently, with the script's own exit code still reading success.
# The report channel immediately above it already did this correctly
# (mktemp render -> explicit exit-status check -> mv into place).
#
# This drives scripts/render-artifact.sh with a FAKE engine (via the
# documented MIF_RH_CLI override in scripts/lib/engine.sh) that writes partial
# output to its destination and exits non-zero, and asserts for BOTH published
# channels (blog and book):
#   - a failed render exits non-zero (the pre-fix script exited 0);
#   - a failed render never creates $OUT when it didn't exist;
#   - a failed render leaves a PRIOR good $OUT byte-identical (temp-then-move,
#     never an in-place overwrite of the published file);
#   - a failed render prints a diagnostic on stderr (never silent);
#   - a successful render still lands the full content at $OUT and exits 0.
#
# Exit 0 = the atomic-write contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  render-artifact-atomic-write: %s\n' "$1"; }

# Fake engine: answers --version (engine.sh's engine_bin probes it), then in
# FAKE_ENGINE_MODE=fail writes a partial line to the final argument (the
# output path) and exits 1 — the exact "crashed partway through writing"
# shape #681 describes. In FAKE_ENGINE_MODE=ok it writes a complete document
# and exits 0.
FAKE_ENGINE="$TMP/fake-mif-rh-cli"
cat > "$FAKE_ENGINE" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "mif-rh-cli 99.0.0"
  exit 0
fi
out=""
for a in "$@"; do out="$a"; done
if [ "${FAKE_ENGINE_MODE:-fail}" = "ok" ]; then
  printf 'complete rendered document\n' > "$out"
  exit 0
fi
printf 'partial garb' > "$out"
exit 1
FAKE
chmod +x "$FAKE_ENGINE"

ART="$TMP/artifact.json"
printf '{}' > "$ART"

for channel in blog book; do
  # 1. A failed render with NO pre-existing output: must exit non-zero, must
  #    not create $OUT, and must say so on stderr.
  OUT="$TMP/$channel-fresh.md"
  if MIF_RH_CLI="$FAKE_ENGINE" FAKE_ENGINE_MODE=fail \
       bash scripts/render-artifact.sh "$ART" "$channel" "$OUT" >/dev/null 2>"$TMP/err"; then
    note "FAIL: $channel render exited 0 despite the engine failing"; fail=1
  else
    note "$channel: a failed render exits non-zero"
  fi
  if [ -e "$OUT" ]; then
    note "FAIL: $channel failed render left a file at \$OUT ($(cat "$OUT"))"; fail=1
  else
    note "$channel: a failed render never creates \$OUT"
  fi
  if grep -q "composing the $channel output failed" "$TMP/err"; then
    note "$channel: a failed render prints a diagnostic (never silent)"
  else
    note "FAIL: $channel failed render printed no diagnostic on stderr"; fail=1
  fi

  # 2. A failed re-render must leave a PRIOR good published file untouched —
  #    and, like step 1, must still exit non-zero with a stderr diagnostic
  #    (a regression that "protects" the prior file by silently exiting 0
  #    would otherwise pass this step).
  OUT="$TMP/$channel-existing.md"
  printf 'prior good render\n' > "$OUT"
  if MIF_RH_CLI="$FAKE_ENGINE" FAKE_ENGINE_MODE=fail \
       bash scripts/render-artifact.sh "$ART" "$channel" "$OUT" >/dev/null 2>"$TMP/err"; then
    note "FAIL: $channel re-render exited 0 despite the engine failing"; fail=1
  else
    note "$channel: a failed re-render exits non-zero"
  fi
  if grep -q "composing the $channel output failed" "$TMP/err"; then
    note "$channel: a failed re-render prints a diagnostic (never silent)"
  else
    note "FAIL: $channel failed re-render printed no diagnostic on stderr"; fail=1
  fi
  if [ "$(cat "$OUT")" = "prior good render" ]; then
    note "$channel: a failed re-render leaves the prior published file byte-identical"
  else
    note "FAIL: $channel failed re-render corrupted the prior published file"; fail=1
  fi

  # 3. A successful render still lands the complete content and exits 0.
  OUT="$TMP/$channel-ok.md"
  if MIF_RH_CLI="$FAKE_ENGINE" FAKE_ENGINE_MODE=ok \
       bash scripts/render-artifact.sh "$ART" "$channel" "$OUT" >/dev/null 2>&1 \
     && [ "$(cat "$OUT")" = "complete rendered document" ]; then
    note "$channel: a successful render lands the full content at \$OUT"
  else
    note "FAIL: $channel successful render did not land the expected content"; fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "render-artifact-atomic-write: PASS"
  exit 0
fi
echo "render-artifact-atomic-write: FAIL"
exit 1
