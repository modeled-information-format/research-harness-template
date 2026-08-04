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

Start a new record from [`template.md`](../template/), numbered sequentially.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](../0001-four-layer-single-repository-architecture/) | Four-layer single-repository architecture | accepted |
| [0002](../0002-mif-level-3-io-conformance/) | MIF Level-3 I/O conformance as the harness substrate | accepted |
| [0003](../0003-config-declared-research-dimensions/) | Domain-general, config-declared research dimensions | accepted |
| [0004](../0004-single-adversarial-falsification-gate/) | Single adversarial falsification gate with ordinal verdicts | accepted |
| [0005](../0005-packs-and-plugins-extension-model/) | Packs and plugins as the only extension surface | accepted |
| [0006](../0006-content-hashed-append-only-goal-versioning/) | Content-hashed, append-only goal versioning | proposed |
| [0007](../0007-report-channel-canonical-blog-mif-exempt/) | Canonical report channel as L3 source of truth; blog channel MIF-exempt | accepted |
| [0008](../0008-attested-fail-closed-supply-chain/) | Attested delivery and fail-closed supply-chain verification | accepted |
| [0009](../0009-site-renders-full-instance-corpus/) | The Astro/Starlight site renders the full instance corpus | accepted |
| [0010](../0010-change-driven-component-versioning/) | Change-driven component versioning | accepted |
| [0011](../0011-fail-closed-ontology-completeness-gate/) | Fail-closed ontology-completeness gate before synthesis | accepted |
| [0012](../0012-on-demand-ontology-vendoring/) | On-demand ontology vendoring from a canonical registry | accepted |
| [0013](../0013-configurable-site-base-path/) | Configurable site base path | accepted |
| [0014](../0014-compiled-ontology-engine-cli-and-mcp/) | Compiled ontology engine as a scoped CLI+MCP proof-of-concept | accepted |
| [0015](../0015-confidence-tier-consumption-and-scored-suggestion-routing/) | Confidence-tier consumption and scored-suggestion routing | accepted |
| [0016](../0016-engine-only-classification/) | Engine-only classification: hard cutover to mif-rh | accepted |
| [0017](../0017-mif-container-instance-scoped-export-import-format/) | MIF Container: an instance-scoped export/import manifest format | accepted |
| [0018](../0018-mif-docs-plugin-as-document-tooling-substrate/) | mif-docs-plugin as the document-tooling and provenance substrate | accepted |
| [0019](../0019-github-actions-cron-scheduling-primitive/) | GitHub Actions cron as the continuous-monitoring scheduling/trigger primitive | accepted |
