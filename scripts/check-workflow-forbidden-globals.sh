#!/usr/bin/env bash
# check-workflow-forbidden-globals.sh — static regression gate for #618
# (research-falsify.js crashed on every finding: new Date() disallowed in
# Workflow scripts broke the entire adversarial gate).
#
# The Workflow runtime throws if a module's own body calls new Date(),
# Date.now(), or Math.random() — deterministic replay on resume requires the
# script to be a pure function of its args, never of the wall clock or a PRNG
# (research-falsify.js's real crash: "Date.now() / new Date() are unavailable
# in workflow scripts (breaks resume). Stamp results after the workflow
# returns, or pass timestamps via args."). No existing eval executed
# research-falsify.js's Gate phase for real (every driver stubs the Enumerate
# agent to return an empty workingSet, short-circuiting before the crashing
# line ever ran) — nothing caught this at authoring time. This is the
# structural fix: grep every vendored module for the three forbidden calls,
# so a FUTURE addition of one is caught by CI before it ships, not discovered
# live against a real corpus.
#
# Comment-aware: a bare textual grep would false-positive on this exact
# module header (this comment, and research-falsify.js's own #618
# explanation, both say "new Date()" in prose) and on any doc comment that
# quotes the runtime's error message. Comments and the static-text portions
# of string/template literals are stripped first via a small state-machine
# tokenizer (not a regex — a regex comment-stripper mishandles strings
# containing "//"), preserving line numbers exactly (every stripped
# character that was a newline is re-emitted) so a real hit still names the
# right line. A template literal's `${...}` expressions are left as real,
# scanned code (tracked via a frame stack with brace-depth counting, so
# nested templates — `${dec.claims.map((c) => `- ${c}`)}` — resolve
# correctly) since a forbidden call written inside one, e.g.
# `` `stamp=${Date.now()}` ``, is exactly as real a violation as a bare
# top-level call. A single space is emitted whenever the tokenizer starts
# stripping a comment/string/template or starts scanning a `${...}`
# expression, so removing delimiters never fuses adjacent tokens together
# (e.g. `new/*x*/Date(` must not collapse to `newDate(`, which would
# silently defeat the `\bnew\s+Date\s*\(` match below).
#
# Regex-literal aware (#680): a regex literal like /^a\/*b$/ contains the
# two-character sequence /* right after a backslash. Without a regex frame
# the tokenizer would read that as a block-comment opener and silently strip
# everything up to the next literal */ (or EOF) — hiding any forbidden call
# after it. A `/` in code position therefore opens a regex frame (contents
# stripped, escapes and [...] character classes honored) whenever the
# preceding significant token can't end an expression (after `=`, `(`, `,`,
# a keyword like return/typeof, or at start of input); otherwise it is
# division and passes through as plain code.
#
# Compile-only: nothing is executed. Wired into verify.sh's gate_workflows,
# alongside check-workflow-syntax.sh; the regression eval is
# evals/workflow-forbidden-globals-check.sh.
#
# Usage: check-workflow-forbidden-globals.sh [file.js ...]   # default: .claude/workflows/*.js
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v node >/dev/null 2>&1 || {
  echo "check-workflow-forbidden-globals: node is required but not on PATH" >&2
  exit 5
}

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  shopt -s nullglob
  files=("$ROOT"/.claude/workflows/*.js)
  shopt -u nullglob
  if [ "${#files[@]}" -eq 0 ]; then
    echo "check-workflow-forbidden-globals: no workflow modules found under .claude/workflows/" >&2
    exit 2
  fi
fi

rc=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "check-workflow-forbidden-globals: not a file: $f" >&2
    rc=1
    continue
  fi
  if node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const src = fs.readFileSync(file, "utf8");

    // Strip // line comments, /* */ block comments, and the static-text
    // portions of \x27/"/` strings, while re-emitting every newline verbatim
    // (including ones consumed inside a comment or a multi-line template
    // literal) so line numbers in the stripped text still match the
    // original file 1:1. Not a regex: a regex comment-stripper mishandles
    // a string containing "//" (e.g. a URL) or a template literal
    // containing "/*".
    //
    // A template literal\x27s `${...}` expressions are NOT stripped — they are
    // real, executable code (workflow modules routinely nest one, e.g.
    // `${dec.claims.map((c) => `- ${c}`)}`), so a forbidden call written
    // inside one (`stamp=${Date.now()}`) must still be caught. A small
    // stack tracks nesting: entering `${` pushes a "templateExpr" frame
    // (itself scanned as code, including further nested templates); a `{`
    // inside it deepens an object-literal brace so the matching `}` isn\x27t
    // mistaken for the expression\x27s closing brace.
    //
    // Emits a single space whenever it starts stripping a comment/string/
    // template so removing the delimiters never fuses adjacent tokens
    // together (e.g. `new/*x*/Date(` must not collapse to `newDate(`,
    // which would silently defeat the `\bnew\s+Date\s*\(` match below).
    //
    // Regex literals are recognized too (#680): without a regex frame, a
    // literal like /^a\/*b$/ is misread — the code frame has no escape
    // handling, so the `\` passes through as a plain character and the
    // following `/*` opens a phantom block comment that swallows the rest
    // of the file (hiding any forbidden call after it). Whether a `/` in
    // code position starts a regex literal or is a division operator is
    // decided by the last significant character already emitted: after
    // something that can END an expression (an identifier/number, `)`,
    // `]`, `}`, or a same-line postfix `++`/`--`) it is division; after
    // anything else (`=`, `(`, `,`, `!`,
    // a keyword like return/typeof, start of input) it opens a regex
    // frame, whose contents are stripped like a string (escapes honored,
    // `/` inside a [...] character class does not terminate it, trailing
    // flags consumed). An unterminated regex frame pops at the newline —
    // real regex literals cannot span lines, so a misclassified division
    // can never swallow more than the remainder of its own line.
    // Can a `/` at this point start a regex literal? Looks back at the last
    // significant (non-whitespace) character of the stripped output so far:
    // if it can end an expression (identifier/number character, `)`, `]`,
    // `}`) the `/` is division; otherwise (operator, opening bracket,
    // comma, start of input, or a keyword such as `return`) it starts a
    // regex. Keywords need the word check because they end in identifier
    // characters: `return /re/` is a regex, `count /2/ x` is division.
    // Postfix `++`/`--` also ends an expression, so `x++ / 2` is division —
    // but only on the same line: across a newline ASI terminates the
    // statement (`++`/`--` is a restricted production), so `x++`
    // newline `/re/` is still a regex.
    const REGEX_PRECEDING_KEYWORDS = new Set([
      "return", "typeof", "instanceof", "in", "of", "new", "delete",
      "void", "case", "do", "else", "yield", "await", "throw",
    ]);
    function regexAllowed(prev) {
      let j = prev.length - 1;
      let sawNewline = false;
      while (j >= 0 && /\s/.test(prev[j])) {
        if (prev[j] === "\n") sawNewline = true;
        j--;
      }
      if (j < 0) return true; // start of input
      const ch = prev[j];
      // Postfix increment/decrement can end an expression: a `/` right
      // after `++`/`--` on the same line is division, never a regex.
      if (!sawNewline && (ch === "+" || ch === "-") && j > 0 && prev[j - 1] === ch) return false;
      if (/[A-Za-z0-9_$]/.test(ch)) {
        let k = j;
        while (k >= 0 && /[A-Za-z0-9_$]/.test(prev[k])) k--;
        return REGEX_PRECEDING_KEYWORDS.has(prev.slice(k + 1, j + 1));
      }
      return ch !== ")" && ch !== "]" && ch !== "}";
    }

    function stripCommentsAndStrings(text) {
      let out = "";
      let i = 0;
      const n = text.length;
      const stack = [{ type: "code" }];
      while (i < n) {
        const frame = stack[stack.length - 1];
        const c = text[i];
        const c2 = i + 1 < n ? text[i + 1] : "";

        if (frame.type === "linecomment") {
          if (c === "\n") { stack.pop(); out += c; }
          i++; continue;
        }
        if (frame.type === "blockcomment") {
          if (c === "*" && c2 === "/") { stack.pop(); i += 2; continue; }
          if (c === "\n") out += c;
          i++; continue;
        }
        if (frame.type === "string") {
          if (c === "\n") out += c;
          if (c === "\\") { i += 2; continue; } // skip escaped char, never mistaken for the closing quote
          if (c === frame.quote) stack.pop();
          i++; continue;
        }
        if (frame.type === "regex") {
          // A regex literal cannot contain an unescaped newline; if one
          // shows up the literal was misidentified (or malformed) — pop
          // back to code so at most one line is ever stripped.
          if (c === "\n") { stack.pop(); out += c; i++; continue; }
          if (c === "\\") { i += 2; continue; } // skip escaped char (incl. \/ and \[)
          if (c === "[") { frame.inClass = true; i++; continue; }
          if (c === "]") { frame.inClass = false; i++; continue; }
          if (c === "/" && !frame.inClass) {
            stack.pop();
            i++;
            while (i < n && /[A-Za-z]/.test(text[i])) i++; // trailing flags
            continue;
          }
          i++; continue;
        }
        if (frame.type === "template") {
          if (c === "\n") { out += c; i++; continue; }
          if (c === "\\") { i += 2; continue; } // skip escaped char (incl. an escaped ` or $)
          if (c === "`") { stack.pop(); i++; continue; }
          if (c === "$" && c2 === "{") { stack.push({ type: "templateExpr", braceDepth: 0 }); out += " "; i += 2; continue; }
          i++; continue;
        }
        // frame.type is "code" or "templateExpr" — real, scannable code.
        if (frame.type === "templateExpr") {
          if (c === "{") { frame.braceDepth++; out += c; i++; continue; }
          if (c === "}") {
            if (frame.braceDepth > 0) { frame.braceDepth--; out += c; i++; continue; }
            stack.pop(); i++; continue; // closing brace of ${...} itself
          }
        }
        if (c === "/" && c2 === "/") { stack.push({ type: "linecomment" }); out += " "; i += 2; continue; }
        if (c === "/" && c2 === "*") { stack.push({ type: "blockcomment" }); out += " "; i += 2; continue; }
        if (c === "/" && regexAllowed(out)) { stack.push({ type: "regex", inClass: false }); out += " "; i++; continue; }
        if (c === "\x27" || c === "\"") { stack.push({ type: "string", quote: c }); out += " "; i++; continue; }
        if (c === "`") { stack.push({ type: "template" }); out += " "; i++; continue; }
        out += c;
        i++;
      }
      return out;
    }

    const stripped = stripCommentsAndStrings(src);
    const FORBIDDEN = [
      { re: /\bnew\s+Date\s*\(/g, name: "new Date(" },
      { re: /\bDate\.now\s*\(/g, name: "Date.now(" },
      { re: /\bMath\.random\s*\(/g, name: "Math.random(" },
    ];
    const hits = [];
    for (const { re, name } of FORBIDDEN) {
      let m;
      while ((m = re.exec(stripped))) {
        const line = stripped.slice(0, m.index).split("\n").length;
        hits.push(`${file}:${line}: forbidden call ${name} — Workflow-runtime scripts cannot call it (breaks resume determinism; thread a value through args instead, see #618)`);
      }
    }
    if (hits.length) {
      for (const h of hits) console.error(h);
      process.exit(1);
    }
  ' "$f"; then
    echo "  ok  $f"
  else
    rc=1
  fi
done
exit "$rc"
