---
title: "Domain-general, config-declared research dimensions"
description: "Read research dimensions from harness.config.json rather than hardwiring a domain taxonomy into the engine."
type: adr
category: architecture
tags: [domain-general, configuration, dimensions, orchestration, manifest]
status: accepted
created: 2026-06-23
updated: 2026-06-23
author: zircote
project: research-harness-template
technologies: [JSON Schema, Claude Code]
audience: [developers, architects]
related: [0006-content-hashed-append-only-goal-versioning.md, 0005-packs-and-plugins-extension-model.md]
---

# ADR-0003: Domain-general, config-declared research dimensions

## Status

Accepted

## Context

### Background and Problem Statement

A research harness fans out across "dimensions" of inquiry. The template must
research anything — software architecture, regenerative agriculture, K-12
publishing — without the engine carrying a fixed domain vocabulary. The question
is where the dimensions a session analyzes come from (`harness.config.json`
`dimensions[]`, the `dimension-analyst` agent).

### Current Limitations

The prior generation hardwired a market-research taxonomy into the engine, which
made the tool unusable outside that one domain.

## Decision Drivers

### Primary Decision Drivers

1. The core must be domain-general; no domain taxonomy may be hardwired.
2. A clone should change its research lens by editing one file, not the engine.

### Secondary Decision Drivers

1. The orchestrator and the `dimension-analyst` must read dimensions, not embed
   them.
2. The default set should be sensible but fully overridable.

## Considered Options

### Option 1: Hardcoded dimension taxonomy

**Description:** Embed a fixed set of dimensions (e.g. market-research dimensions) directly in the engine.

- **Advantages:** Zero configuration for the one domain it targets.
- **Disadvantages:** Couples the engine to a domain and reproduces the prior system's central limitation.
- **Risk Assessment:** technical low; schedule low; ecosystem high.

### Option 2: Config-declared dimensions

**Description:** Read dimensions from `harness.config.json` `dimensions[]`; parameterize the `dimension-analyst` by a dimension id resolved at run time.

- **Advantages:** `dimensions[]` is the single control surface; the default ships `technical`, `landscape`, `trajectory`, each with a description, and a clone replaces them wholesale; the analyst resolves methodology (a pack skill if pack-provided, else general web research) rather than a fixed taxonomy.
- **Disadvantages:** A misconfigured `dimensions[]` yields a thin or skewed run.
- **Risk Assessment:** technical low; schedule low; ecosystem low.

### Option 3: Per-session free-form dimensions

**Description:** Invent dimensions ad hoc at run time with no manifest declaration.

- **Advantages:** Maximally flexible per run.
- **Disadvantages:** Nothing is declarative or reviewable; the goal contract and the manifest lose a stable reference, undermining verifiability.
- **Risk Assessment:** technical medium; schedule low; ecosystem medium.

## Decision

Adopt **Option 2: config-declared dimensions.** Dimensions are read from
`harness.config.json` `dimensions[]`. The orchestrator fans out one
`dimension-analyst` per declared dimension, and the goal schema's `dimensions[]`
references those same ids. The shipped default (`technical`, `landscape`,
`trajectory`) is illustrative, not canonical.

## Consequences

### Positive

1. The harness is domain-general and re-targeted by editing one manifest array.
2. The goal contract, orchestrator, and analysts agree on dimension identity by
   config, not by code.

### Negative

1. The quality of a run depends on how well the clone declares its dimensions.

### Neutral

1. The shipped defaults serve as an example only and are expected to be replaced.

## Decision Outcome

Config-declared dimensions keep the engine domain-general while making the
research lens a one-file edit. The dependence on good configuration is inherent
to a domain-general tool and is mitigated by shipping a sensible default set and
schema validation of the manifest.

## Related Decisions

- [ADR-0005: Packs and plugins extension model](0005-packs-and-plugins-extension-model.md)
- [ADR-0006: Content-hashed, append-only goal versioning](0006-content-hashed-append-only-goal-versioning.md)

## Links

- `harness.config.json`
- `schemas/goal.schema.json`

## More Information

- **Date:** 2026-06-23
- **Source:** `harness.config.json`, `schemas/goal.schema.json`

## Audit

### 2026-06-23

**Status:** Compliant

**Findings:**

| Finding | Files | Assessment |
| --- | --- | --- |
| Dimensions declared in the manifest | `harness.config.json` (`dimensions[]`) | compliant |
| Goal schema references dimension ids | `schemas/goal.schema.json` (`dimensions[]`) | compliant |
| Manifest validated by schema | `harness.config.schema.json` | compliant |

**Summary:** Dimensions are declared in `harness.config.json` and referenced by the goal schema; the manifest is schema-validated.

**Action Required:** None
