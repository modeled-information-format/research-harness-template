#!/usr/bin/env python3
"""Validate Mermaid code blocks in Markdown files (stdlib-only, no runtime deps).

This is a STRUCTURAL validator, not a full Mermaid grammar parser. It catches the
failure modes that actually occur in this harness's rendered output:

  1. Empty ```mermaid block.
  2. Unknown / missing diagram-type header (first content token).
  3. Markdown-escape corruption — a backslash-escaped `\\*`, `\\_`, `\\<`, `\\>`
     inside the diagram. These are never valid Mermaid; they are the signature of
     a renderer that escaped prose characters inside the fence (the deglob bug
     fixed in render-artifact.sh). This is the regression this gate guards.
  4. Unbalanced (), [], {} once quoted strings are removed.

For full Mermaid grammar validation use @mermaid-js/mermaid-cli (`mmdc`); it is a
heavy npm + headless-Chromium dependency and is deliberately NOT adopted here —
the harness runtime stays pure stdlib/shell. Usage:

    check-mermaid.py FILE [FILE ...]      # validate every ```mermaid block

Exit 0 iff every block in every file is valid; otherwise prints one line per
problem and exits 1.
"""
from __future__ import annotations

import re
import sys

# Known Mermaid diagram-type headers (the first token of a diagram).
DIAGRAM_TYPES = {
    "flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram",
    "stateDiagram-v2", "erDiagram", "journey", "gantt", "pie", "quadrantChart",
    "requirementDiagram", "gitGraph", "mindmap", "timeline", "zenuml",
    "sankey-beta", "xychart-beta", "block-beta", "packet-beta", "kanban",
    "architecture-beta", "C4Context", "C4Container", "C4Component", "C4Dynamic",
    "C4Deployment",
}

FENCE = re.compile(r"^```mermaid[ \t]*$(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)
QUOTED = re.compile(r'"[^"]*"' + r"|'[^']*'")
CORRUPTION = re.compile(r"\\[*_<>]")


def first_token(block: str) -> str | None:
    for line in block.splitlines():
        s = line.strip()
        if not s or s.startswith("%%"):  # skip blanks and %% comments
            continue
        # the diagram type is the first whitespace/`:`-delimited token
        return re.split(r"[\s:]", s, maxsplit=1)[0]
    return None


def validate_block(block: str) -> list[str]:
    errs: list[str] = []
    if not block.strip():
        return ["empty mermaid block"]
    tok = first_token(block)
    if tok not in DIAGRAM_TYPES:
        errs.append(f"unknown/missing diagram type: {tok!r}")
    m = CORRUPTION.search(block)
    if m:
        errs.append(
            f"markdown-escape corruption {m.group(0)!r} inside the diagram "
            "(renderer escaped a fenced block)"
        )
    stripped = QUOTED.sub("", block)
    for op, cl in (("(", ")"), ("[", "]"), ("{", "}")):
        if stripped.count(op) != stripped.count(cl):
            errs.append(
                f"unbalanced '{op}{cl}': {stripped.count(op)} '{op}' vs "
                f"{stripped.count(cl)} '{cl}'"
            )
    return errs


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: check-mermaid.py FILE [FILE ...]", file=sys.stderr)
        return 2
    total = 0
    bad = 0
    for path in argv:
        try:
            text = open(path, encoding="utf-8").read()
        except OSError as e:
            print(f"{path}: cannot read ({e})", file=sys.stderr)
            bad += 1
            continue
        for i, m in enumerate(FENCE.finditer(text), 1):
            total += 1
            errs = validate_block(m.group(1))
            for err in errs:
                bad += 1
                print(f"{path}: mermaid block #{i}: {err}")
    print(f"check-mermaid: {total} block(s) checked, {bad} problem(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
