# Research Harness

One distributable template repository that a user clones (or instantiates with
Copier) to get a complete, self-contained research harness: the orchestration
engine, the methodology skills, the workflows, the contracts, the knowledge
graph, multi-topic support, and the research→blog and research→book output
pipelines — all in one package.

## Layout

The repository has four layers, all present on clone (design spec §5):

1. **Engine** — `.claude/agents/` orchestrator + dimension-analyst +
   falsification-analyst + source-chunker + report-synthesizer, and the
   `.claude/commands/` that delegate to them.
2. **Contracts** — `schemas/`: the MIF-backed findings schema, the
   `harness.config.json` manifest schema, the pack contract, and the
   Structured Data Protocol.
3. **Harness services** — multi-topic registry, knowledge graph, search,
   discovery, reindex — operating directly on the MIF substrate.
4. **Outputs** — blog and book are first-class; other channels and all
   deliverable genres arrive as optional **plugins** — one per skill under
   `packs/<family>/<skill>/`, enabled selectively (see
   [docs/explanation/pack-structure.md](docs/explanation/pack-structure.md)).

Cross-cutting: bundled enforcement hooks (`.claude/hooks/`), bundled docs
(`docs/`, Diataxis), and `evals/`.

## The one file you edit

`harness.config.json` is the deploy contract: it declares your topics, research
dimensions, output targets, and which packs are enabled. It is validated by
`harness.config.schema.json`.

## Quality gate

`bash scripts/verify.sh` runs the full build gate (schema validation, the
citation-integrity gate, and each milestone's acceptance gate).
`markdownlint-cli2 "**/*.md"` must report zero errors. Both run in CI on every
push and pull request.

## Documentation

See `docs/` for the merged Diataxis set: tutorials, how-to guides, reference,
and explanation.
