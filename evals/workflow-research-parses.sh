#!/usr/bin/env bash
# workflow-research-parses.sh — structural eval for .claude/workflows/research.js
# (ADR-0020). Workflow-tool scripts are plain JS bodies the runtime wraps in an
# implicit async function -- `node --check` on the raw file always fails on the
# top-level `await`/`return` statements every real workflow script uses, so
# this eval wraps the body the same way before checking, then cross-checks
# that meta.phases[] names exactly the same set of titles used by every
# phase() call in the body (the tool's own documented invariant: mismatched
# titles silently split progress into an extra, unlabeled group).
#
# No live agent spawning -- purely static/structural, fast and free to run in CI.
#
# Exit 0 = script parses and meta/phase() titles agree. Exit 1 = either fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

SCRIPT="$ROOT/.claude/workflows/research.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
note() { printf '  workflow-research-parses: %s\n' "$1"; }

if [ ! -f "$SCRIPT" ]; then
  note "$SCRIPT does not exist"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  note "'node' is required on PATH and was not found"
  exit 1
fi

# Wrap the body in an async function shell to match how the Workflow runtime
# actually executes it (top-level await/return are otherwise a syntax error).
# The `export const meta = {...}` block must be stripped first -- `export` is
# illegal inside a function body, and wrapping it in anyway does NOT produce a
# clean syntax error the way you'd expect: confirmed empirically (2026-07-17)
# that node --check on a script wrapped THIS way (export left in) reports a
# false "no error" on a file that genuinely fails to parse (a duplicate `const`
# declaration slipped through two independently-merged PRs, research-harness#25
# and #28, completely undetected by this eval in its unstripped form). Node
# --check on the unstripped-but-wrapped file exits 0 silently; only stripping
# the meta block first and wrapping the remainder surfaces the real error.
node -e "
  const fs = require('fs');
  const src = fs.readFileSync(process.argv[1], 'utf8');
  const m = src.match(/export const meta = \{[\s\S]*?\n\}\n\n/);
  if (!m) { console.error('could not locate the export const meta = {...} block to strip'); process.exit(1); }
  const rest = src.slice(m[0].length);
  const wrapped = 'async function __wf(args, phase, log, agent, pipeline, parallel, workflow, budget) {\n' + rest + '\n}\n';
  fs.writeFileSync(process.argv[2], wrapped);
" "$SCRIPT" "$TMP/wrapped.js"
if [ ! -s "$TMP/wrapped.js" ]; then
  note "could not strip the meta block from $SCRIPT to build the wrapped check file"
  exit 1
fi

if ! node --check "$TMP/wrapped.js" >"$TMP/check.log" 2>&1; then
  note "syntax error (wrapped as an async function body):"
  sed 's/^/    /' "$TMP/check.log"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  node -e "
    const fs = require('fs');
    const src = fs.readFileSync(process.argv[1], 'utf8');
    const metaMatch = src.match(/export const meta = (\{[\s\S]*?\n\})\n\n/);
    if (!metaMatch) { console.error('could not locate export const meta = {...} block'); process.exit(1); }
    let meta;
    try { meta = eval('(' + metaMatch[1] + ')'); }
    catch (e) { console.error('meta block did not eval as a literal: ' + e.message); process.exit(1); }
    const metaTitles = new Set((meta.phases || []).map(p => p.title));
    const calls = [...src.matchAll(/phase\('([^']+)'\)/g)].map(m => m[1]);
    const callTitles = new Set(calls);
    const missing = [...callTitles].filter(t => !metaTitles.has(t));
    const unused = [...metaTitles].filter(t => !callTitles.has(t));
    if (missing.length || unused.length) {
      if (missing.length) console.error('phase() call title(s) not in meta.phases: ' + missing.join(', '));
      if (unused.length) console.error('meta.phases title(s) never called via phase(): ' + unused.join(', '));
      process.exit(1);
    }
  " "$SCRIPT" 2>"$TMP/titles.log"
  if [ $? -ne 0 ]; then
    note "meta.phases / phase() call title mismatch:"
    sed 's/^/    /' "$TMP/titles.log"
    fail=1
  fi
fi

[ "$fail" -eq 0 ] && note "research.js parses and meta.phases matches every phase() call"
exit "$fail"
