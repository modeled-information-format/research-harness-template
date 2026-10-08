#!/usr/bin/env python3
"""migrate-mif-ids.py -- migrate legacy MIF ids to the MIF 1.4 concept-URN form.

MIF 1.4 requires a concept ``@id`` to match ``^urn:mif:<uuid>$``. Corpora written
before it carry structured ids (``urn:mif:concept:<ns>:<slug>``,
``urn:mif:source:...``, ``urn:mif:report:...``, ``urn:mif:blog:...``, ...) and
documents carry bare-slug frontmatter ``id``s. This rewrites every such id with
the org-wide rule in ``scripts/lib/mif_id.py`` (uuid5 in the MIF namespace of the
remainder after ``urn:mif:``), so the result agrees with ids the mif-rs engine
mints and with every other migrated corpus.

The rewrite is a pure function of the old id, applied to every occurrence in a
file (an ``@id``, a ``relationships[].target``, a graph node/edge, an index
row), so referential integrity is preserved across files without any lookup
table. Reserved non-concept URNs (``urn:mif:entity:``, ``agent:``,
``activity:``, ``conversation:``, ``vector:``), ids that are already UUID URNs,
and placeholder/templated ids (``urn:mif:concept:<ns>:<slug>``,
``urn:mif:concept:$NS:...``) are left alone, so the tool is idempotent.

With ``--aliases``, a migrated top-level concept (a JSON object or a markdown
frontmatter block carrying an ``@id``) also records its old id in ``aliases``,
so it stays findable by the id older references and notes used.

Usage::

    migrate-mif-ids.py [--write] [--aliases] <file>...       # rewrite urn:mif ids
    migrate-mif-ids.py [--write] --doc-ids <file.md>...      # frontmatter `id: <slug>` -> uuid

Without ``--write`` it is a dry run: it prints what would change and exits 1
when anything would (0 when every file is already migrated).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
from mif_id import RESERVED_KINDS, UUID_RE, concept_urn, slug_uuid  # noqa: E402

# A urn:mif: run, wide enough to also swallow template punctuation so a
# placeholder (urn:mif:concept:<ns>:<slug>, urn:mif:concept:$NS:x) is seen whole
# and skipped rather than half-rewritten.
TOKEN = re.compile(r"urn:mif:([A-Za-z0-9_./:<>${}*-]+)")
TEMPLATED = set("<>${}*")
KIND = re.compile(r"^[a-z][a-z0-9-]*$")


# What may legitimately follow a complete id: a quote, whitespace, JSON/YAML/
# prose punctuation, or end of text. Anything else (`%d`, `[x]`, `+`) means the
# match is the head of a longer, constructed string -- left alone.
TERMINATORS = set("\"'`,;)]}>|\\ \t\r\n")


def migrate_token(rest: str, following: str = "") -> tuple[str, str] | None:
    """Return (old_id, new_id) for a legacy structured id, else None.

    ``following`` is the character right after the matched run. A run that
    ends in an id separator (``:``, ``/``, ``-``) is a prefix being
    concatenated with something else (``'urn:mif:concept:' + ns``), not an
    id, and is left alone; only a sentence-ending ``.`` may trail an id.
    """
    stripped = rest.rstrip(".")
    if not stripped or stripped[-1] in ":/-" or TEMPLATED & set(stripped):
        return None
    if following and following not in TERMINATORS:
        return None
    kind, sep, tail = stripped.partition(":")
    if not sep or not tail or tail[0] == "/" or not KIND.match(kind) or kind in RESERVED_KINDS:
        return None
    if UUID_RE.match(stripped):
        return None
    old = "urn:mif:" + stripped
    return old, concept_urn(stripped)


def rewrite_ids(text: str) -> tuple[str, dict[str, str]]:
    changes: dict[str, str] = {}

    def sub(m: re.Match) -> str:
        rest = m.group(1)
        hit = migrate_token(rest, text[m.end(): m.end() + 1])
        if not hit:
            return m.group(0)
        old, new = hit
        changes[old] = new
        return new + rest[len(old) - len("urn:mif:"):]

    return TOKEN.sub(sub, text), changes


def json_alias(text: str, old: str, new: str) -> str:
    """Add "aliases": [old] to the top-level object, keeping the file's style.

    A file in canonical 2-space JSON is edited structurally (sorted keys stay
    sorted, as `jq -S` writes findings); anything else gets a textual insert
    right after the top-level "@id".
    """
    doc = json.loads(text)
    for indent in (2, None):
        if json.dumps(doc, indent=indent, ensure_ascii=False) + "\n" == text:
            keys = list(doc)
            doc["aliases"] = [old]
            if keys == sorted(keys):
                doc = dict(sorted(doc.items()))
            else:
                at = keys.index("@id") + 1
                order = keys[:at] + ["aliases"] + keys[at:]
                doc = {k: doc[k] for k in order}
            return json.dumps(doc, indent=indent, ensure_ascii=False) + "\n"
    m = re.search(r'("@id"\s*:\s*)"' + re.escape(new) + r'"(\s*,)?([ \t]*\n([ \t]*))?', text)
    if not m:
        return text
    if m.group(3) is not None:  # multi-line object: own line, same indent
        indent = m.group(4)
        insert = f'"@id": "{new}",\n{indent}"aliases": [{json.dumps(old)}]'
        if m.group(2):
            insert += ",\n" + indent
        else:
            insert += "\n" + indent
        return text[: m.start()] + insert + text[m.end():]
    sep = ", " if m.group(2) else ""
    return text[: m.start()] + f'"@id": "{new}", "aliases": [{json.dumps(old)}]{sep}' + text[m.end():]


def json_top_concept_id(text: str) -> str | None:
    try:
        doc = json.loads(text)
    except ValueError:
        return None
    if isinstance(doc, dict) and isinstance(doc.get("@id"), str) and "aliases" not in doc:
        return doc["@id"]
    return None


FM_ID = re.compile(r"^(['\"]?@id['\"]?:[ \t]*)(['\"]?)(urn:mif:[^'\"\s]+)\2[ \t]*$", re.M)


def md_alias(text: str, old: str) -> str:
    """Add `aliases: [old]` to a markdown file's frontmatter, after its @id."""
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---", 4)
    if end < 0:
        return text
    fm = text[4:end]
    if re.search(r"^aliases:", fm, re.M):
        return text
    m = FM_ID.search(fm)
    if not m:
        return text
    line_end = fm.find("\n", m.end())
    line_end = len(fm) if line_end < 0 else line_end
    fm = fm[:line_end] + f"\naliases:\n  - {old}" + fm[line_end:]
    return "---\n" + fm + text[end:]


DOC_ID = re.compile(r"^id:[ \t]*(['\"]?)([^'\"\s]+)\1[ \t]*$", re.M)


def migrate_doc_id(text: str) -> tuple[str, dict[str, str]]:
    if not text.startswith("---\n"):
        return text, {}
    end = text.find("\n---", 4)
    if end < 0:
        return text, {}
    fm = text[4:end]
    m = DOC_ID.search(fm)
    if not m or UUID_RE.match(m.group(2)):
        return text, {}
    old = m.group(2)
    new = slug_uuid(old)
    fm = fm[: m.start()] + f"id: {new}" + fm[m.end():]
    return "---\n" + fm + text[end:], {old: new}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("--write", action="store_true", help="rewrite files in place")
    ap.add_argument("--aliases", action="store_true", help="record each migrated top-level @id in aliases")
    ap.add_argument("--doc-ids", action="store_true", help="migrate markdown frontmatter `id: <slug>` instead")
    ap.add_argument("files", nargs="+")
    args = ap.parse_args(argv)

    pending = 0
    for path in args.files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        if args.doc_ids:
            new_text, changes = migrate_doc_id(text)
        else:
            top_old = json_top_concept_id(text) if path.endswith(".json") else None
            fm = FM_ID.search(text[: text.find("\n---", 4)]) if path.endswith(".md") and text.startswith("---\n") else None
            new_text, changes = rewrite_ids(text)
            if args.aliases:
                if top_old in changes:
                    new_text = json_alias(new_text, top_old, changes[top_old])
                elif fm and fm.group(3) in changes:
                    new_text = md_alias(new_text, fm.group(3))
        if new_text != text:
            pending += 1
            print(f"{path}: {len(changes)} id(s)")
            if args.write:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new_text)
    if not args.write and pending:
        print(f"migrate-mif-ids: {pending} file(s) carry legacy MIF ids (re-run with --write)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
