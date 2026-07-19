#!/usr/bin/env bash
# workflow-research-mode-integrity.sh — structural eval for mode-resolution
# integrity across ALL THREE modes (full/augment/update) in
# .claude/workflows/research.js (research-harness#22), complementing
# workflow-research-parses.sh, workflow-research-structure.sh (which already
# covers augment-mode branch structure, #20), and
# workflow-research-update-mode.sh (which already covers update-mode's
# membership/tag-gap resolution content, #19). No live agent spawning --
# purely static checks, fast and free to run in CI:
#
#   1. Exactly ONE `const MODE = ...` declaration exists. Regression guard for
#      a real bug that shipped on main and was fixed by commit ffec3e7f: PR
#      #25 (update-mode) and PR #28 (augment-mode) each added their own
#      top-level `const MODE = ...`, and GitHub merged both cleanly (no
#      textual conflict) -- leaving BOTH in the file, a genuine `SyntaxError:
#      Identifier 'MODE' has already been declared` at real execution time,
#      invisible to `node --check` on the raw wrap because the file's leading
#      `export const meta = {...}` trips Node's ESM auto-detection and `node
#      --check` silently exits 0 anyway (workflow-research-parses.sh's own
#      fix, also part of ffec3e7f, strips that export before wrapping so the
#      check is reliable again). This check catches the duplicate-declaration
#      regression class directly, independent of that `node --check` quirk,
#      so a future merge of two mode-adding PRs can't reintroduce it silently.
#   2. SUPPORTED_MODES recognizes exactly the three implemented modes --
#      catches the same merge-defect shape from a second angle: the
#      surviving half of a bad merge could just as easily have been
#      `const MODE = A.mode === 'update' ? 'update' : 'full'`, which silently
#      collapses `mode:"augment"` back to `"full"` -- a caller in augment mode
#      would silently run full-mode research instead. SUPPORTED_MODES alone
#      doesn't catch that collapse, so check 3 below asserts the resolution
#      expression itself.
#   3. MODE resolves directly off A.mode (not a narrowed ternary that maps
#      an unrecognized/other mode string back to a default silently) --
#      `const MODE = A.mode || 'full'` (or equivalent direct assignment),
#      never a ternary keyed to a single mode literal.
#   4. resolve-membership.sh's gap/membership-resolution call site (the one
#      inside the update-mode Phase 0b block that computes gapDimensions/
#      staleIds) is reachable ONLY from the `if (MODE === 'update')` branch
#      -- distinct from the Project phase's own unconditional
#      resolve-membership.sh call (deliberate, runs every mode for corpus
#      indexing) which this check does not touch.
#   5. UPDATE_MEMBERSHIP_SCHEMA (the mode-specific return schema added for
#      update mode) exists and is one of the *_SCHEMA constants
#      workflow-research-structure.sh already proves compiles as valid JSON
#      Schema -- named-constant presence check only; compilation is that
#      script's job, not duplicated here.
#
# Exit 0 = all five hold. Exit 1 = any fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SCRIPT="$ROOT/.claude/workflows/research.js"
fail=0
note() { printf '  workflow-research-mode-integrity: %s\n' "$1"; }

if [ ! -f "$SCRIPT" ]; then
  note "$SCRIPT does not exist"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  note "'node' is required on PATH and was not found"
  exit 1
fi

# All three checks below tolerate benign whitespace/formatting variance
# (extra/missing spaces around `=`, brackets, commas) via [[:space:]]* /
# [[:space:]]+ -- they enforce the semantic constraints only (single MODE
# declaration; SUPPORTED_MODES contains exactly those three modes, in order;
# MODE derives directly from A.mode via `||` or `??`), not exact source
# formatting, so a harmless reformat of research.js can't false-positive them.

# --- 1. exactly one `const MODE = ...` declaration ---------------------------
mode_decls="$(grep -cE "^const[[:space:]]+MODE[[:space:]]*=" "$SCRIPT")"
if [ "$mode_decls" -eq 1 ]; then
  note "exactly one top-level 'const MODE = ...' declaration"
else
  note "found $mode_decls top-level 'const MODE = ...' declarations, expected exactly 1 -- a duplicate const MODE is a real SyntaxError at runtime (Identifier 'MODE' has already been declared), the exact class of bug fixed on main by commit ffec3e7f"
  fail=1
fi

# --- 2. SUPPORTED_MODES recognizes exactly full/augment/update ---------------
if grep -qE "const[[:space:]]+SUPPORTED_MODES[[:space:]]*=[[:space:]]*\[[[:space:]]*'full'[[:space:]]*,[[:space:]]*'augment'[[:space:]]*,[[:space:]]*'update'[[:space:]]*\]" "$SCRIPT"; then
  note "SUPPORTED_MODES recognizes full, augment, and update"
else
  note "SUPPORTED_MODES does not list exactly ['full', 'augment', 'update'] -- a mode is missing or misordered/extra"
  fail=1
fi

# --- 3. MODE resolves directly off A.mode, not a single-mode-keyed ternary ---
if grep -qE "^const[[:space:]]+MODE[[:space:]]*=[[:space:]]*A\.mode[[:space:]]*(\|\||\?\?)[[:space:]]*'full'" "$SCRIPT"; then
  note "MODE resolves directly off A.mode (no narrowing ternary that silently collapses an unmatched mode to a default)"
else
  note "MODE is not resolved as 'const MODE = A.mode || \'full\'' (or the equivalent '??' form) -- if it's a ternary keyed to one specific mode literal (e.g. \"A.mode === 'update' ? 'update' : 'full'\"), every OTHER real mode (e.g. augment) silently collapses to full"
  fail=1
fi

# --- 4. resolve-membership.sh's gap-resolution call is update-mode-only ------
# Ephemeral stderr capture goes to mktemp outside the tree, never a raw
# /tmp/$$ path (CLAUDE.md; matches workflow-research-update-mode.sh) -- honors
# $TMPDIR, uses a random name, and a trap reaps it even on interrupt.
node_err_log="$(mktemp "${TMPDIR:-/tmp}/workflow-research-mode-integrity.XXXXXX.log")"
trap 'rm -f "$node_err_log"' EXIT
node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  // Tolerate arbitrary whitespace before 'for' (not a hardcoded 2-space
  // indent) so a harmless reformat of research.js can't false-negative this.
  const updateBranch = src.match(/if\s*\(\s*MODE\s*===\s*'update'\s*\)\s*\{([\s\S]*?)\n\s*for\s*\(\s*let\s+round\s*=\s*1/);
  if (!updateBranch) { console.error('could not locate the if (MODE === \'update\') { ... } block preceding the round for-loop'); process.exit(1); }
  // Match actual bash invocations only (the literal 'bash scripts/…' call
  // text), not descriptive prose mentions of the script name in comments or
  // prompt narration -- those are expected to appear near, but not only
  // inside, the guarded block and would otherwise false-positive this check.
  const INVOKE_RE = /bash scripts\/resolve-membership\.sh/g;
  if (!INVOKE_RE.test(updateBranch[1])) {
    console.error('resolve-membership.sh is not actually invoked (bash scripts/resolve-membership.sh) inside the update-mode gap-resolution block');
    process.exit(1);
  }
  // Every actual invocation OUTSIDE this block must be a separately-justified,
  // unconditional call (e.g. Project phase corpus indexing) -- not a second
  // update-mode-scoped one that duplicates or bypasses the guard above. There
  // must be exactly one such site.
  const withoutUpdateBlock = src.replace(updateBranch[0], '');
  const outsideCount = (withoutUpdateBlock.match(/bash scripts\/resolve-membership\.sh/g) || []).length;
  if (outsideCount !== 1) {
    console.error('expected exactly 1 actual resolve-membership.sh invocation outside the update-mode block (the Project phase\'s unconditional corpus-indexing call), found ' + outsideCount);
    process.exit(1);
  }
" "$SCRIPT" 2>"$node_err_log"
rc=$?
if [ "$rc" -eq 0 ]; then
  note "resolve-membership.sh's gap-resolution call site is reachable only from the update-mode branch (the Project phase's separate unconditional call is untouched)"
else
  sed 's/^/    /' "$node_err_log"
  fail=1
fi
rm -f "$node_err_log"
trap - EXIT

# --- 5. UPDATE_MEMBERSHIP_SCHEMA exists as a named schema constant -----------
if grep -q "const UPDATE_MEMBERSHIP_SCHEMA = {" "$SCRIPT"; then
  note "UPDATE_MEMBERSHIP_SCHEMA constant present (compilation proven by workflow-research-structure.sh)"
else
  note "no UPDATE_MEMBERSHIP_SCHEMA constant found -- update mode's Phase 0b return has no dedicated schema"
  fail=1
fi

exit "$fail"
