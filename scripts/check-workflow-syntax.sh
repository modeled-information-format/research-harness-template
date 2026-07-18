#!/usr/bin/env bash
# check-workflow-syntax.sh — parse-check Workflow-runtime modules (#552).
#
# Modules under .claude/workflows/ use the Workflow runtime's async-function-
# body shape: the runtime strips the `export const meta` statement and
# evaluates the remaining source as the BODY of an async function, so
# top-level `await` and `return` are legal in the file. A bare `node --check`
# therefore rejects a perfectly valid workflow module. This checker reproduces
# the runtime's framing instead: strip the `export` keyword, compile the
# source as an async function body (the AsyncFunction constructor), and fail
# loudly — naming the file and the error — on any genuine syntax error.
#
# Compile-only: nothing is executed. Wired into verify.sh's gate_workflows so
# the required `verify` CI context covers it; the regression eval is
# evals/workflow-parse-check.sh.
#
# Usage: check-workflow-syntax.sh [file.js ...]   # default: .claude/workflows/*.js
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "check-workflow-syntax: node is required but not on PATH" >&2
  exit 5
}

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  shopt -s nullglob
  files=("$ROOT"/.claude/workflows/*.js)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    echo "check-workflow-syntax: no workflow modules found under .claude/workflows/" >&2
    exit 2
  fi
fi

rc=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "check-workflow-syntax: not a file: $f" >&2
    rc=1
    continue
  fi
  if node -e '
    const fs = require("fs");
    const file = process.argv[1];
    let src = fs.readFileSync(file, "utf8");
    // Mirror the runtime framing: drop the export keyword, then compile the
    // source as an async function body (top-level return/await stay legal).
    src = src.replace(/^export[ \t]+/gm, "");
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    try {
      new AsyncFunction("args", "phase", "agent", "log", "workflow", src);
    } catch (e) {
      console.error(`${file}: ${e.constructor.name}: ${e.message}`);
      process.exit(1);
    }
  ' "$f"; then
    echo "  ok  $f"
  else
    rc=1
  fi
done
exit "$rc"
