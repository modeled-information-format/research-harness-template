---
title: "Architectural Decision Records"
---

# Architectural Decision Records

This directory records the architectural decisions behind the research-harness
template, using the [Structured MADR (SMADR)](https://github.com/modeled-information-format/structured-madr)
format — MADR enriched with structured YAML frontmatter, per-option risk
assessment, and an audit trail. Each record captures one decision: its context,
the options weighed, the outcome, the consequences, and an audit of how the
decision is realized in the repository. Records are immutable once accepted; a
reversal is a new record that supersedes the old one.

Start a new record from [`template.md`](template.md), numbered sequentially.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-four-layer-single-repository-architecture.md) | Four-layer single-repository architecture | accepted |
| [0002](0002-mif-level-3-io-conformance.md) | MIF Level-3 I/O conformance as the harness substrate | accepted |
| [0003](0003-config-declared-research-dimensions.md) | Domain-general, config-declared research dimensions | accepted |
| [0004](0004-single-adversarial-falsification-gate.md) | Single adversarial falsification gate with ordinal verdicts | accepted |
| [0005](0005-packs-and-plugins-extension-model.md) | Packs and plugins as the only extension surface | accepted |
| [0006](0006-content-hashed-append-only-goal-versioning.md) | Content-hashed, append-only goal versioning | proposed |
| [0007](0007-report-channel-canonical-blog-mif-exempt.md) | Canonical report channel as L3 source of truth; blog channel MIF-exempt | accepted |
| [0008](0008-attested-fail-closed-supply-chain.md) | Attested delivery and fail-closed supply-chain verification | accepted |
| [0009](0009-site-renders-full-instance-corpus.md) | The Astro/Starlight site renders the full instance corpus | accepted |
| [0010](0010-change-driven-component-versioning.md) | Change-driven component versioning | accepted |
| [0011](0011-fail-closed-ontology-completeness-gate.md) | Fail-closed ontology-completeness gate before synthesis | accepted |
| [0012](0012-on-demand-ontology-vendoring.md) | On-demand ontology vendoring from a canonical registry | accepted |
| [0013](0013-configurable-site-base-path.md) | Configurable site base path | accepted |
