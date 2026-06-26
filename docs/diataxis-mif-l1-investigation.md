---
title: "Investigation: MIF Level-1 frontmatter for the Diátaxis channel"
---

# Investigation: MIF Level-1 frontmatter for the Diátaxis channel

## Question

Can the `diataxis` channel's rendered docs carry frontmatter that makes them
**MIF Level-1 compliant** while staying **markdownlint-clean** and **Diátaxis
compliant** (a `diataxis_type` marker plus a single body H1)?

**Verdict: YES.** The three requirements do not conflict, because MIF Level 1
does not require a frontmatter `title:` key — the one key that previously forced
the MD025 (single-title) failure resolved by emitting the title as the body H1.

## 1. What MIF Level 1 requires (derived from `schemas/mif/`)

MIF is not split into three separate schemas; the conformance levels are tiers of
richness over one concept schema. Reading the vendored contract:

- `schemas/mif/mif.schema.json` (`required`) defines the base concept — the
  Level-1 floor — as exactly six fields:
  - `@context`, `@type`, `@id` (pattern `^urn:mif:`), `conceptType`
    (`semantic` | `episodic` | `procedural`), `content` (string),
    `created` (RFC 3339 `date-time`).
  - `title` is **not** required; `additionalProperties` is unset, so extra keys
    (such as `diataxis_type`) are permitted.
- `harness.config.schema.json` describes Level 3 as "provenance + citations +
  entities + extensions". Those four are required by `schemas/findings.schema.json`
  (the L3 finding contract), **not** by the base concept schema.

**Reading:** Level 1 = a document whose frontmatter-plus-body projects to a JSON
object that validates against `schemas/mif/mif.schema.json` (the six base fields),
without the Level-3 additions (provenance, citations, entities, extensions, and
the harness verification verdict) that `findings.schema.json` mandates.

### L1 validation method

Mirror `scripts/mif-project.sh`'s projection (split the YAML frontmatter, convert
it with `yq`, fold the Markdown body in as `content`), then validate against the
**base concept** schema rather than the findings schema:

```bash
ajv validate --spec=draft2020 --strict=false -c ajv-formats \
  -s schemas/mif/mif.schema.json \
  -r schemas/mif/definitions/entity-reference.schema.json \
  -d concept.json
```

This is Level 1, not Level 3: it checks only the base concept and omits the
provenance, citations, entities, and verification that `mif-project.sh` enforces
via `findings.schema.json`.

## 2. Proposed frontmatter scheme

Add the base concept fields to each quadrant doc, keep `diataxis_type`, and add
**no** `title:` key. `content` is folded from the body by the projector, so it is
not a frontmatter key.

```yaml
---
"@context": https://mif-spec.dev/schema/context.jsonld
"@type": Concept
"@id": urn:mif:doc:<namespace>:<path-slug>   # shipped: reference-<dim>-<finding-slug>
conceptType: procedural   # tutorial/how-to -> procedural; reference/explanation -> semantic
created: "<RFC 3339 date-time>"
namespace: <namespace>
diataxis_type: tutorial    # the Diátaxis marker; an allowed extra property
audience: newcomers        # optional, tutorial only
---
```

The quoted `@`-prefixed keys are required because `@` is a reserved YAML
indicator; the `yq` toolchain already round-trips this form in the `report`
channel's frontmatter. Per-quadrant the only differences are `@id`, `conceptType`,
and the `diataxis_type` value.

## 3. Proof

A sample tutorial doc authored under this scheme satisfies all three checks at
once (commands and outputs reproduced from the session):

- **MIF L1** — projecting the frontmatter+body and validating against
  `schemas/mif/mif.schema.json` prints `concept.json valid` (exit 0).
- **markdownlint** — `markdownlint-cli2 --config .markdownlint-cli2.jsonc <file>`
  prints `Summary: 0 error(s)`.
- **Diátaxis** — `grep -nE '^(diataxis_type:|# )' <file>` prints exactly one
  `diataxis_type:` line and exactly one `#` heading.

## 4. Verdict and why it holds

**YES — MIF L1 + markdownlint + Diátaxis co-exist.** The only field that breaks
markdownlint MD025 is a frontmatter `title:` colliding with the body H1, and MIF
Level 1 does not require `title`. Omitting it (the body H1 carries the title) and
relying on `additionalProperties` to admit `diataxis_type` lets one frontmatter
block be both a valid MIF concept and a Diátaxis marker.

Trade-off worth noting: this raises the channel from MIF-exempt to MIF Level 1
only — not Level 3. Level 3 would require provenance, citations, entities, and a
falsification verdict in the frontmatter, which is the role of the canonical
`report` channel; pushing it into authored documentation would mix internal MIF
identity into published prose. Level 1 adds stable, typed MIF identity
(`@id`, `conceptType`, `created`) without that cost.

## Status

This began as an investigation; the scheme was subsequently **adopted in
production**. The shipped `diataxis` renderer emits MIF Level-1 frontmatter on
every page, `schemas/diataxis-doc.schema.json` is the validating contract, and
`verify.sh` `gate_m16` enforces it. The shipped `@id` is minted from the page's
output path — `urn:mif:doc:<namespace>:<relpath-with-slashes-as-dashes>` (e.g.
`urn:mif:doc:harness/example-topic:reference-technical-<finding-slug>`) — rather
than the `<topic>-<quadrant>-<slug>` sketch above. This document is retained as
the feasibility rationale; the renderer, schema, and gate are the source of truth.
