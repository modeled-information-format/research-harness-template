---
name: ai-spec
description: Render a topic's surviving findings into an AI-ready, agent-executable architecture spec. A genre-shaping of the artifact -> Markdown pipeline (not a new mechanism) — finding_refs become grounded evidence sections, the goal's completion checks become EARS acceptance criteria, and the artifact sections become the document structure. Use to turn research into a buildable spec a downstream coding agent executes.
version: 0.1.0
argument-hint: "<topic> [--genre architecture-spec|kiro-spec|feature-spec] [-o <out.md>]"
allowed-tools: Read, Write, Bash, Glob, Grep
---

# Channel: AI-Ready Spec

Delivery adapter (SPEC §6d, §10). Turns a topic's research into a buildable spec for a
downstream AI coding agent. The channel owns **delivery** (artifact -> document); a spec-genre
pack (`architecture-spec` / `kiro-spec` / `feature-spec`) owns **shape**. Build on the existing
`artifact.json` -> Markdown pipeline; this is a genre-shaping of that path, not a parallel one.

## Inputs

- `reports/<topic>/findings/*.json` — surviving findings (verdict != `falsified`).
- `reports/<topic>/goal.json` — `completion_condition.checks[]` become the acceptance criteria.
- `reports/<topic>/ontology-map.json` — per-finding resolved type, for the entity-catalog grounding.
- The selected spec genre (default `architecture-spec`).

## Procedure

1. **Select** — gather surviving and weakened findings for the topic; resolve their ontology
   types so entity-catalog rows carry their grounding.
2. **Synthesize** — run `scripts/synthesize-artifact.sh <findings-dir> <genre> <artifact.json>`
   with the chosen genre, so `artifact.json` carries `genre`, `finding_refs[]` for every cited
   finding, and `sections[]` for the taxonomy.
3. **Shape (genre)** — apply the genre pack's section taxonomy and frontmatter contract:
   - `finding_refs[]` → grounded evidence sections (every design claim carries a `finding_ref`
     or a named external standard).
   - goal `completion_condition.checks[]` → **EARS** acceptance criteria (`WHEN … SHALL …` +
     the check's verify command as the executable test).
   - `artifact.sections[]` → the document structure.
   - when an ontology pack is bound, render its entity inventory as a grounded entity-catalog
     section and its inter-type relationships as a relationship-model section, each row naming
     its source vocabulary.
4. **Render** — deterministically write the spec to the `<out.md>` path passed to
   `render-artifact.sh` (same findings -> byte-identical Markdown). The architecture-spec default
   is `reports/<topic>/<topic>-build-spec.md`; qualify other genres with the genre so switching
   `--genre` does not overwrite a sibling spec (`<topic>-kiro-build-spec.md`,
   `<topic>-feature-build-spec.md`). Carry MIF frontmatter + the genre markers (`genre`,
   `audience: implementer`, `status`, `evidence_base`).
5. **Gate** — the spec must pass `markdownlint-cli2` with zero errors; every evidence row must
   carry a citation; the body carries no internal `urn:mif:` identity.

## Greenfield vs brownfield

`status: proposed` for a greenfield build (work not yet done). To document/affirm an existing
build, use the worked-specimen framing ("these artifacts already exist") — same genre, same
taxonomy, `status` and the objective framing differ.

## Output

The agent-consumable spec, written to the `<out.md>` path given to `render-artifact.sh`. The
architecture-spec default is `reports/<topic>/<topic>-build-spec.md`; non-architecture genres take
a genre-qualified path (`<topic>-kiro-build-spec.md`, `<topic>-feature-build-spec.md`) so changing
genre does not overwrite a sibling spec. A companion **worked specimen** (the genre rendered
end-to-end for a concrete subject) proves the genre is real output, not just described.

## Dependencies

`scripts/synthesize-artifact.sh`, `scripts/render-artifact.sh`, a bound spec-genre pack,
`schemas/artifact.schema.json`, `reports/<topic>/goal.json`.
