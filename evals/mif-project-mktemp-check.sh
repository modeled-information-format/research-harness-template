#!/usr/bin/env bash
# mif-project-mktemp-check.sh — regression eval for
# research-harness-template#775: scripts/mif-project.sh's
# `TMPD="$(mktemp -d)"` was unchecked. If mktemp -d fails (e.g. /tmp full or
# unwritable), TMPD is empty and `TMP="$TMPD/projection.json"` silently
# becomes the absolute root path `/projection.json` — which then fails on
# permission grounds under a non-root user, surfacing as a generic "not
# compliant" / citation-integrity failure that masks the real root cause (no
# usable temp directory).
#
# Proof: drive the real script with a stubbed `mktemp` on PATH that always
# fails, and a stubbed `mif-rh-cli` (via MIF_RH_CLI) that only needs to
# answer `--version` (mktemp fires right after engine_bin() resolves, before
# the engine is ever actually invoked). Confirm:
#   A. mif-project.sh exits non-zero (not a false "compliant").
#   B. it prints a named "mktemp failed" diagnostic on stderr, not a
#      downstream citation-integrity failure.
#   C. it never attempts to write to /projection.json (the fallback root
#      path this issue reports) — proven by asserting the path does not
#      exist after the run (root-owned repos could let the write silently
#      succeed and mask the bug).
#
# Hermetic: bash + coreutils only, no network, no real engine call.
#
# Exit 0 = all cases hold. Exit 1 = a case failed. Exit 2 = a required
# fixture/tool is missing.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  mif-project-mktemp-check: %s\n' "$1"; }

SCRIPT="scripts/mif-project.sh"
[ -f "$SCRIPT" ] || { note "$SCRIPT not found"; exit 2; }

TMP="$(mktemp -d)" || { note "mktemp failed setting up the eval's own scratch dir"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# A stub mif-rh-cli that only needs to answer --version — mif-project.sh's
# mktemp call happens immediately after engine_bin() resolves the binary,
# before the engine is ever actually invoked, so nothing beyond --version
# needs to work for this eval.
cat > "$TMP/mif-rh-cli" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "0.7.0"; exit 0; fi
echo "stub mif-rh-cli: unexpected invocation: $*" >&2
exit 9
STUB
chmod +x "$TMP/mif-rh-cli"

# A fake PATH dir whose `mktemp` always fails, shadowing the real one. Only
# `mktemp` is faked; everything else the script needs still resolves via the
# real PATH appended after it.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/mktemp" <<'STUB'
#!/usr/bin/env bash
echo "stub mktemp: simulated failure (e.g. /tmp full or unwritable)" >&2
exit 1
STUB
chmod +x "$TMP/fakebin/mktemp"

# A minimal report fixture — never reached if the fix works (the script must
# fail at the mktemp step, before ever invoking the engine on this file).
REPORT="$TMP/report.md"
cat > "$REPORT" <<'MD'
---
id: urn:mif:test:mktemp-check
type: Finding
---
placeholder
MD

set +e
PATH="$TMP/fakebin:$PATH" MIF_RH_CLI="$TMP/mif-rh-cli" bash "$SCRIPT" "$REPORT" >"$TMP/stdout.log" 2>"$TMP/stderr.log"
rc=$?
set -e 2>/dev/null || true

if [ "$rc" -eq 0 ]; then
  note "FAIL: mif-project.sh exited 0 despite a failing mktemp -d — the unchecked-mktemp defect (#775) is present"
  fail=1
else
  note "ok: mif-project.sh exits non-zero ($rc) when mktemp -d fails"
fi

if grep -qi 'mktemp failed' "$TMP/stderr.log"; then
  note "ok: stderr names the real cause (mktemp failure), not a downstream citation-integrity misdiagnosis"
else
  note "FAIL: stderr does not name a mktemp failure — got: $(cat "$TMP/stderr.log")"
  fail=1
fi

if grep -qi 'citation-integrity' "$TMP/stderr.log"; then
  note "FAIL: stderr still reaches the citation-integrity gate — mktemp failure is not short-circuiting early as it must"
  fail=1
fi

if [ -e /projection.json ]; then
  note "FAIL: /projection.json exists on disk — the root-path fallback this issue reports actually wrote there"
  fail=1
else
  note "ok: no /projection.json was created at the filesystem root"
fi

[ "$fail" -eq 0 ] && note "mif-project.sh checks mktemp -d's exit status and fails closed with a named diagnostic instead of silently falling back to the root path /projection.json"
exit "$fail"
