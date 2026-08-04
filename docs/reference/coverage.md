---
id: reference-coverage
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-23T23:49:53.330Z'
namespace: docs/reference
tags:
  - documentation
  - reference
title: "Reference: documentation coverage"
diataxis_type: reference
temporal:
  '@type': TemporalMetadata
  validFrom: '2026-06-24T10:25:46-04:00'
  ttl: P6M
  recordedAt: '2026-06-24T10:25:46-04:00'
provenance:
  '@type': Provenance
  agent: claude-code/claude-sonnet-5
  wasGeneratedBy:
    '@id': urn:mif:activity:claude-code-session:526419e5-77d7-4f96-a34a-22d8d5baa46f
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.218
---

# Reference: documentation coverage

This page is the audit index for the harness's adoptable surface. Every pack,
core skill, command, agent, and script discoverable in the repository appears
below with a link to where it is documented. The counts at the end assert that
the **discovered** set equals the **documented** set.

## Coverage summary

| Category | Discovered | Documented | Source of truth |
| --- | --- | --- | --- |
| Packs | 77 | 77 | `harness.config.json` `packs[]` + `ontologies[]` |
| Core skills | 10 | 10 | `.claude/skills/*/SKILL.md` |
| Commands | 12 | 12 | `.claude/commands/*.md` |
| Agents | 7 | 7 | `.claude/agents/*.md` |
| Scripts | 58 | 58 | `scripts/**` (excludes `__pycache__`); the 24 scripts Epic #416 added moved to `packs/monitoring/continuous-monitor/scripts/**` (research-harness-template#483) and are documented in [../packs/monitoring/](../packs/monitoring/), not counted here |
| **Total** | **164** | **164** | — |

Reproduce the discovered counts:

```sh
echo $(( $(jq '.packs | length' harness.config.json) + $(jq '.ontologies | length' harness.config.json) )) # 77 packs
ls .claude/skills | wc -l        # 10 core skills
ls .claude/commands/*.md | wc -l # 12 commands
ls .claude/agents/*.md | wc -l   # 7 agents
find scripts -type f \( -name '*.sh' -o -name '*.py' -o -name '*.jq' \) \
  | grep -v __pycache__ | wc -l  # 58 scripts
```

Domain ontology packs are vendored on demand (ADR-0012) — `packs/ontologies/`
may be empty on a fresh clone until `scripts/fetch-ontology.sh --all-enabled`
runs. `harness.config.json` `ontologies[]` is the enabled/declared set and the
authoritative count either way.

## Packs (77)

Plugin packs (54, registered in `harness.config.json` `packs[]`):

| Pack | Family | Documented in |
| --- | --- | --- |
| book | channels | [packs/channels.md](../packs/channels/#book) |
| diataxis | channels | [packs/channels.md](../packs/channels/#diataxis) |
| github-discuss | channels | [packs/channels.md](../packs/channels/#github-discuss) |
| github-issues | channels | [packs/channels.md](../packs/channels/#github-issues) |
| jats | channels | [packs/channels.md](../packs/channels/#jats) |
| notebooklm | channels | [packs/channels.md](../packs/channels/#notebooklm) |
| pdf | channels | [packs/channels.md](../packs/channels/#pdf) |
| xbrl | channels | [packs/channels.md](../packs/channels/#xbrl) |
| ectd | channels | [packs/channels.md](../packs/channels/#ectd) |
| ai-spec | channels | [packs/channels.md](../packs/channels/#ai-spec) |
| competitive-analysis | market-research | [packs/market-research.md](../packs/market-research/#competitive-analysis) |
| customer-research | market-research | [packs/market-research.md](../packs/market-research/#customer-research) |
| financial-analysis | market-research | [packs/market-research.md](../packs/market-research/#financial-analysis) |
| market-sizing | market-research | [packs/market-research.md](../packs/market-research/#market-sizing) |
| regulatory-review | market-research | [packs/market-research.md](../packs/market-research/#regulatory-review) |
| ai-architecture-doc | genres | [packs/genres.md](../packs/genres/#ai-architecture-doc) |
| kiro-requirements | genres | [packs/genres.md](../packs/genres/#kiro-requirements) |
| kiro-design | genres | [packs/genres.md](../packs/genres/#kiro-design) |
| kiro-tasks | genres | [packs/genres.md](../packs/genres/#kiro-tasks) |
| feature-spec | genres | [packs/genres.md](../packs/genres/#feature-spec) |
| trend-modeling | trend-modeling | [packs/trend-modeling.md](../packs/trend-modeling/#trend-modeling) |
| continuous-monitor | monitoring | [packs/monitoring.md](../packs/monitoring/#continuous-monitor) |
| academic | reports | [packs/reports.md](../packs/reports/#academic) |
| briefing | reports | [packs/reports.md](../packs/reports/#briefing) |
| computing-paper | reports | [packs/reports.md](../packs/reports/#computing-paper) |
| engineering | reports | [packs/reports.md](../packs/reports/#engineering) |
| clinical-submission | reports | [packs/reports.md](../packs/reports/#clinical-submission) |
| exec-summary | reports | [packs/reports.md](../packs/reports/#exec-summary) |
| legal-memo | reports | [packs/reports.md](../packs/reports/#legal-memo) |
| trend-analysis | reports | [packs/reports.md](../packs/reports/#trend-analysis) |
| regulatory-disclosure | reports | [packs/reports.md](../packs/reports/#regulatory-disclosure) |
| sustainability-report | reports | [packs/reports.md](../packs/reports/#sustainability-report) |
| humanities-chicago | reports | [packs/reports.md](../packs/reports/#humanities-chicago) |
| humanities-mla | reports | [packs/reports.md](../packs/reports/#humanities-mla) |
| security-pentest | reports | [packs/reports.md](../packs/reports/#security-pentest) |
| market-research-report | reports | [packs/reports.md](../packs/reports/#market-research-report) |
| systematic-review | reports | [packs/reports.md](../packs/reports/#systematic-review) |
| compliance-audit | reports | [packs/reports.md](../packs/reports/#compliance-audit) |
| competitive-quadrant | reports | [packs/reports.md](../packs/reports/#competitive-quadrant) |
| nist-sp | reports | [packs/reports.md](../packs/reports/#nist-sp) |
| adr | reports | [packs/reports.md](../packs/reports/#adr) |
| arc42-arch-doc | reports | [packs/reports.md](../packs/reports/#arc42-arch-doc) |
| c4-model-diagram | reports | [packs/reports.md](../packs/reports/#c4-model-diagram) |
| changelog | reports | [packs/reports.md](../packs/reports/#changelog) |
| google-design-doc | reports | [packs/reports.md](../packs/reports/#google-design-doc) |
| playbook | reports | [packs/reports.md](../packs/reports/#playbook) |
| prd | reports | [packs/reports.md](../packs/reports/#prd) |
| python-pep | reports | [packs/reports.md](../packs/reports/#python-pep) |
| rust-rfc | reports | [packs/reports.md](../packs/reports/#rust-rfc) |
| sre-runbook | reports | [packs/reports.md](../packs/reports/#sre-runbook) |
| diataxis-explanation | reports | [packs/reports.md](../packs/reports/#diataxis-explanation) |
| diataxis-how-to | reports | [packs/reports.md](../packs/reports/#diataxis-how-to) |
| diataxis-reference | reports | [packs/reports.md](../packs/reports/#diataxis-reference) |
| diataxis-tutorial | reports | [packs/reports.md](../packs/reports/#diataxis-tutorial) |

Ontology data packs (23, enabled in `harness.config.json` `ontologies[]`,
vendored on demand per ADR-0012 — `packs/ontologies/` isn't a bundled
directory and may be absent on a fresh, unvendored clone, see
[Ontology packs](../packs/ontologies/)):

| Pack | Documented in |
| --- | --- |
| biology-research-lab | [packs/ontologies.md](../packs/ontologies/#biology-research-lab) |
| cardiology | [packs/ontologies.md](../packs/ontologies/#cardiology) |
| clinical-health-base | [packs/ontologies.md](../packs/ontologies/#clinical-health-base) |
| cosmology | [packs/ontologies.md](../packs/ontologies/#cosmology) |
| data-engineering | [packs/ontologies.md](../packs/ontologies/#data-engineering) |
| fitness | [packs/ontologies.md](../packs/ontologies/#fitness) |
| health | [packs/ontologies.md](../packs/ontologies/#health) |
| heliophysics | [packs/ontologies.md](../packs/ontologies/#heliophysics) |
| market-research | [packs/ontologies.md](../packs/ontologies/#market-research) |
| mif-docs | [packs/ontologies.md](../packs/ontologies/#mif-docs) |
| non-ionizing-radiation | [packs/ontologies.md](../packs/ontologies/#non-ionizing-radiation) |
| observability | [packs/ontologies.md](../packs/ontologies/#observability) |
| physical-science-base | [packs/ontologies.md](../packs/ontologies/#physical-science-base) |
| plasma-physics | [packs/ontologies.md](../packs/ontologies/#plasma-physics) |
| platform-engineering | [packs/ontologies.md](../packs/ontologies/#platform-engineering) |
| psycholinguistics | [packs/ontologies.md](../packs/ontologies/#psycholinguistics) |
| regenerative-agriculture | [packs/ontologies.md](../packs/ontologies/#regenerative-agriculture) |
| regenerative-agriculture-research | [packs/ontologies.md](../packs/ontologies/#regenerative-agriculture-research) |
| regulatory-legal | [packs/ontologies.md](../packs/ontologies/#regulatory-legal) |
| scientific | [packs/ontologies.md](../packs/ontologies/#scientific) |
| software-engineering | [packs/ontologies.md](../packs/ontologies/#software-engineering) |
| software-security | [packs/ontologies.md](../packs/ontologies/#software-security) |
| trend-analysis | [packs/ontologies.md](../packs/ontologies/#trend-analysis) |

## Core skills (10)

All documented in [../core-skills/](../core-skills/): `discover`, `graph`, `lab`,
`md-fix`, `ontology-manager`, `publish-blog`, `publish-report`, `readme`,
`search`, `topics`.

## Commands (12)

All documented in [../commands/](../commands/): `/configure`, `/export`,
`/falsify`, `/goal-writer`, `/import`, `/ontology-review`, `/research`,
`/resume`, `/start`, `/status`, `/synthesize-corpus`, `/topics`.

## Agents (7)

All documented in [../agents/](../agents/): `orchestrator`, `dimension-analyst`,
`falsification-analyst`, `report-synthesizer`, `corpus-synthesizer`,
`harness-configurator`, `source-chunker`.

## Scripts (58)

All documented in [../scripts/](../scripts/):
`assert-graph-mif`,
`author-ontology`, `backfill-report-slugs`, `build-concordance`,
`build-graph-viz`, `build-graph`, `build-index`, `build-topic-readme`,
`bump-version`, `check-citation-integrity`, `check-mermaid.py`,
`check-coverage-doc.py`, `check-fetch-engine-gh-token`, `check-ontology-lock`, `check-pack-docs.py`, `check-relationship-targets`,
`check-shippable-typing`, `check-version-bump`, `check-workflow-forbidden-globals`, `check-workflow-syntax`,
`codegen/bundle_schema.py`,
`codegen/gen-models`, `falsify`, `fetch-engine`, `fetch-mif-docs-plugin`,
`fetch-ontology`, `goal-version`, `import-corpus`, `install-hooks`,
`install-monitoring-workflows`,
`lib/container-lock`, `lib/engine`, `lib/unreadable-probe`, `lint-goal`, `mif-container-detect-sameas`,
`mif-container-digest`, `mif-container-export`, `mif-container-import`,
`mif-container-migration-eval-bench`, `mif-container-resolve-scope`,
`mif-project`, `ontology-review`, `pack-toggle`, `reconcile-session`,
`render-artifact`, `resolve-membership`, `resolve-ontology`, `run-lock`,
`site-toggle`, `sync-packs`, `sync-registry-ontologies`,
`synthesize-artifact`, `synthesize-corpus`, `update`, `validate-concordance`,
`verify`, `wrap-source`, `write-finding`.

The 24 scripts Epic #416 added for continuous monitoring moved to
`packs/monitoring/continuous-monitor/scripts/**` (research-harness-template#483) —
they are pack-owned now, documented in [../packs/monitoring/](../packs/monitoring/)
rather than counted in this core-scripts inventory, the same way
`packs/channels/diataxis/scripts/render-diataxis.sh` was never counted here.

## Assertion

Discovered (164) equals documented (164) across all five categories. No pack,
skill, command, agent, or script is omitted.
