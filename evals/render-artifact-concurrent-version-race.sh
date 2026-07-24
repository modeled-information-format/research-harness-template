#!/usr/bin/env bash
# render-artifact-concurrent-version-race.sh — regression test for issue #776:
# two concurrent render-artifact.sh invocations targeting the SAME $OUT used to
# both read the same prior `version:` before either had written its own
# output, both compute the same next VERSION, and both render+mv into $OUT --
# silently producing a duplicate version stamp instead of a true monotonic
# counter, with NO error raised (the exact "primary on-disk record that this
# is revision N" guarantee the script's own header comment promises callers,
# broken without a trace).
#
# Drives N invocations of render-artifact.sh at the same, not-yet-existing
# $OUT (the single most reliable way to force every racer to see
# `[ -f "$OUT" ]` false and all independently compute VERSION=1 -- the
# worst-case collision) with a FAKE engine (the documented MIF_RH_CLI override
# in scripts/lib/engine.sh) that sleeps briefly before writing, guaranteeing
# every invocation is still mid-render before any one of them can land its
# `mv` -- widening the exact race window #776 describes. Each invocation logs
# the version IT computed to its own private file (never $OUT itself, which
# gets overwritten by whichever racer's mv lands last) so every racer's
# individually-computed version is independently observable after the fact.
#
# Asserts:
#   - no two SUCCESSFUL invocations ever logged the identical version number
#     (the defect itself: a duplicate version stamp);
#   - at least one invocation succeeds (the fix must not make concurrent
#     rendering of a topic wholly impossible, just serialized);
#   - every invocation that did NOT succeed exited non-zero with a clear
#     stderr diagnostic naming the render lock -- never a silent, misleading
#     success the way the pre-fix race was (issue #776's central complaint:
#     "without any error being raised").
#
# Exit 0 = the concurrency contract holds. Exit 1 = a case failed.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  render-artifact-concurrent-version-race: %s\n' "$1"; }

# Fake engine: answers --version (engine.sh's engine_bin probes it), then for
# the real render call sleeps briefly (simulating real render work) before
# writing content to its own private BTMP path (the script's own temp-then-
# move discipline means the engine never touches $OUT directly) and, if
# RENDER_TEST_LOG is set, records the --version flag value it was given --
# this is how each concurrent invocation's own computed VERSION becomes
# observable after $OUT has since been overwritten by later racers.
FAKE_ENGINE="$TMP/fake-mif-rh-cli"
cat > "$FAKE_ENGINE" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  echo "mif-rh-cli 99.0.0"
  exit 0
fi
out="" version="" prev=""
for a in "$@"; do
  [ "$prev" = "--version" ] && version="$a"
  prev="$a"
  out="$a"
done
sleep "${RENDER_TEST_SLEEP:-0.3}"
printf 'rendered content, version=%s\n' "$version" > "$out"
[ -n "${RENDER_TEST_LOG:-}" ] && printf '%s\n' "$version" > "$RENDER_TEST_LOG"
exit 0
FAKE
chmod +x "$FAKE_ENGINE"

ART="$TMP/artifact.json"
printf '{}' > "$ART"
OUT="$TMP/concurrent.md"
N=6

pids=()
for i in $(seq 1 "$N"); do
  (
    if MIF_RH_CLI="$FAKE_ENGINE" RENDER_TEST_LOG="$TMP/version.$i" \
         bash scripts/render-artifact.sh "$ART" blog "$OUT" \
         >"$TMP/out.$i" 2>"$TMP/err.$i"; then
      echo 0 > "$TMP/rc.$i"
    else
      echo 1 > "$TMP/rc.$i"
    fi
  ) &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p"; done

successes=0
declare -a versions=()
for i in $(seq 1 "$N"); do
  rc="$(cat "$TMP/rc.$i" 2>/dev/null || echo '?')"
  if [ "$rc" = "0" ]; then
    successes=$((successes + 1))
    if [ -f "$TMP/version.$i" ]; then
      versions+=("$(cat "$TMP/version.$i")")
    else
      note "FAIL: run $i exited 0 but logged no version at all"; fail=1
    fi
  elif [ "$rc" = "1" ]; then
    if grep -q "could not acquire the render lock" "$TMP/err.$i"; then
      note "run $i: denied loudly, with a clear render-lock diagnostic (never silent)"
    else
      note "FAIL: run $i exited non-zero but printed no render-lock diagnostic on stderr: $(cat "$TMP/err.$i")"; fail=1
    fi
  else
    note "FAIL: run $i produced no readable exit status"; fail=1
  fi
done

if [ "$successes" -ge 1 ]; then
  note "at least one concurrent invocation succeeded ($successes/$N)"
else
  note "FAIL: zero of $N concurrent invocations succeeded -- the lock must serialize, not starve every racer"; fail=1
fi

# The defect itself: two successful renders both stamping the SAME version.
dup="$(printf '%s\n' "${versions[@]:-}" | sort | uniq -d)"
if [ -z "$dup" ]; then
  note "no two successful invocations logged a duplicate version stamp"
else
  note "FAIL: duplicate version stamp(s) across concurrent successful renders: $dup"; fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "render-artifact-concurrent-version-race: PASS"
  exit 0
fi
echo "render-artifact-concurrent-version-race: FAIL"
exit 1
