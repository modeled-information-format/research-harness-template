---
title: "Documentation"
---

# Documentation

The harness ships one merged [Diátaxis](https://diataxis.fr/) documentation set,
so a clone is self-documenting (design spec §4a, "Diataxis docs — KEEP → bundle").

| Quadrant | For | Start here |
| --- | --- | --- |
| [Tutorials](../tutorials/getting-started/) | Learning by doing | [getting-started.md](../tutorials/getting-started/) |
| [How-to guides](../how-to/run-a-research-session/) | Achieving a task | [run-a-research-session.md](../how-to/run-a-research-session/), [adopt-packs.md](../how-to/adopt-packs/), [verify-a-release.md](../how-to/verify-a-release/) |
| [Reference](../reference/contracts/) | Looking up facts | [contracts.md](../reference/contracts/), [dependencies.md](../reference/dependencies/), [coverage.md](../reference/coverage/) |
| [Explanation](../explanation/reading-the-research/) | Understanding why | [reading-the-research.md](../explanation/reading-the-research/) (start here — what you get & how to read it), [architecture.md](../explanation/architecture/), [pack-structure.md](../explanation/pack-structure/), [living-corpus.md](../explanation/living-corpus/) |

## Adopting the harness

These pages cover the full adoptable surface — every pack, skill, command,
agent, and script, plus what you must install and how to verify a release.

| Page | What it gives you |
| --- | --- |
| [Dependencies and requirements](../reference/dependencies/) | Every external tool/runtime, minimum version, install command, and which component needs it |
| [Documentation coverage](../reference/coverage/) | Audit index proving every pack, skill, command, agent, and script is documented |
| [Pack catalog](../reference/packs/) | Every bundled pack — purpose, dependencies, benefits, and how to enable it |
| [Core skills](../reference/core-skills/) · [Commands](../reference/commands/) · [Agents](../reference/agents/) · [Scripts](../reference/scripts/) | The non-pack core surface |
| [How to adopt a pack](../how-to/adopt-packs/) | Enable/disable a pack and satisfy its prerequisites |
| [How to verify a release](../how-to/verify-a-release/) | Confirm a downloaded artifact with `gh attestation verify` |

## Authoring a new doc

Every doc in this tree routes through `mif-docs-plugin`'s shared substrate
(ADR-0018) — never hand-write frontmatter from scratch:

- **ADRs** (`docs/adr/`): use `mif-docs-plugin`'s `adr` skill. The `adr`
  genre is exempt from `mif-validate` — per that plugin's own ADR-0001, its
  ADRs are validated by the `structured-madr` GitHub Action instead, and
  this repo's own `ci.yml` runs it (`adr-smadr` job, `smadr` mode, strict,
  required — research-harness-template#435). Conform to the
  [Structured MADR](https://github.com/modeled-information-format/structured-madr)
  format/tooling by following `docs/adr/template.md`'s shape — a new ADR
  that departs from it will fail this required CI check.
- **Diátaxis docs** (`docs/explanation/`, `docs/how-to/`, `docs/reference/`,
  `docs/tutorials/`): use the matching `diataxis-explanation` /
  `diataxis-how-to` / `diataxis-reference` / `diataxis-tutorial` skill.
- **Proposals** (`docs/proposals/`): use the genre skill matching the
  proposal's actual shape (`ai-architecture-doc`, `feature-spec`, `prd`,
  `rust-rfc`, …) — the filename should name the skill that produced it.

After authoring, run `mif-validate --level 1|2|3` (via the `mif-validate`
skill or `mif-mcp`'s `validate_mif_document` tool) before committing, and
`mif-provenance stamp` if the session's capture ledger witnessed the write
(`mifProvenance.capture` is enabled by default in `.claude/settings.json` —
see [Dependencies and requirements](../reference/dependencies/)).

Audited 2026-07-12 (research-harness-template#410): every existing
non-ADR Diátaxis doc already passes `mif-validate --level 1`
(schema-conformant, lossless round-trip) under this repo's existing
frontmatter convention. Reaching L3 (`temporal` + witnessed `provenance`)
on the existing corpus is a retrofit, not a one-time backfill this story
performs wholesale — `mif-provenance stamp` declines on any file the
current session's ledger never touched, so retroactively fabricating a
provenance block would misrepresent authorship. Existing docs climb to L3
the next time they're genuinely re-authored or substantively edited in a
live session; new docs should be authored at L3 from the start via the
skills above.
