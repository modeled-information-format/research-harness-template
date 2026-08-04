---
title: "mif-docs-plugin as the document-tooling and provenance substrate"
description: "Route document-level frontmatter authoring, MIF conformance validation, and provenance for every document-shaped deliverable through mif-docs-plugin; retire local duplicates of its genres."
type: adr
category: architecture
tags: [mif, mif-docs, provenance, conformance, deprecation]
status: accepted
created: 2026-07-12
updated: 2026-07-12
author: zircote
project: research-harness-template
technologies: [mif-docs-plugin, MIF, Claude Code plugins]
audience: [developers, architects]
related: [0002-mif-level-3-io-conformance.md, 0005-packs-and-plugins-extension-model.md, 0012-on-demand-ontology-vendoring.md]
---

# ADR-0018: mif-docs-plugin as the document-tooling and provenance substrate

## Status

Accepted

## Context

### Background and Problem Statement

ADR-0002 bound the harness's findings, knowledge graph, citations, and reports
to MIF Level-3, validated against the vendored `schemas/mif/` closure via
`ajv`. That schema-conformance gate is real but narrow: it proves a document's
JSON shape is valid, not that its provenance is anything more than
model-asserted frontmatter. Separately, `research-harness-template#228`
externalized 18 of 21 bundled report genres to
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)
(`docs/reference/packs/reports.md`), but that migration was scoped to those
report genres alone — three bundled genre packs
(`packs/genres/architecture-spec`, `feature-spec`, `kiro-spec`) still
duplicate `mif-docs-plugin` skills locally
(`ai-architecture-doc`, `feature-spec`, `kiro-design`/`kiro-requirements`/
`kiro-tasks`), and the harness's own `docs/` tree (ADRs, Diátaxis docs,
proposals) has no wiring to the plugin at all.

`mif-docs-plugin` ships a distinct, complementary capability ADR-0002 does not
cover: `mif-provenance`, a hook-observed, witnessed provenance stamper
(`agent`, `agentVersion`, the session activity URN) as opposed to
model-asserted provenance a schema gate cannot distinguish from a fabricated
block. It also ships `mif-frontmatter`/`mif-validate` as a shared authoring
and validation substrate, and one skill per document genre.

### Current Limitations

- No document in this repo carries `mif-docs`-witnessed provenance — every
  provenance block, including in synthesized reports, is model-asserted.
- Three bundled genre packs reimplement document tooling `mif-docs-plugin`
  already ships, duplicating maintenance burden the #228 migration was meant
  to eliminate.
- `docs/` (ADRs, Diátaxis docs, proposals) has no relationship to
  `mif-docs-plugin` at all — every file's frontmatter and structure is
  hand-authored against no shared substrate, and conformance is unverified.

## Decision Drivers

### Primary Decision Drivers

1. Provenance must be witnessed, not merely schema-valid — the two are
   different properties and only `mif-docs-plugin`'s `mif-provenance`
   supplies the former.
2. Duplicate document tooling (a bundled genre pack that reimplements an
   existing `mif-docs-plugin` skill) is technical debt this repo has already
   committed to eliminating (#228's stated goal).

### Secondary Decision Drivers

1. The harness's own `docs/` tree should not be exempt from the conformance
   bar its own deliverables must meet.
2. The findings/knowledge-graph schema substrate (ADR-0002) is working and
   scoped correctly — this decision must not disturb it.

## Considered Options

### Option 1: Extend the harness's own ajv/schema mechanism to cover provenance

**Description:** Add a witnessed-provenance concept to the harness's local
`schemas/mif/` closure and enforcement scripts, instead of adopting
`mif-docs-plugin`'s `mif-provenance`.

- **Advantages:** No new external dependency; stays inside the mechanism
  ADR-0002 already established.
- **Disadvantages:** Reimplements hook-observed session-ledger witnessing
  that `mif-docs-plugin` already ships and maintains; duplicates the exact
  class of maintenance burden #228 eliminated for report genres.
- **Risk Assessment:** technical medium; schedule medium; ecosystem high
  (diverges from the org's shared `mif-docs` substrate other repos already
  consume).

### Option 2: Keep bundled genres as "thin wrappers" over mif-docs-plugin

**Description:** Keep `packs/genres/architecture-spec`, `feature-spec`,
`kiro-spec` as local packs, but have each delegate its actual rendering to
the equivalent `mif-docs-plugin` skill internally.

- **Advantages:** Preserves the harness-specific `artifact.json` → sections
  mapping documented in each pack's `SKILL.md` without a full external-ref
  migration.
- **Disadvantages:** Still three packs to maintain that exist only to call
  another plugin; the #228 precedent already rejected this shape for the 18
  report genres in favor of direct `marketplace-ref` consumption.
- **Risk Assessment:** technical low; schedule low; ecosystem medium (a
  second, inconsistent extension pattern alongside #228's).

### Option 3: mif-docs-plugin as the single document-tooling and provenance substrate

**Description:** Adopt `mif-docs-plugin`'s `mif-frontmatter`/`mif-validate`/
`mif-provenance` as the substrate for every document-shaped deliverable's
frontmatter authoring, conformance, and provenance. Retire the three
remaining duplicate bundled genre packs via direct `marketplace-ref`
consumption, matching #228's pattern exactly. Migrate `docs/` (ADRs, Diátaxis
docs) onto the plugin's `adr`/`diataxis-*` skills. Leave the harness-local
`ajv` schema-conformance gate for findings/knowledge-graph data (ADR-0002)
unchanged — it answers a different question (schema shape) than
`mif-provenance` answers (witnessed authorship).

- **Advantages:** One consistent extension pattern across every document
  genre this repo touches; witnessed provenance closes a real gap; no
  duplicate document tooling remains.
- **Disadvantages:** A broader migration surface (docs/ retrofit, three
  genre packs, a new CI gate) than either alternative alone.
- **Risk Assessment:** technical low; schedule low; ecosystem low (extends an
  already-adopted, already-pinned dependency rather than introducing a new
  one).

## Decision

Adopt **Option 3**. `mif-docs-plugin` (pinned via `harness.config.json`
`marketplaces[]`; `mif-mcp` wiring in `.mcp.json` and `mifProvenance` capture
in `.claude/settings.json` tracked by research-harness-template#406) is the
single substrate for document-level
frontmatter authoring, MIF conformance validation, and provenance across
every document-shaped deliverable this harness produces or the harness repo
itself contains. `packs/genres/architecture-spec`, `feature-spec`,
`kiro-spec` are retired in favor of direct `marketplace-ref` consumption of
`mif-docs-plugin`'s `ai-architecture-doc`, `feature-spec`, and
`kiro-design`/`kiro-requirements`/`kiro-tasks` (research-harness-template#409).
`docs/adr/*` and `docs/{explanation,how-to,reference,tutorials}/*` are
migrated onto the plugin's `adr` and `diataxis-*` skills
(research-harness-template#410). ADR-0002's `ajv` schema-conformance gate for
findings and the knowledge graph is unchanged and continues to run — it is
complementary to, not superseded by, this decision.

### Deprecation policy

A document type produced by this repo that duplicates an existing
`mif-docs-plugin` genre is retired in favor of direct external consumption —
not kept in parallel, and not reimplemented as a thin wrapper (Option 2,
rejected above). A document type genuinely specific to this harness, with no
`mif-docs-plugin` genre equivalent, is still built as an extension of the
plugin's `mif-frontmatter`/`mif-validate`/`mif-provenance` substrate rather
than a fully bespoke mechanism.

## Consequences

### Positive

1. Every document-shaped deliverable can carry witnessed, not merely
   asserted, provenance.
2. No duplicate document tooling remains once `packs/genres/architecture-spec`,
   `feature-spec`, `kiro-spec` are retired.
3. `docs/` conformance becomes verifiable instead of assumed.

### Negative

1. Retiring three bundled genre packs and migrating `docs/` is nontrivial
   migration work, tracked across research-harness-template#408–#414.

### Neutral

1. The harness now carries two document-conformance mechanisms operating at
   different layers (ADR-0002's schema gate for findings/graph data;
   `mif-docs-plugin`'s substrate for authored documents) rather than one —
   this is intentional, not drift, since they answer different questions.

## Decision Outcome

`mif-docs-plugin` becomes this repo's single authority for document-level
authoring, conformance, and provenance, closing the witnessed-provenance gap
ADR-0002 left open and eliminating duplicate document tooling per the
deprecation policy stated above. The findings/knowledge-graph schema
substrate ADR-0002 established is unaffected.

## Related Decisions

- [ADR-0002: MIF Level-3 I/O conformance as the harness substrate](../0002-mif-level-3-io-conformance/)
- [ADR-0005: Packs and plugins as the only extension surface](../0005-packs-and-plugins-extension-model/)
- [ADR-0012: On-demand ontology vendoring from a canonical registry](../0012-on-demand-ontology-vendoring/)

## Links

- `docs/reference/packs/reports.md`
- `docs/reference/dependencies.md`
- Epic research-harness-template#405, Story research-harness-template#406

## More Information

- **Date:** 2026-07-12
- **Source:** `docs/reference/packs/reports.md`, `docs/reference/dependencies.md`,
  Epic research-harness-template#405, Story research-harness-template#406

## Audit

### 2026-07-12

**Status:** Pending

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| `mif-docs-plugin` marketplace pin present | `harness.config.json` `marketplaces[]` | compliant |
| `mif-mcp` wired in `.mcp.json` | tracked — research-harness-template#406 | pending |
| Provenance capture enabled | tracked — research-harness-template#406 (`.claude/settings.json` `mifProvenance.capture`) | pending |
| Duplicate genre packs retired | pending — research-harness-template#409 | pending |
| `docs/` migrated onto plugin skills | pending — research-harness-template#410 | pending |

**Summary:** The marketplace pin this decision builds on already exists; the
`mif-mcp`/`mifProvenance` wiring (#406), the deprecation of duplicate genre
packs (#409), and the `docs/` migration (#410) this ADR authorizes are all
tracked and not yet complete as of this ADR's own branch.

**Action Required:** Land research-harness-template#406, #409, and #410 to
close the pending items above.
