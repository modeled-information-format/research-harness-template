#!/usr/bin/env bash
# workflow-docs-check.sh — regression eval for the engine-workflows
# reference documentation (research-harness-template#553, Epic #539).
#
# docs/reference/engine-workflows.md is the reference entry for the
# Workflow-runtime modules under .claude/workflows/. This eval keeps the
# page and the module set bidirectionally honest, and keeps the
# /goal-writer positioning + supersession note from silently regressing:
#
#   1. every .claude/workflows/*.js module has a "## <name>" section in
#      docs/reference/engine-workflows.md;
#   2. every module-shaped H2 heading (lowercase kebab, no spaces) in the
#      page names a real module — no phantom entries;
#   3. the page and docs/reference/commands.md cross-link each other
#      (engine-workflows.md -> commands.md, /goal-writer entry ->
#      engine-workflows.md);
#   4. the supersession note is present on both surfaces: each states that
#      deterministic chaining supersedes prompt-discipline gating, and each
#      keeps /goal-writer as the interactive path;
#   5. .claude/commands/goal-writer.md carries the engine-counterpart note
#      pointing at the reference page.
#
# Exit 0 = every case holds. Exit 1 = a case failed.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

fail=0
note() { printf '  workflow-docs-check: %s\n' "$1"; }

DOC=docs/reference/engine-workflows.md
CMDS=docs/reference/commands.md
CMD=.claude/commands/goal-writer.md

if [ ! -f "$DOC" ]; then
  note "missing $DOC"
  exit 1
fi

# Case 1: every workflow module is documented.
for wf in .claude/workflows/*.js; do
  name="$(basename "$wf" .js)"
  if ! grep -qE "^## ${name}\$" "$DOC"; then
    note "module $wf has no '## ${name}' section in $DOC"
    fail=1
  fi
done

# Case 2: every module-shaped H2 heading names a real module.
while IFS= read -r name; do
  if [ ! -f ".claude/workflows/${name}.js" ]; then
    note "$DOC documents '## ${name}' but .claude/workflows/${name}.js does not exist"
    fail=1
  fi
done < <(grep -oE '^## [a-z0-9][a-z0-9-]*$' "$DOC" | cut -d' ' -f2)

# Case 3: bidirectional cross-links between the reference pages.
grep -q 'commands.md' "$DOC" || { note "$DOC does not link to commands.md"; fail=1; }
grep -q 'engine-workflows.md' "$CMDS" || { note "$CMDS does not link to engine-workflows.md"; fail=1; }

# Case 4: the supersession note holds on both surfaces.
for f in "$DOC" "$CMDS"; do
  grep -qi 'supersede' "$f" || { note "$f lost the supersession note"; fail=1; }
  grep -qi 'interactive' "$f" || { note "$f lost the interactive-path positioning"; fail=1; }
done

# Case 5: the command manual points at the engine reference entry.
grep -q 'engine-workflows.md' "$CMD" || { note "$CMD lost its engine-counterpart note"; fail=1; }

exit "$fail"
