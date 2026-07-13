---
title: "Packs and plugins as the only extension surface"
description: "Ship every optional capability as a one-skill Claude Code plugin, toggled in harness.config.json and distributed via the marketplace."
type: adr
category: architecture
tags: [plugins, packs, extensibility, marketplace, configuration]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [Claude Code, JSON Schema, Copier]
audience: [developers, architects]
related: [0001-four-layer-single-repository-architecture.md, 0003-config-declared-research-dimensions.md]
---

# ADR-0005: Packs and plugins as the only extension surface

## Status

Accepted

## Context

### Background and Problem Statement

The core researches anything, but real use needs optional capabilities: render
channels (book, diataxis, pdf, notebooklm, github-discuss, github-issues), deliverable genres
(engineering, exec-summary, academic, briefing, trend-analysis), domain
methodologies (competitive-analysis, market-sizing), and domain ontologies. The
question is how optional capabilities are packaged, toggled, and distributed
(`docs/explanation/pack-structure.md`,
`docs/explanation/architecture.md` §7b).

### Current Limitations

If these capabilities are baked into the core, the core stops being
domain-general; if they are unstructured add-ons, selective adoption and clean
distribution break down.

## Decision Drivers

### Primary Decision Drivers

1. The core must hardwire no domain, genre, channel, or vocabulary.
2. A clone must adopt one capability without inheriting a whole bundle.

### Secondary Decision Drivers

1. Capabilities must be distributable, including external/private ones.
2. Enabling or disabling a capability must be a single declarative edit.

## Considered Options

### Option 1: Bake capabilities into the core

**Description:** Embed channels, genres, and methodologies in the core behind feature flags.

- **Advantages:** Nothing to install — everything is present.
- **Disadvantages:** The core re-acquires domain coupling, the exact failure mode ADR-0003 avoids for dimensions.
- **Risk Assessment:** technical medium; schedule low; ecosystem high.

### Option 2: Coarse packs (one plugin per family)

**Description:** Package each family (channels, reports, market-research) as a single plugin adopted all-or-nothing.

- **Advantages:** Fewer plugins to register and maintain.
- **Disadvantages:** A clone wanting only `exec-summary` is forced to adopt the entire `reports` family; selective adoption is lost.
- **Risk Assessment:** technical low; schedule low; ecosystem medium.

### Option 3: One plugin per skill

**Description:** Each `packs/<family>/<skill>/` is a self-contained Claude Code plugin containing exactly one skill, grouped into families by directory, toggled in `harness.config.json` `packs[]` and distributed via the marketplace.

- **Advantages:** Selective adoption is exact (enable one skill, leave siblings disabled); each plugin's `.claude-plugin/plugin.json` is validated against `schemas/pack.schema.json`; the `packs[]` control plane lists each by bare name with `enabled` and `source`; `scripts/sync-packs.sh` materializes enabled plugins into Claude Code's native `enabledPlugins`, `scripts/pack-toggle.sh` flips one; external/private plugins ingest the same way.
- **Disadvantages:** Many small plugins mean more registry entries to maintain.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

## Decision

Adopt **Option 3: one plugin per skill.** Every optional channel, genre,
methodology, and ontology ships as a plugin containing exactly one skill, grouped
into pack families by directory (the families themselves are containers, not
plugins). `harness.config.json` `packs[]` toggles each; packs compose with the
core and never patch it. Distribution is the Claude Code plugin marketplace
(`.claude-plugin/marketplace.json`) over the Copier living template. By default
the five `reports` genres are enabled and every other plugin is opt-in.

## Consequences

### Positive

1. Selective adoption is exact, and external/private plugins ingest the same way.
2. The extension surface is uniform across all families.

### Negative

1. The marketplace manifest and per-plugin `plugin.json` files multiply.

### Neutral

1. The default-enabled set (five `reports` genres) defines an opinionated
   starting point that a clone can change freely.

## Decision Outcome

A one-plugin-per-skill model keeps the core domain-general while making every
capability individually adoptable, distributable, and toggled by a single
manifest edit. The cost is more registry entries, contained by schema-validated
`plugin.json` files and the marketplace manifest.

## Related Decisions

- [ADR-0001: Four-layer single-repository architecture](0001-four-layer-single-repository-architecture.md)
- [ADR-0003: Domain-general, config-declared research dimensions](0003-config-declared-research-dimensions.md)

## Links

- `docs/explanation/pack-structure.md`
- `.claude-plugin/marketplace.json`
- `harness.config.json`

## More Information

- **Date:** 2026-06-23
- **Source:** `docs/explanation/pack-structure.md`, `.claude-plugin/marketplace.json`, `harness.config.json`

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Pack control plane declared | `harness.config.json` (`packs[]`) | compliant |
| Marketplace lists per-skill plugins | `.claude-plugin/marketplace.json` | compliant |
| Pack contract schema present | `schemas/pack.schema.json` | compliant |
| Plugins live under pack families | `packs/` | compliant |

**Summary:** The `packs[]` control plane, the marketplace manifest, the pack contract schema, and the `packs/` tree all exist and reflect the one-plugin-per-skill model.

**Action Required:** None
