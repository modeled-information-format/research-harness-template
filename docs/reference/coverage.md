---
diataxis_type: reference
---

# Reference: documentation coverage

This page is the audit index for the harness's adoptable surface. Every pack,
core skill, command, agent, and script discoverable in the repository appears
below with a link to where it is documented. The counts at the end assert that
the **discovered** set equals the **documented** set.

## Coverage summary

| Category | Discovered | Documented | Source of truth |
| --- | --- | --- | --- |
| Packs | 25 | 25 | `harness.config.json` `packs[]` (17) + `packs/ontologies/` (8) |
| Core skills | 10 | 10 | `.claude/skills/*/SKILL.md` |
| Commands | 7 | 7 | `.claude/commands/*.md` |
| Agents | 5 | 5 | `.claude/agents/*.md` |
| Scripts | 28 | 28 | `scripts/**` (excludes `__pycache__`) |
| **Total** | **75** | **75** | — |

Reproduce the discovered counts:

```sh
# packs: 17 plugin packs + 8 ontology packs = 25
echo $(( $(jq '.packs | length' harness.config.json) + $(ls -d packs/ontologies/*/ | wc -l) ))
ls .claude/skills | wc -l        # 10 core skills
ls .claude/commands/*.md | wc -l # 7 commands
ls .claude/agents/*.md | wc -l   # 5 agents
find scripts -type f \( -name '*.sh' -o -name '*.py' -o -name '*.jq' \) \
  | grep -v __pycache__ | wc -l  # 28 scripts
```

## Packs (25)

Plugin packs (17, registered in `harness.config.json`):

| Pack | Family | Documented in |
| --- | --- | --- |
| book | channels | [packs/channels.md](packs/channels.md#book) |
| diataxis | channels | [packs/channels.md](packs/channels.md#diataxis) |
| github-discuss | channels | [packs/channels.md](packs/channels.md#github-discuss) |
| github-issues | channels | [packs/channels.md](packs/channels.md#github-issues) |
| notebooklm | channels | [packs/channels.md](packs/channels.md#notebooklm) |
| pdf | channels | [packs/channels.md](packs/channels.md#pdf) |
| competitive-analysis | market-research | [packs/market-research.md](packs/market-research.md#competitive-analysis) |
| customer-research | market-research | [packs/market-research.md](packs/market-research.md#customer-research) |
| financial-analysis | market-research | [packs/market-research.md](packs/market-research.md#financial-analysis) |
| market-sizing | market-research | [packs/market-research.md](packs/market-research.md#market-sizing) |
| regulatory-review | market-research | [packs/market-research.md](packs/market-research.md#regulatory-review) |
| academic | reports | [packs/reports.md](packs/reports.md#academic) |
| briefing | reports | [packs/reports.md](packs/reports.md#briefing) |
| engineering | reports | [packs/reports.md](packs/reports.md#engineering) |
| exec-summary | reports | [packs/reports.md](packs/reports.md#exec-summary) |
| trend-analysis | reports | [packs/reports.md](packs/reports.md#trend-analysis) |
| trend-modeling | trend-modeling | [packs/trend-modeling.md](packs/trend-modeling.md#trend-modeling) |

Ontology data packs (8, under `packs/ontologies/`):

| Pack | Documented in |
| --- | --- |
| backstage | [packs/ontologies.md](packs/ontologies.md#backstage) |
| biology-research-lab | [packs/ontologies.md](packs/ontologies.md#biology-research-lab) |
| csi-5w1h | [packs/ontologies.md](packs/ontologies.md#csi-5w1h) |
| data-engineering | [packs/ontologies.md](packs/ontologies.md#data-engineering) |
| k12-educational-publishing | [packs/ontologies.md](packs/ontologies.md#k12-educational-publishing) |
| regenerative-agriculture | [packs/ontologies.md](packs/ontologies.md#regenerative-agriculture) |
| regenerative-agriculture-research | [packs/ontologies.md](packs/ontologies.md#regenerative-agriculture-research) |
| software-engineering | [packs/ontologies.md](packs/ontologies.md#software-engineering) |

## Core skills (10)

All documented in [core-skills.md](core-skills.md): `discover`, `graph`, `lab`,
`md-fix`, `ontology-manager`, `publish-blog`, `publish-report`, `readme`,
`search`, `topics`.

## Commands (7)

All documented in [commands.md](commands.md): `/falsify`, `/goal-writer`,
`/ontology-review`, `/resume`, `/start`, `/status`, `/topics`.

## Agents (5)

All documented in [agents.md](agents.md): `orchestrator`, `dimension-analyst`,
`falsification-analyst`, `report-synthesizer`, `source-chunker`.

## Scripts (28)

All documented in [scripts.md](scripts.md): `assert-graph-mif`,
`build-concordance`, `build-graph-viz`, `build-graph`, `build-index`,
`build-topic-readme`, `check-citation-integrity`, `codegen/bundle_schema.py`,
`codegen/gen-models`, `convert-sigint-corpus`, `falsify`, `goal-version`,
`import-corpus`, `mif-project`, `ontology-review`, `pack-toggle`,
`reconcile-session`, `render-artifact`, `resolve-membership`,
`resolve-ontology`, `run-lock`, `sigint-to-mif.jq`, `sync-packs`,
`synthesize-artifact`, `validate-concordance`, `verify`, `wrap-source`,
`write-finding`.

## Assertion

Discovered (75) equals documented (75) across all five categories. No pack,
skill, command, agent, or script is omitted.
