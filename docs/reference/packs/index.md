---
diataxis_type: reference
---

# Packs Reference

Packs extend the research harness with domain knowledge, output channels, and data vocabularies.
Each pack is a self-contained unit: one plugin per skill, with its own `.claude-plugin/plugin.json` and `SKILL.md`.
Ontology packs use `*.ontology.yaml` and `ontology.pack.json` instead of a skill.

For control-plane mechanics — enabling, disabling, and listing packs — see
[Packs and Plugins](../packs-and-plugins.md).

## Pack inventory

| Name | Family | Kind | Purpose | External dependencies |
| --- | --- | --- | --- | --- |
| book | channels | channel | Renders surviving findings as a book chapter or full manuscript | none |
| diataxis | channels | channel | Emits a Diátaxis documentation site from the findings corpus | jq |
| github-discuss | channels | channel | Posts findings-grounded GitHub Discussions threads | gh, jq |
| github-issues | channels | channel | Files categorized GitHub Issues from findings | gh, jq |
| notebooklm | channels | channel | Adds findings to a NotebookLM notebook and exports assets | nlm, jq, python3 |
| pdf | channels | channel | Produces a self-contained PDF report via pandoc | pandoc + PDF engine, @mermaid-js/mermaid-cli (optional), jq |
| competitive-analysis | market-research | methodology | Porter's 5 Forces, competitor matrix, and positioning map | @mermaid-js/mermaid-cli (optional) |
| customer-research | market-research | methodology | Persona, JTBD, journey mapping, and segmentation | none |
| financial-analysis | market-research | methodology | Unit economics, SaaS benchmarks, and revenue-model analysis | none |
| market-sizing | market-research | methodology | TAM / SAM / SOM sizing across three methodologies | none |
| regulatory-review | market-research | methodology | Regulatory landscape, risk matrix, and penalty ranges | none |
| academic | reports | genre | Peer-review-style academic paper | none |
| briefing | reports | genre | One-page decision brief | none |
| engineering | reports | genre | Technical engineering report with comparison tables | @mermaid-js/mermaid-cli (optional) |
| exec-summary | reports | genre | 1-2 page BLUF executive summary | none |
| humanities-mla | reports | genre | Argumentative humanities essay (MLA author-page, Works Cited) | none |
| trend-analysis | reports | genre | Trajectory report with scenario diagrams | @mermaid-js/mermaid-cli (optional) |
| trend-modeling | trend-modeling | methodology | Three-valued logic (INC/DEC/CONST) scenario modeling | @mermaid-js/mermaid-cli (optional) |
| biology-research-lab | ontologies | ontology | Full research lab lifecycle entity vocabulary | none |
| data-engineering | ontologies | ontology | Data engineering domain entity vocabulary | none |
| market-research | ontologies | ontology | Market and competitive research entity vocabulary | none |
| regenerative-agriculture | ontologies | ontology | Farm business operations entity vocabulary | none |
| regenerative-agriculture-research | ontologies | ontology | Regenerative agriculture research entity vocabulary | none |
| regulatory-legal | ontologies | ontology | Regulatory and legal domain entity vocabulary | none |
| scientific | ontologies | ontology | Scientific research and data-provenance entity vocabulary | none |
| security | ontologies | ontology | Security threat-intelligence and compliance entity vocabulary | none |
| software-engineering | ontologies | ontology | Software engineering entity vocabulary | none |
| trend-analysis | ontologies | ontology | Strategic foresight and trend-analysis entity vocabulary | none |

## Family pages

- [Channel packs](channels.md) — output delivery channels (book, diataxis, github-discuss, github-issues, notebooklm, pdf)
- [Market-research packs](market-research.md) — research methodology dimensions
- [Report packs](reports.md) — deliverable genre templates
- [Trend-modeling pack](trend-modeling.md) — three-valued logic scenario framework
- [Ontology packs](ontologies.md) — domain entity vocabularies
