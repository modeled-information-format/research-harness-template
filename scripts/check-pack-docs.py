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

A pack whose ``harness.config.json`` ``packs[]`` entry declares an external
``source`` (``{"type": "git"|"marketplace", "url": ...}`` — see ADR/discussion
#228's genre-consolidation migration) has no ``packs/<family>/<name>/``
directory. It is still required to carry a ``## <name>`` doc section (whichever
family page already documents it establishes its family), but is exempt from the
outbound in-repo source link (its section must instead link to the declared
external ``url``) and from the inbound ``README.md`` back-link (there is no local
directory to carry one).

Run from the repository root. Prints a report and exits non-zero on any gap.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PACKS = REPO / "packs"
PACK_DOCS = REPO / "docs" / "reference" / "packs"
INDEX = PACK_DOCS / "index.md"
FAMILIES = ["channels", "genres", "market-research", "ontologies", "reports", "trend-modeling"]
DOC_URL_SUBSTR = "modeled-information-format.github.io/research-harness-template/reference/packs"


def declared_ontologies() -> list[str]:
    """Ontology packs are vendored on demand (ADR-0012/#224): they are NOT committed
    under packs/ontologies/, so their authoritative component set is the declared list
    in harness.config.json ``ontologies[]`` (union any locally-vendored copies)."""
    ids: set[str] = set()
    cfg = REPO / "harness.config.json"
    if cfg.is_file():
        data = json.loads(cfg.read_text(encoding="utf-8"))
        ids = {o["id"] for o in data.get("ontologies", []) if isinstance(o, dict) and "id" in o}
    local = PACKS / "ontologies"
    if local.is_dir():
        ids |= {p.name for p in local.iterdir() if p.is_dir()}
    return sorted(ids)


def external_packs() -> tuple[dict[str, str], list[str]]:
    """Packs consumed from an external source (ADR/#228): {name: source url}.

    A ``harness.config.json`` ``packs[]`` entry with an object ``source``
    (``{"type": "git"|"marketplace", "url": ...}``, or ``{"type":
    "marketplace-ref", "marketplace": <name>}`` resolved against the top-level
    ``marketplaces[]``) has no committed ``packs/<family>/<name>/`` directory —
    its family membership is resolved by whichever family page already
    documents it (see ``main``).

    Also returns a list of error strings for ``marketplace-ref`` entries whose
    ``marketplace`` name has no matching ``marketplaces[]`` declaration, so a
    typo surfaces as its own diagnostic instead of a misleading downstream
    "cannot resolve its family" error."""
    ids: dict[str, str] = {}
    errors: list[str] = []
    cfg = REPO / "harness.config.json"
    if cfg.is_file():
        data = json.loads(cfg.read_text(encoding="utf-8"))
        marketplaces = {m["name"]: m for m in data.get("marketplaces", []) if isinstance(m, dict) and "name" in m}
        for p in data.get("packs", []):
            src = p.get("source")
            if not isinstance(src, dict):
                continue
            if src.get("type") == "marketplace-ref":
                mkt_name = src.get("marketplace")
                mkt = marketplaces.get(mkt_name)
                if mkt is not None and isinstance(mkt.get("url"), str):
                    ids[p["name"]] = mkt["url"]
                else:
                    errors.append(
                        f"pack '{p.get('name')}' references marketplace '{mkt_name}' "
                        f"which is not declared in harness.config.json marketplaces[]"
                    )
            elif isinstance(src.get("url"), str):
                ids[p["name"]] = src["url"]
    return ids, errors


def components() -> dict[str, list[str]]:
    """Map each family to its sorted list of component names.

    Committed families enumerate their on-disk component directories. The
    ``ontologies`` family is vendored on demand (#224), so it enumerates the declared
    registry set instead of an (empty) on-disk directory. A missing committed family
    directory yields an empty list rather than raising, so the caller can report it as
    a normal validation error and still print the rest.
    """
    out: dict[str, list[str]] = {}
    for fam in FAMILIES:
        if fam == "ontologies":
            out[fam] = declared_ontologies()
            continue
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
    layers = shared_ontology_layers()
    ext, errors = external_packs()

    # External packs (ADR/#228) have no packs/<family>/<name>/ directory. Resolve
    # each one's family from whichever family page already documents it (a family
    # page must exist and carry the `## <name>` section — checked below like any
    # other component), then fold it into that family's component list.
    ext_unresolved = set(ext)
    # Which family EACH external name actually resolved into — not just "is this
    # name a key in ext", since a pack name can collide with an unrelated
    # component of the same name in another family (e.g. a report genre and an
    # ontology id both called "trend-analysis"). Only the family it resolved
    # into treats it as external; every other family's same-named component
    # (if any) is left alone.
    ext_by_fam: dict[str, set[str]] = {}
    for fam in FAMILIES:
        if fam == "ontologies":
            continue
        page = PACK_DOCS / f"{fam}.md"
        if not page.is_file():
            continue
        heads = set(headings(page))
        for name in list(ext_unresolved):
            if name in heads and name not in comps[fam]:
                comps[fam] = sorted([*comps[fam], name])
                ext_by_fam.setdefault(fam, set()).add(name)
                ext_unresolved.discard(name)
    for name in sorted(ext_unresolved):
        errors.append(
            f"external pack '{name}' (harness.config.json packs[]) has no '## {name}' "
            f"section in any family page — cannot resolve its family"
        )

    total = sum(len(v) for v in comps.values())

    print("=== Pack documentation coverage ===")
    print(f"Components tracked: {total} ({len(ext) - len(ext_unresolved)} external)")
    for fam, names in comps.items():
        print(f"  {fam}: {len(names)}")

    # A missing family directory is a real error UNLESS every one of that
    # family's components is external (ontologies is vendored on demand,
    # #224; a genre family can end up fully externalized the same way once
    # every one of its packs moves to a marketplace-ref source, #228) — then
    # there is nothing to commit under packs/<family>/ and absence is expected.
    for fam in FAMILIES:
        if fam == "ontologies":
            continue
        if not (PACKS / fam).is_dir():
            names = comps.get(fam, [])
            fam_ext = ext_by_fam.get(fam, set())
            if names and all(n in fam_ext for n in names):
                continue
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

        # Outbound link per component section: an external pack must link its
        # declared source url instead of an (absent) in-repo packs/ path. Only
        # names this family actually resolved as external take the ext[] url —
        # a same-named component in another family is never external here.
        fam_ext = ext_by_fam.get(fam, set())
        for n in names:
            target = ext[n] if n in fam_ext else f"packs/{fam}/{n}"
            if target not in text:
                errors.append(f"[{fam}] section '{n}' missing source link to {target}")
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

    # Inbound: each component dir has a README.md linking to the doc site. The
    # ontologies family is vendored on demand (#224) — its packs are not committed, so
    # there is no in-repo README to back-link; the registry copy carries provenance.
    # External packs (ADR/#228) are likewise not committed here — same exemption.
    inbound_total = 0
    inbound_expected = total - len(comps.get("ontologies", [])) - (len(ext) - len(ext_unresolved))
    for fam, names in comps.items():
        if fam == "ontologies":
            continue
        for n in names:
            if n in ext_by_fam.get(fam, set()):
                continue
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
    print(f"Inbound pack -> doc back-links:          {inbound_total}/{inbound_expected} (ontologies vendored on demand; external packs exempt)")

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
