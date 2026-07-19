#!/usr/bin/env bash
# command-research-mode-flags.sh — structural eval for mode resolution wired
# into .claude/commands/research.md (research-harness#21), complementing
# workflow-research-parses.sh / workflow-research-structure.sh /
# workflow-research-update-mode.sh (which cover .claude/workflows/research.js
# itself). No live agent spawning -- purely static checks, fast and free to
# run in CI:
#
#   1. research.md's argument-hint documents --augment [<dimension>] and
#      --update, matching start.md's flag shape.
#   2. research.md's Arguments section resolves MODE from those flags the
#      same way start.md does (MODE=augment / MODE=update / MODE=full),
#      including the mutual-exclusivity + "requires an existing goal" framing.
#   3. research.md's Phase 0 branches on mode: augment/update must NOT author
#      a goal (only full mode does).
#   4. research.md's Phase 2 Workflow() args block actually passes mode (and
#      dimension) through to the workflow -- the two pieces of design work
#      (research.js supporting the modes, research.md exposing them) must be
#      wired together, not just independently present.
#   5. The stale "Only full mode is supported here" caveat this issue's
#      acceptance criteria calls out is gone.
#   6. No regression: research.md still documents full-mode inline goal
#      authoring (goal-writer's methodology) unconditionally.
#   7. Cross-check against research.js itself: the modes research.md documents
#      (augment, update) are modes research.js's SUPPORTED_MODES constant
#      actually implements -- catches the docs and the implementation
#      silently drifting apart in either direction.
#
# Exit 0 = all seven hold. Exit 1 = any fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

CMD="$ROOT/.claude/commands/research.md"
WF="$ROOT/.claude/workflows/research.js"
fail=0
note() { printf '  command-research-mode-flags: %s\n' "$1"; }

if [ ! -f "$CMD" ]; then
  note "$CMD does not exist"
  exit 1
fi
if [ ! -f "$WF" ]; then
  note "$WF does not exist"
  exit 1
fi

# --- 1. argument-hint documents --augment [<dimension>] and --update -------
if grep -qE '^argument-hint:.*--augment \[<dimension>\]' "$CMD" && grep -qE '^argument-hint:.*--update' "$CMD"; then
  note "argument-hint documents --augment [<dimension>] and --update"
else
  note "argument-hint does not document both --augment [<dimension>] and --update"
  fail=1
fi

# --- 2. MODE resolution mirrors start.md ------------------------------------
if grep -qE 'MODE=augment' "$CMD" && grep -qE 'MODE=update' "$CMD" && grep -qiE 'mutually exclusive' "$CMD"; then
  note "MODE resolution (augment/update/full, mutually exclusive) is documented"
else
  note "MODE resolution paragraph missing or incomplete (expected MODE=augment, MODE=update, and a mutual-exclusivity statement)"
  fail=1
fi

# --- 3. Phase 0 requires an existing goal in augment/update, never authors one
if grep -qiE 'Augment/update mode.*goal must already exist|goal must already exist' "$CMD" \
  && grep -qiE 'do NOT author or reshape a goal' "$CMD"; then
  note "Phase 0 requires an existing goal in augment/update mode and never authors one"
else
  note "Phase 0 does not clearly require an existing goal (and forbid authoring one) in augment/update mode"
  fail=1
fi

# --- 4. Phase 2 Workflow() args actually pass mode/dimension through -------
# NOTE: grep -E's `\s` is NOT a whitespace class -- it's a literal `s`. Use
# `[[:space:]]*` (POSIX bracket class), which grep -E does support, to match
# the space after the colon in `mode: "{MODE}"` / `dimension: "{DIMENSION...}`.
if grep -qE 'mode:[[:space:]]*"\{MODE\}"' "$CMD" && grep -qE 'dimension:[[:space:]]*"\{DIMENSION' "$CMD"; then
  note "Phase 2's Workflow(args:{...}) passes mode and dimension through"
else
  note "Phase 2's Workflow(args:{...}) does not pass mode/dimension through to research.js -- the flags would be parsed but never actually reach the workflow"
  fail=1
fi

# --- 5. the stale full-mode-only caveat is gone -----------------------------
if grep -qiE 'Only full mode is supported here' "$CMD"; then
  note "stale 'Only full mode is supported here' caveat is still present -- must be corrected or removed per this issue's acceptance criteria"
  fail=1
else
  note "'Only full mode is supported here' caveat has been corrected/removed"
fi

# --- 6. no regression: full-mode inline goal authoring is still documented -
if grep -qiE "author a new one following .goal-writer\.md.'s Elicitation" "$CMD"; then
  note "full-mode inline goal authoring (goal-writer methodology) is still documented -- no regression"
else
  note "full-mode inline goal authoring section appears to be missing -- regression risk"
  fail=1
fi

# --- 7. cross-check against research.js's actual SUPPORTED_MODES -----------
# Parsed structurally (string literals pulled out with a regex), not eval()'d
# -- this is CI running arbitrary text from a repo file, and a simple parse
# is both safer and less fragile than executing it as JS.
SUPPORTED="$(node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  const m = src.match(/const SUPPORTED_MODES = \[([^\]]*)\]/);
  if (!m) { console.error('could not locate SUPPORTED_MODES in research.js'); process.exit(1); }
  const items = [...m[1].matchAll(/'([^']*)'|\"([^\"]*)\"/g)].map(mm => mm[1] !== undefined ? mm[1] : mm[2]);
  if (!items.length) { console.error('SUPPORTED_MODES array contained no string literals'); process.exit(1); }
  console.log(items.join(','));
" "$WF" 2>&1)"
if [ $? -ne 0 ]; then
  note "could not extract research.js's SUPPORTED_MODES: $SUPPORTED"
  fail=1
else
  missing=""
  for mode in augment update; do
    case ",$SUPPORTED," in
      *",$mode,"*) : ;;
      *) missing="$missing $mode" ;;
    esac
  done
  if [ -n "$missing" ]; then
    note "research.md documents mode(s)$missing but research.js's SUPPORTED_MODES=[$SUPPORTED] does not implement them -- docs/implementation drift"
    fail=1
  else
    note "research.js's SUPPORTED_MODES=[$SUPPORTED] covers every mode research.md documents"
  fi
fi

exit "$fail"
