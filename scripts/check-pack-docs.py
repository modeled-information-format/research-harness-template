#!/usr/bin/env python3
"""Verify the pack documentation is complete and bidirectionally cross-linked.

Checks, all of which must pass (exit 0):

1. Coverage (both directions): every pack component under
   ``packs/<family>/<component>/`` has a ``## <component>`` section in its family
   reference page, and every component-shaped heading in a family page (and in the
   inventory table of ``index.md``) names a real component or a real shared
   ontology layer under ``schemas/ontologies/`` — no phantom entries.
2. Outbound cross-links: each component section links to its in-repo source
   (``packs/<family>/<component>``). Count must equal the component count.
3. Inbound cross-links: each component dir carries a ``README.md`` linking back to
   its published doc anchor. Count must equal the component count.

Run from the repository root. Prints a report and exits non-zero on any gap.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PACKS = REPO / "packs"
PACK_DOCS = REPO / "docs" / "reference" / "packs"
INDEX = PACK_DOCS / "index.md"
FAMILIES = ["channels", "genres", "market-research", "ontologies", "reports", "trend-modeling"]
DOC_URL_SUBSTR = "modeled-information-format.github.io/research-harness-template/reference/packs"


def components() -> dict[str, list[str]]:
    """Map each family to its sorted list of component directory names.

    A missing family directory yields an empty list rather than raising, so the
    caller can report it as a normal validation error and still print the rest.
    """
    out: dict[str, list[str]] = {}
    for fam in FAMILIES:
        fam_dir = PACKS / fam
        out[fam] = (
            sorted(p.name for p in fam_dir.iterdir() if p.is_dir())
            if fam_dir.is_dir()
            else []
        )
    return out


def headings(md: Path) -> list[str]:
    """Return the text of every ``## `` heading in a markdown file."""
    return [
        m.group(1).strip()
        for m in re.finditer(r"^##\s+(.+?)\s*$", md.read_text(encoding="utf-8"), re.MULTILINE)
    ]


def is_component_shaped(heading: str) -> bool:
    """A component heading is a bare slug: lowercase, digits, hyphens only."""
    return re.fullmatch(r"[a-z0-9][a-z0-9-]*", heading) is not None


def shared_ontology_layers() -> set[str]:
    sch = REPO / "schemas" / "ontologies"
    if not sch.is_dir():
        return set()
    return {p.name for p in sch.iterdir() if p.is_dir()}


def main() -> int:
    comps = components()
    total = sum(len(v) for v in comps.values())
    layers = shared_ontology_layers()
    errors: list[str] = []

    print("=== Pack documentation coverage ===")
    print(f"Components on disk: {total}")
    for fam, names in comps.items():
        print(f"  {fam}: {len(names)}")

    # A missing family directory is a real error, not a crash.
    for fam in FAMILIES:
        if not (PACKS / fam).is_dir():
            errors.append(f"missing pack family directory: packs/{fam}")

    documented_total = 0
    outbound_total = 0
    for fam, names in comps.items():
        page = PACK_DOCS / f"{fam}.md"
        if not page.is_file():
            errors.append(f"missing family page: {page.relative_to(REPO)}")
            continue
        text = page.read_text(encoding="utf-8")
        heads = set(headings(page))

        # Forward: every component has a section.
        missing = [n for n in names if n not in heads]
        if missing:
            errors.append(f"[{fam}] components with no doc section: {missing}")

        # Reverse: every component-shaped heading is a real component or shared layer.
        phantom = [
            h
            for h in heads
            if is_component_shaped(h) and h not in names and h not in layers
        ]
        if phantom:
            errors.append(f"[{fam}] doc sections with no matching component: {phantom}")

        documented = [n for n in names if n in heads]
        documented_total += len(documented)

        # Outbound link per component section.
        for n in names:
            if f"packs/{fam}/{n}" not in text:
                errors.append(f"[{fam}] section '{n}' missing source link to packs/{fam}/{n}")
            else:
                outbound_total += 1

    # index.md inventory table must not name a non-existent component.
    all_names = {n for names in comps.values() for n in names}
    if not INDEX.is_file():
        errors.append(f"missing inventory page: {INDEX.relative_to(REPO)}")
    else:
        idx_phantom = [
            h
            for h in headings(INDEX)
            if is_component_shaped(h) and h not in all_names and h not in layers
        ]
        # The inventory lives in a table, not headings; scan table rows too.
        for line in INDEX.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\|\s*([a-z0-9][a-z0-9-]*)\s*\|", line)
            if m and m.group(1) not in all_names and m.group(1) not in layers:
                idx_phantom.append(m.group(1))
        if idx_phantom:
            errors.append(
                f"[index.md] inventory names non-existent components: {sorted(set(idx_phantom))}"
            )

    # Inbound: each component dir has a README.md linking to the doc site.
    inbound_total = 0
    for fam, names in comps.items():
        for n in names:
            readme = PACKS / fam / n / "README.md"
            if not readme.is_file():
                errors.append(f"[{fam}] component '{n}' has no README.md back-link")
            else:
                body = readme.read_text(encoding="utf-8")
                if DOC_URL_SUBSTR not in body:
                    errors.append(f"[{fam}] component '{n}' README.md missing doc back-link")
                elif "**Dependencies:**" not in body:
                    errors.append(f"[{fam}] component '{n}' README.md missing explicit Dependencies")
                else:
                    inbound_total += 1

    print("\n=== Cross-link tallies ===")
    print(f"Documented components (section present): {documented_total}/{total}")
    print(f"Outbound doc -> pack source links:       {outbound_total}/{total}")
    print(f"Inbound pack -> doc back-links:          {inbound_total}/{total}")

    print("\n=== Result ===")
    if errors:
        print(f"FAIL ({len(errors)} problem(s)):")
        for e in errors:
            print("  -", e)
        return 1
    print(f"PASS: all {total} components documented, with {outbound_total} outbound")
    print(f"      and {inbound_total} inbound cross-links. No phantom entries.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
