#!/usr/bin/env python3
"""Verify docs/reference/coverage.md's counts against the real repository state.

research-harness-template#481: the "Coverage summary" table's Discovered
counts, the per-category section headings, and the "## Assertion" line all
drifted independently from real repo state (new packs/commands/scripts added
without anyone re-running this page's own reproduce commands), with nothing
catching it. This script recomputes the same five counts coverage.md's own
"Reproduce the discovered counts" code block documents, then cross-checks:

1. The "## Coverage summary" table's Discovered column matches the real count
   for every category.
2. Each category's Documented column equals its Discovered column (the page's
   own stated invariant: discovered == documented).
3. The Total row equals the sum of the five category rows.
4. Each category's own "## <Category> (N)" heading count matches its row in
   the summary table.
5. The "## Assertion" line's two numbers match the real Total.

Run from the repository root. Prints a report and exits non-zero on any gap.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOC = REPO / "docs" / "reference" / "coverage.md"

# category label -> (summary-table row label, "## <label> (" heading prefix)
CATEGORIES = ["Packs", "Core skills", "Commands", "Agents", "Scripts"]


def real_counts() -> dict[str, int]:
    cfg = json.loads((REPO / "harness.config.json").read_text(encoding="utf-8"))
    packs = len(cfg.get("packs", [])) + len(cfg.get("ontologies", []))
    core_skills = len([p for p in (REPO / ".claude" / "skills").iterdir() if p.is_dir()])
    commands = len(list((REPO / ".claude" / "commands").glob("*.md")))
    agents = len(list((REPO / ".claude" / "agents").glob("*.md")))
    scripts = len(
        [
            p
            for p in (REPO / "scripts").rglob("*")
            if p.is_file()
            and p.suffix in (".sh", ".py", ".jq")
            and "__pycache__" not in p.parts
        ]
    )
    return {
        "Packs": packs,
        "Core skills": core_skills,
        "Commands": commands,
        "Agents": agents,
        "Scripts": scripts,
    }


def main() -> int:
    errors: list[str] = []
    if not DOC.is_file():
        print(f"::error::missing {DOC.relative_to(REPO)}")
        return 1
    text = DOC.read_text(encoding="utf-8")
    real = real_counts()

    summary_match = re.search(
        r"## Coverage summary\n\n(.*?)\n\n", text, re.DOTALL
    )
    if not summary_match:
        errors.append("no '## Coverage summary' table found")
        summary_rows: dict[str, tuple[int, int]] = {}
    else:
        summary_rows = {}
        for line in summary_match.group(1).splitlines():
            m = re.match(
                r"\|\s*\**([A-Za-z ]+?)\**\s*\|\s*\**(\d+)\**\s*\|\s*\**(\d+)\**\s*\|",
                line,
            )
            if m:
                summary_rows[m.group(1).strip()] = (int(m.group(2)), int(m.group(3)))

    real_total = 0
    for cat in CATEGORIES:
        real_total += real[cat]
        if cat not in summary_rows:
            errors.append(f"[summary] no row found for '{cat}'")
            continue
        discovered, documented = summary_rows[cat]
        if discovered != real[cat]:
            errors.append(
                f"[summary] {cat}: Discovered={discovered} != real {real[cat]}"
            )
        if documented != discovered:
            errors.append(
                f"[summary] {cat}: Documented={documented} != Discovered={discovered} "
                "(coverage.md's own stated invariant is discovered == documented)"
            )
        heading = re.search(rf"^## {re.escape(cat)} \((\d+)", text, re.MULTILINE)
        if not heading:
            errors.append(f"[heading] no '## {cat} (N)' heading found")
        elif int(heading.group(1)) != real[cat]:
            errors.append(
                f"[heading] '## {cat}' states {heading.group(1)} != real {real[cat]}"
            )

    if "Total" in summary_rows:
        total_discovered, total_documented = summary_rows["Total"]
        if total_discovered != real_total:
            errors.append(
                f"[summary] Total Discovered={total_discovered} != real sum {real_total}"
            )
        if total_documented != total_discovered:
            errors.append(
                f"[summary] Total Documented={total_documented} != Total Discovered={total_discovered}"
            )
    else:
        errors.append("[summary] no 'Total' row found")

    assertion = re.search(
        r"Discovered \((\d+)\) equals documented \((\d+)\)", text
    )
    if not assertion:
        errors.append("no '## Assertion' line found")
    else:
        for label, val in (("Discovered", assertion.group(1)), ("documented", assertion.group(2))):
            if int(val) != real_total:
                errors.append(f"[assertion] {label} states {val} != real total {real_total}")

    print("=== coverage.md counts ===")
    for cat in CATEGORIES:
        print(f"  {cat}: {real[cat]}")
    print(f"  Total: {real_total}")

    print("\n=== Result ===")
    if errors:
        print(f"FAIL ({len(errors)} problem(s)):")
        for e in errors:
            print("  -", e)
        return 1
    print("PASS: coverage.md's summary table, per-category headings, and assertion all match real repo state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
