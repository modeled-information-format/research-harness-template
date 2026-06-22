"""Deterministic JSON emitter for harness authoring models.

The emitted JSON is the contract. Agents build a typed dict (see the generated
``harness_models.<schema>`` modules) and call :func:`dump_json` / :func:`write`
instead of hand-composing JSON in the shell — eliminating the ``jq -n`` / ``eval``
quoting footgun. ``json`` guarantees syntactically valid output; this module pins
the *canonical form* so the same logical content always produces byte-identical
bytes:

* keys sorted lexicographically (object key order is semantically irrelevant to
  the schema, so a stable order is chosen for the contract),
* two-space indent, UTF-8 preserved (``ensure_ascii=False``),
* exactly one trailing newline.

**Values are emitted faithfully — nothing is dropped.** The models mark optional
fields ``NotRequired``: to omit one, leave the key out of the dict entirely. A
``None`` that is present is intentional and serializes as ``null`` (some fields,
e.g. ``session-state`` ``attempted_at``, are *required and nullable* — dropping
their ``null`` would make the contract invalid). ajv is the validity gate that
catches a ``null`` placed where the schema forbids it. Array order is preserved.
Pure stdlib.
"""

from __future__ import annotations

import json
from typing import Any


def dump_json(obj: Any) -> str:
    """Return the canonical contract JSON string for ``obj`` (with trailing newline).

    ``allow_nan=False`` makes NaN/Infinity raise instead of emitting the bare
    ``NaN``/``Infinity`` tokens that are not valid JSON — the emitter never
    produces output it claims is valid.
    """
    return (
        json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True, allow_nan=False) + "\n"
    )


def write(obj: Any, path: str) -> str:
    """Write the canonical contract JSON for ``obj`` to ``path``. Returns ``path``.

    Typical use: write to a staging file, then hand it to
    ``scripts/write-finding.sh <staging> <findings-dir> <name.json>`` which
    validates against the schema and atomically renames it into place.
    """
    # newline="" disables platform newline translation so the on-disk bytes match
    # dump_json exactly (the canonical "\n" form) on every platform.
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(dump_json(obj))
    return path
