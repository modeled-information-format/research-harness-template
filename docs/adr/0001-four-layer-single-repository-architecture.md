---
title: "Four-layer single-repository architecture"
description: "Ship the engine, contracts, harness services, and outputs as four layers inside one repository so a clone is a complete harness."
type: adr
category: architecture
tags: [architecture, packaging, single-repo, claude-code, distribution]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [Claude Code, Copier, JSON Schema]
audience: [developers, architects]
related: [0002-mif-level-3-io-conformance.md, 0005-packs-and-plugins-extension-model.md]
---

# ADR-0001: Four-layer single-repository architecture

## Status

Accepted

## Context

### Background and Problem Statement

A research harness must package the orchestration engine, the methodology skills,
the contracts, the knowledge graph, and the output pipelines into something a
user can clone (or instantiate with Copier) and use immediately. The question is
where the boundary between the engine and the harness services should fall:
across repositories, or inside one (`docs/explanation/architecture.md`, design
spec §1, §3).

### Current Limitations

The defining defect of the prior system was that the capability was split across
two repositories that had to be assembled by hand: the engine (a Claude Code
plugin) and the harness layer (a corpus repo). Neither half alone was a research
harness, and the quality-enforcement hooks lived corpus-side, so they did not
travel with the tool on clone.

## Decision Drivers

### Primary Decision Drivers

1. A clone must be a working harness with nothing left to assemble by hand.
2. Enforcement (hooks, gates) must ship and run on clone, not live elsewhere.

### Secondary Decision Drivers

1. The engine/services split should remain legible without a repo boundary.
2. One distribution unit must support both `git clone` and Copier instantiation.

## Considered Options

### Option 1: Two repositories (engine plugin + corpus repo)

**Description:** Keep the prior system's shape — the engine ships as a Claude Code plugin in one repo and the corpus/harness layer lives in a second repo, assembled together by the user.

- **Advantages:** Each half can be released on its own cadence and versioned independently.
- **Disadvantages:** Neither half is a harness alone; assembly is manual and error-prone, and enforcement hooks stay corpus-side and do not travel with the tool.
- **Risk Assessment:** technical low; schedule low; ecosystem high (reproduces the assembly defect).

### Option 2: Single repository, four internal layers

**Description:** Ship Engine, Contracts, Harness services, and Outputs as four layers inside one repository, all present on clone, with the engine/services boundary as a module boundary inside the repo.

- **Advantages:** The whole harness ships on clone; bundled hooks under `.claude/hooks/` travel with the engine; `harness.config.json` is the single deploy contract a user edits.
- **Disadvantages:** The engine cannot be versioned fully independently of the corpus.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

### Option 3: Monorepo of many published packages

**Description:** Split each layer into an independently versioned and released package within a monorepo.

- **Advantages:** Maximal independent versioning of each layer.
- **Disadvantages:** Reintroduces the assembly problem and demands heavy release tooling for a single-author template.
- **Risk Assessment:** technical high; schedule high; ecosystem medium.

## Decision

Adopt **Option 2: a single repository with four internal layers.** The
repository ships four layers on clone — Engine (`.claude/agents/` +
`.claude/commands/`), Contracts (`schemas/`), Harness services (multi-topic
registry, knowledge graph, search, discovery, reindex), and Outputs
(`reports/`, channels, packs). The engine↔services boundary is a module boundary
inside one repo (§6a), and enforcement hooks ship under `.claude/hooks/`.

## Consequences

### Positive

1. A clone is immediately a complete harness; enforcement is portable because it
   travels with the engine.
2. `harness.config.json` is the single deploy contract a user edits.

### Negative

1. The engine is not independently releasable from the corpus.

### Neutral

1. The engine/services split is preserved as a module boundary rather than a repo
   boundary — the same separation, expressed differently.

## Decision Outcome

The four-layer single repository eliminates the manual-assembly defect of the
prior two-repo system: everything needed to research, verify, and publish ships
on clone. The loss of independent engine versioning is the deliberate trade that
buys portability of both capability and enforcement.

## Related Decisions

- [ADR-0002: MIF Level-3 I/O conformance](0002-mif-level-3-io-conformance.md)
- [ADR-0005: Packs and plugins extension model](0005-packs-and-plugins-extension-model.md)

## Links

- `docs/explanation/architecture.md`
- `README.md`

## More Information

- **Date:** 2026-06-23
- **Source:** `docs/explanation/architecture.md`, `README.md`

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Engine layer ships on clone | `.claude/agents/`, `.claude/commands/` | compliant |
| Contracts layer ships on clone | `schemas/` | compliant |
| Single deploy contract present | `harness.config.json`, `harness.config.schema.json` | compliant |
| Enforcement travels with the engine | `.claude/hooks/` | compliant |

**Summary:** All four layers and the bundled hooks are present in the repository on clone.

**Action Required:** None
