#!/usr/bin/env python3
"""mif_id.py -- the org-wide MIF concept-id rule (MIF 1.4.x, SPECIFICATION §6.1).

MIF 1.4 requires a concept ``@id`` to be ``urn:mif:<uuid>``. Structured ids
(``urn:mif:concept:<ns>:<slug>``, ``urn:mif:source:...``, ``urn:mif:report:...``)
and bare slugs are no longer valid. The org mints them deterministically, so the
same logical concept gets the same id in every tool:

    NS  = uuid5(NAMESPACE_URL, "https://mif-spec.dev")
    urn:mif:<X>   (legacy structured id)  ->  urn:mif:uuid5(NS, "<X>")
    <s>           (bare slug id)          ->  urn:mif:uuid5(NS, "<s>")

``<X>`` is the remainder after ``urn:mif:``, hashed verbatim. This is exactly what
mif-rs does (``mif_core::concept_urn``): a source envelope is
``uuid5(NS, "source:<ns>:<slug>")`` and a rendered report/blog/book is
``uuid5(NS, "<channel>:<ns>:<slug>")``, i.e. the remainders of the old
``urn:mif:source:<ns>:<slug>`` / ``urn:mif:report:<ns>:<slug>`` forms. A finding
is ``uuid5(NS, "concept:<ns>:<slug>")``.

Reserved non-concept namespaces (``urn:mif:entity:``, ``agent:``, ``activity:``,
``conversation:``, ``vector:``) are NOT concept ids and are returned unchanged.

CLI (stdlib only)::

    mif_id.py concept:harness/my-topic:my-slug     -> urn:mif:<uuid>
    mif_id.py urn:mif:concept:harness/t:s          -> urn:mif:<uuid>  (same id)
    mif_id.py --slug my-doc-id                     -> <uuid>          (bare, no urn: prefix)
    mif_id.py urn:mif:<uuid> | <uuid>              -> urn:mif:<uuid> (idempotent)
    mif_id.py entity:org:acme                      -> urn:mif:entity:org:acme (reserved, not hashed)
"""
from __future__ import annotations

import re
import sys
import uuid

MIF_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, "https://mif-spec.dev")
RESERVED_KINDS = ("entity", "agent", "activity", "conversation", "vector")
UUID_RE = re.compile(
    r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
)
CONCEPT_URN_RE = re.compile(r"^urn:mif:" + UUID_RE.pattern[1:])


def is_concept_urn(value: str) -> bool:
    """True when ``value`` already has the MIF 1.4 concept-URN form."""
    return bool(CONCEPT_URN_RE.match(value))


def is_reserved(value: str) -> bool:
    """True for a reserved non-concept URN (entity/agent/activity/...)."""
    return any(value.startswith(f"urn:mif:{k}:") for k in RESERVED_KINDS)


def slug_uuid(slug: str) -> str:
    """uuid5(NS, slug) as a bare UUID string (a document's frontmatter ``id``)."""
    return str(uuid.uuid5(MIF_NAMESPACE, slug))


def concept_urn(remainder: str) -> str:
    """``urn:mif:`` + uuid5(NS, remainder); accepts a full legacy URN too.

    Idempotent on an existing concept URN; reserved URNs pass through.
    """
    if is_concept_urn(remainder) or is_reserved(remainder):
        return remainder
    if remainder.startswith("urn:mif:"):
        remainder = remainder[len("urn:mif:"):]
    if not remainder:
        raise ValueError("empty id remainder")
    # A bare UUID is already a concept id's identifier, and a remainder in a
    # reserved namespace (entity:org:acme) is not a concept at all: give both
    # back in URN form instead of hashing them into a new, unrelated id.
    if UUID_RE.match(remainder) or is_reserved("urn:mif:" + remainder):
        return "urn:mif:" + remainder
    return "urn:mif:" + slug_uuid(remainder)


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "--slug":
        print(slug_uuid(argv[1]))
        return 0
    if len(argv) != 1 or argv[0] in ("-h", "--help"):
        print(__doc__.split("CLI (stdlib only)::", 1)[-1].rstrip(), file=sys.stderr)
        return 2
    try:
        print(concept_urn(argv[0]))
    except ValueError as e:
        print(f"mif_id: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
