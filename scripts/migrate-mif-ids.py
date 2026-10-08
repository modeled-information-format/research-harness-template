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
``activity:``, ``conversation:``, ``vector:``) and ids that are already UUID
URNs are left alone. A placeholder or runtime-constructed id
(``urn:mif:concept:<ns>:<slug>``, ``'urn:mif:concept:' + ns``,
``urn:mif:concept:harness/$TOPIC:x``) cannot be rewritten by a text pass: each
one is named on stderr as NOT migrated, so nothing is skipped silently.

With ``--aliases``, a migrated top-level concept (a JSON object or a markdown
frontmatter block carrying an ``@id``) also records its old id in ``aliases``
(appended, in order, to any existing aliases), so it stays findable by the id
older references and notes used. Ids inside an ``aliases`` list are never
rewritten, which also makes a second run a no-op.

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

# A urn:mif: run: the id characters only. What follows the run decides
# whether it is a whole id (see NON_TERMINATORS); a run that ends in an id
# separator is a prefix or a placeholder (`urn:mif:concept:<ns>:<slug>`,
# `'urn:mif:concept:' + ns`, `urn:mif:concept:harness/$TOPIC:x`) and is left
# alone.
TOKEN = re.compile(r"urn:mif:([A-Za-z0-9_./:-]+)")
KIND = re.compile(r"^[a-z][a-z0-9-]*$")
# A character right after an id that means the match is only the head of a
# longer, constructed string (`f%d`, `chars[test]`, `x + y`, `${...}`). Any
# other character -- a quote, whitespace, punctuation, `<` of a closing HTML
# tag, `>` of an autolink, `#`/`?`, an em dash -- ends a complete id.
NON_TERMINATORS = set("%[+$({*@=~^")


def classify(rest: str, following: str = "") -> tuple[str, str] | str | None:
    """Classify the run after `urn:mif:`.

    Returns (old_id, new_id) for a legacy structured id to migrate, the string
    "skipped" for something that looks like a legacy id but is templated or
    constructed (reported, never rewritten), or None for anything else
    (reserved URNs, UUID URNs, non-ids).
    """
    stripped = rest.rstrip(".")
    kind, sep, tail = stripped.partition(":")
    if not sep or not KIND.match(kind) or kind in RESERVED_KINDS or UUID_RE.match(stripped):
        return None
    if not tail or tail[0] == "/" or stripped[-1] in ":/-" or following in NON_TERMINATORS:
        return "skipped"
    old = "urn:mif:" + stripped
    return old, concept_urn(stripped)


def alias_spans(text: str) -> list[tuple[int, int]]:
    """Character spans of every `aliases` list in the text (JSON arrays, YAML
    flow lists, YAML block lists). The legacy ids recorded there ARE the old
    form on purpose, so the rewrite must never touch them -- that is also what
    keeps a second run a no-op."""
    spans = []
    for m in re.finditer(r'"aliases"\s*:\s*\[|^aliases:[ \t]*\[', text, re.M):
        i, depth, quote = m.end() - 1, 0, None
        while i < len(text):
            c = text[i]
            if quote:
                if c == "\\":
                    i += 1
                elif c == quote:
                    quote = None
            elif c in "\"'" and text[m.start()] == '"':
                quote = c if c == '"' else None
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        spans.append((m.start(), i + 1))
    for m in re.finditer(r"^aliases:[ \t]*\n((?:[ \t]+- .*(?:\n|$))+)", text, re.M):
        spans.append((m.start(), m.end()))
    return spans


def rewrite_ids(text: str) -> tuple[str, dict[str, str], list[str]]:
    changes: dict[str, str] = {}
    skipped: list[str] = []
    protected = alias_spans(text)

    def sub(m: re.Match) -> str:
        if any(a <= m.start() < b for a, b in protected):
            return m.group(0)
        rest = m.group(1)
        hit = classify(rest, text[m.end(): m.end() + 1])
        if hit == "skipped":
            skipped.append(m.group(0) + text[m.end(): m.end() + 1])
            return m.group(0)
        if not hit:
            return m.group(0)
        old, new = hit
        changes[old] = new
        return new + rest[len(old) - len("urn:mif:"):]

    return TOKEN.sub(sub, text), changes, skipped


def _with_alias(aliases, old: str) -> list:
    aliases = list(aliases) if isinstance(aliases, list) else []
    return aliases if old in aliases else aliases + [old]


def json_alias(text: str, old: str, new: str) -> str:
    """Record `old` in the top-level object's "aliases", keeping the file's style.

    A file in canonical JSON (2-space or compact) is edited structurally:
    sorted keys stay sorted (as `jq -S` writes findings), an existing aliases
    array is appended to in order. Otherwise a new "aliases" goes in textually
    right after the top-level "@id"; a non-canonical file that already has an
    "aliases" array is re-serialized with a 2-space indent.
    """
    doc = json.loads(text)
    for indent in (2, None):
        if json.dumps(doc, indent=indent, ensure_ascii=False) + "\n" == text:
            keys = list(doc)
            doc["aliases"] = _with_alias(doc.get("aliases"), old)
            if "aliases" not in keys:
                if keys == sorted(keys):
                    doc = dict(sorted(doc.items()))
                else:
                    at = keys.index("@id") + 1
                    order = keys[:at] + ["aliases"] + keys[at:]
                    doc = {k: doc[k] for k in order}
            return json.dumps(doc, indent=indent, ensure_ascii=False) + "\n"
    if "aliases" in doc:
        doc["aliases"] = _with_alias(doc.get("aliases"), old)
        return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"
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
    if isinstance(doc, dict) and isinstance(doc.get("@id"), str):
        return doc["@id"]
    return None


FM_ID = re.compile(r"^(['\"]?@id['\"]?:[ \t]*)(['\"]?)(urn:mif:[^'\"\s]+)\2[ \t]*$", re.M)


def md_alias(text: str, old: str) -> str:
    """Record `old` in a markdown file's frontmatter `aliases`.

    A missing `aliases` is added right after the `@id` line; an existing block
    list (`aliases:` + `  - x` items) or flow list (`aliases: [x, y]`) is
    appended to, in order.
    """
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---", 4)
    if end < 0:
        return text
    fm = text[4:end]
    am = re.search(r"^aliases:[ \t]*(.*)$", fm, re.M)
    if am:
        rest = am.group(1).strip()
        if rest.startswith("["):  # flow list
            close = fm.rfind("]", am.start(), am.end())
            if close < 0:
                return text
            body = fm[fm.index("[", am.start()) + 1: close]
            if old in [x.strip().strip("'\"") for x in body.split(",")]:
                return text
            ins = (", " if body.strip() else "") + old
            fm = fm[:close] + ins + fm[close:]
        elif rest == "":  # block list: append after its last item
            items = re.compile(r"\n([ \t]+)- (.*)")
            pos, indent, seen = am.end(), "  ", []
            for im in items.finditer(fm, am.end()):
                if im.start() != pos:
                    break
                indent, pos = im.group(1), im.end()
                seen.append(im.group(2).strip().strip("'\""))
            if old in seen:
                return text
            fm = fm[:pos] + f"\n{indent}- {old}" + fm[pos:]
        else:
            return text
        return "---\n" + fm + text[end:]
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
        skipped: list[str] = []
        if args.doc_ids:
            new_text, changes = migrate_doc_id(text)
        else:
            top_old = json_top_concept_id(text) if path.endswith(".json") else None
            fm = FM_ID.search(text[: text.find("\n---", 4)]) if path.endswith(".md") and text.startswith("---\n") else None
            new_text, changes, skipped = rewrite_ids(text)
            if args.aliases:
                if top_old in changes:
                    new_text = json_alias(new_text, top_old, changes[top_old])
                elif fm and fm.group(3) in changes:
                    new_text = md_alias(new_text, fm.group(3))
        if skipped:
            # Never silent: a templated or constructed id (a placeholder in
            # prose, a prefix concatenated at runtime) cannot be rewritten by
            # a text pass -- name every one so it can be fixed by hand.
            for tok in sorted(set(skipped)):
                print(f"{path}: NOT migrated (templated or constructed): {tok!r}", file=sys.stderr)
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
