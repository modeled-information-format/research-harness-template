---
name: ai-spec
description: Render a topic's surviving findings into an AI-ready, agent-executable architecture spec. A genre-shaping of the artifact -> Markdown pipeline (not a new mechanism) — finding_refs become grounded evidence sections, the goal's completion checks become EARS acceptance criteria, and the artifact sections become the document structure. Use to turn research into a buildable spec a downstream coding agent executes.
version: 0.13.0
argument-hint: "<topic> [--genre ai-architecture-doc|feature-spec|kiro-requirements|kiro-design|kiro-tasks] [-o <out.md>]"
allowed-tools: Read, Write, Bash, Glob, Grep
---

# Channel: AI-Ready Spec

Delivery adapter (SPEC §6d, §10). Turns a topic's research into a buildable spec for a
downstream AI coding agent. The channel owns **delivery** (artifact -> document); a spec-genre
skill (`ai-architecture-doc` / `feature-spec` / `kiro-requirements` / `kiro-design` /
`kiro-tasks`, each an external `mif-docs-plugin` skill per ADR-0018) owns **shape**. Build on the
existing `artifact.json` -> Markdown pipeline; this is a genre-shaping of that path, not a
parallel one.

## Inputs

- `reports/<topic>/findings/*.json` — surviving findings (verdict != `falsified`).
- `reports/<topic>/goal.json` — `completion_condition.checks[]` become the acceptance criteria.
- `reports/<topic>/ontology-map.json` — per-finding resolved type, for the entity-catalog grounding.
- The selected spec genre (default `ai-architecture-doc`).

## Procedure

1. **Select** — gather surviving and weakened findings for the topic; resolve their ontology
   types so entity-catalog rows carry their grounding.
2. **Synthesize** — run `scripts/synthesize-artifact.sh <findings-dir> <genre> <artifact.json>`
   with the chosen genre, so `artifact.json` carries `genre`, `finding_refs[]` for every cited
   finding, and `sections[]` for the taxonomy.
3. **Shape (genre)** — apply the genre skill's section taxonomy and frontmatter contract:
   - `finding_refs[]` → grounded evidence sections (every design claim carries a `finding_ref`
     or a named external standard).
   - goal `completion_condition.checks[]` → **EARS** acceptance criteria (`WHEN … SHALL …` +
     the check's verify command as the executable test).
   - `artifact.sections[]` → the document structure.
   - when an ontology pack is bound, render its entity inventory as a grounded entity-catalog
     section and its inter-type relationships as a relationship-model section, each row naming
     its source vocabulary.
4. **Render** — deterministically write the spec to the `<out.md>` path passed to
   `render-artifact.sh` (same findings -> byte-identical Markdown). Default output paths, so
   switching `--genre` never overwrites a sibling spec:
   - `ai-architecture-doc` (default): `reports/<topic>/<topic>-build-spec.md`
   - `feature-spec`: `reports/<topic>/<topic>-feature-build-spec.md`
   - `kiro-requirements`: `reports/<topic>/<topic>-kiro-requirements.md`
   - `kiro-design`: `reports/<topic>/<topic>-kiro-design.md`
   - `kiro-tasks`: `reports/<topic>/<topic>-kiro-tasks.md`

   Carry MIF frontmatter + the genre markers (`genre`, `audience: implementer`, `status`,
   `evidence_base`).
5. **Gate** — the spec must pass `markdownlint-cli2` with zero errors; every evidence row must
   carry a citation; the body carries no internal `urn:mif:` identity.

## Greenfield vs brownfield

`status: proposed` for a greenfield build (work not yet done). To document/affirm an existing
build, use the worked-specimen framing ("these artifacts already exist") — same genre, same
taxonomy, `status` and the objective framing differ.

## The Kiro three-document set

`kiro-requirements`, `kiro-design`, and `kiro-tasks` are three independently selectable genres
(matching how `mif-docs-plugin` ships them), not one combined genre — a caller wanting the full
Kiro spec set for one feature runs this channel three times, once per genre, against the same
findings. This replaced a single bundled `kiro-spec` pack (research-harness-template#409); see
that story and ADR-0018 for the rationale.

## Output

The agent-consumable spec, written to the `<out.md>` path given to `render-artifact.sh`, at the
default path named for its genre above unless overridden. A companion **worked specimen** (the
genre rendered end-to-end for a concrete subject) proves the genre is real output, not just
described.

## Dependencies

`scripts/synthesize-artifact.sh`, `scripts/render-artifact.sh`, an enabled `mif-docs-plugin`
spec-genre skill (`harness.config.json` `packs[]`, `marketplace-ref` against the `mif-docs`
marketplace), `schemas/artifact.schema.json`, `reports/<topic>/goal.json`.
