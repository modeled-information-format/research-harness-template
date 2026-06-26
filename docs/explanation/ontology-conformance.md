---
title: "Ontology conformance"
diataxis_type: explanation
---

# Ontology conformance

Ontology is a **deterministic, per-topic member** of the harness — held to the same
fail-closed bar as findings, reports, and sources. This explains why it is structured
the way it is.

## The problem it closes

MIF's `mif.schema.json` ships an ontology *reference* (`OntologyReference`) and an
`EntityData` block with `additionalProperties: true`, but nothing validated that a
referenced ontology existed, that an `entity_type` was one the ontology declared, or
that an entity's fields matched. Ontology was conformance-*claimed* but unenforced —
pure agent trust. `gate_m12` makes it real: the build fails on any unresolvable
reference, undeclared/ambiguous type, missing required field, dangling
binding/catalog link, or broken (missing/invalid) `VENDOR.lock` provenance.

## Vendored from MIF, not invented

The **contract** (`schemas/mif/ontology.schema.json` + context) was seeded from
`github.com/modeled-information-format/MIF`, with provenance (source, commit, seed SHA-256) recorded in
`schemas/mif/VENDOR.lock`. **Nothing is locked** — the contract is first-class and
evolves in-repo (e.g. the `subtype_of` entity-type subsumption field) on its way back
to MIF; `gate_m12` asserts no file is verbatim-locked. The base ontologies (`mif-base`,
`shared-traits`) and the example ontologies were seeded the same way and are equally
editable: created, expanded, and enriched via the `ontology-manager` skill (see
`/ontology-review` Phase 3). `gate_m12` re-validates every ontology — original or
edited — against the contract on each build, so authoring stays fail-closed by
*validation*, not by freezing files. The `ontology-manager` skill is copied in and
tweaked for the harness: PyPI-stripped (its optional `jsonschema`→`ajv`, `pyyaml`
dropped for `yq`), repointed at the vendored schema. The only authored ontology is
`mif-generic` — MIF's built-in entity types (concept/person/organization/technology/
file) expressed so they can be classified against.

## Registry as yaml, projected on the fly

The registry is the set of vendored ontology **YAMLs** — the single committed source
of truth. JSON is projected with `yq -o=json | ajv` at validate time and never
committed. This avoids three failure modes a committed projection would create: an
uncheckable file outside VENDOR.lock, silent drift when the yaml changes, and hostage
to whatever `yq` version produced the json.

## Per-topic binding, with an always-on core

`mif-generic` + `mif-base` are **always enabled for every topic** (cataloged as core),
so any finding can be typed generically even with no domain ontology. The example domain
ontologies are optional **data packs** (`packs/ontologies/<id>/`, `kind: ontology`) —
not Claude Code plugins, so they never touch `gate_m5`. They are disabled by default;
`harness.config.json` `ontologies[]` enables them, `sync-packs.sh` catalogs the enabled
subset, and `topics[].ontologies[]` binds them per topic. An extended ontology applies
**only** to topics that bind it — domain typing stays scoped to where it belongs.

Binding is **transitive over `extends`**: the resolved set for a topic is the always-on
core ∪ the topic's bound ontologies ∪ each bound ontology's `extends` ancestors. A
binding therefore reaches its ancestor LAYERS — e.g. binding `software-engineering`
(which `extends: engineering-base`) also resolves the shared engineering supertypes
`engineering-base` declares (`component`, `design-pattern`, …). The intermediate
`engineering-base` layer is cataloged **present-but-not-core** (`core=false`): it is
never always-on, so a non-engineering topic never resolves those types. This keeps the
upstream-submittable generic core domain-neutral while the engineering domains share one
supertype layer. `resolve-ontology.sh` and `validate-concordance.sh` both walk the chain
and fail closed if an `extends` target is not cataloged.

## Classification vs resolution — the deterministic split

Two layers, deliberately separated by what can be proven deterministically:

- **Classification** — deciding which `entity_type` a finding *resembles* — is an
  agent step (topic onboarding in `/start`, the `dimension-analyst`). It is
  best-effort and **not** gate-proven, the same posture as inbound source-wrapping.
- **Resolution + validation + recording** — `resolve-ontology.sh` — is fully
  deterministic and is what `gate_m12` enforces. Whatever type an agent stamps must
  resolve to a bound ontology and satisfy its schema, or the build fails.

So a stamped type is never trusted on faith: it is resolved against the topic's bound
ontologies and validated, with the result recorded to `reports/<topic>/ontology-map.json`.
