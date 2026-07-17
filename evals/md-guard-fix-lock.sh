#!/usr/bin/env bash
# md-guard-fix-lock.sh — contract test for .claude/hooks/markdown/md_guard.py's
# serialized, corruption-guarded `--fix` (issue #510): parallel Edit batches
# fire concurrent PostToolUse hook chains against the SAME file, and the
# unserialized read-modify-write `markdownlint-cli2 --fix` raced itself,
# corrupting a file's YAML frontmatter while every hook reported success.
#
# This invokes the REAL hook (like evals/guard-falsify-gate.sh) with synthetic
# PostToolUse JSON on stdin and a stub `markdownlint-cli2` on PATH, and asserts:
#   1. a fix pass that destroys the leading "---" frontmatter is detected:
#      pre-fix content RESTORED, corrupted output kept under state/, exit 2;
#   2. a clean fix pass is unaffected: exit 0, no lock left behind;
#   3. a FRESH lock held by another process makes the hook SKIP the fix
#      (bounded wait, never a race) and stay non-blocking (exit 0);
#   4. a STALE lock (crashed holder) is stolen and the fix still runs;
#   5. two hooks fired in parallel on one file run their fix passes strictly
#      serially (no overlapping stub intervals).
#
# Exit 0 = the contract holds. Exit 1 = a case failed.

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/markdown/md_guard.py"
fail=0
note() { printf '  md-guard-fix-lock: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
STUB_BIN="$TMP/bin"
mkdir -p "$STATE" "$STUB_BIN"
export MD_GUARD_STATE_DIR="$STATE"
export PATH="$STUB_BIN:$PATH"

FRONTMATTER=$'---\ntitle: test doc\n---\n\n# Heading\n\nBody text.\n'

# run_hook <file_path> — feeds PostToolUse JSON to the real hook; returns its rc.
run_hook() {
  jq -cn --arg fp "$1" '{tool_input:{file_path:$fp}, session_id:"eval-510"}' \
    | python3 "$HOOK" post
}

lock_dir_for() {
  python3 -c 'import hashlib,sys; print("fix-lock-"+hashlib.sha256(sys.argv[1].encode()).hexdigest()[:16])' "$1"
}

# --- Case 1: corrupting fix -> restore + exit 2 ----------------------------
# Stub strips the file's first line, exactly the "frontmatter no longer starts
# the file" corruption class, then exits 0 as if everything were fine.
cat > "$STUB_BIN/markdownlint-cli2" <<'EOS'
#!/usr/bin/env bash
for last; do :; done
tail -n +2 "$last" > "$last.stub" && mv "$last.stub" "$last"
exit 0
EOS
chmod +x "$STUB_BIN/markdownlint-cli2"

DOC1="$TMP/case1.md"
printf '%s' "$FRONTMATTER" > "$DOC1"
ERR1="$TMP/case1.err"
run_hook "$DOC1" 2> "$ERR1"
RC1=$?
if [ "$RC1" -ne 2 ]; then
  note "FAIL: corrupting fix exited $RC1, want 2 (loud non-zero)"; fail=1
elif [ "$(cat "$DOC1")" != "$(printf '%s' "$FRONTMATTER")" ]; then
  note "FAIL: pre-fix content was not restored after corruption"; fail=1
elif ! grep -q "CORRUPTED" "$ERR1"; then
  note "FAIL: corruption exit carried no loud stderr message"; fail=1
elif ! ls "$STATE"/corrupt-*.md >/dev/null 2>&1; then
  note "FAIL: corrupted output was not kept under state/ for forensics"; fail=1
else
  note "corrupting fix: content restored, corrupted copy kept, exit 2, loud stderr"
fi
rm -f "$STATE"/corrupt-*.md

# --- Case 2: clean fix -> exit 0, lock released ----------------------------
cat > "$STUB_BIN/markdownlint-cli2" <<'EOS'
#!/usr/bin/env bash
exit 0
EOS
chmod +x "$STUB_BIN/markdownlint-cli2"

DOC2="$TMP/case2.md"
printf '%s' "$FRONTMATTER" > "$DOC2"
run_hook "$DOC2" >/dev/null 2>&1
RC2=$?
LOCK2="$STATE/$(lock_dir_for "$DOC2")"
if [ "$RC2" -ne 0 ]; then
  note "FAIL: clean fix exited $RC2, want 0"; fail=1
elif [ "$(cat "$DOC2")" != "$(printf '%s' "$FRONTMATTER")" ]; then
  note "FAIL: clean fix altered the file"; fail=1
elif [ -d "$LOCK2" ]; then
  note "FAIL: lock directory left behind after a clean fix"; fail=1
else
  note "clean fix: exit 0, file intact, lock released"
fi

# --- Case 3: fresh lock held -> fix SKIPPED within bounded wait -------------
cat > "$STUB_BIN/markdownlint-cli2" <<EOS
#!/usr/bin/env bash
touch "$TMP/case3.invoked"
exit 0
EOS
chmod +x "$STUB_BIN/markdownlint-cli2"

DOC3="$TMP/case3.md"
printf '%s' "$FRONTMATTER" > "$DOC3"
LOCK3="$STATE/$(lock_dir_for "$DOC3")"
mkdir -p "$LOCK3"   # a live holder
OUT3="$(MD_GUARD_LOCK_WAIT_SEC=1 run_hook "$DOC3" 2>/dev/null)"
RC3=$?
if [ "$RC3" -ne 0 ]; then
  note "FAIL: lock-held path exited $RC3, want 0 (non-blocking skip)"; fail=1
elif [ -e "$TMP/case3.invoked" ]; then
  note "FAIL: --fix ran despite a fresh lock held by another process"; fail=1
elif ! printf '%s' "$OUT3" | jq -e '.hookSpecificOutput.additionalContext | test("skipped")' >/dev/null 2>&1; then
  note "FAIL: skip carried no additionalContext warning"; fail=1
else
  note "fresh lock held: fix skipped within bounded wait, warning emitted"
fi
rm -rf "$LOCK3"

# --- Case 4: stale lock -> stolen, fix runs, lock released ------------------
cat > "$STUB_BIN/markdownlint-cli2" <<EOS
#!/usr/bin/env bash
touch "$TMP/case4.invoked"
exit 0
EOS
chmod +x "$STUB_BIN/markdownlint-cli2"

DOC4="$TMP/case4.md"
printf '%s' "$FRONTMATTER" > "$DOC4"
LOCK4="$STATE/$(lock_dir_for "$DOC4")"
mkdir -p "$LOCK4"
sleep 2   # age the lock past the 1s staleness window below
MD_GUARD_LOCK_STALE_SEC=1 run_hook "$DOC4" >/dev/null 2>&1
RC4=$?
if [ "$RC4" -ne 0 ]; then
  note "FAIL: stale-lock path exited $RC4, want 0"; fail=1
elif [ ! -e "$TMP/case4.invoked" ]; then
  note "FAIL: stale lock was not stolen -- --fix never ran"; fail=1
elif [ -d "$LOCK4" ]; then
  note "FAIL: stolen lock left behind after the fix"; fail=1
else
  note "stale lock: stolen through atomic re-acquire, fix ran, lock released"
fi

# --- Case 5: two parallel hooks on ONE file run strictly serially -----------
LOG5="$TMP/case5.log"
cat > "$STUB_BIN/markdownlint-cli2" <<EOS
#!/usr/bin/env bash
python3 -c 'import time; print("S %.6f" % time.time())' >> "$LOG5"
sleep 1
python3 -c 'import time; print("E %.6f" % time.time())' >> "$LOG5"
exit 0
EOS
chmod +x "$STUB_BIN/markdownlint-cli2"

DOC5="$TMP/case5.md"
printf '%s' "$FRONTMATTER" > "$DOC5"
run_hook "$DOC5" >/dev/null 2>&1 & P1=$!
run_hook "$DOC5" >/dev/null 2>&1 & P2=$!
wait "$P1"; RC5A=$?
wait "$P2"; RC5B=$?
if [ "$RC5A" -ne 0 ] || [ "$RC5B" -ne 0 ]; then
  note "FAIL: parallel hooks exited $RC5A/$RC5B, want 0/0"; fail=1
elif ! python3 - "$LOG5" <<'EOF'
import sys

events = []
with open(sys.argv[1]) as fh:
    for line in fh:
        kind, ts = line.split()
        events.append((float(ts), kind))
events.sort()
kinds = [k for _, k in events]
# Two serialized runs produce S E S E; any overlap produces adjacent S S.
sys.exit(0 if len(kinds) == 4 and kinds == ["S", "E", "S", "E"] else 1)
EOF
then
  note "FAIL: parallel hooks overlapped ($(tr '\n' ' ' < "$LOG5"))"; fail=1
else
  note "parallel hooks on one file ran their fix passes strictly serially"
fi

if [ "$fail" -eq 0 ]; then
  echo "md-guard-fix-lock: PASS"
  exit 0
fi
echo "md-guard-fix-lock: FAIL"
exit 1
