---
id: reference-packs-genres
type: semantic
created: '2026-06-30T03:12:58-04:00'
modified: '2026-07-12T14:39:25.260Z'
namespace: docs/reference/packs
tags:
  - documentation
  - reference
title: "Reference: genre packs"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-30T03:12:58-04:00'
  ttl: P6M
  recordedAt: '2026-06-30T03:12:58-04:00'
provenance:
  '@type': Provenance
  sourceType: agent_inferred
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:ae91b6b6-8d5c-4bea-963d-9e4b7907cf09
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Genre packs

Spec-genre packs define the *shape* of an AI-ready, agent-executable
specification; the `ai-spec` channel renders them. Each is optional and
toggle-ready (`enabled:false`). Choose by what the deliverable defines.

| Genre | Use when the deliverable defines | Form |
| --- | --- | --- |
| `ai-architecture-doc` | a **structure** (cross-cutting types, relationships, namespaces) | arc42/C4 §1–§12 + EARS |
| `kiro-requirements` | a **single feature**'s numbered requirements | EARS acceptance criteria per requirement |
| `kiro-design` | a **single feature**'s technical design, traced to its requirements | design doc |
| `kiro-tasks` | a **single feature**'s implementation plan | numbered, checkbox task list |
| `feature-spec` | **one capability** authored for a coding agent | Spec Kit single-feature + EARS |

All five express acceptance criteria in **EARS** (`WHEN … SHALL …` + the goal
check's verify command), and ground every design claim in a surviving finding
or a named external standard.

**Source:** external — consumed from
[`mif-docs-plugin`](https://github.com/modeled-information-format/mif-docs-plugin)'s
`ai-architecture-doc`, `kiro-requirements`, `kiro-design`, `kiro-tasks`, and
`feature-spec` skills (SHA-pinned via `harness.config.json`
`marketplaces[]`), not bundled `packs/genres/` directories. Retired their
bundled equivalents (research-harness-template#409), completing this
family's consolidation onto `mif-docs` as the single genre and conformance
authority per ADR-0018 — the same pattern research-harness-template#228
already applied to the report genres (`docs/reference/packs/reports.md`).
Frontmatter authoring and conformance go through `mif-docs`' shared
`mif-frontmatter` / `mif-validate` substrate.

## ai-architecture-doc

The arc42/C4 genre. Fixes a §1–§12 taxonomy (introduction and goals,
constraints, context and scope, solution strategy, building-block and
runtime views, decisions-with-alternatives, evidence base, risks) and
expresses acceptance criteria in EARS. Use when the deliverable defines a
**structure**: cross-cutting types, relationships, and namespaces. Consumed
by the `ai-spec` channel.

## kiro-requirements

Part of the Kiro three-document genre set (previously one bundled
`kiro-spec` pack; now three independently selectable `mif-docs-plugin`
skills, matching how the plugin itself ships them —
research-harness-template#409). The numbered requirements document for a
**single feature** with a clear task decomposition, each requirement
expressed as an EARS acceptance criterion drawn from the goal's completion
checks. Consumed by the `ai-spec` channel.

## kiro-design

The technical design document for the same single feature, traced back to
its `kiro-requirements`. Consumed by the `ai-spec` channel.

## kiro-tasks

The implementation task list for the same single feature, decomposed from
its `kiro-design`. Consumed by the `ai-spec` channel.

## feature-spec

The GitHub Spec Kit single-capability genre. Use when the deliverable
defines **one capability** authored for a coding agent (summary, motivation,
behaviour, EARS acceptance criteria, out of scope). Consumed by the
`ai-spec` channel.

## Enable

```bash
bash scripts/pack-toggle.sh ai-architecture-doc on
bash scripts/pack-toggle.sh ai-spec on
bash scripts/sync-packs.sh
```
