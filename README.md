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
4. **Outputs** — the generic `report` channel is the canonical MIF Level-3 source
   of truth (`reports/<topic>/<slug>.md`); blog and book are first-class published
   projections; other channels and all deliverable genres arrive as optional
   **plugins** — one per skill under `packs/<family>/<skill>/`, enabled selectively
   (see [docs/explanation/pack-structure.md](docs/explanation/pack-structure.md)).
   All information in and out of the harness is MIF (see
   [docs/explanation/mif-io-conformance.md](docs/explanation/mif-io-conformance.md)).
   Findings are typed against per-topic ontologies (an always-on generic core plus
   optional domain ontology packs), enforced deterministically — see
   [docs/explanation/ontology-conformance.md](docs/explanation/ontology-conformance.md).

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
push and pull request. Toolchain: `jq` and `yq` (the YAML analog of jq, used by
the MIF report projector), `ajv-cli` + `ajv-formats`, and `copier` for the
distribution gate.

## Supply-chain verification

Every dependency or tool the harness downloads is cryptographically verified, via
a waterfall: prefer a GitHub build-provenance attestation (`gh attestation
verify`); when upstream publishes none, relax to the minimum — a pinned version
plus a SHA-256 cross-checked against the upstream signed `checksums`. A
verification miss fails the build; nothing installs unverified. Package-manager
installs (`npm`, `pip`/`pipx`) are integrity-verified against the registry by the
manager itself. The raw `yq` binary is downloaded with this waterfall in
`.github/workflows/ci.yml` (yq publishes no attestation, so it lands on the
pinned-SHA-256 floor).

## Documentation

See `docs/` for the merged Diataxis set: tutorials, how-to guides, reference,
and explanation.
