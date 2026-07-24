#!/usr/bin/env bash
# mif-project-json-out-cp-check.sh — regression eval for
# research-harness-template#752: scripts/mif-project.sh's
# `[ -n "$JSON_OUT" ] && cp "$TMP" "$JSON_OUT"` was unchecked. If the cp fails
# (e.g. the target directory doesn't exist, the filesystem is full, or
# permissions deny the write), `cp` prints its own error to stderr but the
# script has no `set -e` and no explicit check on this line, so execution
# falls through unconditionally to the "projects to a valid MIF L3 finding"
# success message and exits 0 — masking the real write failure and, if
# out.json already existed from a prior run, leaving a downstream consumer
# (e.g. render-artifact.sh's report channel) silently reading stale JSON
# while believing this run succeeded.
#
# Proof: run the REAL scripts/mif-project.sh (copied byte-for-byte, never
# re-typed, so a future edit that regresses the check is caught structurally)
# inside a synthetic ROOT with:
#   - a stub mif-rh-cli (via MIF_RH_CLI) that answers --version and, for
#     `harness project-report`, writes a minimal placeholder to whatever
#     --json-out path it's given;
#   - a stub scripts/check-citation-integrity.sh that always passes (this
#     eval targets only the FINAL cp-to-caller's-JSON_OUT step, not the
#     earlier projection/validation pipeline).
# Nothing in the real repo tree is touched.
#
# Two cases:
#   A. --json-out points into a directory that does not exist -> the final
#      cp must fail -> the script must exit non-zero with a named
#      diagnostic and must NOT print the false success message.
#   B. --json-out points at a real, writable path (happy path) -> exit 0 and
#      the JSON is actually written (no regression).
#
# Hermetic: bash + coreutils only, no network, no real engine call.
#
# Exit 0 = all cases hold. Exit 1 = a case failed. Exit 2 = a required
# fixture/tool is missing.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
note() { printf '  mif-project-json-out-cp-check: %s\n' "$1"; }

REAL_SCRIPT="$REPO_ROOT/scripts/mif-project.sh"
REAL_ENGINE_LIB="$REPO_ROOT/scripts/lib/engine.sh"
[ -f "$REAL_SCRIPT" ] || { note "$REAL_SCRIPT not found"; exit 2; }
[ -f "$REAL_ENGINE_LIB" ] || { note "$REAL_ENGINE_LIB not found"; exit 2; }

TMP="$(mktemp -d)" || { note "mktemp failed setting up the eval's own scratch dir"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# Synthetic ROOT: scripts/mif-project.sh resolves ROOT as
# "$(cd "$(dirname "$0")/.." && pwd)", so copying the real script (verbatim)
# into <synthetic-root>/scripts/ makes it resolve ROOT to <synthetic-root> —
# no real repo file is touched.
SYN_ROOT="$TMP/syn-root"
mkdir -p "$SYN_ROOT/scripts/lib"
cp "$REAL_SCRIPT" "$SYN_ROOT/scripts/mif-project.sh"
cp "$REAL_ENGINE_LIB" "$SYN_ROOT/scripts/lib/engine.sh"
chmod +x "$SYN_ROOT/scripts/mif-project.sh"

# Stub check-citation-integrity.sh — always passes, so the run reaches the
# final cp step under test.
cat > "$SYN_ROOT/scripts/check-citation-integrity.sh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SYN_ROOT/scripts/check-citation-integrity.sh"

# Stub mif-rh-cli — answers --version, and for `harness project-report`
# writes a placeholder projection to whatever --json-out path it's given.
cat > "$TMP/mif-rh-cli" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "0.7.0"; exit 0; fi
if [ "${1:-}" = "harness" ] && [ "${2:-}" = "project-report" ]; then
  out=""
  prev=""
  for a in "$@"; do
    if [ "$prev" = "--json-out" ]; then out="$a"; fi
    prev="$a"
  done
  [ -n "$out" ] || { echo "stub mif-rh-cli: no --json-out given" >&2; exit 9; }
  echo '{"id":"urn:mif:test:json-out-cp-check","type":"Finding"}' > "$out"
  exit 0
fi
echo "stub mif-rh-cli: unexpected invocation: $*" >&2
exit 9
STUB
chmod +x "$TMP/mif-rh-cli"

# A minimal report fixture.
REPORT="$TMP/report.md"
cat > "$REPORT" <<'MD'
---
id: urn:mif:test:json-out-cp-check
type: Finding
---
placeholder
MD

# --- A: cp target's containing directory does not exist -> cp must fail ---
BAD_JSON_OUT="$TMP/does-not-exist/out.json"
set +e
out_a="$(MIF_RH_CLI="$TMP/mif-rh-cli" bash "$SYN_ROOT/scripts/mif-project.sh" "$REPORT" --json-out "$BAD_JSON_OUT" 2>&1)"
rc_a=$?
set -e 2>/dev/null || true

if [ "$rc_a" -eq 0 ]; then
  note "FAIL: mif-project.sh exited 0 despite a failing cp to --json-out — the unchecked-cp defect (#752) is present"
  fail=1
else
  note "ok: mif-project.sh exits non-zero ($rc_a) when cp to --json-out fails"
fi

if printf '%s' "$out_a" | grep -qi 'failed to write JSON projection'; then
  note "ok: stderr names the real cause (JSON projection write failure)"
else
  note "FAIL: stderr does not name the JSON projection write failure — got: $out_a"
  fail=1
fi

if printf '%s' "$out_a" | grep -q 'projects to a valid MIF L3 finding'; then
  note "FAIL: script still printed the success message despite the cp failure — the exact defect #752 reports"
  fail=1
else
  note "ok: the false success message is not printed when cp fails"
fi

# --- B: happy path — a real, writable --json-out target ------------------
GOOD_JSON_OUT="$TMP/out.json"
set +e
out_b="$(MIF_RH_CLI="$TMP/mif-rh-cli" bash "$SYN_ROOT/scripts/mif-project.sh" "$REPORT" --json-out "$GOOD_JSON_OUT" 2>&1)"
rc_b=$?
set -e 2>/dev/null || true

if [ "$rc_b" -eq 0 ] && [ -f "$GOOD_JSON_OUT" ]; then
  note "ok: happy path still exits 0 and writes the JSON projection"
else
  note "FAIL: happy path regressed (rc=$rc_b, exists=$([ -f "$GOOD_JSON_OUT" ] && echo yes || echo no)): $out_b"
  fail=1
fi

[ "$fail" -eq 0 ] && note "mif-project.sh checks the final cp to --json-out's exit status and fails closed with a named diagnostic instead of silently reporting success"
exit "$fail"
