"""harness_models — typed authoring models + deterministic emitter.

The per-schema modules (``findings``, ``goal``, ``artifact``, ``concordance``,
``pack``, ``session_state``, ``ontology``, ``source_envelope``) are GENERATED from
``schemas/*.schema.json`` by ``scripts/codegen/gen-models.sh`` — do not edit them by
hand; change the schema and regenerate. They are ``typing.TypedDict`` shapes (pure
stdlib): construct a plain dict with the real contract keys (``@id``, ``@context``,
``@type`` …) and the type checker validates the shape.

Emit with :func:`harness_models.emit.dump_json` / :func:`harness_models.emit.write`
to get the canonical, byte-stable contract JSON, then validate/land it through
``scripts/write-finding.sh`` (ajv is the validity gate).
"""

from . import emit

__all__ = ["emit"]
