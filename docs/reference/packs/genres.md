---
title: "Reference: genre packs"
diataxis_type: reference
---

# Genre packs

Spec-genre packs (`packs/genres/`) define the *shape* of an AI-ready, agent-executable
specification; the `ai-spec` channel renders them. Each is optional and toggle-ready
(`enabled:false`). Choose by what the deliverable defines.

| Genre | Use when the deliverable defines | Form |
| --- | --- | --- |
| `architecture-spec` | a **structure** (cross-cutting types, relationships, namespaces) | arc42/C4 §1–§12 + EARS |
| `kiro-spec` | a **single feature** with a clear task decomposition | requirements → design → tasks + EARS |
| `feature-spec` | **one capability** authored for a coding agent | Spec Kit single-feature + EARS |

All three express acceptance criteria in **EARS** (`WHEN … SHALL …` + the goal check's verify
command), and ground every design claim in a surviving finding or a named external standard. The
`architecture-spec` template is self-demonstrating: its own §1–§12 taxonomy is an architecture spec.

## architecture-spec

**Source:** [`packs/genres/architecture-spec/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/genres/architecture-spec)

The arc42/C4 genre. Fixes a §1–§12 taxonomy (introduction and goals, constraints, context and
scope, solution strategy, building-block and runtime views, decisions-with-alternatives, evidence
base, risks) and expresses acceptance criteria in EARS. Use when the deliverable defines a
**structure**: cross-cutting types, relationships, and namespaces. Consumed by the `ai-spec`
channel.

## kiro-spec

**Source:** [`packs/genres/kiro-spec/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/genres/kiro-spec)

The Kiro three-part genre (requirements, design, tasks). Use when the deliverable defines a
**single feature** with a clear task decomposition; acceptance criteria are EARS drawn from the
goal's completion checks. Consumed by the `ai-spec` channel.

## feature-spec

**Source:** [`packs/genres/feature-spec/`](https://github.com/modeled-information-format/research-harness-template/tree/main/packs/genres/feature-spec)

The GitHub Spec Kit single-capability genre. Use when the deliverable defines **one capability**
authored for a coding agent (summary, motivation, behaviour, EARS acceptance criteria, out of
scope). Consumed by the `ai-spec` channel.

## Enable

```bash
bash scripts/pack-toggle.sh architecture-spec on
bash scripts/pack-toggle.sh ai-spec on
bash scripts/sync-packs.sh
```
