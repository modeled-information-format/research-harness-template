---
id: reference-coverage
type: semantic
created: '2026-06-24T10:25:46-04:00'
modified: '2026-07-12T21:38:12.254Z'
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
    '@id': urn:mif:activity:claude-code-session:581ee0b6-ce7b-4099-a6dd-2fbb44ce2e1c
    '@type': prov:Activity
  trustLevel: user_stated
  agentVersion: 2.1.207
---

# Reference: documentation coverage

This page is the audit index for the harness's adoptable surface. Every pack,
core skill, command, agent, and script discoverable in the repository appears
below with a link to where it is documented. The counts at the end assert that
the **discovered** set equals the **documented** set.

## Coverage summary

| Category | Discovered | Documented | Source of truth |
| --- | --- | --- | --- |
| Packs | 62 | 58 | `harness.config.json` `packs[]` + `packs/ontologies/` — stale, see #481 |
| Core skills | 10 | 10 | `.claude/skills/*/SKILL.md` |
| Commands | 11 | 9 | `.claude/commands/*.md` — stale, see #481 |
| Agents | 7 | 7 | `.claude/agents/*.md` |
| Scripts | 74 | 65 | `scripts/**` (excludes `__pycache__`) — the 9-script gap predates Epic #416 and shares #481's root cause; the 23 scripts Epic #416 added (`scripts/monitoring/**`) are fully itemized below |
| **Total** | **164** | **149** | — |

Reproduce the discovered counts:

```sh
echo $(( $(jq '.packs | length' harness.config.json) + $(jq '.ontologies | length' harness.config.json) )) # 62 packs
ls .claude/skills | wc -l        # 10 core skills
ls .claude/commands/*.md | wc -l # 11 commands
ls .claude/agents/*.md | wc -l   # 7 agents
find scripts -type f \( -name '*.sh' -o -name '*.py' -o -name '*.jq' \) \
  | grep -v __pycache__ | wc -l  # 74 scripts
```

Domain ontology packs are vendored on demand (ADR-0012) — `packs/ontologies/`
may be empty on a fresh clone until `scripts/fetch-ontology.sh --all-enabled`
runs. `harness.config.json` `ontologies[]` is the enabled/declared set and the
authoritative count either way.

## Packs (58)

Plugin packs (37, registered in `harness.config.json` `packs[]`):

| Pack | Family | Documented in |
| --- | --- | --- |
| book | channels | [packs/channels.md](packs/channels.md#book) |
| diataxis | channels | [packs/channels.md](packs/channels.md#diataxis) |
| github-discuss | channels | [packs/channels.md](packs/channels.md#github-discuss) |
| github-issues | channels | [packs/channels.md](packs/channels.md#github-issues) |
| jats | channels | [packs/channels.md](packs/channels.md#jats) |
| notebooklm | channels | [packs/channels.md](packs/channels.md#notebooklm) |
| pdf | channels | [packs/channels.md](packs/channels.md#pdf) |
| xbrl | channels | [packs/channels.md](packs/channels.md#xbrl) |
| ectd | channels | [packs/channels.md](packs/channels.md#ectd) |
| ai-spec | channels | [packs/channels.md](packs/channels.md#ai-spec) |
| competitive-analysis | market-research | [packs/market-research.md](packs/market-research.md#competitive-analysis) |
| customer-research | market-research | [packs/market-research.md](packs/market-research.md#customer-research) |
| financial-analysis | market-research | [packs/market-research.md](packs/market-research.md#financial-analysis) |
| market-sizing | market-research | [packs/market-research.md](packs/market-research.md#market-sizing) |
| regulatory-review | market-research | [packs/market-research.md](packs/market-research.md#regulatory-review) |
| ai-architecture-doc | genres | [packs/genres.md](packs/genres.md#ai-architecture-doc) |
| kiro-requirements | genres | [packs/genres.md](packs/genres.md#kiro-requirements) |
| kiro-design | genres | [packs/genres.md](packs/genres.md#kiro-design) |
| kiro-tasks | genres | [packs/genres.md](packs/genres.md#kiro-tasks) |
| feature-spec | genres | [packs/genres.md](packs/genres.md#feature-spec) |
| trend-modeling | trend-modeling | [packs/trend-modeling.md](packs/trend-modeling.md#trend-modeling) |
| academic | reports | [packs/reports.md](packs/reports.md#academic) |
| briefing | reports | [packs/reports.md](packs/reports.md#briefing) |
| computing-paper | reports | [packs/reports.md](packs/reports.md#computing-paper) |
| engineering | reports | [packs/reports.md](packs/reports.md#engineering) |
| clinical-submission | reports | [packs/reports.md](packs/reports.md#clinical-submission) |
| exec-summary | reports | [packs/reports.md](packs/reports.md#exec-summary) |
| legal-memo | reports | [packs/reports.md](packs/reports.md#legal-memo) |
| trend-analysis | reports | [packs/reports.md](packs/reports.md#trend-analysis) |
| regulatory-disclosure | reports | [packs/reports.md](packs/reports.md#regulatory-disclosure) |
| sustainability-report | reports | [packs/reports.md](packs/reports.md#sustainability-report) |
| humanities-chicago | reports | [packs/reports.md](packs/reports.md#humanities-chicago) |
| humanities-mla | reports | [packs/reports.md](packs/reports.md#humanities-mla) |
| security-pentest | reports | [packs/reports.md](packs/reports.md#security-pentest) |
| market-research-report | reports | [packs/reports.md](packs/reports.md#market-research-report) |
| systematic-review | reports | [packs/reports.md](packs/reports.md#systematic-review) |
| compliance-audit | reports | [packs/reports.md](packs/reports.md#compliance-audit) |
| competitive-quadrant | reports | [packs/reports.md](packs/reports.md#competitive-quadrant) |
| nist-sp | reports | [packs/reports.md](packs/reports.md#nist-sp) |

Ontology data packs (21, enabled in `harness.config.json` `ontologies[]`,
vendored under `packs/ontologies/`):

| Pack | Documented in |
| --- | --- |
| biology-research-lab | [packs/ontologies.md](packs/ontologies.md#biology-research-lab) |
| cardiology | [packs/ontologies.md](packs/ontologies.md#cardiology) |
| clinical-health-base | [packs/ontologies.md](packs/ontologies.md#clinical-health-base) |
| cosmology | [packs/ontologies.md](packs/ontologies.md#cosmology) |
| data-engineering | [packs/ontologies.md](packs/ontologies.md#data-engineering) |
| fitness | [packs/ontologies.md](packs/ontologies.md#fitness) |
| health | [packs/ontologies.md](packs/ontologies.md#health) |
| market-research | [packs/ontologies.md](packs/ontologies.md#market-research) |
| mif-docs | [packs/ontologies.md](packs/ontologies.md#mif-docs) |
| observability | [packs/ontologies.md](packs/ontologies.md#observability) |
| physical-science-base | [packs/ontologies.md](packs/ontologies.md#physical-science-base) |
| plasma-physics | [packs/ontologies.md](packs/ontologies.md#plasma-physics) |
| platform-engineering | [packs/ontologies.md](packs/ontologies.md#platform-engineering) |
| psycholinguistics | [packs/ontologies.md](packs/ontologies.md#psycholinguistics) |
| regenerative-agriculture | [packs/ontologies.md](packs/ontologies.md#regenerative-agriculture) |
| regenerative-agriculture-research | [packs/ontologies.md](packs/ontologies.md#regenerative-agriculture-research) |
| regulatory-legal | [packs/ontologies.md](packs/ontologies.md#regulatory-legal) |
| scientific | [packs/ontologies.md](packs/ontologies.md#scientific) |
| software-engineering | [packs/ontologies.md](packs/ontologies.md#software-engineering) |
| software-security | [packs/ontologies.md](packs/ontologies.md#software-security) |
| trend-analysis | [packs/ontologies.md](packs/ontologies.md#trend-analysis) |

## Core skills (10)

All documented in [core-skills.md](core-skills.md): `discover`, `graph`, `lab`,
`md-fix`, `ontology-manager`, `publish-blog`, `publish-report`, `readme`,
`search`, `topics`.

## Commands (9)

All documented in [commands.md](commands.md): `/configure`, `/falsify`,
`/goal-writer`, `/ontology-review`, `/resume`, `/start`, `/status`,
`/synthesize-corpus`, `/topics`.

## Agents (7)

All documented in [agents.md](agents.md): `orchestrator`, `dimension-analyst`,
`falsification-analyst`, `report-synthesizer`, `corpus-synthesizer`,
`harness-configurator`, `source-chunker`.

## Scripts (74 discovered, 65 documented — see #481)

Pre-Epic-#416 baseline, all documented in [scripts.md](scripts.md):
`assert-graph-mif`,
`author-ontology`, `backfill-report-slugs`, `build-concordance`,
`build-graph-viz`, `build-graph`, `build-index`, `build-topic-readme`,
`bump-version`, `check-citation-integrity`, `check-mermaid.py`,
`check-ontology-lock`, `check-pack-docs.py`, `check-relationship-targets`,
`check-shippable-typing`, `check-version-bump`, `codegen/bundle_schema.py`,
`codegen/gen-models`, `falsify`, `fetch-engine`, `fetch-ontology`,
`goal-version`, `import-corpus`, `lib/engine`, `mif-project`,
`ontology-review`, `pack-toggle`, `reconcile-session`, `render-artifact`,
`resolve-membership`, `resolve-ontology`, `run-lock`, `site-toggle`,
`sync-packs`, `sync-registry-ontologies`, `synthesize-artifact`,
`synthesize-corpus`, `update`, `validate-concordance`, `verify`,
`wrap-source`, `write-finding` — 42 named here, though the pre-Epic
baseline is actually 51 (a 9-script gap that predates and is unrelated
to Epic #416, see #481).

Added by Epic #416 (continuous monitoring, all documented in
[scripts.md](scripts.md#continuous-monitoring-epic-416)):
`monitoring/run-monitoring.sh`, `monitoring/run-with-budget.sh`,
`monitoring/interest-inference.sh`, `monitoring/recommend.sh`,
`monitoring/editorial-gate.sh`, `monitoring/output-router.sh`,
`monitoring/run-gate-and-publish.sh`,
`monitoring/connectors/{arxiv,openalex,crossref,semantic-scholar,pubmed,biorxiv,gdelt,hn}.sh`,
`monitoring/lib/connector-common.sh`, `monitoring/lib/continuity-log.sh`,
`monitoring/lib/{editorial_gate,interest_inference,mif_tokenize,recommend,recommendation_to_finding,xml_to_json}.py`
— 23 scripts, fully itemized.

## Assertion

Discovered (126) equals documented (126) across all five categories. No pack,
skill, command, agent, or script is omitted.
